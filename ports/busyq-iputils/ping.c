/* ping.c - minimal ICMP ping implementation for busyq
 *
 * Provides core ping functionality:
 *   - Send ICMP echo requests to a host
 *   - Receive ICMP echo replies
 *   - Print per-packet RTT and summary statistics
 *   - IPv4 support (IPPROTO_ICMP dgram socket, no raw socket needed)
 *   - Configurable count (-c) and timeout
 *
 * Uses IPPROTO_ICMP datagram sockets (Linux 3.0+) which do not require
 * CAP_NET_RAW or root privileges, making this work in unprivileged
 * distroless containers.
 *
 * This is a standalone implementation with no external dependencies
 * beyond POSIX/libc and Linux-specific ICMP socket support.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/ip_icmp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>

static volatile int running = 1;

static void handle_sigint(int sig)
{
    (void)sig;
    running = 0;
}

static unsigned short checksum(void *data, int len)
{
    unsigned short *buf = data;
    unsigned int sum = 0;
    unsigned short result;

    for (; len > 1; len -= 2)
        sum += *buf++;
    if (len == 1)
        sum += *(unsigned char *)buf;

    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);
    result = ~sum;
    return result;
}

static double tv_diff_ms(struct timeval *t1, struct timeval *t0)
{
    return (t1->tv_sec - t0->tv_sec) * 1000.0 +
           (t1->tv_usec - t0->tv_usec) / 1000.0;
}

int main(int argc, char **argv)
{
    int count = -1; /* -1 = infinite */
    int opt, sock, ret;
    const char *host;
    char ip_str[INET_ADDRSTRLEN];
    struct addrinfo hints = {0}, *res;
    struct sockaddr_in dest;
    int seq = 0, received = 0;
    double rtt_min = 1e9, rtt_max = 0, rtt_sum = 0;
    pid_t ident;

    while ((opt = getopt(argc, argv, "c:")) != -1) {
        switch (opt) {
        case 'c':
            count = atoi(optarg);
            break;
        default:
            fprintf(stderr, "Usage: ping [-c count] host\n");
            return 1;
        }
    }

    if (optind >= argc) {
        fprintf(stderr, "Usage: ping [-c count] host\n");
        return 1;
    }
    host = argv[optind];

    /* Resolve hostname */
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    ret = getaddrinfo(host, NULL, &hints, &res);
    if (ret) {
        fprintf(stderr, "ping: %s: %s\n", host, gai_strerror(ret));
        return 2;
    }

    memcpy(&dest, res->ai_addr, sizeof(dest));
    inet_ntop(AF_INET, &dest.sin_addr, ip_str, sizeof(ip_str));
    freeaddrinfo(res);

    /* Create ICMP datagram socket (unprivileged, Linux 3.0+) */
    sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (sock < 0) {
        /* Fallback: try raw socket (requires CAP_NET_RAW) */
        sock = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
        if (sock < 0) {
            fprintf(stderr, "ping: socket: %s (try running as root or with CAP_NET_RAW)\n",
                    strerror(errno));
            return 2;
        }
    }

    /* Set receive timeout */
    struct timeval tv_timeout = { .tv_sec = 1, .tv_usec = 0 };
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv_timeout, sizeof(tv_timeout));

    ident = getpid() & 0xFFFF;

    printf("PING %s (%s) 56 data bytes\n", host, ip_str);

    signal(SIGINT, handle_sigint);

    while (running && (count < 0 || seq < count)) {
        struct icmphdr icmp_req;
        struct timeval tv_send, tv_recv;
        char recv_buf[1024];
        struct sockaddr_in from;
        socklen_t fromlen = sizeof(from);
        ssize_t n;
        struct pollfd pfd;

        /* Build ICMP echo request */
        memset(&icmp_req, 0, sizeof(icmp_req));
        icmp_req.type = ICMP_ECHO;
        icmp_req.code = 0;
        icmp_req.un.echo.id = htons(ident);
        icmp_req.un.echo.sequence = htons(seq);
        icmp_req.checksum = 0;
        icmp_req.checksum = checksum(&icmp_req, sizeof(icmp_req));

        gettimeofday(&tv_send, NULL);

        if (sendto(sock, &icmp_req, sizeof(icmp_req), 0,
                   (struct sockaddr *)&dest, sizeof(dest)) < 0) {
            perror("ping: sendto");
            seq++;
            sleep(1);
            continue;
        }

        /* Wait for reply */
        pfd.fd = sock;
        pfd.events = POLLIN;

        if (poll(&pfd, 1, 1000) > 0 && (pfd.revents & POLLIN)) {
            n = recvfrom(sock, recv_buf, sizeof(recv_buf), 0,
                         (struct sockaddr *)&from, &fromlen);
            if (n >= (ssize_t)sizeof(struct icmphdr)) {
                gettimeofday(&tv_recv, NULL);

                /* For DGRAM ICMP sockets, kernel strips the IP header;
                 * the received data starts with the ICMP header directly */
                struct icmphdr *reply = (struct icmphdr *)recv_buf;

                if (reply->type == ICMP_ECHOREPLY) {
                    double rtt = tv_diff_ms(&tv_recv, &tv_send);
                    char from_str[INET_ADDRSTRLEN];

                    inet_ntop(AF_INET, &from.sin_addr, from_str, sizeof(from_str));
                    printf("%zd bytes from %s: icmp_seq=%d time=%.1f ms\n",
                           n, from_str, seq, rtt);

                    received++;
                    rtt_sum += rtt;
                    if (rtt < rtt_min) rtt_min = rtt;
                    if (rtt > rtt_max) rtt_max = rtt;
                }
            }
        }

        seq++;

        /* Sleep 1 second between pings (unless this is the last one) */
        if (running && (count < 0 || seq < count))
            sleep(1);
    }

    close(sock);

    /* Print statistics */
    printf("\n--- %s ping statistics ---\n", host);
    printf("%d packets transmitted, %d received, %d%% packet loss\n",
           seq, received,
           seq > 0 ? (int)((seq - received) * 100 / seq) : 0);
    if (received > 0) {
        printf("rtt min/avg/max = %.3f/%.3f/%.3f ms\n",
               rtt_min, rtt_sum / received, rtt_max);
    }

    return received > 0 ? 0 : 1;
}
