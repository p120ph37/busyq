/*
 * applet_table.c - Applet dispatch for busyq
 *
 * Combines busybox's own applet registry with curl and jq entries.
 * Busybox applets are looked up via find_applet_by_name() from libbb,
 * which is always in sync with the compiled-in applets — no generated
 * header needed.
 */

#include "applet_table.h"
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

/* Busybox applet lookup (from libbb) */
extern int find_applet_by_name(const char *name);
/* Busybox runtime initialization (sets bb_errno, applet_name, etc.) */
extern void lbb_prepare(const char *applet);
/* Busybox applet execution — does not return, calls exit() */
extern void run_applet_no_and_exit(int applet_no, const char *name, char **argv);

/* External tool entry points */
extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);

static const struct busyq_applet extra_applets[] = {
    { "curl", curl_main, 0 },
    { "jq",   jq_main,   0 },
};
static const int extra_count = sizeof(extra_applets) / sizeof(extra_applets[0]);

/*
 * Sentinel entry returned for busybox applets.  The main_func is a
 * wrapper that forks and calls run_applet_no_and_exit().
 */
static int busybox_applet_dispatch(int argc, char **argv);
static const struct busyq_applet bb_sentinel = {
    "busybox", busybox_applet_dispatch, 0
};

const struct busyq_applet *busyq_find_applet(const char *name)
{
    int i;

    /* Check extra applets first (curl, jq) */
    for (i = 0; i < extra_count; i++) {
        if (strcmp(name, extra_applets[i].name) == 0)
            return &extra_applets[i];
    }

    /* Check busybox applets */
    if (find_applet_by_name(name) >= 0)
        return &bb_sentinel;

    return NULL;
}

/*
 * Dispatch a busybox applet.  This is called from a forked child
 * (execute_cmd.c forks for non-NOFORK applets), so we can call
 * run_applet_no_and_exit() which calls exit() and never returns.
 */
static int busybox_applet_dispatch(int argc, char **argv)
{
    int applet_no;

    (void)argc;
    if (!argv || !argv[0])
        return -1;

    applet_no = find_applet_by_name(argv[0]);
    if (applet_no < 0)
        return -1;

    /* Initialize busybox runtime (sets bb_errno, applet_name) */
    lbb_prepare(argv[0]);

    /* Does not return — calls exit() internally */
    run_applet_no_and_exit(applet_no, argv[0], argv);
    return 127; /* unreachable */
}
