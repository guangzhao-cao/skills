# Raspberry Pi Status

A small, portable, read-only Agent Skill for inspecting Raspberry Pi system health on Linux.

The skill collects a one-time system snapshot as stable JSON, then guides a compatible AI Agent to explain the result in the user's language. It is Agent-agnostic and does not depend on Hermes, Codex, Claude Code, or another vendor-specific API.

## Features

- Raspberry Pi model and hardware identity
- Linux distribution, architecture, and kernel
- Uptime and 1/5/15-minute load average
- Visible CPUs plus cgroup quota and CPU-set constraints
- System-visible and cgroup memory
- Root filesystem capacity and usage
- CPU/SoC temperature
- Raspberry Pi throttling and undervoltage state through Linux firmware sysfs or optional `vcgencmd`
- Conservative container detection with per-metric scope
- Graceful degradation when an interface or optional command is unavailable

## Supported environments

v0.1 targets Raspberry Pi hardware running Linux, including Raspberry Pi OS, Debian, Ubuntu, Alpine, and other common Linux distributions. Other Linux hardware receives a best-effort generic report. Non-Linux operating systems receive a structured unsupported result.

The collector is designed for Raspberry Pi 3, 4, 5, and Zero families, but compatibility claims will distinguish design intent from environments tested on real hardware.

### Tested environments

- Raspberry Pi 4 Model B Rev 1.4, Ubuntu 24.04.4 LTS, Linux 6.8, ARM64, cgroup v2
- Docker container on the same Host, Debian 13 user space, 2-CPU quota, and 4 GiB memory limit

The Host and container tests cover sysfs temperature and throttling, system-visible versus cgroup memory, CPU quota and CPU-set reporting, container root filesystem scope, and Docker detection. Other Raspberry Pi models and Linux distributions are designed targets but are not yet claimed as tested.

## Install

Install from GitHub with a compatible Agent Skills installer:

```sh
npx skills add guangzhao-cao/raspberry-pi-status
```

Then ask the Agent, for example:

- “Is my Raspberry Pi healthy?”
- “What is my Raspberry Pi temperature?”
- “How much memory is available?”
- “Is the root filesystem running out of space?”

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

## Container behavior

A container can expose a mixture of Host-visible and container-specific data. For example, `/proc/meminfo` may show broader system memory while cgroup files describe the Agent's effective memory limit. The container root filesystem usually does not represent the Raspberry Pi Host root filesystem.

The skill therefore labels data as `host`, `container`, or `unknown` and requires the Agent to warn:

> Some metrics may describe the Agent container rather than the Raspberry Pi host.

v0.1 does not use privileged containers, the Docker socket, custom Host `/proc` or `/sys` mounts, or SSH callbacks to bypass isolation.

## Safety

The collector is strictly read-only. It does not install dependencies, use `sudo`, modify files or permissions, manage packages or services, kill processes, delete data, reboot, or shut down the system. Missing metrics remain unavailable rather than triggering a repair or permission change.

The workflow is:

```text
Observe → Collect → Interpret → Report
```

It is not an automatic remediation tool.

## Known limitations

- Container detection is heuristic and cannot prove that a runtime has a complete Host view.
- `vcgencmd` is optional and may be absent or inaccessible in containers.
- Thermal sensor names vary; unrecognized zones are not reported as CPU temperature.
- v0.1 does not collect network state, instantaneous CPU usage, processes, services, storage devices, fan state, Wi-Fi, SMART data, or historical metrics.
- Non-Linux operating systems are not supported.

## Development

Run the smoke test:

```sh
sh tests/smoke.sh
```

Run ShellCheck when available:

```sh
shellcheck -s sh \
  scripts/status.sh \
  tests/smoke.sh \
  tests/fixtures/mock-linux-bin/uname \
  tests/fixtures/mock-linux-bin/vcgencmd
```

The runtime collector has no Python dependency. The development smoke test uses Python's standard library only to validate JSON.

## License

[MIT](LICENSE)

This project is not affiliated with or endorsed by Raspberry Pi Ltd.
