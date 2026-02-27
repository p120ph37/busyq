/*
 * applet_table.c - Applet dispatch for busyq
 *
 * Each embedded tool has a renamed main() that we call from the forked
 * child process in bash's shell_execve().  New upstream packages are
 * added here as {name, main_func} entries.
 *
 * Multi-call packages (coreutils, gzip, bzip2, xz, dos2unix, hostname)
 * use a single dispatch entry point that routes based on argv[0].
 * Multi-binary packages (diffutils, findutils, bc, sharutils, procps,
 * psmisc) expose separate entry points for each command.
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

/* Phase 2: Text processing */
extern int gawk_main(int argc, char **argv);
extern int sed_main(int argc, char **argv);
extern int grep_main(int argc, char **argv);
extern int diff_main(int argc, char **argv);
extern int cmp_main(int argc, char **argv);
extern int diff3_main(int argc, char **argv);
extern int sdiff_main(int argc, char **argv);
extern int find_main(int argc, char **argv);
extern int xargs_main(int argc, char **argv);
extern int ed_main(int argc, char **argv);
extern int patch_main(int argc, char **argv);

/* Phase 3: Archival */
extern int tar_main(int argc, char **argv);
extern int gzip_main(int argc, char **argv);
extern int bzip2_main(int argc, char **argv);
extern int xz_main(int argc, char **argv);
extern int cpio_main(int argc, char **argv);
extern int lzop_main(int argc, char **argv);
extern int zip_main(int argc, char **argv);
extern int unzip_main(int argc, char **argv);

/* Phase 4: Small standalone tools */
extern int bc_main(int argc, char **argv);
extern int dc_main(int argc, char **argv);
extern int less_main(int argc, char **argv);
extern int strings_main(int argc, char **argv);
extern int time_main(int argc, char **argv);
extern int dos2unix_main(int argc, char **argv);
extern int uuencode_main(int argc, char **argv);
extern int uudecode_main(int argc, char **argv);
extern int tset_main(int argc, char **argv);
extern int which_main(int argc, char **argv);

/* Phase 5: Networking */
extern int wget_main(int argc, char **argv);
extern int nc_main(int argc, char **argv);
extern int ping_main(int argc, char **argv);
extern int hostname_main(int argc, char **argv);
extern int whois_main(int argc, char **argv);

/* Phase 6: Process utilities */
extern int ps_main(int argc, char **argv);
extern int free_main(int argc, char **argv);
extern int top_main(int argc, char **argv);
extern int pgrep_main(int argc, char **argv);
extern int pkill_main(int argc, char **argv);
extern int pidof_main(int argc, char **argv);
extern int pmap_main(int argc, char **argv);
extern int pwdx_main(int argc, char **argv);
extern int watch_main(int argc, char **argv);
extern int sysctl_main(int argc, char **argv);
extern int vmstat_main(int argc, char **argv);
extern int killall_main(int argc, char **argv);
extern int fuser_main(int argc, char **argv);
extern int pstree_main(int argc, char **argv);
extern int lsof_main(int argc, char **argv);

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

    /* --- Phase 2: Text processing --- */
    { "awk",        gawk_main,      0 },
    { "gawk",       gawk_main,      0 },
    { "sed",        sed_main,       0 },
    { "grep",       grep_main,      0 },
    { "egrep",      grep_main,      0 },
    { "fgrep",      grep_main,      0 },
    { "diff",       diff_main,      0 },
    { "cmp",        cmp_main,       0 },
    { "diff3",      diff3_main,     0 },
    { "sdiff",      sdiff_main,     0 },
    { "find",       find_main,      0 },
    { "xargs",      xargs_main,     0 },
    { "ed",         ed_main,        0 },
    { "patch",      patch_main,     0 },

    /* --- Phase 3: Archival --- */
    { "tar",        tar_main,       0 },
    { "gzip",       gzip_main,      0 },
    { "gunzip",     gzip_main,      0 },
    { "zcat",       gzip_main,      0 },
    { "bzip2",      bzip2_main,     0 },
    { "bunzip2",    bzip2_main,     0 },
    { "bzcat",      bzip2_main,     0 },
    { "xz",         xz_main,        0 },
    { "unxz",       xz_main,        0 },
    { "xzcat",      xz_main,        0 },
    { "lzma",       xz_main,        0 },
    { "unlzma",     xz_main,        0 },
    { "lzcat",      xz_main,        0 },
    { "cpio",       cpio_main,      0 },
    { "lzop",       lzop_main,      0 },
    { "zip",        zip_main,       0 },
    { "unzip",      unzip_main,     0 },

    /* --- Phase 4: Small standalone tools --- */
    { "bc",         bc_main,        0 },
    { "dc",         dc_main,        0 },
    { "less",       less_main,      0 },
    { "strings",    strings_main,   0 },
    { "time",       time_main,      0 },
    { "dos2unix",   dos2unix_main,  0 },
    { "unix2dos",   dos2unix_main,  0 },
    { "uuencode",   uuencode_main,  0 },
    { "uudecode",   uudecode_main,  0 },
    { "reset",      tset_main,      0 },
    { "tset",       tset_main,      0 },
    { "which",      which_main,     0 },

    /* --- Phase 5: Networking --- */
    { "wget",       wget_main,      0 },
    { "nc",         nc_main,        0 },
    { "ping",       ping_main,      0 },
    { "hostname",   hostname_main,  0 },
    { "dnsdomainname", hostname_main, 0 },
    { "whois",      whois_main,     0 },

    /* --- Phase 6: Process utilities --- */
    /* procps-ng (entry points dynamically named from object basenames) */
    { "ps",         ps_main,        0 },
    { "free",       free_main,      0 },
    { "top",        top_main,       0 },
    { "pgrep",      pgrep_main,     0 },
    { "pkill",      pkill_main,     0 },
    { "pidof",      pidof_main,     0 },
    { "pmap",       pmap_main,      0 },
    { "pwdx",       pwdx_main,      0 },
    { "watch",      watch_main,     0 },
    { "sysctl",     sysctl_main,    0 },
    { "vmstat",     vmstat_main,    0 },
    /* psmisc */
    { "killall",    killall_main,   0 },
    { "fuser",      fuser_main,     0 },
    { "pstree",     pstree_main,    0 },
    /* lsof */
    { "lsof",       lsof_main,      0 },
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
            "busyq - single-binary bash+curl+jq+coreutils+tools\n\n"
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
