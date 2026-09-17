# Development guide

## Run the collector directly

From the skill directory:

```sh
sh scripts/status.sh
```

stdout contains one JSON document using schema version `1`. The interface intentionally favors stable Agent parsing over terminal-oriented formatting. Values use base units such as bytes and seconds; the Agent formats them for people.

Example excerpt:

```json
{
  "schema_version": 1,
  "supported": true,
  "hardware": {
    "is_raspberry_pi": true,
    "model": "Raspberry Pi 4 Model B Rev 1.5"
  },
  "runtime": {
    "environment": "container",
    "confidence": "high"
  }
}
```

See [`references/metrics.md`](references/metrics.md) for field semantics, scope, thresholds, and throttling bit meanings.

## Tests

Tests are maintained outside the installable skill directory. From the repository root, run the smoke test:

```sh
sh tests/raspberry-pi-status/smoke.sh
```

Run ShellCheck from the repository root when available:

```sh
shellcheck -s sh \
  skills/raspberry-pi-status/scripts/status.sh \
  tests/raspberry-pi-status/smoke.sh \
  tests/raspberry-pi-status/fixtures/mock-linux-bin/uname \
  tests/raspberry-pi-status/fixtures/mock-linux-bin/vcgencmd
```

The runtime collector has no Python dependency. The development smoke test uses Python's standard library only to validate JSON.

## Existing hardware validation

The project records testing on a Raspberry Pi 4 Model B Rev 1.4 running Ubuntu 24.04.4 LTS, Linux 6.8, ARM64, and cgroup v2, plus a Docker container on that host running Debian 13 with a 2-CPU quota and a 4 GiB memory limit.

These tests cover sysfs temperature and throttling, system-visible versus cgroup memory, CPU quota and CPU-set reporting, container root filesystem scope, and Docker detection. Document the actual hardware and environment when adding compatibility results; distinguish tested support from design targets.
