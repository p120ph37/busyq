/*
 * applets.c — Applet dispatch for busyq
 *
 * Consumes applets.h (X-macro registry) to build the applet table at
 * compile time.  Only applets whose APPLET_<command> macro evaluates to 1
 * are included; their entry functions are the only symbols referenced,
 * allowing LTO to strip everything else.
 *
 * Full build (default):
 *   cc -Isrc/ src/applets.c ...
 *
 * Custom build (only selected applets):
 *   cc -DBUSYQ_CUSTOM_APPLETS -DAPPLET_curl=1 -DAPPLET_jq=1 \
 *      -Isrc/ src/applets.c ...
 *
 * This file replaces gen-applet-table.sh — no code generation step
 * needed; the C preprocessor handles filtering directly.
 */

#include "applet_table.h"
#include <string.h>
#include <unistd.h>

/* Include applets.h to activate the default macros (APPLET_<cmd> = 0|1).
 * APPLET is not yet defined, so the no-op default in applets.h applies.
 * This pass just establishes the enable/disable defaults. */
#include "applets.h"

/* ------------------------------------------------------------------ */
/* External entry points                                               */
/*                                                                     */
/* Only enabled functions are actually referenced in the table below.   */
/* Unreferenced externs do not create linker dependencies; LTO/gc-      */
/* sections will strip the corresponding code.                         */
/* ------------------------------------------------------------------ */

extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);
extern int coreutils_main(int argc, char **argv);
#if BUSYQ_SSL
extern int ssl_client_main(int argc, char **argv);
#endif

static int busyq_help_main(int argc, char **argv);

/* ------------------------------------------------------------------ */
/* Applet table — populated via X-macro                                */
/*                                                                     */
/* _BQ_IF(APPLET_<cmd>) conditionally expands each entry.  When the    */
/* flag is 0 the entire table row (including the function reference)    */
/* is elided, so LTO can drop the unreferenced symbol.                 */
/* ------------------------------------------------------------------ */

#define APPLET(mod, cmd, func) { #cmd, func, 0 },
static const struct busyq_applet applets[] = {
#include "applets.h"
};
#undef APPLET

static const int applet_count = sizeof(applets) / sizeof(applets[0]);

/* ------------------------------------------------------------------ */
/* Lookup                                                              */
/* ------------------------------------------------------------------ */

const struct busyq_applet *busyq_find_applet(const char *name)
{
    int i;
    for (i = 0; i < applet_count; i++) {
        if (strcmp(name, applets[i].name) == 0)
            return &applets[i];
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Help — lists all compiled-in commands                               */
/* ------------------------------------------------------------------ */

static int busyq_help_main(int argc, char **argv)
{
    int i, col;

    (void)argc;
    (void)argv;

    {
        const char hdr[] =
            "busyq - single-binary bash+curl+jq+coreutils\n\n"
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
