# `duration` value converted from out-of-range double to int

`config_parse_duration()` (`src/config.c:828`) computes `duration = val * rate` from `atof()` and stores it
into an `int`. A value such as `duration 1e10` is outside the range of `int`, which is undefined behavior
(UBSan `float-cast-overflow`: "1e+10 is outside the range of representable values of type 'int'").

Reproduce: `/mayhem/fuzz_config-standalone mayhem/fuzz_config/known-findings/duration-float-cast-overflow/crash-input`

Impact: the stored duration is indeterminate (typically INT_MIN on x86), so `duration <= 0` is not caught.

Fix: compare `val * rate` against `INT_MAX` (as a double) before the conversion and return -1 if it is larger.
