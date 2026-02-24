/*
 * applet_table.c - Applet dispatch for busyq
 *
 * Each embedded tool has a renamed main() that we call from the forked
 * child process in bash's shell_execve().  New upstream packages are
 * added here as {name, main_func} entries.
 *
 * Multi-call packages (coreutils) use a single dispatch entry point
 * that routes based on argv[0], similar to how busybox worked.
 */

#include "applet_table.h"
#include <string.h>
#include <unistd.h>

/* External tool entry points */
extern int curl_main(int argc, char **argv);
extern int jq_main(int argc, char **argv);
extern int coreutils_main(int argc, char **argv);
#ifdef BUSYQ_SSL
extern int ssl_client_main(int argc, char **argv);
#endif

static int busyq_help_main(int argc, char **argv);

/*
 * Applet table.  For multi-call packages like coreutils, each command
 * name maps to the same dispatch function — it routes on argv[0].
 */
static const struct busyq_applet applets[] = {
    /* --- busyq meta --- */
    { "busyq",      busyq_help_main, 0 },

    /* --- curl & jq --- */
    { "curl",       curl_main,       0 },
    { "jq",         jq_main,         0 },
#ifdef BUSYQ_SSL
    { "ssl_client", ssl_client_main, 0 },
#endif

    /* --- GNU coreutils (single-binary dispatch on argv[0]) --- */
    { "arch",       coreutils_main, 0 },
    { "b2sum",      coreutils_main, 0 },
    { "base32",     coreutils_main, 0 },
    { "base64",     coreutils_main, 0 },
    { "basename",   coreutils_main, 0 },
    { "basenc",     coreutils_main, 0 },
    { "cat",        coreutils_main, 0 },
    { "chcon",      coreutils_main, 0 },
    { "chgrp",      coreutils_main, 0 },
    { "chmod",      coreutils_main, 0 },
    { "chown",      coreutils_main, 0 },
    { "chroot",     coreutils_main, 0 },
    { "cksum",      coreutils_main, 0 },
    { "comm",       coreutils_main, 0 },
    { "cp",         coreutils_main, 0 },
    { "csplit",     coreutils_main, 0 },
    { "cut",        coreutils_main, 0 },
    { "date",       coreutils_main, 0 },
    { "dd",         coreutils_main, 0 },
    { "df",         coreutils_main, 0 },
    { "dir",        coreutils_main, 0 },
    { "dircolors",  coreutils_main, 0 },
    { "dirname",    coreutils_main, 0 },
    { "du",         coreutils_main, 0 },
    { "echo",       coreutils_main, 0 },
    { "env",        coreutils_main, 0 },
    { "expand",     coreutils_main, 0 },
    { "expr",       coreutils_main, 0 },
    { "factor",     coreutils_main, 0 },
    { "false",      coreutils_main, 0 },
    { "fmt",        coreutils_main, 0 },
    { "fold",       coreutils_main, 0 },
    { "groups",     coreutils_main, 0 },
    { "head",       coreutils_main, 0 },
    { "hostid",     coreutils_main, 0 },
    { "id",         coreutils_main, 0 },
    { "install",    coreutils_main, 0 },
    { "join",       coreutils_main, 0 },
    { "kill",       coreutils_main, 0 },
    { "link",       coreutils_main, 0 },
    { "ln",         coreutils_main, 0 },
    { "logname",    coreutils_main, 0 },
    { "ls",         coreutils_main, 0 },
    { "md5sum",     coreutils_main, 0 },
    { "mkdir",      coreutils_main, 0 },
    { "mkfifo",     coreutils_main, 0 },
    { "mknod",      coreutils_main, 0 },
    { "mktemp",     coreutils_main, 0 },
    { "mv",         coreutils_main, 0 },
    { "nice",       coreutils_main, 0 },
    { "nl",         coreutils_main, 0 },
    { "nohup",      coreutils_main, 0 },
    { "nproc",      coreutils_main, 0 },
    { "numfmt",     coreutils_main, 0 },
    { "od",         coreutils_main, 0 },
    { "paste",      coreutils_main, 0 },
    { "pathchk",    coreutils_main, 0 },
    { "pinky",      coreutils_main, 0 },
    { "pr",         coreutils_main, 0 },
    { "printenv",   coreutils_main, 0 },
    { "printf",     coreutils_main, 0 },
    { "ptx",        coreutils_main, 0 },
    { "pwd",        coreutils_main, 0 },
    { "readlink",   coreutils_main, 0 },
    { "realpath",   coreutils_main, 0 },
    { "rm",         coreutils_main, 0 },
    { "rmdir",      coreutils_main, 0 },
    { "runcon",     coreutils_main, 0 },
    { "seq",        coreutils_main, 0 },
    { "sha1sum",    coreutils_main, 0 },
    { "sha224sum",  coreutils_main, 0 },
    { "sha256sum",  coreutils_main, 0 },
    { "sha384sum",  coreutils_main, 0 },
    { "sha512sum",  coreutils_main, 0 },
    { "shred",      coreutils_main, 0 },
    { "shuf",       coreutils_main, 0 },
    { "sleep",      coreutils_main, 0 },
    { "sort",       coreutils_main, 0 },
    { "split",      coreutils_main, 0 },
    { "stat",       coreutils_main, 0 },
    { "stty",       coreutils_main, 0 },
    { "sum",        coreutils_main, 0 },
    { "sync",       coreutils_main, 0 },
    { "tac",        coreutils_main, 0 },
    { "tail",       coreutils_main, 0 },
    { "tee",        coreutils_main, 0 },
    { "test",       coreutils_main, 0 },
    { "[",          coreutils_main, 0 },
    { "timeout",    coreutils_main, 0 },
    { "touch",      coreutils_main, 0 },
    { "tr",         coreutils_main, 0 },
    { "true",       coreutils_main, 0 },
    { "truncate",   coreutils_main, 0 },
    { "tsort",      coreutils_main, 0 },
    { "tty",        coreutils_main, 0 },
    { "uname",      coreutils_main, 0 },
    { "unexpand",   coreutils_main, 0 },
    { "uniq",       coreutils_main, 0 },
    { "unlink",     coreutils_main, 0 },
    { "uptime",     coreutils_main, 0 },
    { "users",      coreutils_main, 0 },
    { "vdir",       coreutils_main, 0 },
    { "wc",         coreutils_main, 0 },
    { "who",        coreutils_main, 0 },
    { "whoami",     coreutils_main, 0 },
    { "yes",        coreutils_main, 0 },
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
