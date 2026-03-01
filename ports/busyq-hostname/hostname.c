/* hostname.c - minimal hostname/dnsdomainname implementation for busyq
 *
 * Provides:
 *   - hostname:       print or set the system hostname
 *   - dnsdomainname:  print the DNS domain portion of the hostname
 *
 * Dispatches based on argv[0] (basename), so the same binary serves
 * both commands when registered in the busyq applet table.
 *
 * This is a standalone implementation with no external dependencies
 * beyond POSIX/libc, avoiding the need to pull in net-tools.
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>

int main(int argc, char **argv)
{
    char buf[256];
    const char *prog = argv[0];
    const char *p;
    int show_short = 0;
    int show_fqdn = 0;
    int show_domain = 0;
    int show_ip = 0;
    int opt;

    /* Get basename of argv[0] for multi-call dispatch */
    p = strrchr(prog, '/');
    if (p)
        prog = p + 1;

    /* If invoked as dnsdomainname, show domain only */
    if (strcmp(prog, "dnsdomainname") == 0)
        show_domain = 1;

    while ((opt = getopt(argc, argv, "sfdi")) != -1) {
        switch (opt) {
        case 's':
            show_short = 1;
            break;
        case 'f':
            show_fqdn = 1;
            break;
        case 'd':
            show_domain = 1;
            break;
        case 'i':
            show_ip = 1;
            break;
        default:
            fprintf(stderr,
                    "Usage: hostname [-s|-f|-d|-i] [newname]\n"
                    "       dnsdomainname\n");
            return 1;
        }
    }

    /* Set hostname if a non-option argument is given */
    if (optind < argc && !show_short && !show_fqdn && !show_domain && !show_ip) {
        if (sethostname(argv[optind], strlen(argv[optind])) < 0) {
            perror("hostname: sethostname");
            return 1;
        }
        return 0;
    }

    if (gethostname(buf, sizeof(buf)) < 0) {
        perror("hostname: gethostname");
        return 1;
    }
    buf[sizeof(buf) - 1] = '\0';

    if (show_fqdn || show_domain || show_ip) {
        /* Resolve to get FQDN */
        struct addrinfo hints = {0}, *res;
        char fqdn[256];

        hints.ai_family = AF_UNSPEC;
        hints.ai_flags = AI_CANONNAME;
        if (getaddrinfo(buf, NULL, &hints, &res) == 0 && res->ai_canonname) {
            strncpy(fqdn, res->ai_canonname, sizeof(fqdn) - 1);
            fqdn[sizeof(fqdn) - 1] = '\0';
            freeaddrinfo(res);
        } else {
            strncpy(fqdn, buf, sizeof(fqdn) - 1);
            fqdn[sizeof(fqdn) - 1] = '\0';
        }

        if (show_ip) {
            /* Resolve hostname to IP address */
            struct addrinfo hints2 = {0}, *res2;
            char ipbuf[64];

            hints2.ai_family = AF_UNSPEC;
            if (getaddrinfo(buf, NULL, &hints2, &res2) == 0) {
                if (getnameinfo(res2->ai_addr, res2->ai_addrlen,
                                ipbuf, sizeof(ipbuf), NULL, 0,
                                NI_NUMERICHOST) == 0) {
                    puts(ipbuf);
                }
                freeaddrinfo(res2);
            }
        } else if (show_domain) {
            char *dot = strchr(fqdn, '.');
            if (dot)
                puts(dot + 1);
            else
                puts("");
        } else {
            /* show_fqdn */
            puts(fqdn);
        }
    } else if (show_short) {
        /* Truncate at first dot */
        char *dot = strchr(buf, '.');
        if (dot)
            *dot = '\0';
        puts(buf);
    } else {
        puts(buf);
    }

    return 0;
}
