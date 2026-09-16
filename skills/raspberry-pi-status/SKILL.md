---
name: raspberry-pi-status
description: Inspect the health and runtime status of a Raspberry Pi or other Linux system using a read-only collector, including container-aware CPU, memory, storage, temperature, and throttling data. Use when a user asks whether their Raspberry Pi is healthy or requests one of these system metrics.
---

# Raspberry Pi Status

Collect a read-only system snapshot and turn it into a concise, evidence-based status report.

## Collect

Run the collector from this skill's directory:

```sh
sh scripts/status.sh
```

Parse stdout as one JSON document. Schema version `1` is the supported format. A zero exit code means the collector produced valid JSON; individual metrics can still be unavailable.

Never install dependencies, request elevated privileges, alter container configuration, or modify the system to obtain additional metrics.

## Interpret

Read [references/metrics.md](references/metrics.md) when deciding whether a value needs attention, decoding thermal or power conditions, or explaining container limitations.

- Treat `scope` as part of every result. Never describe `container` or `unknown` data as confirmed Raspberry Pi host data.
- When system-visible and cgroup values both exist, report both. Explain that cgroup limits govern the Agent runtime while system-visible values may describe a broader system.
- Do not infer Raspberry Pi hardware from ARM architecture, Raspberry Pi OS, or the presence of `vcgencmd`. Trust the collector's hardware result.
- Do not treat an unavailable metric as healthy.
- Base health conclusions only on collected evidence. The script collects facts; the Agent interprets them.

## Report

Answer in the user's language. Lead with both:

- **Observed health:** `Normal`, `Needs attention`, `Critical`, or `Unknown`.
- **Assessment coverage:** `Sufficient`, `Partial`, or `Insufficient`.

Then provide compact details for system identity, CPU/load, memory, root storage, temperature, and throttling/undervoltage. Show important unavailable metrics and their practical consequence.

If the runtime is a container, include this warning or an accurate translation:

> Some metrics may describe the Agent container rather than the Raspberry Pi host.

`Partial + Normal` means no problem was found in the observed data; it does not prove the whole host is healthy.

When a problem is observed, give at most a few non-automatic, human-directed checks. Never reboot, shut down, kill processes, delete files, install or upgrade packages, change configuration or permissions, restart or stop services, or otherwise attempt a fix.

