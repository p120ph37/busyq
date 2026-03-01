/* whois.c - minimal whois client for busyq
 *
 * Provides core whois functionality:
 *   - Query whois servers for domain/IP information
 *   - Default server: whois.iana.org (IANA referral service)
 *   - Custom server via -h flag
 *   - Automatic referral following (parses "refer:" lines)
 *
 * This is a standalone implementation with no external dependencies
 * beyond POSIX/libc, avoiding the complexity of Marco d'Itri's whois
 * with its extensive server routing tables.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netdb.h>
#include <errno.h>

#define WHOIS_PORT   "43"
#define DEFAULT_HOST "whois.iana.org"
#define BUF_SIZE     4096
#define MAX_REFERRALS 3

static int whois_query(const char *server, const char *query, int follow_referrals)
{
    struct addrinfo hints = {0}, *res;
    int sock, ret;
    char buf[BUF_SIZE];
    ssize_t n;
    char referral[256] = {0};

    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    ret = getaddrinfo(server, WHOIS_PORT, &hints, &res);
    if (ret) {
        fprintf(stderr, "whois: %s: %s\n", server, gai_strerror(ret));
        return 1;
    }

    sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sock < 0) {
        perror("whois: socket");
        freeaddrinfo(res);
        return 1;
    }

    if (connect(sock, res->ai_addr, res->ai_addrlen) < 0) {
        fprintf(stderr, "whois: connect to %s: %s\n", server, strerror(errno));
        close(sock);
        freeaddrinfo(res);
        return 1;
    }
    freeaddrinfo(res);

    /* Send query */
    dprintf(sock, "%s\r\n", query);

    /* Read and print response, looking for referral server */
    while ((n = read(sock, buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        fwrite(buf, 1, n, stdout);

        /* Look for referral in IANA responses: "refer:  whois.example.com" */
        if (follow_referrals && !referral[0]) {
            char *line = buf;
            while (line && *line) {
                if (strncasecmp(line, "refer:", 6) == 0) {
                    char *val = line + 6;
                    while (*val == ' ' || *val == '\t')
                        val++;
                    char *end = val;
                    while (*end && *end != '\r' && *end != '\n' && *end != ' ')
                        end++;
                    if (end > val && (size_t)(end - val) < sizeof(referral)) {
                        memcpy(referral, val, end - val);
                        referral[end - val] = '\0';
                    }
                    break;
                }
                /* Advance to next line */
                line = strchr(line, '\n');
                if (line)
                    line++;
            }
        }
    }

    close(sock);

    /* Follow referral if found */
    if (referral[0] && follow_referrals > 0) {
        printf("\n# Querying referral server: %s\n\n", referral);
        return whois_query(referral, query, follow_referrals - 1);
    }

    return 0;
}

int main(int argc, char **argv)
{
    const char *server = DEFAULT_HOST;
    const char *query;
    int opt;
    int no_referral = 0;

    while ((opt = getopt(argc, argv, "h:r")) != -1) {
        switch (opt) {
        case 'h':
            server = optarg;
            no_referral = 1; /* Don't follow referrals for explicit server */
            break;
        case 'r':
            no_referral = 1;
            break;
        default:
            fprintf(stderr, "Usage: whois [-h server] [-r] query\n");
            return 1;
        }
    }

    if (optind >= argc) {
        fprintf(stderr, "Usage: whois [-h server] [-r] query\n");
        return 1;
    }

    query = argv[optind];

    return whois_query(server, query, no_referral ? 0 : MAX_REFERRALS);
}
