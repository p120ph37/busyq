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
/* Busybox applet function pointer table (from applet_tables.h) */
extern int (*const applet_main[])(int argc, char **argv);
/* Busybox global applet name pointer (used by error reporting) */
extern const char *applet_name;

/* External tool entry points */
extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);

/* Busybox applet name list (NUL-separated flat string from applet_tables.h) */
extern const char applet_names[];

static int busyq_help_main(int argc, char **argv);

static const struct busyq_applet extra_applets[] = {
    { "busyq",  busyq_help_main, 0 },
    { "curl",   curl_main, 0 },
    { "jq",     jq_main,   0 },
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
 * (execute_cmd.c forks for non-NOFORK applets).  We call the applet's
 * main function directly via applet_main[] rather than using
 * run_applet_no_and_exit(), because the latter calls exit() which runs
 * bash's atexit handlers in the child and corrupts state.  The caller
 * in execute_cmd.c wraps this in _exit().
 */
static int busybox_applet_dispatch(int argc, char **argv)
{
    int applet_no;

    if (!argv || !argv[0])
        return -1;

    applet_no = find_applet_by_name(argv[0]);
    if (applet_no < 0)
        return -1;

    /* Initialize busybox runtime (sets bb_errno, applet_name) */
    lbb_prepare(argv[0]);
    applet_name = argv[0];

    return applet_main[applet_no](argc, argv);
}

/*
 * List all available commands: busyq extras + busybox applets.
 * Invoked as "busyq" applet (e.g. `busyq --help` or just `busyq`
 * when called as a non-bash name).
 */
static int busyq_help_main(int argc, char **argv)
{
    const char *p;
    int col, count;

    (void)argc;
    (void)argv;

    {
        const char hdr[] =
            "busyq - single-binary bash+curl+jq+busybox\n\n"
            "Built-in commands:\n"
            "  bash, sh, curl, jq\n\n"
            "Busybox applets:\n";
        write(STDOUT_FILENO, hdr, sizeof(hdr) - 1);
    }

    /* Walk the NUL-separated applet_names list */
    col = 0;
    count = 0;
    for (p = applet_names; *p; p += strlen(p) + 1) {
        int len = strlen(p);
        if (col == 0) {
            write(STDOUT_FILENO, "  ", 2);
            col = 2;
        } else if (col + len + 2 > 78) {
            write(STDOUT_FILENO, "\n  ", 3);
            col = 2;
        } else {
            write(STDOUT_FILENO, ", ", 2);
            col += 2;
        }
        write(STDOUT_FILENO, p, len);
        col += len;
        count++;
    }
    write(STDOUT_FILENO, "\n", 1);

    return 0;
}
