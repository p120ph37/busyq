/*
 * busyq - Single-binary bash+curl+jq+busybox
 *
 * Entry point: normally launches bash.  However, when re-exec'd via
 * /proc/self/exe with argv[0] set to an applet name (as busybox does
 * internally, e.g. wget forking ssl_client), we dispatch to the applet
 * instead of starting bash.
 *
 * Bash's own argv[0] semantics are preserved: "sh" enters POSIX mode,
 * "bash" / "busyq" / anything unrecognised falls through to bash.
 */

#include "applet_table.h"
#include <string.h>

/* Declared in bash's shell.h, but we just need the prototype */
extern int bash_main(int argc, char **argv);

/* Return the last path component of 'path'. */
static const char *my_basename(const char *path)
{
    const char *p = strrchr(path, '/');
    return p ? p + 1 : path;
}

int main(int argc, char **argv)
{
    const char *name = my_basename(argv[0]);

    /*
     * If argv[0] looks like an applet (not bash/sh/busyq), dispatch it.
     * This handles the case where busybox internally does:
     *   execv("/proc/self/exe", {"ssl_client", "-s", "5", NULL});
     */
    if (strcmp(name, "bash") != 0 &&
        strcmp(name, "sh")   != 0 &&
        strcmp(name, "busyq") != 0) {
        const struct busyq_applet *applet = busyq_find_applet(name);
        if (applet)
            return applet->main_func(argc, argv);
    }

    return bash_main(argc, argv);
}
