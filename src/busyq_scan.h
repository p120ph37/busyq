/*
 * busyq_scan.h - Shared types for the busyq-scan binary
 *
 * Defines the record types and linked list used to pass results
 * from the AST walker (busyq_scan_walk.c, compiled within bash port)
 * to the main/classifier (busyq_scan_main.c, compiled at top level).
 */

#ifndef BUSYQ_SCAN_H
#define BUSYQ_SCAN_H

enum scan_type {
    SCAN_CMD,       /* Simple command reference */
    SCAN_EVAL,      /* eval invocation */
    SCAN_SOURCE,    /* source/. invocation */
    SCAN_FUNC,      /* Function definition */
    SCAN_PATH       /* Path-based invocation */
};

struct scan_record {
    enum scan_type type;
    char *value;            /* Command name, expression, or path */
    const char *file;       /* Source filename */
    int line;               /* Line number */
    struct scan_record *next;
};

/* Global result list — populated by the walker, consumed by main */
extern struct scan_record *scan_results;

/* Tail pointer for appending — must be kept in sync if scan_results is
 * modified externally (e.g. by collect_records for multi-file support). */
extern struct scan_record **scan_results_tail;

#endif /* BUSYQ_SCAN_H */
