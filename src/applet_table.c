/*
 * applet_table.c - Applet dispatch for busyq
 *
 * Each embedded tool has a renamed main() that we call from the forked
 * child process in bash's shell_execve().  New upstream packages are
 * added here as {name, main_func} entries.
 *
 * Currently registered:
 *   curl     → curl_main(argc, argv)
 *   jq       → jq_main(argc, argv)
 *
 * The table will grow as upstream packages replace busybox applets
 * (coreutils, gawk, sed, grep, findutils, tar, etc.).
 */

#include "applet_table.h"
#include <string.h>
#include <unistd.h>

/* External tool entry points */
extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);
#ifdef BUSYQ_SSL
extern int ssl_client_main(int argc, char **argv);
#endif

static int busyq_help_main(int argc, char **argv);

static const struct busyq_applet applets[] = {
    { "busyq",      busyq_help_main, 0 },
    { "curl",       curl_main,       0 },
    { "jq",         jq_main,         0 },
#ifdef BUSYQ_SSL
    { "ssl_client", ssl_client_main, 0 },
#endif
};
static const int applet_count = sizeof(applets) / sizeof(applets[0]);

const struct busyq_applet *busyq_find_applet(const char *name)
{
    int i;

    for (i = 0; i < applet_count; i++) {
        if (strcmp(name, applets[i].name) == 0)
            return &applets[i];
    }

    return NULL;
}

/*
 * List all available commands.
 * Invoked when argv[0] is "busyq" (not bash/sh).
 */
static int busyq_help_main(int argc, char **argv)
{
    int i, col;

    (void)argc;
    (void)argv;

    {
        const char hdr[] =
            "busyq - single-binary bash+curl+jq\n\n"
            "Built-in commands:\n";
        write(STDOUT_FILENO, hdr, sizeof(hdr) - 1);
    }

    col = 0;
    for (i = 0; i < applet_count; i++) {
        int len = strlen(applets[i].name);
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
        write(STDOUT_FILENO, applets[i].name, len);
        col += len;
    }
    write(STDOUT_FILENO, "\n", 1);

    return 0;
}
