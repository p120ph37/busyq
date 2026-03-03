/* dig.c - DNS lookup utility for busyq
 *
 * Provides dig-style DNS lookups with detailed output showing
 * query/answer/authority/additional sections.
 *
 * Usage:
 *   dig [@server] name [type] [+short]
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
#include <time.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <netinet/in.h>
#include <resolv.h>
#include <netdb.h>

/* DNS record type constants */
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
    default: {
        static char buf[16];
        snprintf(buf, sizeof(buf), "TYPE%d", type);
        return buf;
    }
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

static unsigned short get16(const unsigned char *p)
{
    return (p[0] << 8) | p[1];
}

static unsigned int get32(const unsigned char *p)
{
    return ((unsigned int)p[0] << 24) | ((unsigned int)p[1] << 16) |
           ((unsigned int)p[2] << 8) | p[3];
}

static const char *rcode_str(int rcode)
{
    switch (rcode) {
    case 0: return "NOERROR";
    case 1: return "FORMERR";
    case 2: return "SERVFAIL";
    case 3: return "NXDOMAIN";
    case 4: return "NOTIMP";
    case 5: return "REFUSED";
    default: return "UNKNOWN";
    }
}

/* Format rdata as a string for the given record type.
 * Returns pointer to static buffer. */
static const char *format_rdata(int type, const unsigned char *rdata, int rdlen,
                                const unsigned char *msg, int msglen)
{
    static char buf[1024];
    char nbuf[256];

    switch (type) {
    case ns_t_a:
        if (rdlen >= 4)
            inet_ntop(AF_INET, rdata, buf, sizeof(buf));
        else
            snprintf(buf, sizeof(buf), "(invalid)");
        return buf;

    case ns_t_aaaa:
        if (rdlen >= 16)
            inet_ntop(AF_INET6, rdata, buf, sizeof(buf));
        else
            snprintf(buf, sizeof(buf), "(invalid)");
        return buf;

    case ns_t_cname:
    case ns_t_ns:
    case ns_t_ptr:
        if (dn_expand(msg, msg + msglen, rdata, nbuf, sizeof(nbuf)) >= 0) {
            snprintf(buf, sizeof(buf), "%s.", nbuf);
        } else {
            snprintf(buf, sizeof(buf), "(error)");
        }
        return buf;

    case ns_t_mx: {
        unsigned short pref = get16(rdata);
        if (dn_expand(msg, msg + msglen, rdata + 2, nbuf, sizeof(nbuf)) >= 0)
            snprintf(buf, sizeof(buf), "%u %s.", pref, nbuf);
        else
            snprintf(buf, sizeof(buf), "%u (error)", pref);
        return buf;
    }

    case ns_t_txt: {
        char *p = buf;
        const unsigned char *rd = rdata;
        const unsigned char *end = rdata + rdlen;
        *p++ = '"';
        while (rd < end) {
            int slen = *rd++;
            if (rd + slen > end) slen = end - rd;
            if (p + slen + 3 >= buf + sizeof(buf)) break;
            memcpy(p, rd, slen);
            p += slen;
            rd += slen;
        }
        *p++ = '"';
        *p = '\0';
        return buf;
    }

    case ns_t_soa: {
        char ns_name[256], email[256];
        int off = dn_expand(msg, msg + msglen, rdata, ns_name, sizeof(ns_name));
        if (off < 0) return "(error)";
        const unsigned char *q = rdata + off;
        off = dn_expand(msg, msg + msglen, q, email, sizeof(email));
        if (off < 0) return "(error)";
        q += off;
        if (q + 20 <= rdata + rdlen) {
            snprintf(buf, sizeof(buf), "%s. %s. %u %u %u %u %u",
                     ns_name, email,
                     get32(q), get32(q+4), get32(q+8),
                     get32(q+12), get32(q+16));
        } else {
            snprintf(buf, sizeof(buf), "(truncated)");
        }
        return buf;
    }

    case ns_t_srv: {
        if (rdlen >= 6) {
            unsigned short pri = get16(rdata);
            unsigned short weight = get16(rdata + 2);
            unsigned short port = get16(rdata + 4);
            if (dn_expand(msg, msg + msglen, rdata + 6, nbuf, sizeof(nbuf)) >= 0)
                snprintf(buf, sizeof(buf), "%u %u %u %s.", pri, weight, port, nbuf);
            else
                snprintf(buf, sizeof(buf), "%u %u %u (error)", pri, weight, port);
        }
        return buf;
    }

    default:
        snprintf(buf, sizeof(buf), "\\# %d", rdlen);
        return buf;
    }
}

/* Parse and print a section of resource records.
 * Returns updated pointer, or NULL on error. */
static const unsigned char *print_section(const char *section_name,
                                          const unsigned char *p,
                                          const unsigned char *end,
                                          const unsigned char *msg, int msglen,
                                          unsigned short count, int short_mode)
{
    if (count > 0 && !short_mode)
        printf("\n;; %s SECTION:\n", section_name);

    for (unsigned short i = 0; i < count && p < end; i++) {
        char rname[256];
        int n = dn_expand(msg, end, p, rname, sizeof(rname));
        if (n < 0) return NULL;
        p += n;

        if (p + 10 > end) return NULL;
        unsigned short rtype = get16(p);
        unsigned short rclass = get16(p + 2);
        unsigned int rttl = get32(p + 4);
        unsigned short rdlen = get16(p + 8);
        p += 10;

        if (p + rdlen > end) return NULL;

        const char *rdata_str = format_rdata(rtype, p, rdlen, msg, msglen);

        if (short_mode) {
            printf("%s\n", rdata_str);
        } else {
            (void)rclass;
            printf("%s.\t\t%u\tIN\t%s\t%s\n",
                   rname, rttl, type_to_str(rtype), rdata_str);
        }

        p += rdlen;
    }

    return p;
}

int main(int argc, char **argv)
{
    int qtype = ns_t_a;
    const char *name = NULL;
    const char *server = NULL;
    int short_mode = 0;
    int i;

    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '@') {
            server = argv[i] + 1;
        } else if (argv[i][0] == '+') {
            if (strcmp(argv[i], "+short") == 0)
                short_mode = 1;
            else if (strcmp(argv[i], "+noall") == 0 ||
                     strcmp(argv[i], "+answer") == 0)
                ; /* accepted but ignored for compatibility */
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Usage: dig [@server] name [type] [+short]\n"
                   "Types: A, AAAA, MX, NS, SOA, TXT, CNAME, PTR, SRV, ANY\n");
            return 0;
        } else if (!name) {
            name = argv[i];
        } else {
            int t = str_to_type(argv[i]);
            if (t >= 0)
                qtype = t;
        }
    }

    if (!name) {
        /* No name → query root NS */
        name = ".";
        qtype = ns_t_ns;
    }

    /* Configure custom server if specified */
    if (server) {
        res_init();
        struct addrinfo hints = {0}, *res;
        hints.ai_family = AF_INET;
        if (getaddrinfo(server, NULL, &hints, &res) == 0) {
            struct sockaddr_in *sa = (struct sockaddr_in *)res->ai_addr;
            _res.nscount = 1;
            _res.nsaddr_list[0] = *sa;
            _res.nsaddr_list[0].sin_port = htons(53);
            freeaddrinfo(res);
        } else {
            fprintf(stderr, ";; connection timed out; no servers could be reached\n");
            return 1;
        }
    } else {
        res_init();
    }

    if (!short_mode) {
        printf("; <<>> busyq-dig <<>> ");
        if (server) printf("@%s ", server);
        printf("%s", name);
        if (qtype != ns_t_a) printf(" %s", type_to_str(qtype));
        printf("\n");
    }

    /* Perform query */
    unsigned char answer[4096];
    struct timeval tv_start, tv_end;

    gettimeofday(&tv_start, NULL);
    int anslen = res_query(name, ns_c_in, qtype, answer, sizeof(answer));
    gettimeofday(&tv_end, NULL);

    if (anslen < 0) {
        fprintf(stderr, ";; connection timed out; no servers could be reached\n");
        return 1;
    }

    if (anslen < 12) {
        fprintf(stderr, ";; truncated response\n");
        return 1;
    }

    long query_ms = (tv_end.tv_sec - tv_start.tv_sec) * 1000 +
                    (tv_end.tv_usec - tv_start.tv_usec) / 1000;

    /* Parse header */
    unsigned short id = get16(answer);
    unsigned short flags = get16(answer + 2);
    unsigned short qdcount = get16(answer + 4);
    unsigned short ancount = get16(answer + 6);
    unsigned short nscount = get16(answer + 8);
    unsigned short arcount = get16(answer + 10);

    int qr = (flags >> 15) & 1;
    int opcode = (flags >> 11) & 0xf;
    int aa = (flags >> 10) & 1;
    int tc = (flags >> 9) & 1;
    int rd = (flags >> 8) & 1;
    int ra = (flags >> 7) & 1;
    int rcode = flags & 0xf;

    if (!short_mode) {
        printf(";; Got answer:\n");
        printf(";; ->>HEADER<<- opcode: %s, status: %s, id: %u\n",
               opcode == 0 ? "QUERY" : "UPDATE", rcode_str(rcode), id);
        printf(";; flags:%s%s%s%s%s; QUERY: %u, ANSWER: %u, AUTHORITY: %u, ADDITIONAL: %u\n",
               qr ? " qr" : "", aa ? " aa" : "", tc ? " tc" : "",
               rd ? " rd" : "", ra ? " ra" : "",
               qdcount, ancount, nscount, arcount);
    }

    const unsigned char *p = answer + 12;
    const unsigned char *end = answer + anslen;

    /* Print question section */
    if (qdcount > 0 && !short_mode)
        printf("\n;; QUESTION SECTION:\n");
    for (unsigned short qi = 0; qi < qdcount && p < end; qi++) {
        char qname[256];
        int n = dn_expand(answer, end, p, qname, sizeof(qname));
        if (n < 0) return 1;
        p += n;
        if (p + 4 > end) return 1;
        unsigned short qt = get16(p);
        p += 4;
        if (!short_mode)
            printf(";%s.\t\t\tIN\t%s\n", qname, type_to_str(qt));
    }

    /* Print answer section */
    p = print_section("ANSWER", p, end, answer, anslen, ancount, short_mode);
    if (!p) return 1;

    /* Print authority section */
    if (!short_mode) {
        p = print_section("AUTHORITY", p, end, answer, anslen, nscount, 0);
        if (!p) return 1;

        /* Print additional section */
        p = print_section("ADDITIONAL", p, end, answer, anslen, arcount, 0);
    }

    /* Footer */
    if (!short_mode) {
        char srvip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &_res.nsaddr_list[0].sin_addr, srvip, sizeof(srvip));

        time_t now = time(NULL);
        char timebuf[64];
        struct tm *tm = localtime(&now);
        strftime(timebuf, sizeof(timebuf), "%a %b %d %H:%M:%S %Z %Y", tm);

        printf("\n;; Query time: %ld msec\n", query_ms);
        printf(";; SERVER: %s#53(%s)\n", srvip, srvip);
        printf(";; WHEN: %s\n", timebuf);
        printf(";; MSG SIZE  rcvd: %d\n", anslen);
    }

    return 0;
}
