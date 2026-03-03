/* nslookup.c - DNS lookup utility for busyq
 *
 * Provides non-interactive DNS lookups using the system resolver.
 * Supports forward lookups (hostname -> address), reverse lookups
 * (address -> hostname), and specific record type queries.
 *
 * Output format matches ISC BIND's nslookup for compatibility.
 *
 * Usage:
 *   nslookup [-type=TYPE] HOST [SERVER]
 *
 * This is a standalone implementation using res_query() from libc,
 * avoiding the need to build ISC BIND.  On musl, the resolver is
 * part of libc (no -lresolv needed).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <netinet/in.h>
#include <resolv.h>
#include <netdb.h>

/* DNS record type constants (in case arpa/nameser.h doesn't define them all) */
#ifndef ns_t_a
#define ns_t_a      1
#define ns_t_ns     2
#define ns_t_cname  5
#define ns_t_soa    6
#define ns_t_ptr    12
#define ns_t_mx     15
#define ns_t_txt    16
#define ns_t_aaaa   28
#define ns_t_srv    33
#define ns_t_any    255
#endif

#ifndef ns_c_in
#define ns_c_in     1
#endif

static const char *type_to_str(int type)
{
    switch (type) {
    case ns_t_a:     return "A";
    case ns_t_ns:    return "NS";
    case ns_t_cname: return "CNAME";
    case ns_t_soa:   return "SOA";
    case ns_t_ptr:   return "PTR";
    case ns_t_mx:    return "MX";
    case ns_t_txt:   return "TXT";
    case ns_t_aaaa:  return "AAAA";
    case ns_t_srv:   return "SRV";
    default:         return "UNKNOWN";
    }
}

static int str_to_type(const char *s)
{
    if (!strcasecmp(s, "A"))     return ns_t_a;
    if (!strcasecmp(s, "AAAA"))  return ns_t_aaaa;
    if (!strcasecmp(s, "MX"))    return ns_t_mx;
    if (!strcasecmp(s, "NS"))    return ns_t_ns;
    if (!strcasecmp(s, "SOA"))   return ns_t_soa;
    if (!strcasecmp(s, "TXT"))   return ns_t_txt;
    if (!strcasecmp(s, "CNAME")) return ns_t_cname;
    if (!strcasecmp(s, "PTR"))   return ns_t_ptr;
    if (!strcasecmp(s, "SRV"))   return ns_t_srv;
    if (!strcasecmp(s, "ANY"))   return ns_t_any;
    return -1;
}

static int is_ipv4(const char *s)
{
    struct in_addr v4;
    return inet_pton(AF_INET, s, &v4) == 1;
}

static int is_ipv6(const char *s)
{
    struct in6_addr v6;
    return inet_pton(AF_INET6, s, &v6) == 1;
}

static int is_ip_address(const char *s)
{
    return is_ipv4(s) || is_ipv6(s);
}

/* Build a PTR query name from an IP address.
 * E.g., "1.2.3.4" -> "4.3.2.1.in-addr.arpa" */
static int make_ptr_name(const char *ip, char *buf, size_t bufsz)
{
    struct in_addr v4;
    struct in6_addr v6;

    if (inet_pton(AF_INET, ip, &v4) == 1) {
        unsigned char *b = (unsigned char *)&v4;
        snprintf(buf, bufsz, "%u.%u.%u.%u.in-addr.arpa",
                 b[3], b[2], b[1], b[0]);
        return 0;
    }
    if (inet_pton(AF_INET6, ip, &v6) == 1) {
        char *p = buf;
        for (int i = 15; i >= 0; i--) {
            p += snprintf(p, bufsz - (p - buf), "%x.%x.",
                          v6.s6_addr[i] & 0xf, (v6.s6_addr[i] >> 4) & 0xf);
        }
        snprintf(p, bufsz - (p - buf), "ip6.arpa");
        return 0;
    }
    return -1;
}

/* Read a 16-bit big-endian value from a buffer */
static unsigned short get16(const unsigned char *p)
{
    return (p[0] << 8) | p[1];
}

/* Read a 32-bit big-endian value from a buffer */
static unsigned int get32(const unsigned char *p)
{
    return ((unsigned int)p[0] << 24) | ((unsigned int)p[1] << 16) |
           ((unsigned int)p[2] << 8) | p[3];
}

/* Configure the resolver to use a specific nameserver.
 * Returns 0 on success, 1 on failure. */
static int setup_resolver(const char *server)
{
    res_init();

    if (!server)
        return 0;

    struct in_addr addr;
    if (inet_pton(AF_INET, server, &addr) == 1) {
        _res.nscount = 1;
        _res.nsaddr_list[0].sin_family = AF_INET;
        _res.nsaddr_list[0].sin_addr = addr;
        _res.nsaddr_list[0].sin_port = htons(53);
        return 0;
    }

    /* IPv6 address or hostname -- resolve to IPv4 for _res */
    struct addrinfo hints = {0}, *res;
    hints.ai_family = AF_INET;
    if (getaddrinfo(server, NULL, &hints, &res) == 0) {
        struct sockaddr_in *sa = (struct sockaddr_in *)res->ai_addr;
        _res.nscount = 1;
        _res.nsaddr_list[0] = *sa;
        _res.nsaddr_list[0].sin_port = htons(53);
        freeaddrinfo(res);
        return 0;
    }

    fprintf(stderr, ";; connection timed out; no servers could be reached\n");
    return 1;
}

/* Print the server header (called once per invocation). */
static void print_server_header(void)
{
    char srvip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &_res.nsaddr_list[0].sin_addr, srvip, sizeof(srvip));
    printf("Server:\t\t%s\n", srvip);
    printf("Address:\t%s#53\n\n", srvip);
}

/* Print a resource record in ISC nslookup format.
 * qname is the queried name (used for NS/CNAME/PTR output). */
static void print_rdata(const char *qname, int type,
                        const unsigned char *rdata, int rdlen,
                        const unsigned char *msg, int msglen)
{
    char nbuf[256];

    switch (type) {
    case ns_t_a:
        if (rdlen >= 4) {
            char ip[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, rdata, ip, sizeof(ip));
            printf("Address: %s\n", ip);
        }
        break;

    case ns_t_aaaa:
        if (rdlen >= 16) {
            char ip[INET6_ADDRSTRLEN];
            inet_ntop(AF_INET6, rdata, ip, sizeof(ip));
            printf("Address: %s\n", ip);
        }
        break;

    case ns_t_cname:
        if (dn_expand(msg, msg + msglen, rdata, nbuf, sizeof(nbuf)) >= 0)
            printf("%s\tcanonical name = %s\n", qname, nbuf);
        break;

    case ns_t_ns:
        if (dn_expand(msg, msg + msglen, rdata, nbuf, sizeof(nbuf)) >= 0)
            printf("%s\tnameserver = %s\n", qname, nbuf);
        break;

    case ns_t_ptr:
        if (dn_expand(msg, msg + msglen, rdata, nbuf, sizeof(nbuf)) >= 0)
            printf("%s\tname = %s\n", qname, nbuf);
        break;

    case ns_t_mx: {
        unsigned short pref = get16(rdata);
        if (dn_expand(msg, msg + msglen, rdata + 2, nbuf, sizeof(nbuf)) >= 0)
            printf("%s\tmail exchanger = %u %s\n", qname, pref, nbuf);
        break;
    }

    case ns_t_txt: {
        const unsigned char *p = rdata;
        const unsigned char *end = rdata + rdlen;
        printf("%s\ttext = \"", qname);
        while (p < end) {
            int slen = *p++;
            if (p + slen > end) slen = end - p;
            fwrite(p, 1, slen, stdout);
            p += slen;
        }
        printf("\"\n");
        break;
    }

    case ns_t_soa: {
        char ns_name[256], email[256];
        int off = dn_expand(msg, msg + msglen, rdata, ns_name, sizeof(ns_name));
        if (off < 0) break;
        const unsigned char *p = rdata + off;
        off = dn_expand(msg, msg + msglen, p, email, sizeof(email));
        if (off < 0) break;
        p += off;
        if (p + 20 <= rdata + rdlen) {
            printf("%s\n\torigin = %s\n\tmail addr = %s\n"
                   "\tserial = %u\n\trefresh = %u\n\tretry = %u\n"
                   "\texpire = %u\n\tminimum = %u\n",
                   qname, ns_name, email,
                   get32(p), get32(p+4), get32(p+8),
                   get32(p+12), get32(p+16));
        }
        break;
    }

    case ns_t_srv: {
        if (rdlen >= 6) {
            unsigned short pri = get16(rdata);
            unsigned short weight = get16(rdata + 2);
            unsigned short port = get16(rdata + 4);
            if (dn_expand(msg, msg + msglen, rdata + 6, nbuf, sizeof(nbuf)) >= 0)
                printf("%s\tservice = %u %u %u %s\n",
                       qname, pri, weight, port, nbuf);
        }
        break;
    }

    default:
        printf("%s\t%s (type %d, %d bytes)\n", qname,
               type_to_str(type), type, rdlen);
        break;
    }
}

/* Parse and print the answer section of a DNS response.
 * If print_aa is true, print "Non-authoritative answer:" header.
 * Returns 0 on success (at least one answer), 1 if no answers. */
static int print_answers(const char *qname, int qtype,
                         const unsigned char *answer, int anslen,
                         int print_aa)
{
    if (anslen < 12)
        return 1;

    unsigned short flags = get16(answer + 2);
    unsigned short qdcount = get16(answer + 4);
    unsigned short ancount = get16(answer + 6);
    int aa = (flags >> 10) & 1;

    if (print_aa && !aa)
        printf("Non-authoritative answer:\n");

    /* Skip question section */
    const unsigned char *p = answer + 12;
    const unsigned char *end = answer + anslen;
    for (unsigned short i = 0; i < qdcount && p < end; i++) {
        char name[256];
        int n = dn_expand(answer, end, p, name, sizeof(name));
        if (n < 0) return 1;
        p += n + 4; /* skip QTYPE + QCLASS */
    }

    if (ancount == 0)
        return 1;

    /* Parse answer records */
    for (unsigned short i = 0; i < ancount && p < end; i++) {
        char rname[256];
        int n = dn_expand(answer, end, p, rname, sizeof(rname));
        if (n < 0) break;
        p += n;

        if (p + 10 > end) break;
        unsigned short rtype = get16(p);
        /* rclass at p+2, rttl at p+4 (unused) */
        unsigned short rdlen = get16(p + 8);
        p += 10;

        if (p + rdlen > end) break;

        /* For A/AAAA records, print "Name:\t<name>" before each address */
        if (rtype == ns_t_a || rtype == ns_t_aaaa)
            printf("Name:\t%s\n", rname);

        print_rdata(rname, rtype, p, rdlen, answer, anslen);
        p += rdlen;
    }

    return 0;
}

int main(int argc, char **argv)
{
    int qtype = ns_t_a;
    int explicit_type = 0;
    const char *host = NULL;
    const char *server = NULL;
    int i;

    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-type=", 6) == 0 ||
            strncmp(argv[i], "-query=", 7) == 0 ||
            strncmp(argv[i], "-querytype=", 11) == 0) {
            const char *val = strchr(argv[i], '=') + 1;
            int t = str_to_type(val);
            if (t < 0) {
                fprintf(stderr, "nslookup: unknown query type: %s\n", val);
                return 1;
            }
            qtype = t;
            explicit_type = 1;
        } else if (strcmp(argv[i], "-help") == 0 ||
                   strcmp(argv[i], "--help") == 0) {
            printf("Usage: nslookup [-type=TYPE] HOST [SERVER]\n"
                   "Types: A, AAAA, MX, NS, SOA, TXT, CNAME, PTR, SRV, ANY\n");
            return 0;
        } else if (argv[i][0] != '-') {
            if (!host)
                host = argv[i];
            else if (!server)
                server = argv[i];
        }
    }

    if (!host) {
        fprintf(stderr, "Usage: nslookup [-type=TYPE] HOST [SERVER]\n");
        return 1;
    }

    /* Set up resolver and print server header once */
    if (setup_resolver(server) != 0)
        return 1;
    print_server_header();

    /* Auto-detect reverse lookup when given an IP address */
    if (is_ip_address(host) && !explicit_type) {
        char ptrbuf[256];
        if (make_ptr_name(host, ptrbuf, sizeof(ptrbuf)) == 0) {
            unsigned char answer[4096];
            int anslen = res_query(ptrbuf, ns_c_in, ns_t_ptr,
                                   answer, sizeof(answer));
            if (anslen < 0) {
                fprintf(stderr, "** server can't find %s: %s\n",
                        host, hstrerror(h_errno));
                return 1;
            }
            return print_answers(ptrbuf, ns_t_ptr, answer, anslen, 1);
        }
    }

    /* Default query: try both A and AAAA (like ISC nslookup) */
    if (!explicit_type) {
        unsigned char answer_a[4096], answer_aaaa[4096];
        int anslen_a, anslen_aaaa;
        int got_a, got_aaaa;

        anslen_a = res_query(host, ns_c_in, ns_t_a,
                             answer_a, sizeof(answer_a));
        anslen_aaaa = res_query(host, ns_c_in, ns_t_aaaa,
                                answer_aaaa, sizeof(answer_aaaa));

        got_a = (anslen_a >= 12);
        got_aaaa = (anslen_aaaa >= 12);

        if (!got_a && !got_aaaa) {
            fprintf(stderr, "** server can't find %s: %s\n",
                    host, hstrerror(h_errno));
            return 1;
        }

        /* Print "Non-authoritative answer:" header once */
        if (got_a) {
            unsigned short flags = get16(answer_a + 2);
            if (!((flags >> 10) & 1))
                printf("Non-authoritative answer:\n");
        }

        /* Print A answers */
        if (got_a)
            print_answers(host, ns_t_a, answer_a, anslen_a, 0);

        /* Print AAAA answers */
        if (got_aaaa) {
            unsigned short ancount = get16(answer_aaaa + 6);
            if (ancount > 0)
                print_answers(host, ns_t_aaaa, answer_aaaa, anslen_aaaa, 0);
        }

        printf("\n");
        return 0;
    }

    /* Explicit type query */
    {
        unsigned char answer[4096];
        int anslen = res_query(host, ns_c_in, qtype,
                               answer, sizeof(answer));
        if (anslen < 0) {
            fprintf(stderr, "** server can't find %s: %s\n",
                    host, hstrerror(h_errno));
            return 1;
        }
        if (print_answers(host, qtype, answer, anslen, 1) != 0) {
            printf("*** Can't find %s: No answer\n", host);
            return 1;
        }
        printf("\n");
        return 0;
    }
}
