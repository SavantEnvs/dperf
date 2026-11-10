#!/usr/bin/env bash
#
# mayhem/build.sh — build dperf's fuzz harnesses (sanitized, instrumented) and its test oracle
# (normal flags). Runs in the commit image as `mayhem` in /mayhem; offline-safe: the only
# dependency, DPDK, comes from the image's apt packages (libdpdk-dev, found through pkg-config).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

FUZZ_DIR="$SRC/mayhem/build-fuzz"
TEST_DIR="$SRC/mayhem/build-tests"
mkdir -p "$FUZZ_DIR/obj" "$TEST_DIR/obj"

# What `make` does for upstream, minus main.c (the harnesses and selftest bring their own entry
# point). kni.c is only part of the RTE_SDK build; this is the DPDK >= 20.11 / pkg-config build.
SRCS=$(cd src && ls *.c | grep -vE '^(main|kni)\.c$')
DPDK_CFLAGS=$(pkg-config --cflags libdpdk)
DPDK_LIBS="$(pkg-config --libs libdpdk) -lrte_net_bond -lrte_bus_pci -lrte_bus_vdev"
PROJECT_DEFS="-DHTTP_PARSE -DALLOW_EXPERIMENTAL_API -I$SRC/src -Wno-address-of-packed-member"

# 1) The project, sanitized + SanCov-instrumented (fuzzer-no-link, unconditionally, so the fuzzed
#    code carries coverage even in the no-sanitizer build), DWARF 3.
# shellcheck disable=SC2086
printf '%s\n' $SRCS | xargs -P "$MAYHEM_JOBS" -I{} \
    $CC $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1 $PROJECT_DEFS $DPDK_CFLAGS \
        -c "src/{}" -o "$FUZZ_DIR/obj/{}.o"
FUZZ_OBJS=$(printf "$FUZZ_DIR/obj/%s.o " $SRCS)

# 2) Harnesses: the fuzzer binary and a run-once standalone reproducer each, leak detection off.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FUZZ_DIR/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ_DIR/standalone_main.o"
for h in fuzz_config:harness_config fuzz_http_parse:harness_http_parse; do
    name=${h%%:*}; harness=${h##*:}
    # shellcheck disable=SC2086
    $CC $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1 $PROJECT_DEFS $DPDK_CFLAGS \
        -c "$SRC/mayhem/$harness.c" -o "$FUZZ_DIR/$harness.o"
    # shellcheck disable=SC2086
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ_DIR/$harness.o" $FUZZ_OBJS \
        "$FUZZ_DIR/lsan_off.o" $DPDK_LIBS -lpthread -lm -o "/mayhem/$name"
    # shellcheck disable=SC2086
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$FUZZ_DIR/$harness.o" "$FUZZ_DIR/standalone_main.o" $FUZZ_OBJS \
        "$FUZZ_DIR/lsan_off.o" $DPDK_LIBS -lpthread -lm -o "/mayhem/$name-standalone"
done

# 3) The test oracle, with upstream's own flags (gcc -O3 -g, as its Makefile): the real dperf
#    binary (its `-t -c` mode validates a config file) and the known-answer probe.
# shellcheck disable=SC2086
printf '%s\n' $SRCS main.c | xargs -P "$MAYHEM_JOBS" -I{} \
    gcc -O3 -g $COVERAGE_FLAGS $PROJECT_DEFS $DPDK_CFLAGS -Wall -c "src/{}" -o "$TEST_DIR/obj/{}.o"
TEST_OBJS=$(printf "$TEST_DIR/obj/%s.o " $SRCS)
gcc -O3 -g $COVERAGE_FLAGS $PROJECT_DEFS $DPDK_CFLAGS -Wall -c "$SRC/mayhem/selftest.c" -o "$TEST_DIR/selftest.o"
# shellcheck disable=SC2086
gcc $COVERAGE_FLAGS $TEST_OBJS "$TEST_DIR/obj/main.c.o" $DPDK_LIBS -lpthread -lm -o "$TEST_DIR/dperf"
# shellcheck disable=SC2086
gcc $COVERAGE_FLAGS $TEST_OBJS "$TEST_DIR/selftest.o" $DPDK_LIBS -lpthread -lm -o "$TEST_DIR/dperf-selftest"
