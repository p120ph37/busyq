/* nc.c - minimal netcat implementation for busyq
 *
 * Provides core netcat functionality:
 *   - TCP connect mode: nc host port
 *   - TCP listen mode:  nc -l -p port
 *   - Bidirectional stdin/stdout relay via poll()
 *   - IPv4 and IPv6 support
 *
 * This is a standalone implementation with no external dependencies
 * beyond POSIX/libc, avoiding the complexity of pulling in nmap's ncat
 * or OpenBSD netcat with their build system dependencies.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>

static void relay(int sock)
{
    struct pollfd fds[2];
    char buf[8192];
    ssize_t n;

    fds[0].fd = STDIN_FILENO;
    fds[0].events = POLLIN;
    fds[1].fd = sock;
    fds[1].events = POLLIN;

    while (poll(fds, 2, -1) > 0) {
        if (fds[0].revents & POLLIN) {
            n = read(STDIN_FILENO, buf, sizeof(buf));
            if (n <= 0)
                break;
            if (write(sock, buf, n) != n)
                break;
        }
        if (fds[1].revents & POLLIN) {
            n = read(sock, buf, sizeof(buf));
            if (n <= 0)
                break;
            if (write(STDOUT_FILENO, buf, n) != n)
                break;
        }
        if (fds[0].revents & (POLLERR | POLLHUP))
            break;
        if (fds[1].revents & (POLLERR | POLLHUP))
            break;
    }
}

int main(int argc, char **argv)
{
    int listen_mode = 0, opt, port = 0, sock, ret;
    const char *host = NULL;

    signal(SIGPIPE, SIG_IGN);

    while ((opt = getopt(argc, argv, "lp:")) != -1) {
        switch (opt) {
        case 'l':
            listen_mode = 1;
            break;
        case 'p':
            port = atoi(optarg);
            break;
        default:
            fprintf(stderr, "Usage: nc [-l] [-p port] [host] [port]\n");
            return 1;
        }
    }

    if (!listen_mode) {
        /* Connect mode */
        if (optind + 1 < argc) {
            host = argv[optind];
            port = atoi(argv[optind + 1]);
        } else if (optind < argc && port) {
            host = argv[optind];
        } else {
            fprintf(stderr, "Usage: nc host port\n");
            return 1;
        }

        struct addrinfo hints = {0}, *res;
        char portstr[16];
        snprintf(portstr, sizeof(portstr), "%d", port);
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        ret = getaddrinfo(host, portstr, &hints, &res);
        if (ret) {
            fprintf(stderr, "nc: %s\n", gai_strerror(ret));
            return 1;
        }

        sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock < 0) {
            perror("socket");
            return 1;
        }
        if (connect(sock, res->ai_addr, res->ai_addrlen) < 0) {
            perror("connect");
            return 1;
        }
        freeaddrinfo(res);
    } else {
        /* Listen mode */
        if (!port && optind < argc)
            port = atoi(argv[optind]);
        if (!port) {
            fprintf(stderr, "nc: no port specified\n");
            return 1;
        }

        struct sockaddr_in6 addr = {0};
        addr.sin6_family = AF_INET6;
        addr.sin6_port = htons(port);
        addr.sin6_addr = in6addr_any;

        int srv = socket(AF_INET6, SOCK_STREAM, 0);
        if (srv < 0) {
            perror("socket");
            return 1;
        }
        int one = 1;
        setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        int zero = 0;
        setsockopt(srv, IPPROTO_IPV6, IPV6_V6ONLY, &zero, sizeof(zero));

        if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            perror("bind");
            return 1;
        }
        if (listen(srv, 1) < 0) {
            perror("listen");
            return 1;
        }

        sock = accept(srv, NULL, NULL);
        if (sock < 0) {
            perror("accept");
            return 1;
        }
        close(srv);
    }

    relay(sock);
    close(sock);
    return 0;
}
