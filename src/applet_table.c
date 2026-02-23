/*
 * applet_table.c - Unified applet table for busyq
 *
 * This file defines the combined applet table that includes:
 * 1. All enabled busybox applets (via generated include)
 * 2. curl and jq as additional applets
 *
 * The table is sorted alphabetically for binary search lookup.
 *
 * During the build, busybox's applet table is generated into a header
 * that we include here. The curl and jq entries are added manually.
 */

#include "applet_table.h"
#include <string.h>
#include <stddef.h>

/*
 * Forward declarations for applet main functions.
 * These are the entry points of each embedded tool.
 */
extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);

/*
 * Busybox applet entries are generated at build time.
 * The build system produces busybox_applets.h which contains
 * BUSYQ_BB_APPLET(name, main_func, flags) entries for each
 * enabled busybox applet.
 *
 * Example generated content:
 *   BUSYQ_BB_APPLET("awk", awk_main, 0)
 *   BUSYQ_BB_APPLET("cat", cat_main, BUSYQ_APPLET_NOFORK)
 *   BUSYQ_BB_APPLET("grep", grep_main, 0)
 *   ...
 */

/* Declare all busybox applet main functions */
#define BUSYQ_BB_APPLET(name, func, flags) extern int func(int, char**);
#include "busybox_applets.h"
#undef BUSYQ_BB_APPLET

/*
 * The unified, sorted applet table.
 * Busybox applets are interspersed with curl/jq in alphabetical order.
 *
 * IMPORTANT: This table MUST remain sorted by name for binary search.
 * The build system generates busybox_applets.h already sorted, and
 * curl/jq are inserted at the correct alphabetical positions.
 *
 * For now, we build the table in two parts and sort at init time,
 * since the exact set of busybox applets depends on the config.
 */

static struct busyq_applet applet_list[] = {
    /* Busybox applets (from generated header) */
#define BUSYQ_BB_APPLET(n, func, f) { n, func, f },
#include "busybox_applets.h"
#undef BUSYQ_BB_APPLET

    /* Additional applets */
    { "curl", curl_main, 0 },
    { "jq",   jq_main,   0 },
};

static const int applet_count = sizeof(applet_list) / sizeof(applet_list[0]);
static int table_sorted = 0;

/* Simple comparison for qsort */
static int applet_cmp(const void *a, const void *b) {
    return strcmp(((const struct busyq_applet *)a)->name,
                 ((const struct busyq_applet *)b)->name);
}

static void ensure_sorted(void) {
    if (!table_sorted) {
        qsort(applet_list, applet_count, sizeof(applet_list[0]), applet_cmp);
        table_sorted = 1;
    }
}

const struct busyq_applet *busyq_find_applet(const char *name) {
    int lo, hi, mid, cmp;

    ensure_sorted();

    lo = 0;
    hi = applet_count - 1;
    while (lo <= hi) {
        mid = (lo + hi) / 2;
        cmp = strcmp(name, applet_list[mid].name);
        if (cmp < 0)
            hi = mid - 1;
        else if (cmp > 0)
            lo = mid + 1;
        else
            return &applet_list[mid];
    }
    return NULL;
}

const struct busyq_applet *busyq_applet_table(int *count) {
    ensure_sorted();
    if (count)
        *count = applet_count;
    return applet_list;
}
