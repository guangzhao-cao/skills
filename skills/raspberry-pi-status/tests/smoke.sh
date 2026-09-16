#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd)
project_dir=$(CDPATH='' cd "$script_dir/.." && pwd)
collector=$project_dir/scripts/status.sh

if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "python3 is required for the development smoke test" >&2
    exit 1
fi

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/raspberry-pi-status-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

sh -n "$collector"

if ! sh "$collector" >"$test_dir/output.json" 2>"$test_dir/stderr"; then
    printf '%s\n' "collector returned a failure status" >&2
    exit 1
fi

if [ -s "$test_dir/stderr" ]; then
    printf '%s\n' "collector wrote unexpected diagnostics to stderr" >&2
    sed -n '1,20p' "$test_dir/stderr" >&2
    exit 1
fi

python3 - "$test_dir/output.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

required = {
    "schema_version",
    "collected_at",
    "supported",
    "unsupported_reason",
    "hardware",
    "operating_system",
    "kernel",
    "runtime",
    "uptime",
    "cpu",
    "memory",
    "root_filesystem",
    "temperature",
    "throttling",
}

missing = required.difference(data)
assert not missing, f"missing top-level fields: {sorted(missing)}"
assert data["schema_version"] == 1
assert isinstance(data["supported"], bool)
assert data["runtime"]["environment"] in {"host", "container", "unknown"}
assert data["runtime"]["confidence"] in {"high", "medium", "low"}
assert isinstance(data["runtime"]["evidence"], list)

for metric in ("uptime", "root_filesystem", "temperature", "throttling"):
    assert isinstance(data[metric]["available"], bool), metric
    assert data[metric]["scope"] in {"host", "container", "unknown"}, metric

assert data["cpu"]["logical_count_visible"]["scope"] in {
    "host", "container", "unknown"
}
assert data["memory"]["system_visible"]["scope"] in {
    "host", "container", "unknown"
}
PY

# Exercise Linux-only fallbacks, JSON escaping, and vcgencmd decoding even when
# the development host is not Linux. Kernel virtual files remain live inputs.
mock_bin=$project_dir/tests/fixtures/mock-linux-bin
PATH="$mock_bin:$PATH" sh "$collector" >"$test_dir/mock-linux.json" 2>"$test_dir/mock-linux-stderr"

if [ -s "$test_dir/mock-linux-stderr" ]; then
    printf '%s\n' "mock Linux run wrote unexpected diagnostics to stderr" >&2
    sed -n '1,20p' "$test_dir/mock-linux-stderr" >&2
    exit 1
fi

python3 - "$test_dir/mock-linux.json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))

assert data["supported"] is True
assert data["hardware"]["architecture"]["value"] == "aarch64"
assert data["kernel"]["release"] == '6.8.0-"mock"\\kernel'
assert data["throttling"]["available"] is True
assert data["throttling"]["raw"] == "0x50005"
assert data["throttling"]["current"] == {
    "undervoltage": True,
    "frequency_capped": False,
    "throttled": True,
    "soft_temperature_limit": False,
}
assert data["throttling"]["occurred_since_boot"] == {
    "undervoltage": True,
    "frequency_capped": False,
    "throttled": True,
    "soft_temperature_limit": False,
}
PY

MOCK_VCGENCMD_FAIL=1 PATH="$mock_bin:$PATH" sh "$collector" >"$test_dir/mock-vcgencmd-failure.json" 2>"$test_dir/mock-vcgencmd-failure-stderr"

python3 - "$test_dir/mock-vcgencmd-failure.json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))

assert data["throttling"]["available"] is False
assert data["throttling"]["raw"] is None
assert data["throttling"]["reason"] == "not_exposed"
PY

set +e
sh "$collector" unexpected >"$test_dir/invalid-stdout" 2>"$test_dir/invalid-stderr"
invalid_status=$?
set -e

if [ "$invalid_status" -ne 2 ]; then
    printf '%s\n' "invalid invocation did not return exit code 2" >&2
    exit 1
fi

if [ -s "$test_dir/invalid-stdout" ]; then
    printf '%s\n' "invalid invocation polluted stdout" >&2
    exit 1
fi

printf '%s\n' "smoke test passed"
