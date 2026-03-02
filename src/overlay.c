/*
 * overlay.c - Embedded script overlay support for busyq
 *
 * Detects data appended after the ELF binary ("overlay") by parsing
 * the ELF headers to find the logical end of the file.  Works for
 * both regular and UPX-compressed binaries.
 *
 * For UPX-compressed binaries, UPX metadata after the ELF segments
 * is automatically detected and skipped by scanning forward for
 * valid script content (gzip magic or printable text).
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
 * Check if a byte is a valid text character (printable ASCII,
 * tab, newline, or carriage return).
 */
static int is_text_byte(unsigned char c)
{
    return (c >= 0x20 && c <= 0x7e) ||
           c == '\t' || c == '\n' || c == '\r';
}

/*
 * Find the start of a script overlay within post-ELF data, skipping
 * any leading binary metadata (e.g. UPX pack header and overlay offset).
 *
 * Scans forward looking for:
 *   1. Gzip magic (0x1f 0x8b) — indicates gzip-compressed script
 *   2. 16+ consecutive valid text bytes — indicates raw script text
 *
 * UPX metadata is typically ~36 bytes of structured binary data
 * (pack header + overlay offset), which fails both checks.
 *
 * Returns the byte offset, or (size_t)-1 if no script found.
 */
#define OVERLAY_TEXT_MIN 16   /* min consecutive text bytes for detection */
#define OVERLAY_SCAN_MAX 256  /* max bytes to scan for overlay start */

static size_t find_script_start(const unsigned char *data, size_t len)
{
    size_t off;
    size_t limit = len < OVERLAY_SCAN_MAX ? len : OVERLAY_SCAN_MAX;

    for (off = 0; off < limit; off++) {
        /* Check for gzip magic */
        if (off + 1 < len &&
            data[off] == 0x1f && data[off + 1] == 0x8b)
            return off;

        /* Check for consecutive valid text bytes */
        if (off + OVERLAY_TEXT_MIN <= len) {
            size_t i;
            int valid = 1;
            for (i = 0; i < OVERLAY_TEXT_MIN; i++) {
                if (!is_text_byte(data[off + i])) {
                    valid = 0;
                    break;
                }
            }
            if (valid)
                return off;
        }
    }

    return (size_t)-1;
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
         * UPX leaves metadata after ELF segments (pack header +
         * overlay offset, typically ~36 bytes).  Scan forward to
         * find where the actual script data begins.
         */
        size_t script_off = find_script_start(raw, overlay_len);
        if (script_off == (size_t)-1) {
            free(raw);
            return NULL;  /* UPX metadata only, no script overlay */
        }
        data = raw + script_off;
        data_len = overlay_len - script_off;
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
