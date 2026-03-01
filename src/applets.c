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
/* External entry points — auto-generated from applets.h               */
/*                                                                     */
/* The X-macro pass forward-declares each enabled entry function.      */
/* Only referenced functions create linker dependencies; LTO/gc-       */
/* sections will strip the rest.  busyq_help_main is defined below.    */
/* ------------------------------------------------------------------ */

int busyq_help_main(int argc, char **argv);

#define APPLET(mod, cmd, func) extern int func(int, char **);
#include "applets.h"
#undef APPLET

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
/* Lookup — binary search (applets.h entries are sorted by command)    */
/* ------------------------------------------------------------------ */

const struct busyq_applet *busyq_find_applet(const char *name)
{
    int lo = 0, hi = applet_count - 1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        int cmp = strcmp(name, applets[mid].name);
        if (cmp == 0)
            return &applets[mid];
        if (cmp < 0)
            hi = mid - 1;
        else
            lo = mid + 1;
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Help — lists all compiled-in commands                               */
/* ------------------------------------------------------------------ */

int busyq_help_main(int argc, char **argv)
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
