/*
 * applet_table.h - Applet dispatch interface for busyq
 *
 * Provides lookup and execution for all embedded applets: busybox tools,
 * curl, and jq. Busybox applets are dispatched through busybox's own
 * find_applet_by_name()/run_applet_no_and_exit() so the applet list is
 * always in sync with what was actually compiled.
 */

#ifndef BUSYQ_APPLET_TABLE_H
#define BUSYQ_APPLET_TABLE_H

/* Applet flags — kept for the bash patch interface but now only used
 * for curl/jq (busybox handles its own NOFORK/NOEXEC internally). */
#define BUSYQ_APPLET_NOFORK  (1 << 0)
#define BUSYQ_APPLET_NOEXEC  (1 << 1)

typedef int (*applet_main_func)(int argc, char **argv);

struct busyq_applet {
    const char *name;
    applet_main_func main_func;
    unsigned int flags;
};

/*
 * Look up an applet by name.
 * Returns a pointer to the applet entry for curl/jq, or a shared
 * sentinel entry for busybox applets. Returns NULL if not found.
 */
const struct busyq_applet *busyq_find_applet(const char *name);

#endif /* BUSYQ_APPLET_TABLE_H */
