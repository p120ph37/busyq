/* stubs.c - Stub implementations for optional iproute2 subsystems
 *
 * Provides no-op/error stubs for subsystems we don't build:
 * - color: terminal color output (lib/color.c may fail to compile)
 * - BPF/XDP: eBPF program loading (needs libelf/libbpf)
 * - VRF: virtual routing (needs libcap)
 * - _dlsym: static linking plugin resolution
 *
 * These stubs let the ip command link and run without these features.
 */

#include <stdio.h>
#include <stdarg.h>
#include <string.h>

/* --- Color stubs (lib/color.c) ---
 * Color output is cosmetic; stubs just print without color. */

int color_opt_is_always;

enum color_attr {
    COLOR_IFNAME,
    COLOR_MAC,
    COLOR_INET,
    COLOR_INET6,
    COLOR_OPERSTATE_UP,
    COLOR_OPERSTATE_DOWN,
    COLOR_NONE
};

void enable_color(void) {}
void check_enable_color(int color, int json) { (void)color; (void)json; }
int matches_color(const char *arg, int *val) { (void)arg; (void)val; return -1; }

int color_fprintf(FILE *fp, enum color_attr attr, const char *fmt, ...)
{
    va_list ap;
    int r;
    (void)attr;
    va_start(ap, fmt);
    r = vfprintf(fp, fmt, ap);
    va_end(ap);
    return r;
}

const char *oper_state_color(int state)
{
    (void)state;
    return "";
}

const char *ifa_family_color(int family)
{
    (void)family;
    return "";
}

int default_color_opt;

/* --- BPF stubs (lib/bpf_glue.c, lib/bpf_legacy.c) ---
 * BPF/XDP support requires libelf/libbpf which we don't build. */

const char *get_libbpf_version(void) { return "none"; }

int bpf_parse_and_load_common(void *cfg, void *ops, void *env, void *ifindex)
{
    (void)cfg; (void)ops; (void)env; (void)ifindex;
    fprintf(stderr, "BPF not supported in this build\n");
    return -1;
}

int bpf_dump_prog_info(FILE *fp, unsigned int id)
{
    (void)fp; (void)id;
    return 0;
}

/* lwt BPF stubs */
int lwt_parse_bpf(void *res, int type, int *argcp, char ***argvp)
{
    (void)res; (void)type; (void)argcp; (void)argvp;
    fprintf(stderr, "BPF LWT not supported in this build\n");
    return -1;
}

int xdp_parse(int *argc, char ***argv, void *obj, void *attr, int strict)
{
    (void)argc; (void)argv; (void)obj; (void)attr; (void)strict;
    fprintf(stderr, "XDP not supported in this build\n");
    return -1;
}

void xdp_dump(FILE *fp, void *xdp, int ifindex, int details)
{
    (void)fp; (void)xdp; (void)ifindex; (void)details;
}

/* --- VRF stubs (ip/ipvrf.c) ---
 * VRF support requires libcap which we don't build. */

void vrf_reset(void) {}

int do_ipvrf(int argc, char **argv)
{
    (void)argc; (void)argv;
    fprintf(stderr, "VRF not supported in this build\n");
    return -1;
}

/* --- Static dlsym stub ---
 * When NO_SHARED_LIBS is defined, iproute2 uses _dlsym() to resolve
 * link type plugins from a compiled-in table.  The build generates
 * dlsym_impl.c with the table and these functions. */
