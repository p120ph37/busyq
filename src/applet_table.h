/*
 * applet_table.h - Applet dispatch interface for busyq
 *
 * Provides lookup for all embedded applets (curl, jq, and any future
 * upstream tools added as vcpkg overlay ports).  Each applet registers
 * a renamed main() function that is called from bash's shell_execve()
 * via the applet-execute patch.
 */

#ifndef BUSYQ_APPLET_TABLE_H
#define BUSYQ_APPLET_TABLE_H

/* Applet flags (reserved for future use) */
#define BUSYQ_APPLET_NOFORK  (1 << 0)
#define BUSYQ_APPLET_NOEXEC  (1 << 1)

typedef int (*applet_main_func)(int argc, char **argv);

struct busyq_applet {
    const char *name;
    applet_main_func main_func;
    unsigned int flags;
};

/*
 * Look up an applet by name.
 * Returns a pointer to the applet entry, or NULL if not found.
 */
const struct busyq_applet *busyq_find_applet(const char *name);

#endif /* BUSYQ_APPLET_TABLE_H */
