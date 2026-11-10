# `atol()` reads past the end of a non-NUL-terminated receive buffer

`http_parse_header_line()` (`src/http_parse.c:61`) calls `atol()` on `start + CONTENT_LENGTH_SIZE` inside a
segment that is not NUL-terminated. When a segment ends in the middle of a `Content-Length:` line (or right
after the header name, before any CRLF), `atol`/`strtol` scans past the end of the buffer. ASan reports a
heap-buffer-overflow READ in `StrtolFixAndCheck` (the harness hands the parser exact-size heap blocks, one
per TCP segment).

Reproduce: `/mayhem/fuzz_http_parse-standalone mayhem/fuzz_http_parse/known-findings/atol-header-overread/crash-input`
(first byte is the harness's segment-size selector; the rest is the byte stream).

Impact: out-of-bounds read of packet memory, at most a few bytes, parsed into `http_length`.

Fix: bound the digits to `line_len` (copy at most 20 bytes into a NUL-terminated local, or use `strtol` over a
length-checked loop) instead of calling `atol` on the raw receive buffer.
