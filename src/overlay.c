/*
 * overlay.c - Embedded script overlay support for busyq
 *
 * Detects data appended after the ELF binary ("overlay") by parsing
 * the ELF headers to find the logical end of the file.  Works for
 * both regular and UPX-compressed binaries.
 *
 * For UPX-compressed binaries, the post-ELF region contains UPX
 * metadata (decompressor stub, padding, PackHeader, overlay_offset).
 * We scan for a valid UPX PackHeader (32-byte structure with "UPX!"
 * magic + checksum) and skip past it + the 4-byte overlay_offset to
 * find user-appended data.
 *
 * The overlay payload may be raw script text or gzip-compressed
 * data (auto-detected via 0x1f 0x8b magic).
 */

#include "overlay.h"

#include <elf.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

/*
 * Calculate the logical end of an ELF64 file by examining all
 * headers and segments.  Any data beyond this offset is overlay.
 *
 * We take the maximum of:
 *   - ELF header size
 *   - Program header table end
 *   - Section header table end  (may be 0 after strip/UPX)
 *   - Each segment's file end   (p_offset + p_filesz)
 *   - Each section's file end   (sh_offset + sh_size, skip NOBITS)
 *
 * Returns the offset, or (off_t)-1 on error.
 */
static off_t elf_file_end(int fd)
{
    Elf64_Ehdr ehdr;
    off_t end;
    int i;

    if (pread(fd, &ehdr, sizeof(ehdr), 0) != (ssize_t)sizeof(ehdr))
        return (off_t)-1;

    /* Verify ELF magic */
    if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0)
        return (off_t)-1;

    /* Only handle 64-bit (project target is x86_64) */
    if (ehdr.e_ident[EI_CLASS] != ELFCLASS64)
        return (off_t)-1;

    end = (off_t)sizeof(ehdr);

    /* Program header table end */
    if (ehdr.e_phoff) {
        off_t ph_end = (off_t)ehdr.e_phoff +
                       (off_t)ehdr.e_phnum * ehdr.e_phentsize;
        if (ph_end > end)
            end = ph_end;
    }

    /* Section header table end (0 if stripped / UPX'd) */
    if (ehdr.e_shoff) {
        off_t sh_end = (off_t)ehdr.e_shoff +
                       (off_t)ehdr.e_shnum * ehdr.e_shentsize;
        if (sh_end > end)
            end = sh_end;
    }

    /* Scan program headers for segment data ends */
    for (i = 0; i < ehdr.e_phnum; i++) {
        Elf64_Phdr phdr;
        off_t seg_end;
        off_t off = (off_t)ehdr.e_phoff + (off_t)i * ehdr.e_phentsize;

        if (pread(fd, &phdr, sizeof(phdr), off) != (ssize_t)sizeof(phdr))
            return (off_t)-1;

        seg_end = (off_t)phdr.p_offset + (off_t)phdr.p_filesz;
        if (seg_end > end)
            end = seg_end;
    }

    /* Scan section headers for section data ends */
    for (i = 0; i < ehdr.e_shnum; i++) {
        Elf64_Shdr shdr;
        off_t sec_end;
        off_t off = (off_t)ehdr.e_shoff + (off_t)i * ehdr.e_shentsize;

        if (pread(fd, &shdr, sizeof(shdr), off) != (ssize_t)sizeof(shdr))
            return (off_t)-1;

        /* SHT_NOBITS sections (.bss) occupy no file space */
        if (shdr.sh_type == SHT_NOBITS)
            continue;

        sec_end = (off_t)shdr.sh_offset + (off_t)shdr.sh_size;
        if (sec_end > end)
            end = sec_end;
    }

    return end;
}

/*
 * Decompress gzip data using zlib.
 * Returns a malloc'd, null-terminated buffer, or NULL on error.
 * Sets *out_len to the decompressed length.
 */
static char *gunzip(const unsigned char *data, size_t len, size_t *out_len)
{
    z_stream strm;
    size_t buf_size;
    char *buf, *tmp;
    int ret;

    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)data;
    strm.avail_in = (uInt)len;

    /* windowBits = 15 + 16 tells zlib to detect/handle gzip header */
    if (inflateInit2(&strm, 15 + 16) != Z_OK)
        return NULL;

    buf_size = len * 4;  /* initial guess */
    if (buf_size < 4096)
        buf_size = 4096;

    buf = malloc(buf_size);
    if (!buf) {
        inflateEnd(&strm);
        return NULL;
    }

    strm.next_out = (unsigned char *)buf;
    strm.avail_out = (uInt)buf_size;

    for (;;) {
        ret = inflate(&strm, Z_FINISH);
        if (ret == Z_STREAM_END)
            break;

        if (ret == Z_BUF_ERROR || (ret == Z_OK && strm.avail_out == 0)) {
            /* Need more output space */
            size_t have = (size_t)(strm.next_out - (unsigned char *)buf);
            buf_size *= 2;
            tmp = realloc(buf, buf_size);
            if (!tmp) {
                free(buf);
                inflateEnd(&strm);
                return NULL;
            }
            buf = tmp;
            strm.next_out = (unsigned char *)buf + have;
            strm.avail_out = (uInt)(buf_size - have);
            continue;
        }

        /* Decompression error */
        free(buf);
        inflateEnd(&strm);
        return NULL;
    }

    *out_len = strm.total_out;
    inflateEnd(&strm);

    /* Null-terminate for use as C string */
    tmp = realloc(buf, *out_len + 1);
    if (tmp)
        buf = tmp;
    buf[*out_len] = '\0';

    return buf;
}

/*
 * Scan post-ELF data for a valid UPX PackHeader and return the offset
 * where user overlay data begins (right after the trailer).
 *
 * UPX appends metadata after the ELF segments: decompressor stub,
 * metadata words, padding, and finally a 32-byte PackHeader followed
 * by a 4-byte overlay_offset.  The PackHeader contains "UPX!" magic
 * at bytes [0..3] and a checksum at byte [31] (sum of bytes [4..30]
 * mod 251).  We scan for this signature to find the UPX/user boundary.
 *
 * Returns the byte offset within 'data' where user data starts
 * (i.e. right after PackHeader + overlay_offset), or 0 if no valid
 * PackHeader is found (meaning no UPX metadata to skip).
 */
static size_t find_upx_trailer_end(const unsigned char *data, size_t len)
{
    size_t off;

    /* PackHeader(32) + overlay_offset(4) = 36 bytes minimum */
    if (len < 36)
        return 0;

    for (off = 0; off + 36 <= len; off++) {
        unsigned sum;
        int j;

        /* Look for "UPX!" magic */
        if (data[off]   != 'U' || data[off+1] != 'P' ||
            data[off+2] != 'X' || data[off+3] != '!')
            continue;

        /* Validate version (byte 4): 1..63 covers all known and
         * foreseeable UPX versions without being too permissive */
        if (data[off+4] < 1 || data[off+4] > 63)
            continue;

        /* Validate format (byte 5): must be non-zero */
        if (data[off+5] == 0)
            continue;

        /* Validate PackHeader checksum: sum of bytes [4..30] mod 251 */
        sum = 0;
        for (j = 4; j <= 30; j++)
            sum += data[off + j];
        if (data[off+31] != (unsigned char)(sum % 251))
            continue;

        /* Valid PackHeader found.  User data starts after the
         * 32-byte PackHeader + 4-byte overlay_offset. */
        return off + 36;
    }

    return 0;
}

char *busyq_load_overlay(size_t *out_len)
{
    int fd;
    struct stat st;
    off_t elf_end;
    size_t overlay_len;
    unsigned char *raw;
    unsigned char *data;
    size_t data_len;
    char *script;

    fd = open("/proc/self/exe", O_RDONLY);
    if (fd < 0)
        return NULL;

    if (fstat(fd, &st) < 0) {
        close(fd);
        return NULL;
    }

    elf_end = elf_file_end(fd);
    if (elf_end <= 0 || elf_end >= st.st_size) {
        close(fd);
        return NULL;  /* No overlay data */
    }

    overlay_len = (size_t)(st.st_size - elf_end);

    /* Read all post-ELF data */
    raw = malloc(overlay_len);
    if (!raw) {
        close(fd);
        return NULL;
    }

    if (pread(fd, raw, overlay_len, elf_end) != (ssize_t)overlay_len) {
        free(raw);
        close(fd);
        return NULL;
    }
    close(fd);

    data = raw;
    data_len = overlay_len;

    /*
     * Check for UPX metadata in the post-ELF region.
     *
     * UPX places metadata (decompressor stub, padding, PackHeader,
     * overlay_offset) after the ELF segments.  The PackHeader is a
     * 32-byte structure starting with "UPX!" magic and ending with
     * a checksum, followed by a 4-byte overlay_offset.  We scan for
     * this signature to find where UPX metadata ends and any
     * user-appended overlay data begins.
     *
     * This works regardless of whether PT_NOTE data, padding, or
     * other structures sit between the segment end and the trailer.
     */
    {
        size_t upx_end = find_upx_trailer_end(raw, overlay_len);
        if (upx_end > 0) {
            if (upx_end >= overlay_len) {
                free(raw);
                return NULL;  /* UPX metadata only, no user overlay */
            }
            data = raw + upx_end;
            data_len = overlay_len - upx_end;
        }
    }

    /* Auto-detect gzip: magic bytes 0x1f 0x8b */
    if (data_len >= 2 &&
        data[0] == 0x1f && data[1] == 0x8b) {
        script = gunzip(data, data_len, out_len);
        free(raw);
        return script;  /* NULL on decompress error */
    }

    /* Not compressed — copy, null-terminate, return */
    script = malloc(data_len + 1);
    if (!script) {
        free(raw);
        return NULL;
    }
    memcpy(script, data, data_len);
    script[data_len] = '\0';
    *out_len = data_len;
    free(raw);
    return script;
}
