/*
 * applet_table.c - Applet dispatch for busyq
 *
 * All four embedded tools are treated uniformly: each has a renamed
 * main() that we call from the forked child process in shell_execve().
 *   bash     → bash_main(argc, argv)     [always the entry point]
 *   busybox  → busybox_main(argc, argv)  [multiplexes on argv[0]]
 *   curl     → curl_main(argc, argv)
 *   jq       → jq_main(argc, argv)
 *
 * Busybox applets are detected via find_applet_by_name() from libbb.
 * When found, we dispatch through busybox_main() so busybox performs
 * its own initialization (bb_errno, locale, --help, SUID checks) and
 * applet dispatch, exactly as if execve'd on a busybox symlink.
 */

#include "applet_table.h"
#include <string.h>
#include <unistd.h>

/* Busybox applet lookup (from libbb) */
extern int find_applet_by_name(const char *name);
/* Busybox entry point (renamed from main via -Dmain=bb_entry_main).
 * Dispatches based on argv[0], performing full busybox initialization. */
extern int bb_entry_main(int argc, char **argv);
/* Busybox applet name list (NUL-separated flat string from applet_tables.h) */
extern const char applet_names[];

/* External tool entry points */
extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);

static int busyq_help_main(int argc, char **argv);

static const struct busyq_applet extra_applets[] = {
    { "busyq",  busyq_help_main, 0 },
    { "curl",   curl_main, 0 },
    { "jq",     jq_main,   0 },
};
static const int extra_count = sizeof(extra_applets) / sizeof(extra_applets[0]);

/*
 * Sentinel entry returned for busybox applets.  Calls bb_entry_main()
 * (busybox's renamed main) which dispatches based on argv[0], just as
 * if invoked via execve on a busybox symlink.
 */
static const struct busyq_applet bb_sentinel = {
    "busybox", bb_entry_main, 0
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
