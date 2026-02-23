/*
 * busyq - Single-binary bash+curl+jq+busybox
 *
 * Entry point: always launches bash. We do NOT parse argv[0] for
 * busybox-style applet dispatch. However, bash's own argv[0] semantics
 * are preserved: if basename(argv[0]) is "sh", bash enters POSIX mode.
 */

/* Declared in bash's shell.h, but we just need the prototype */
extern int bash_main(int argc, char **argv);

int main(int argc, char **argv) {
    return bash_main(argc, argv);
}
