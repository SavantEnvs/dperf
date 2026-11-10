/*
 * Fuzzes dperf's configuration file parser: main()'s own first step,
 * config_parse(argc, argv, &g_config) with "-c <file>", which tokenizes the file
 * and runs every keyword handler plus all the cross-checks.
 */
#include <limits.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "config.h"

static char sink[4096];

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void)argc;
    (void)argv;
    /* config_parse() reports every error with printf(); keep it off the fuzzer's console. */
    stdout = fmemopen(sink, sizeof(sink), "w");
    if (stdout == NULL) {
        return -1;
    }
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    char path[PATH_MAX];
    const char *dir = getenv("TMPDIR");
    char *argv[] = {"dperf", "-c", path, NULL};
    int fd = -1;

    rewind(stdout);
    if ((dir == NULL) || (dir[0] == 0)) {
        dir = "/tmp";
    }
    snprintf(path, sizeof(path), "%s/dperf-conf-XXXXXX", dir);
    fd = mkstemp(path);
    if (fd < 0) {
        return 0;
    }
    if ((size > 0) && (write(fd, data, size) != (ssize_t)size)) {
        close(fd);
        unlink(path);
        return 0;
    }
    close(fd);

    /* the same starting state main() has: the zeroed global with its one initializer */
    memset(&g_config, 0, sizeof(g_config));
    g_config.tcp_rst = true;
    optind = 0;
    config_parse(3, argv, &g_config);

    unlink(path);
    return 0;
}
