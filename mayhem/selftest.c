/*
 * Known-answer probe for the oracle (mayhem/test.sh): runs dperf's own config parser and HTTP
 * parser on fixed inputs and prints what they computed, one line per case, for test.sh to compare
 * against golden values. Built with the project's normal flags.
 *
 *   dperf-selftest config <file>   parse a config file, print the resulting settings
 *   dperf-selftest http            feed canned HTTP responses to http_parse_run
 */
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "http_parse.h"
#include "socket.h"

static int selftest_config(const char *path)
{
    char *argv[] = {"dperf", "-c", (char *)path, NULL};
    struct config *cfg = &g_config;
    int rc = 0;

    memset(cfg, 0, sizeof(*cfg));
    cfg->tcp_rst = true;
    optind = 0;
    rc = config_parse(3, argv, cfg);
    printf("rc=%d server=%d protocol=%d http=%d ipv6=%d vxlan=%d cpu_num=%d port_num=%d cps=%d cc=%d "
        "duration=%d listen=%d/%d mss=%d\n",
        rc, cfg->server, cfg->protocol, cfg->http, cfg->ipv6, cfg->vxlan, cfg->cpu_num, cfg->port_num,
        cfg->cps, cfg->cc, cfg->duration, cfg->listen, cfg->listen_num, cfg->mss);
    return 0;
}

static void http_case(const char *name, const char *const *segs)
{
    struct socket sk;
    int ret = 0;
    int i = 0;

    memset(&sk, 0, sizeof(sk));
    sk.keepalive = 1;
    printf("%s:", name);
    for (i = 0; segs[i] != NULL; i++) {
        ret = http_parse_run(&sk, (const uint8_t *)segs[i], (int)strlen(segs[i]));
        printf(" ret=%d", ret);
    }
    printf(" state=%d flags=%d keepalive=%d length=%ld\n", sk.http_parse_state, sk.http_flags,
        sk.keepalive, (long)sk.http_length);
}

static int selftest_http(void)
{
    const char *hdr = "HTTP/1.1 200 OK\r\nContent-Length:5\r\nServer: dperf\r\n\r\n";
    const char *whole[] = {"HTTP/1.1 200 OK\r\nContent-Length:5\r\nServer: dperf\r\n\r\nhello", NULL};
    const char *split[] = {hdr, "hel", "lo", NULL};
    const char *chunked[] = {"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n", NULL};
    const char *chunked_split[] = {"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n", "a\r\n0123456789\r\n", "0\r\n\r\n", NULL};
    const char *both[] = {"HTTP/1.1 200 OK\r\nContent-Length:5\r\nTransfer-Encoding: chunked\r\n\r\nhello", NULL};
    const char *extra[] = {"HTTP/1.1 200 OK\r\nContent-Length:5\r\n\r\nhello!!", NULL};
    const char *close_[] = {"HTTP/1.1 200 OK\r\nContent-Length:0\r\nConnection:close\r\n\r\n", NULL};
    const char *keep[] = {"HTTP/1.1 200 OK\r\nContent-Length:0\r\nConnection:keep-alive\r\n\r\n", NULL};
    const char *nolen[] = {"HTTP/1.1 200 OK\r\nServer: dperf\r\n\r\nbody", NULL};

    http_case("whole", whole);
    http_case("split", split);
    http_case("chunked", chunked);
    http_case("chunked_split", chunked_split);
    http_case("both", both);
    http_case("extra", extra);
    http_case("close", close_);
    http_case("keepalive", keep);
    http_case("nolen", nolen);
    return 0;
}

int main(int argc, char **argv)
{
    if ((argc == 3) && (strcmp(argv[1], "config") == 0)) {
        return selftest_config(argv[2]);
    }
    if ((argc == 2) && (strcmp(argv[1], "http") == 0)) {
        return selftest_http();
    }
    fprintf(stderr, "usage: %s config <file> | http\n", argv[0]);
    return 2;
}
