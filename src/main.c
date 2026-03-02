/*
 * busyq - Single-binary bash+curl+jq (+ upstream GNU tools)
 *
 * Entry point: normally launches bash.  However, when re-exec'd via
 * /proc/self/exe with argv[0] set to an applet name (e.g. curl needing
 * ssl_client), we dispatch to the applet instead of starting bash.
 *
 * If overlay support is enabled (via BUSYQ_OVERLAY at features.c
 * compile time) and a script is appended after the ELF binary, the
 * script is loaded and executed with all command-line arguments
 * forwarded to it.
 */

#include "features.h"
#include <stdlib.h>
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
     * This handles the case where a tool internally does:
     *   execv("/proc/self/exe", {"ssl_client", "-s", "5", NULL});
     */
    if (strcmp(name, "bash") != 0 &&
        strcmp(name, "sh")   != 0 &&
        strcmp(name, "busyq") != 0) {
        const struct busyq_applet *applet = busyq_find_applet(name);
        if (applet)
            return applet->main_func(argc, argv);
    }

    /*
     * Check for an embedded script overlay.  If present, run it via
     * bash -c with the original argv[0] as $0 and remaining args as
     * positional parameters.
     *
     * busyq_check_overlay() is a thunk defined in features.c that
     * calls the real overlay loader when BUSYQ_OVERLAY is defined,
     * or returns NULL (no-op) otherwise.  In the no-op case LTO
     * prunes all overlay-related code (ELF parsing, zlib, etc.).
     *
     * This runs after applet dispatch so that internal re-exec (e.g.
     * ssl_client) still works even when an overlay is attached.
     */
    {
        size_t script_len;
        char *script = busyq_check_overlay(&script_len);

        if (script) {
            /*
             * Build: bash -c <script> <argv[0]> <argv[1]> ...
             *
             * In bash -c mode:
             *   argv[0] of bash_main is ignored for $0 purposes
             *   the -c string is the script
             *   next arg becomes $0 in the script
             *   remaining args become $1, $2, ...
             */
            int i, ret;
            int new_argc = 3 + argc;
            char **new_argv = calloc((size_t)new_argc + 1, sizeof(char *));

            if (!new_argv) {
                free(script);
                return 1;
            }

            new_argv[0] = (char *)"bash";
            new_argv[1] = (char *)"-c";
            new_argv[2] = script;
            for (i = 0; i < argc; i++)
                new_argv[3 + i] = argv[i];
            new_argv[new_argc] = NULL;

            ret = bash_main(new_argc, new_argv);
            free(new_argv);
            free(script);
            return ret;
        }
    }

    return bash_main(argc, argv);
}
