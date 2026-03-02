/*
 * overlay.h - Embedded script overlay support for busyq
 *
 * Detects and loads bash scripts appended after the ELF binary
 * (overlay data).  Supports both raw text and gzip-compressed
 * payloads (auto-detected via gzip magic).
 *
 * Compatible with UPX: compress with UPX first, then append the
 * overlay.  UPX metadata is automatically detected and skipped.
 *
 * Attachment examples:
 *   # Raw script:
 *   cat busyq myscript.sh > mybinary && chmod +x mybinary
 *
 *   # Gzip-compressed script:
 *   { cat busyq; gzip -9c myscript.sh; } > mybinary && chmod +x mybinary
 *
 *   # After UPX:
 *   upx --best -o busyq-upx busyq
 *   cat busyq-upx myscript.sh > mybinary && chmod +x mybinary
 */

#ifndef BUSYQ_OVERLAY_H
#define BUSYQ_OVERLAY_H

#include <stddef.h>

/*
 * Try to load an overlay script from /proc/self/exe.
 *
 * Examines the ELF headers to find where the binary ends, then
 * reads any data appended beyond that point.  For UPX-compressed
 * binaries, UPX metadata is automatically skipped.  If the payload
 * begins with gzip magic (0x1f 0x8b), it is automatically decompressed.
 *
 * Returns a malloc'd, null-terminated string containing the script,
 * or NULL if no overlay is present.  Caller must free().
 * Sets *out_len to the script length (excluding null terminator).
 */
char *busyq_load_overlay(size_t *out_len);

#endif /* BUSYQ_OVERLAY_H */
