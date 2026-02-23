/*
 * bb_namespace.h - Symbol namespace isolation for busybox
 *
 * When building busybox as a library to link alongside bash (and other
 * projects), several symbol names collide. This header is force-included
 * via -include bb_namespace.h during busybox compilation, renaming
 * conflicting symbols to bb_-prefixed versions at the preprocessor level.
 *
 * This approach works cleanly with LTO since renaming happens before
 * compilation, not as a post-link fixup.
 */

#ifndef BB_NAMESPACE_H
#define BB_NAMESPACE_H

/* Memory allocation wrappers - both bash and busybox define these */
#define xmalloc     bb_xmalloc
#define xrealloc    bb_xrealloc
#define xcalloc     bb_xcalloc
#define xstrdup     bb_xstrdup
#define xstrndup    bb_xstrndup
#define xzalloc     bb_xzalloc
#define xmalloc_open_read_close bb_xmalloc_open_read_close

/* I/O wrappers - bash defines safe_read/safe_write too */
#define safe_read   bb_safe_read
#define safe_write  bb_safe_write
#define full_read   bb_full_read
#define full_write  bb_full_write

/* String utilities that may collide */
#define skip_whitespace     bb_skip_whitespace
#define skip_non_whitespace bb_skip_non_whitespace
#define is_prefixed_with    bb_is_prefixed_with
#define is_suffixed_with    bb_is_suffixed_with

/* Signal handling - bash has its own signal infrastructure */
#define signal_name         bb_signal_name
#define get_signum          bb_get_signum
#define print_signames      bb_print_signames

/*
 * Note: Additional collisions may be discovered during linking.
 * Add them here as #define OLD_NAME bb_OLD_NAME entries.
 * The build will fail with "multiple definition" errors that
 * identify exactly which symbols need to be added.
 */

#endif /* BB_NAMESPACE_H */
