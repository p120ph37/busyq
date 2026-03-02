/*
 * overlay.c - Embedded script overlay support for busyq
 *
 * Detects data appended after the ELF binary ("overlay") by parsing
 * the ELF headers to find the logical end of the file.  Works for
 * both regular and UPX-compressed binaries.
 *
 * For UPX-compressed binaries, the 36-byte UPX trailer (PackHeader +
 * overlay_offset) after the ELF segments is deterministically parsed
 * and skipped.
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
 * Check if the ELF binary was compressed with UPX.
 *
 * UPX places an l_info structure immediately after the program header
 * table.  The l_magic field (at offset 4 within l_info) contains
 * "UPX!" (0x55505821) for UPX-compressed binaries.
 */
static int is_upx_binary(int fd)
{
    Elf64_Ehdr ehdr;
    unsigned char magic[4];
    off_t l_info_off;

    if (pread(fd, &ehdr, sizeof(ehdr), 0) != (ssize_t)sizeof(ehdr))
        return 0;
    if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0)
        return 0;
    if (ehdr.e_ident[EI_CLASS] != ELFCLASS64)
        return 0;

    /* l_info is right after the program header table */
    l_info_off = (off_t)ehdr.e_phoff +
                 (off_t)ehdr.e_phnum * ehdr.e_phentsize;

    /* l_magic is at offset 4 within l_info */
    if (pread(fd, magic, 4, l_info_off + 4) != 4)
        return 0;

    return magic[0] == 'U' && magic[1] == 'P' &&
           magic[2] == 'X' && magic[3] == '!';
}

/*
 * Compute the size of UPX's end-of-file trailer from post-ELF data.
 *
 * UPX's pack4() writes a PackHeader followed by a 4-byte overlay_offset
 * as the very last data in the file (see p_unix.cpp in UPX source).
 * The PackHeader starts with "UPX!" magic (0x55505821 LE32) and its
 * size depends on the version and format fields at bytes 4-5:
 *
 *   version >= 10, non-DOS format:  32 bytes  (current UPX)
 *   version  4-9, non-DOS format:   28 bytes
 *   version <= 3:                    24 bytes
 *
 * Total trailer = PackHeader + 4-byte overlay_offset.
 *
 * Returns the trailer size in bytes, or 0 if the data doesn't start
 * with a valid UPX PackHeader.
 */
static size_t upx_trailer_size(const unsigned char *data, size_t len)
{
    int version, format;
    int phdr_size;

    /* Need at least magic(4) + version/format(2) */
    if (len < 6)
        return 0;

    /* PackHeader starts with "UPX!" magic (LE32: 0x55505821) */
    if (data[0] != 'U' || data[1] != 'P' ||
        data[2] != 'X' || data[3] != '!')
        return 0;

    version = data[4];
    format = data[5];

    /* PackHeader size from UPX packhead.cpp getPackHeaderSize() */
    if (version <= 3)
        phdr_size = 24;
    else if (format == 1 || format == 2)   /* UPX_F_DOS_COM, UPX_F_DOS_SYS */
        phdr_size = (version <= 9) ? 20 : 22;
    else if (format == 3 || format == 4)   /* UPX_F_DOS_EXE, UPX_F_DOS_EXEH */
        phdr_size = (version <= 9) ? 25 : 27;
    else                                   /* ELF and all other formats */
        phdr_size = (version <= 9) ? 28 : 32;

    /* Trailer = PackHeader + 4-byte overlay_offset */
    if ((size_t)(phdr_size + 4) > len)
        return 0;

    return (size_t)(phdr_size + 4);
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
    int upx;
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

    /* Detect UPX compression */
    upx = is_upx_binary(fd);
    close(fd);

    data = raw;
    data_len = overlay_len;

    if (upx) {
        /*
         * UPX appends a PackHeader (32 bytes for modern ELF) plus a
         * 4-byte overlay_offset as the last data in the file, after
         * all ELF structures.  Parse the trailer size exactly and
         * skip it to find the user's overlay data.
         */
        size_t trailer = upx_trailer_size(raw, overlay_len);
        if (trailer == 0 || trailer >= overlay_len) {
            free(raw);
            return NULL;  /* UPX metadata only, no script overlay */
        }
        data = raw + trailer;
        data_len = overlay_len - trailer;
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
