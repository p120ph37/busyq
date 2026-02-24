/*
 * ssl_client_mbedtls.c - TLS tunnel using mbedtls for busybox wget HTTPS
 *
 * Drop-in replacement for busybox's ssl_client applet.  Busybox wget
 * forks this helper and passes it an already-connected TCP socket FD.
 * We wrap the socket in a TLS session and proxy cleartext between
 * stdin/stdout (back to wget) and the encrypted socket.
 *
 * Usage: ssl_client [-e] -s FD [-r FD] [-n SNI_HOSTNAME]
 *
 *   -s FD   Socket file descriptor (for both read and write)
 *   -r FD   Separate read FD (defaults to value of -s)
 *   -n SNI  Server name for TLS SNI extension
 *   -e      (ignored, kept for busybox compat)
 *
 * Only compiled when BUSYQ_SSL is defined (i.e. the mbedtls build).
 */

#include <mbedtls/ssl.h>
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/x509_crt.h>
#include <mbedtls/error.h>

#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef BUSYQ_EMBEDDED_CERTS
#include "embedded_certs.h"
#endif

/* ---- Custom BIO callbacks for an existing socket FD ---- */

static int net_send(void *ctx, const unsigned char *buf, size_t len)
{
    int fd = *(int *)ctx;
    ssize_t ret = write(fd, buf, len);
    if (ret < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        return MBEDTLS_ERR_NET_SEND_FAILED;
    }
    return (int)ret;
}

static int net_recv(void *ctx, unsigned char *buf, size_t len)
{
    int fd = *(int *)ctx;
    ssize_t ret = read(fd, buf, len);
    if (ret < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return MBEDTLS_ERR_SSL_WANT_READ;
        return MBEDTLS_ERR_NET_RECV_FAILED;
    }
    if (ret == 0)
        return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
    return (int)ret;
}

/* ---- Entry point ---- */

int ssl_client_main(int argc, char **argv)
{
    int write_fd = -1, read_fd = -1;
    const char *sni = NULL;
    int opt, ret;

    while ((opt = getopt(argc, argv, "es:r:n:")) != -1) {
        switch (opt) {
        case 's': write_fd = atoi(optarg); break;
        case 'r': read_fd  = atoi(optarg); break;
        case 'n': sni      = optarg;       break;
        case 'e': /* ignored */            break;
        default:  return 1;
        }
    }

    if (write_fd < 0) {
        static const char msg[] = "ssl_client: -s FD required\n";
        (void)write(STDERR_FILENO, msg, sizeof(msg) - 1);
        return 1;
    }
    if (read_fd < 0)
        read_fd = write_fd;

    /* Initialise mbedtls contexts */
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_x509_crt cacert;

    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_config_init(&conf);
    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_x509_crt_init(&cacert);

    ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func,
                                 &entropy, NULL, 0);
    if (ret != 0) goto cleanup;

    ret = mbedtls_ssl_config_defaults(&conf,
            MBEDTLS_SSL_IS_CLIENT,
            MBEDTLS_SSL_TRANSPORT_STREAM,
            MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) goto cleanup;

    /* CA certificate verification */
#ifdef BUSYQ_EMBEDDED_CERTS
    ret = mbedtls_x509_crt_parse(&cacert,
            (const unsigned char *)busyq_embedded_cacerts,
            strlen(busyq_embedded_cacerts) + 1);
    if (ret >= 0) {   /* ret > 0 means some certs skipped, still usable */
        mbedtls_ssl_conf_ca_chain(&conf, &cacert, NULL);
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_OPTIONAL);
    } else {
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
    }
#else
    mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
#endif

    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);

    ret = mbedtls_ssl_setup(&ssl, &conf);
    if (ret != 0) goto cleanup;

    if (sni) {
        ret = mbedtls_ssl_set_hostname(&ssl, sni);
        if (ret != 0) goto cleanup;
    }

    /* Attach the existing TCP socket via custom BIO callbacks */
    mbedtls_ssl_set_bio(&ssl, &write_fd, net_send, net_recv, NULL);

    /* TLS handshake */
    while ((ret = mbedtls_ssl_handshake(&ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ &&
            ret != MBEDTLS_ERR_SSL_WANT_WRITE)
            goto cleanup;
    }

    /* Proxy loop: stdin <-> TLS socket */
    {
        struct pollfd pfds[2];
        unsigned char buf[8192];

        pfds[0].fd = STDIN_FILENO;
        pfds[0].events = POLLIN;
        pfds[1].fd = read_fd;
        pfds[1].events = POLLIN;

        for (;;) {
            if (poll(pfds, 2, -1) < 0) {
                if (errno == EINTR) continue;
                break;
            }

            /* stdin → TLS (cleartext from wget → encrypted to server) */
            if (pfds[0].revents & POLLIN) {
                ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
                if (n <= 0) break;
                int off = 0;
                while (off < (int)n) {
                    ret = mbedtls_ssl_write(&ssl, buf + off, n - off);
                    if (ret <= 0) goto done;
                    off += ret;
                }
            }
            if (pfds[0].revents & (POLLHUP | POLLERR))
                break;

            /* TLS → stdout (encrypted from server → cleartext to wget) */
            if (pfds[1].revents & (POLLIN | POLLHUP)) {
                ret = mbedtls_ssl_read(&ssl, buf, sizeof(buf));
                if (ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || ret == 0)
                    break;
                if (ret < 0) {
                    if (ret == MBEDTLS_ERR_SSL_WANT_READ) continue;
                    break;
                }
                (void)write(STDOUT_FILENO, buf, ret);
            }
        }
    }

done:
    mbedtls_ssl_close_notify(&ssl);
    ret = 0;  /* normal proxy termination */

cleanup:
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    mbedtls_x509_crt_free(&cacert);

    return ret != 0 ? 1 : 0;
}
