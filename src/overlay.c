/*
 * overlay.c - Embedded script overlay support for busyq
 *
 * Detects data appended after the ELF binary ("overlay") by parsing
 * the ELF headers to find the logical end of the file.  Works for
 * both regular and UPX-compressed binaries (UPX produces valid ELF
 * files with no section headers, so we handle that case).
 *
 * Gzip-compressed overlays are auto-detected (magic 0x1f 0x8b) and
 * transparently decompressed using zlib.
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

char *busyq_load_overlay(size_t *out_len)
{
    int fd;
    struct stat st;
    off_t elf_end;
    size_t overlay_len;
    char *overlay;
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
    if (overlay_len == 0) {
        close(fd);
        return NULL;
    }

    overlay = malloc(overlay_len + 1);
    if (!overlay) {
        close(fd);
        return NULL;
    }

    if (pread(fd, overlay, overlay_len, elf_end) != (ssize_t)overlay_len) {
        free(overlay);
        close(fd);
        return NULL;
    }
    close(fd);

    /* Auto-detect gzip: magic bytes 0x1f 0x8b */
    if (overlay_len >= 2 &&
        (unsigned char)overlay[0] == 0x1f &&
        (unsigned char)overlay[1] == 0x8b) {
        script = gunzip((unsigned char *)overlay, overlay_len, out_len);
        free(overlay);
        return script;  /* NULL on decompress error */
    }

    /* Not compressed — use as-is, null-terminate */
    overlay[overlay_len] = '\0';
    *out_len = overlay_len;
    return overlay;
}
