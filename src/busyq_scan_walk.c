/*
 * busyq_scan_walk.c - AST walker for the busyq-scan binary
 *
 * This file is compiled during the bash port build (where bash's
 * internal headers are available) and packaged into libbusyq_scan.a.
 *
 * It provides __wrap_reader_loop(), which replaces bash's reader_loop()
 * via the linker's --wrap feature.  Instead of executing parsed commands,
 * it walks the AST and accumulates command references in a global list.
 *
 * Record types:
 *   SCAN_CMD      - Simple command reference
 *   SCAN_EVAL     - eval invocation (expression captured)
 *   SCAN_SOURCE   - source/. invocation (file path captured)
 *   SCAN_FUNC     - Function definition
 *   SCAN_PATH     - Path-based invocation (contains /)
 */

#include "config.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "bashtypes.h"
#include "command.h"
#include "shell.h"
#include "flags.h"
#include "dispose_cmd.h"
#include "bashjmp.h"
#include "externs.h"
#include "execute_cmd.h"

/* Shared header defining record types and the result list */
#include "busyq_scan.h"

/* The current filename being parsed, set by the scanner main. */
extern const char *busyq_scan_filename;

/* Global result list — accumulated during parsing, read after bash_main returns */
struct scan_record *scan_results = NULL;
struct scan_record **scan_results_tail = &scan_results;

/* ------------------------------------------------------------------ */
/* Result accumulation                                                 */
/* ------------------------------------------------------------------ */

static void record_add(enum scan_type type, const char *value, int line)
{
    const char *file = busyq_scan_filename ? busyq_scan_filename : "<stdin>";
    if (!value || !*value)
        return;

    struct scan_record *r = malloc(sizeof(*r));
    if (!r)
        return;
    r->type = type;
    r->value = strdup(value);
    r->file = file;  /* points to static/global string, no need to dup */
    r->line = line;
    r->next = NULL;

    *scan_results_tail = r;
    scan_results_tail = &r->next;
}

/* ------------------------------------------------------------------ */
/* AST walker                                                          */
/* ------------------------------------------------------------------ */

static void walk_command(COMMAND *cmd);

/*
 * Scan a word string for command substitution patterns $(...), <(...),
 * >(...), and `...`.  Extract the first token of each substitution as
 * a command reference.
 *
 * In -n mode, bash's parser does not expand these — the raw text is
 * preserved in the word.  We do a lightweight scan to find command
 * names inside substitutions.
 */
static void scan_word_for_subst(const char *word, int line)
{
    const char *p = word;
    if (!p)
        return;

    while (*p) {
        const char *cmd_start;
        int depth;

        if ((p[0] == '$' || p[0] == '<' || p[0] == '>') && p[1] == '(') {
            /* $(...) or <(...) or >(...) substitution */
            p += 2;
            /* Skip leading whitespace */
            while (*p == ' ' || *p == '\t')
                p++;
            /* Extract command name (first token) */
            cmd_start = p;
            while (*p && *p != ' ' && *p != '\t' && *p != ')' &&
                   *p != '|' && *p != ';' && *p != '\n')
                p++;
            if (p > cmd_start) {
                char cmd[256];
                int len = p - cmd_start;
                if (len > (int)sizeof(cmd) - 1)
                    len = sizeof(cmd) - 1;
                memcpy(cmd, cmd_start, len);
                cmd[len] = '\0';
                if (strchr(cmd, '/'))
                    record_add(SCAN_PATH, cmd, line);
                else if (cmd[0] != '$' && cmd[0] != '-' && cmd[0] != '#')
                    record_add(SCAN_CMD, cmd, line);
            }
            /* Scan remainder for nested substitutions */
            depth = 1;
            while (*p && depth > 0) {
                if ((p[0] == '$' || p[0] == '<' || p[0] == '>') && p[1] == '(') {
                    scan_word_for_subst(p, line);
                    p += 2;
                    int inner = 1;
                    while (*p && inner > 0) {
                        if (*p == '(') inner++;
                        else if (*p == ')') inner--;
                        if (inner > 0) p++;
                    }
                    if (*p == ')') { p++; depth--; }
                } else {
                    if (*p == '(') depth++;
                    else if (*p == ')') depth--;
                    if (depth > 0) p++;
                }
            }
            if (*p == ')') p++;
        } else if (*p == '`') {
            /* Backtick substitution */
            p++;
            while (*p == ' ' || *p == '\t')
                p++;
            cmd_start = p;
            while (*p && *p != '`' && *p != ' ' && *p != '\t' &&
                   *p != '|' && *p != ';')
                p++;
            if (p > cmd_start) {
                char cmd[256];
                int len = p - cmd_start;
                if (len > (int)sizeof(cmd) - 1)
                    len = sizeof(cmd) - 1;
                memcpy(cmd, cmd_start, len);
                cmd[len] = '\0';
                if (strchr(cmd, '/'))
                    record_add(SCAN_PATH, cmd, line);
                else if (cmd[0] != '$' && cmd[0] != '-' && cmd[0] != '#')
                    record_add(SCAN_CMD, cmd, line);
            }
            while (*p && *p != '`')
                p++;
            if (*p == '`') p++;
        } else {
            p++;
        }
    }
}

/*
 * Process a simple command's word list.
 * The first non-assignment word is the command name.
 */
static void walk_simple_command(SIMPLE_COM *s)
{
    WORD_LIST *w;
    const char *cmd_name = NULL;
    int line = s->line;

    /* First pass: scan ALL words (including assignments) for command
     * substitutions $(...), `...`, <(...), >(...)  */
    for (w = s->words; w; w = w->next) {
        if (w->word->word)
            scan_word_for_subst(w->word->word, line);
    }

    /* Second pass: find the command name (first non-assignment word) */
    for (w = s->words; w; w = w->next) {
        if (w->word->flags & W_ASSIGNMENT)
            continue;

        cmd_name = w->word->word;
        if (!cmd_name || !*cmd_name)
            continue;

        /* Path-based invocation */
        if (strchr(cmd_name, '/')) {
            record_add(SCAN_PATH, cmd_name, line);
            return;
        }

        /* eval — capture the rest as expression */
        if (strcmp(cmd_name, "eval") == 0) {
            char buf[4096];
            int pos = 0;
            WORD_LIST *r;
            for (r = w->next; r; r = r->next) {
                if (pos > 0 && pos < (int)sizeof(buf) - 1)
                    buf[pos++] = ' ';
                int len = strlen(r->word->word);
                if (pos + len < (int)sizeof(buf) - 1) {
                    memcpy(buf + pos, r->word->word, len);
                    pos += len;
                }
            }
            buf[pos] = '\0';
            record_add(SCAN_EVAL, pos > 0 ? buf : "(empty)", line);
            return;
        }

        /* source / . — next word is the file path */
        if (strcmp(cmd_name, "source") == 0 || strcmp(cmd_name, ".") == 0) {
            if (w->next && w->next->word && w->next->word->word)
                record_add(SCAN_SOURCE, w->next->word->word, line);
            return;
        }

        /* Normal command */
        record_add(SCAN_CMD, cmd_name, line);

        /* Commands that take another command as argument */
        {
            const char *base = strrchr(cmd_name, '/');
            base = base ? base + 1 : cmd_name;

            if (strcmp(base, "xargs") == 0 || strcmp(base, "nice") == 0 ||
                strcmp(base, "nohup") == 0 || strcmp(base, "env") == 0 ||
                strcmp(base, "sudo") == 0 || strcmp(base, "exec") == 0 ||
                strcmp(base, "command") == 0) {
                WORD_LIST *r;
                for (r = w->next; r; r = r->next) {
                    const char *arg = r->word->word;
                    if (!arg || !*arg)
                        continue;
                    if (arg[0] == '-')
                        continue;
                    if (r->word->flags & W_ASSIGNMENT)
                        continue;
                    if (strchr(arg, '/'))
                        record_add(SCAN_PATH, arg, line);
                    else
                        record_add(SCAN_CMD, arg, line);
                    break;
                }
            }
        }
        return;
    }
}

/*
 * Recursively walk a COMMAND AST node.
 */
static void walk_command(COMMAND *cmd)
{
    if (!cmd)
        return;

    switch (cmd->type) {
    case cm_simple:
        walk_simple_command(cmd->value.Simple);
        break;

    case cm_connection:
        walk_command(cmd->value.Connection->first);
        walk_command(cmd->value.Connection->second);
        break;

    case cm_for:
        walk_command(cmd->value.For->action);
        break;

    case cm_case: {
        PATTERN_LIST *p;
        for (p = cmd->value.Case->clauses; p; p = p->next)
            walk_command(p->action);
        break;
    }

    case cm_while:
    case cm_until:
        walk_command(cmd->value.While->test);
        walk_command(cmd->value.While->action);
        break;

    case cm_if:
        walk_command(cmd->value.If->test);
        walk_command(cmd->value.If->true_case);
        walk_command(cmd->value.If->false_case);
        break;

    case cm_function_def:
        record_add(SCAN_FUNC, cmd->value.Function_def->name->word,
                    cmd->value.Function_def->line);
        walk_command(cmd->value.Function_def->command);
        break;

    case cm_group:
        walk_command(cmd->value.Group->command);
        break;

    case cm_subshell:
        walk_command(cmd->value.Subshell->command);
        break;

    case cm_coproc:
        walk_command(cmd->value.Coproc->command);
        break;

#if defined (SELECT_COMMAND)
    case cm_select:
        walk_command(cmd->value.Select->action);
        break;
#endif

#if defined (ARITH_FOR_COMMAND)
    case cm_arith_for:
        walk_command(cmd->value.ArithFor->action);
        break;
#endif

#if defined (DPAREN_ARITHMETIC)
    case cm_arith:
        break;
#endif

#if defined (COND_COMMAND)
    case cm_cond:
        break;
#endif

    default:
        break;
    }
}

/* ------------------------------------------------------------------ */
/* __wrap_reader_loop — replacement for bash's reader_loop()            */
/* ------------------------------------------------------------------ */

int __wrap_reader_loop(void)
{
    COMMAND *current_command;
    int code;

    unset_readahead_token();

    while (EOF_Reached == 0) {
        code = setjmp_nosigs(top_level);
        if (code) {
            if (code == FORCE_EOF || code == EXITPROG || code == EXITBLTIN)
                break;
            if (code == DISCARD)
                continue;
            return (1);
        }

        if (read_command() == 0) {
            current_command = global_command;
            global_command = (COMMAND *)NULL;

            if (current_command) {
                walk_command(current_command);
                dispose_command(current_command);
            }
        } else {
            return (1);
        }
    }

    return (0);
}
