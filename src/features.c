/*
 * features.c — Feature gates and applet dispatch for busyq
 *
 * This is the only file recompiled during a lightweight custom build.
 * It controls two things at compile time:
 *
 * 1. Applet selection — via the APPLET_<command> macros from applets.h.
 *    Only applets whose flag evaluates to 1 appear in the dispatch table;
 *    LTO prunes the entry functions (and transitive code) for the rest.
 *
 * 2. Feature flags — compile-time defines that gate optional subsystems.
 *    When a feature is disabled its thunk returns a no-op value, letting
 *    LTO strip the underlying implementation from the final binary.
 *
 *    Current feature flags:
 *      BUSYQ_OVERLAY   Enable embedded-script overlay support.
 *
 * Full build (default):
 *   cc -DBUSYQ_OVERLAY -Isrc/ src/features.c ...
 *
 * Custom build (only selected applets, no overlay):
 *   cc -DBUSYQ_CUSTOM_APPLETS -DAPPLET_curl=1 -DAPPLET_jq=1 \
 *      -Isrc/ src/features.c ...
 *
 * Custom build (selected applets + overlay):
 *   cc -DBUSYQ_CUSTOM_APPLETS -DBUSYQ_OVERLAY -DAPPLET_curl=1 \
 *      -Isrc/ src/features.c ...
 */

#include "applet_table.h"
#include <string.h>
#include <unistd.h>

#ifdef BUSYQ_OVERLAY
#include "overlay.h"
#endif

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

/* ------------------------------------------------------------------ */
/* Overlay — gate for embedded-script overlay support                  */
/*                                                                     */
/* When BUSYQ_OVERLAY is defined, this calls the real overlay loader   */
/* (busyq_load_overlay in overlay.c).  Otherwise it returns NULL,      */
/* and LTO prunes the overlay code (ELF parsing, zlib, etc.).          */
/* ------------------------------------------------------------------ */

char *busyq_check_overlay(size_t *out_len)
{
#ifdef BUSYQ_OVERLAY
    return busyq_load_overlay(out_len);
#else
    (void)out_len;
    return NULL;
#endif
}
