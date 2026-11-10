#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Known-answer tests. dperf has no unit-test suite of its own, so the oracle drives the two pre-built
# binaries (mayhem/build-tests/, normal flags) and compares their stdout against golden values in bash:
#   dperf -t -c <conf>          the real CLI's config check (message + exit status)
#   dperf-selftest config <f>   config_parse() result and the parsed g_config fields
#   dperf-selftest http         http_parse_run() over fixed responses, whole and split
T=mayhem/build-tests
for b in "$T/dperf" "$T/dperf-selftest"; do
  [ -x "$b" ] || { echo "missing $b (build.sh should have produced it)" >&2; emit_ctrf "dperf-kat" 0 1 0; exit 1; }
done

passed=0 failed=0
check() { # <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed+1)); else
    failed=$((failed+1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2; fi
}

OK='Config file OK'
cli() { local o rc; o=$("$T/dperf" -t -c "$1" 2>&1); rc=$?; printf '%s|rc=%d' "$o" "$rc"; }
sel() { "$T/dperf-selftest" config "$1" 2>&1; }

kat() { # <conf> <expected cli output|rc> <expected config line(s)>
  check "cli $1" "$2" "$(cli "$1")"
  check "config $1" "$3" "$(sel "$1")"
}

kat test/http/client-cps.conf 'Config file OK|rc=0' 'rc=0 server=0 protocol=6 http=0 ipv6=0 vxlan=0 cpu_num=1 port_num=1 cps=10000 cc=0 duration=60 listen=80/1 mss=1460'
kat test/http/server-cps.conf 'Config file OK|rc=0' 'rc=0 server=1 protocol=6 http=0 ipv6=0 vxlan=0 cpu_num=1 port_num=1 cps=0 cc=0 duration=600 listen=80/1 mss=1460'
kat test/udp/client.conf 'Config file OK|rc=0' 'rc=0 server=0 protocol=17 http=0 ipv6=0 vxlan=0 cpu_num=2 port_num=2 cps=1000 cc=2000 duration=60 listen=80/1 mss=1460'
kat test/vxlan/ipv6/vxlan-client-ipv6-udp.conf 'Config file OK|rc=0' 'rc=0 server=0 protocol=17 http=0 ipv6=1 vxlan=1 cpu_num=1 port_num=1 cps=1000000 cc=0 duration=864000 listen=80/1 mss=1440'
kat test/vxlan/ipv4/vxlan-server5.conf 'Config file OK|rc=0' 'rc=0 server=1 protocol=6 http=0 ipv6=0 vxlan=1 cpu_num=5 port_num=1 cps=0 cc=0 duration=872640 listen=80/1 mss=1460'
kat test/bond/bond.conf 'Config file OK|rc=0' 'rc=0 server=1 protocol=6 http=0 ipv6=0 vxlan=0 cpu_num=1 port_num=1 cps=0 cc=0 duration=864000 listen=80/1 mss=1460'
kat test/ipv6/client-cps-ipv6.conf 'Config file OK|rc=0' 'rc=0 server=0 protocol=6 http=0 ipv6=1 vxlan=0 cpu_num=1 port_num=1 cps=10000 cc=0 duration=60 listen=80/1 mss=1440'
kat test/udp/server-cps-ipv6.conf 'Error: client and server address conflict|rc=1' 'Error: client and server address conflict
rc=-1 server=1 protocol=17 http=0 ipv6=1 vxlan=0 cpu_num=1 port_num=1 cps=0 cc=0 duration=600 listen=80/1 mss=1440'

# A config with an unknown keyword is rejected with a line-numbered message.
bad=$(mktemp)
trap 'rm -f "$bad"' EXIT
printf 'port 0000:00:00.0 10.0.0.1 10.0.0.2\nbogus_keyword 1\n' > "$bad"
check "cli bad keyword" 'line 2: unknown config keyword("bogus_keyword")|rc=1' "$(cli "$bad")"
check "config bad keyword" 'line 2: unknown config keyword("bogus_keyword")
rc=-1 server=0 protocol=0 http=0 ipv6=0 vxlan=0 cpu_num=0 port_num=1 cps=0 cc=0 duration=0 listen=0/0 mss=0' "$(sel "$bad")"

check "version" "1.9.0" "$("$T/dperf" -v 2>&1)"

check "http parser" 'whole: ret=1 state=11 flags=2 keepalive=1 length=0
split: ret=0 ret=0 ret=1 state=11 flags=2 keepalive=1 length=0
chunked: ret=1 state=11 flags=4 keepalive=1 length=0
chunked_split: ret=0 ret=0 ret=1 state=11 flags=4 keepalive=1 length=0
both: ret=-1 state=1 flags=2 keepalive=1 length=5
extra: ret=-1 state=3 flags=2 keepalive=1 length=5
close: ret=1 state=11 flags=10 keepalive=0 length=0
keepalive: ret=1 state=11 flags=2 keepalive=1 length=0
nolen: ret=0 state=3 flags=9 keepalive=0 length=-1' "$("$T/dperf-selftest" http 2>&1)"

emit_ctrf "dperf-kat" "$passed" "$failed" 0
