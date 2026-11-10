/*
 * Fuzzes dperf's incremental HTTP response parser (http_parse_run), which tcp.c calls once per
 * received TCP segment with the socket's parse state carried between calls. The first input byte
 * picks the segment size (1..1021 bytes) the rest of the input is cut into; every segment is a
 * fresh exact-size heap block so ASan sees any read past the segment.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "http_parse.h"
#include "socket.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    struct socket sk;
    size_t seg = 0;
    size_t n = 0;
    uint8_t *buf = NULL;
    int ret = 0;

    if (size < 2) {
        return -1;
    }

    seg = 1 + ((size_t)data[0] << 2);
    data++;
    size--;

    memset(&sk, 0, sizeof(sk));
    sk.keepalive = 1;

    while (size > 0) {
        n = (size < seg) ? size : seg;
        buf = malloc(n);
        if (buf == NULL) {
            abort();
        }
        memcpy(buf, data, n);
        ret = http_parse_run(&sk, buf, (int)n);
        free(buf);
        data += n;
        size -= n;
        if (ret == HTTP_PARSE_END || ret == HTTP_PARSE_ERR) {
            /* tcp.c: socket_init_http(), and the connection carries on with the next message */
            socket_init_http(&sk);
        }
    }

    return 0;
}
