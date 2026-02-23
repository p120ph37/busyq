/*
 * applet_table.h - Unified applet table for busyq
 *
 * Provides a lookup interface for all embedded applets (busybox tools,
 * curl, jq). Used by bash's patched command resolution to check for
 * applets before searching PATH.
 */

#ifndef BUSYQ_APPLET_TABLE_H
#define BUSYQ_APPLET_TABLE_H

/* Applet flags (matching busybox conventions) */
#define BUSYQ_APPLET_NOFORK  (1 << 0)  /* Safe to run in-process, no fork */
#define BUSYQ_APPLET_NOEXEC  (1 << 1)  /* Fork but don't exec, call main directly */

typedef int (*applet_main_func)(int argc, char **argv);

struct busyq_applet {
    const char *name;
    applet_main_func main_func;
    unsigned int flags;
};

/*
 * Look up an applet by name.
 * Returns a pointer to the applet entry, or NULL if not found.
 * The table is sorted by name for binary search.
 */
const struct busyq_applet *busyq_find_applet(const char *name);

/*
 * Get the full applet table and its size.
 * Used by bash to enumerate available applets.
 */
const struct busyq_applet *busyq_applet_table(int *count);

#endif /* BUSYQ_APPLET_TABLE_H */
