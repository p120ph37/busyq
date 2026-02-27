/*
 * busyq_scan_main.c - Entry point for the busyq-scan binary
 *
 * Uses bash's parser in -n (no-execute) mode to walk the AST and
 * extract command references.  After parsing, classifies each command
 * as a bash builtin, busyq applet, script-defined function, or
 * external command, and outputs a report.
 *
 * The --wrap=reader_loop linker option redirects bash's reader_loop()
 * to __wrap_reader_loop() in busyq_scan_walk.c, which walks the AST
 * instead of executing commands.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#include "applet_table.h"
#include "busyq_scan.h"

/* Declared in bash's shell.h (compiled without NO_MAIN_ENV_ARG) */
extern int bash_main(int argc, char **argv, char **env);

/* POSIX environ */
extern char **environ;

/*
 * Multi-file support: bash_main() calls exit() when done parsing,
 * so it can only process one file per process.  For multiple files,
 * we fork a child for each non-final file.  The child registers an
 * atexit handler that writes accumulated records to a pipe.  The
 * parent reads them and appends to its own scan_results list.
 * The final file is processed in the parent process.
 */
extern void __real_exit(int status);

/* __wrap_exit: needed because we link with --wrap=exit to support
 * both child atexit handlers and the parent's scan_output handler. */
void __wrap_exit(int status)
{
    __real_exit(status);
}

static int child_pipe_fd = -1;

/* atexit handler for child processes: serialize records to pipe */
static void child_write_records(void)
{
    if (child_pipe_fd < 0)
        return;
    for (struct scan_record *r = scan_results; r; r = r->next)
        dprintf(child_pipe_fd, "%d\t%s\t%s\t%d\n", r->type, r->value, r->file, r->line);
    close(child_pipe_fd);
    child_pipe_fd = -1;
}

/* Read records from pipe fd and append to the parent's scan_results */
static void collect_records(int fd)
{
    FILE *f = fdopen(fd, "r");
    if (!f) { close(fd); return; }

    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        int type_int, line_no;
        char value[1024], file[1024];
        if (sscanf(line, "%d\t%1023[^\t]\t%1023[^\t]\t%d",
                   &type_int, value, file, &line_no) == 4) {
            struct scan_record *r = malloc(sizeof(*r));
            if (!r) continue;
            r->type = (enum scan_type)type_int;
            r->value = strdup(value);
            r->file = strdup(file);
            r->line = line_no;
            r->next = NULL;
            *scan_results_tail = r;
            scan_results_tail = &r->next;
        }
    }
    fclose(f);
}

/* Global filename used by the walker to tag output lines */
const char *busyq_scan_filename = NULL;

/*
 * Stub: the scanner does not need the applet table for command dispatch.
 * All commands are reported and classified by this file instead.
 */
const struct busyq_applet *busyq_find_applet(const char *name)
{
    (void)name;
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Applet registry (compiled-in from applets.h)                        */
/*                                                                     */
/* The scanner always needs the full registry for classification, so   */
/* we include all applets (no BUSYQ_CUSTOM_APPLETS).  ssl_client is    */
/* explicitly enabled since the scanner doesn't link against SSL libs  */
/* but still needs to classify it.                                     */
/* ------------------------------------------------------------------ */

struct applet_entry {
    const char *module;
    const char *command;
};

#define APPLET_ssl_client 1
#define APPLET(mod, cmd, func) { #mod, #cmd },
static const struct applet_entry applet_reg[] = {
#include "applets.h"
};
#undef APPLET

static const int num_applets = sizeof(applet_reg) / sizeof(applet_reg[0]);

static const char *find_applet_module(const char *name)
{
    for (int i = 0; i < num_applets; i++) {
        if (strcmp(applet_reg[i].command, name) == 0)
            return applet_reg[i].module;
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Bash builtins                                                       */
/* ------------------------------------------------------------------ */

static const char *bash_builtins[] = {
    ".", ":", "source", "eval", "exec", "exit", "return",
    "alias", "unalias",
    "bg", "fg", "jobs", "wait", "disown", "suspend",
    "bind", "caller", "cd", "command", "compgen", "complete", "compopt",
    "declare", "typeset", "local", "export", "readonly",
    "dirs", "pushd", "popd",
    "echo", "enable", "fc", "getopts", "hash", "help", "history",
    "kill", "let", "logout",
    "mapfile", "readarray",
    "printf", "pwd", "read",
    "set", "shopt", "shift",
    "test", "trap", "times", "type",
    "ulimit", "umask", "unset",
    "true", "false",
    "[", "[[",
    "break", "continue",
    NULL
};

static int is_bash_builtin(const char *name)
{
    for (const char **b = bash_builtins; *b; b++) {
        if (strcmp(*b, name) == 0)
            return 1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Shell keywords                                                      */
/* ------------------------------------------------------------------ */

static const char *shell_keywords[] = {
    "if", "then", "else", "elif", "fi",
    "case", "esac", "in",
    "for", "select", "while", "until", "do", "done",
    "function", "time", "coproc",
    "!", "{", "}", "]]",
    NULL
};

static int is_shell_keyword(const char *name)
{
    for (const char **k = shell_keywords; *k; k++) {
        if (strcmp(*k, name) == 0)
            return 1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Simple hash set                                                     */
/* ------------------------------------------------------------------ */

#define HASHSET_SIZE 512

struct hashset_entry {
    char *key;
    char *value;
    char *locs;
    struct hashset_entry *next;
};

struct hashset {
    struct hashset_entry *buckets[HASHSET_SIZE];
};

static unsigned hash_str(const char *s)
{
    unsigned h = 5381;
    while (*s)
        h = ((h << 5) + h) + (unsigned char)*s++;
    return h % HASHSET_SIZE;
}

static struct hashset_entry *hashset_find(struct hashset *hs, const char *key)
{
    unsigned h = hash_str(key);
    for (struct hashset_entry *e = hs->buckets[h]; e; e = e->next) {
        if (strcmp(e->key, key) == 0)
            return e;
    }
    return NULL;
}

static struct hashset_entry *hashset_add(struct hashset *hs, const char *key,
                                          const char *value)
{
    struct hashset_entry *e = hashset_find(hs, key);
    if (e)
        return e;

    e = calloc(1, sizeof(*e));
    e->key = strdup(key);
    e->value = value ? strdup(value) : NULL;
    e->locs = NULL;
    unsigned h = hash_str(key);
    e->next = hs->buckets[h];
    hs->buckets[h] = e;
    return e;
}

static void hashset_add_loc(struct hashset_entry *e, const char *file, int line)
{
    char loc[512];
    snprintf(loc, sizeof(loc), "%s:%d", file, line);

    if (e->locs) {
        size_t old_len = strlen(e->locs);
        size_t loc_len = strlen(loc);
        char *new_locs = realloc(e->locs, old_len + 1 + loc_len + 1);
        if (new_locs) {
            new_locs[old_len] = ' ';
            memcpy(new_locs + old_len + 1, loc, loc_len + 1);
            e->locs = new_locs;
        }
    } else {
        e->locs = strdup(loc);
    }
}

static int hashset_keys_sorted(struct hashset *hs, const char **out, int max)
{
    int n = 0;
    for (int i = 0; i < HASHSET_SIZE && n < max; i++) {
        for (struct hashset_entry *e = hs->buckets[i]; e && n < max; e = e->next)
            out[n++] = e->key;
    }
    for (int i = 0; i < n - 1; i++) {
        for (int j = i + 1; j < n; j++) {
            if (strcmp(out[i], out[j]) > 0) {
                const char *tmp = out[i];
                out[i] = out[j];
                out[j] = tmp;
            }
        }
    }
    return n;
}

/* ------------------------------------------------------------------ */
/* Output modes                                                        */
/* ------------------------------------------------------------------ */

enum output_mode {
    MODE_REPORT,
    MODE_APPLETS,
    MODE_MODULES,
    MODE_CMAKE,
    MODE_JSON,
    MODE_RAW
};

static void usage(const char *prog, int code)
{
    fprintf(stderr,
        "busyq-scan - Analyze bash scripts for busyq custom builds\n"
        "\n"
        "Usage: %s [options] <script> [script...]\n"
        "\n"
        "Parses bash scripts using bash's own parser and reports:\n"
        "  - Commands available as busyq applets (with module info)\n"
        "  - Bash builtins (always available, no applet needed)\n"
        "  - Path-based invocations (always use external binary)\n"
        "  - External commands not available in busyq\n"
        "  - eval/source warnings (opaque or indirect command execution)\n"
        "  - Function definitions within the script\n"
        "\n"
        "Options:\n"
        "  --applets       List only busyq applet names needed (one per line)\n"
        "  --modules       List only busyq module names needed (one per line)\n"
        "  --cmake         Output a cmake -D definition for BUSYQ_APPLETS\n"
        "  --json          Output in JSON format\n"
        "  --raw           Output raw tab-separated records\n"
        "  -q, --quiet     Suppress informational output\n"
        "  -h, --help      Show this help\n",
        prog);
    exit(code);
}

/* ------------------------------------------------------------------ */
/* JSON helpers                                                        */
/* ------------------------------------------------------------------ */

static void json_escape_print(const char *s)
{
    while (*s) {
        if (*s == '"') fputs("\\\"", stdout);
        else if (*s == '\\') fputs("\\\\", stdout);
        else if (*s == '\n') fputs("\\n", stdout);
        else if (*s == '\t') fputs("\\t", stdout);
        else putchar(*s);
        s++;
    }
}

/* ------------------------------------------------------------------ */
/* atexit handler — classify and output results                        */
/*                                                                     */
/* bash_main() calls exit() when done parsing, so we cannot run code   */
/* after bash_main() returns.  Instead we register this handler via    */
/* atexit() before calling bash_main().                                */
/* ------------------------------------------------------------------ */

static enum output_mode g_mode = MODE_REPORT;
static int g_quiet = 0;
static int g_num_files = 0;
static int g_output_done = 0;
static int g_is_child = 0;  /* set in forked children to suppress scan_output */

static void scan_output(void)
{
    if (g_output_done || g_is_child) return;
    g_output_done = 1;

    enum output_mode mode = g_mode;
    int quiet = g_quiet;
    int num_files = g_num_files;

    /* ---- Raw mode ---- */
    if (mode == MODE_RAW) {
        static const char *type_names[] = { "CMD", "EVAL", "SOURCE", "FUNC", "PATH" };
        for (struct scan_record *r = scan_results; r; r = r->next)
            printf("%s\t%s\t%s\t%d\n", type_names[r->type], r->value, r->file, r->line);
        return;
    }

    /* ---- Classify ---- */
    struct hashset funcs = {0}, builtins_used = {0}, cmd_applets = {0};
    struct hashset externals = {0}, paths = {0}, evals = {0};
    struct hashset sources_found = {0}, modules = {0};

    for (struct scan_record *r = scan_results; r; r = r->next) {
        if (r->type == SCAN_FUNC) {
            struct hashset_entry *e = hashset_add(&funcs, r->value, NULL);
            hashset_add_loc(e, r->file, r->line);
        }
    }

    for (struct scan_record *r = scan_results; r; r = r->next) {
        switch (r->type) {
        case SCAN_CMD:
            if (is_shell_keyword(r->value)) break;
            if (hashset_find(&funcs, r->value)) break;
            if (is_bash_builtin(r->value)) {
                struct hashset_entry *e = hashset_add(&builtins_used, r->value, NULL);
                hashset_add_loc(e, r->file, r->line);
                break;
            }
            {
                const char *mod = find_applet_module(r->value);
                if (mod) {
                    struct hashset_entry *e = hashset_add(&cmd_applets, r->value, mod);
                    hashset_add_loc(e, r->file, r->line);
                    hashset_add(&modules, mod, NULL);
                    break;
                }
            }
            {
                struct hashset_entry *e = hashset_add(&externals, r->value, NULL);
                hashset_add_loc(e, r->file, r->line);
            }
            break;
        case SCAN_EVAL: {
            char key[512];
            snprintf(key, sizeof(key), "%s:%d", r->file, r->line);
            hashset_add(&evals, key, r->value);
            break;
        }
        case SCAN_SOURCE: {
            char key[512];
            snprintf(key, sizeof(key), "%s:%d", r->file, r->line);
            hashset_add(&sources_found, key, r->value);
            break;
        }
        case SCAN_PATH: {
            struct hashset_entry *e = hashset_add(&paths, r->value, NULL);
            hashset_add_loc(e, r->file, r->line);
            break;
        }
        case SCAN_FUNC:
            break;
        }
    }

    /* ---- Output ---- */
    const char *keys[1024];
    int nkeys;

    if (mode == MODE_APPLETS) {
        nkeys = hashset_keys_sorted(&cmd_applets, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n", keys[k]);
        return;
    }

    if (mode == MODE_MODULES) {
        nkeys = hashset_keys_sorted(&modules, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n", keys[k]);
        return;
    }

    if (mode == MODE_CMAKE) {
        nkeys = hashset_keys_sorted(&cmd_applets, keys, 1024);
        printf("-DBUSYQ_APPLETS=");
        for (int k = 0; k < nkeys; k++) {
            if (k > 0) putchar(';');
            printf("%s", keys[k]);
        }
        putchar('\n');
        return;
    }

    if (mode == MODE_JSON) {
        printf("{\n");
        printf("  \"applets\": {");
        nkeys = hashset_keys_sorted(&cmd_applets, keys, 1024);
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&cmd_applets, keys[k]);
            printf("%s\n    \"%s\": \"%s\"", k ? "," : "", keys[k], e->value ? e->value : "");
        }
        printf("\n  },\n  \"builtins\": [");
        nkeys = hashset_keys_sorted(&builtins_used, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n    \"%s\"", k ? "," : "", keys[k]);
        printf("\n  ],\n  \"functions\": [");
        nkeys = hashset_keys_sorted(&funcs, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n    \"%s\"", k ? "," : "", keys[k]);
        printf("\n  ],\n  \"external\": [");
        nkeys = hashset_keys_sorted(&externals, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n    \"%s\"", k ? "," : "", keys[k]);
        printf("\n  ],\n  \"path_invocations\": [");
        nkeys = hashset_keys_sorted(&paths, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n    \"%s\"", k ? "," : "", keys[k]);
        printf("\n  ],\n  \"eval_warnings\": [");
        nkeys = hashset_keys_sorted(&evals, keys, 1024);
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&evals, keys[k]);
            printf("%s\n    {\"location\": \"%s\", \"expression\": \"", k ? "," : "", keys[k]);
            json_escape_print(e->value ? e->value : "");
            printf("\"}");
        }
        printf("\n  ],\n  \"source_files\": [");
        nkeys = hashset_keys_sorted(&sources_found, keys, 1024);
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&sources_found, keys[k]);
            printf("%s\n    {\"location\": \"%s\", \"path\": \"", k ? "," : "", keys[k]);
            json_escape_print(e->value ? e->value : "");
            printf("\"}");
        }
        printf("\n  ],\n  \"modules\": [");
        nkeys = hashset_keys_sorted(&modules, keys, 1024);
        for (int k = 0; k < nkeys; k++)
            printf("%s\n    \"%s\"", k ? "," : "", keys[k]);
        printf("\n  ]\n}\n");
        return;
    }

    /* ---- Human-readable report ---- */
    printf("busyq-scan: analyzed %d file(s)\n\n", num_files);

    nkeys = hashset_keys_sorted(&cmd_applets, keys, 1024);
    if (nkeys > 0) {
        printf("Busyq applets needed (%d):\n", nkeys);
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&cmd_applets, keys[k]);
            printf("  %-20s [%s]\n", keys[k], e->value ? e->value : "?");
        }
        printf("\n");
    }

    if (!quiet) {
        nkeys = hashset_keys_sorted(&builtins_used, keys, 1024);
        if (nkeys > 0) {
            printf("Bash builtins (always available):\n ");
            for (int k = 0; k < nkeys; k++)
                printf(" %s", keys[k]);
            printf("\n\n");
        }

        nkeys = hashset_keys_sorted(&funcs, keys, 1024);
        if (nkeys > 0) {
            printf("Functions defined in script:\n");
            for (int k = 0; k < nkeys; k++) {
                struct hashset_entry *e = hashset_find(&funcs, keys[k]);
                printf("  %s  (%s)\n", keys[k], e->locs ? e->locs : "");
            }
            printf("\n");
        }
    }

    nkeys = hashset_keys_sorted(&evals, keys, 1024);
    if (nkeys > 0) {
        printf("WARNING: eval usage detected (commands inside eval cannot be analyzed):\n");
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&evals, keys[k]);
            printf("  %s: eval %s\n", keys[k], e->value ? e->value : "");
        }
        printf("\n");
    }

    nkeys = hashset_keys_sorted(&paths, keys, 1024);
    if (nkeys > 0) {
        printf("WARNING: Path-based invocations (always use external binary):\n");
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&paths, keys[k]);
            printf("  %s  (%s)\n", keys[k], e->locs ? e->locs : "");
        }
        printf("\n");
    }

    nkeys = hashset_keys_sorted(&sources_found, keys, 1024);
    if (nkeys > 0) {
        printf("NOTE: Sourced files (should also be scanned):\n");
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&sources_found, keys[k]);
            printf("  %s: source %s\n", keys[k], e->value ? e->value : "");
        }
        printf("\n");
    }

    nkeys = hashset_keys_sorted(&externals, keys, 1024);
    if (nkeys > 0) {
        printf("External commands (not available in busyq):\n");
        for (int k = 0; k < nkeys; k++) {
            struct hashset_entry *e = hashset_find(&externals, keys[k]);
            printf("  %s  (%s)\n", keys[k], e->locs ? e->locs : "");
        }
        printf("\n");
    }

    printf("---\n");
    nkeys = hashset_keys_sorted(&modules, keys, 1024);
    if (nkeys > 0) {
        printf("Busyq modules needed:");
        for (int k = 0; k < nkeys; k++) {
            if (k > 0) putchar(',');
            printf(" %s", keys[k]);
        }
        printf("\n");
    }

    nkeys = hashset_keys_sorted(&cmd_applets, keys, 1024);
    if (nkeys > 0) {
        printf("\nTo build a minimal busyq for these scripts:\n");
        printf("  cmake --preset no-ssl -DBUSYQ_APPLETS=\"");
        for (int k = 0; k < nkeys; k++) {
            if (k > 0) putchar(';');
            printf("%s", keys[k]);
        }
        printf("\"\n");
    }
    printf("\n");
}

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    enum output_mode mode = MODE_REPORT;
    int quiet = 0;
    int file_start = 0;
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--applets") == 0) mode = MODE_APPLETS;
        else if (strcmp(argv[i], "--modules") == 0) mode = MODE_MODULES;
        else if (strcmp(argv[i], "--cmake") == 0) mode = MODE_CMAKE;
        else if (strcmp(argv[i], "--json") == 0) mode = MODE_JSON;
        else if (strcmp(argv[i], "--raw") == 0) mode = MODE_RAW;
        else if (strcmp(argv[i], "-q") == 0 || strcmp(argv[i], "--quiet") == 0) quiet = 1;
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) usage(argv[0], 0);
        else if (argv[i][0] == '-' && strcmp(argv[i], "--") != 0) {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            usage(argv[0], 1);
        }
        else { if (strcmp(argv[i], "--") == 0) i++; break; }
    }
    file_start = i;

    if (file_start >= argc) {
        fprintf(stderr, "Error: no input files\n");
        usage(argv[0], 1);
    }

    /* bash_main() calls exit() when done parsing, so we register our
     * output handler via atexit() and set globals for it to use. */
    int num_files = argc - file_start;
    g_mode = mode;
    g_quiet = quiet;
    g_num_files = num_files;
    atexit(scan_output);

    for (int fi = file_start; fi < argc; fi++) {
        if (access(argv[fi], R_OK) != 0) {
            fprintf(stderr, "Error: cannot read file: %s\n", argv[fi]);
            __real_exit(2);
        }
        busyq_scan_filename = argv[fi];
        char *bash_argv[] = { argv[0], "-n", argv[fi], NULL };

        if (fi < argc - 1) {
            /* Non-final file: fork child to parse, collect via pipe */
            int pipefd[2];
            if (pipe(pipefd) < 0) {
                perror("pipe");
                __real_exit(2);
            }
            pid_t pid = fork();
            if (pid < 0) {
                perror("fork");
                __real_exit(2);
            }
            if (pid == 0) {
                /* Child: register pipe writer, then let bash parse.
                 * bash_main → exit() → atexit handlers → child_write_records */
                close(pipefd[0]);
                g_is_child = 1;
                child_pipe_fd = pipefd[1];
                atexit(child_write_records);
                bash_main(3, bash_argv, environ);
                _exit(0); /* shouldn't reach here */
            }
            /* Parent: close write end, read records from pipe */
            close(pipefd[1]);
            collect_records(pipefd[0]);
            waitpid(pid, NULL, 0);
        } else {
            /* Final file: parse in this process (atexit fires on exit) */
            bash_main(3, bash_argv, environ);
        }
    }

    return 0;
}
