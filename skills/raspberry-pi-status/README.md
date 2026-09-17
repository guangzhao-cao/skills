# Raspberry Pi Status

A small, portable, read-only Agent Skill for inspecting Raspberry Pi system health on Linux.

Ask your AI Agent to check your Raspberry Pi. The skill collects its current status and explains the results in your language.

## Features

- Raspberry Pi model, operating system, and kernel
- Uptime, CPU count, and system load
- Available memory and root filesystem space
- CPU/SoC temperature
- Throttling and undervoltage status
- Container-aware reporting that distinguishes container data from host data

## Supported environments

Designed for Raspberry Pi 3, 4, 5, and Zero families running Linux, including Raspberry Pi OS, Debian, Ubuntu, and Alpine. Other Linux hardware receives a best-effort generic report. Non-Linux systems are not supported.

Tested environments:

- Raspberry Pi 4 Model B Rev 1.4 running Ubuntu 24.04.4 LTS
- A Docker container on that Raspberry Pi running Debian 13

Other Raspberry Pi models and distributions have not yet been verified on real hardware.

## Install and use

Install with a compatible Agent Skills installer:

```sh
npx skills add guangzhao-cao/skills --skill raspberry-pi-status
```

Then ask the Agent:

- “Is my Raspberry Pi healthy?”
- “What is my Raspberry Pi temperature?”
- “How much memory is available?”
- “Is the root filesystem running out of space?”

The Agent needs command access to the Linux environment you want to inspect.

## Example report

An illustrative report with sample values, not a live measurement:

> **Observed health: Normal — Assessment coverage: Partial**
>
> No issue was found in the available data, but the check could not assess power or throttling status.
>
> - System: Raspberry Pi 4, Ubuntu, running for 3 days
> - CPU: 4 cores; 1/5/15-minute load averages of 0.24 / 0.18 / 0.15
> - Memory: 2.5 GiB available out of 4 GiB
> - Root filesystem: 42% used, 18 GiB available
> - Temperature: 48°C
> - Throttling and undervoltage: unavailable in this environment

## Limitations

- When the Agent runs in a container, some readings may describe the container rather than the whole Raspberry Pi. The report notes these limits.
- Temperature, throttling, or undervoltage readings may be unavailable on some systems. Missing readings are reported as unavailable, not assumed healthy.
- Each check is a current snapshot, not continuous monitoring or a guarantee that the entire system is healthy.
- The skill does not inspect network connectivity, individual processes or services, fan status, or drive health.

## Safety

The skill only reads system status. It does not modify the system, install dependencies, or automatically fix problems.

## Development

See [the development guide](CONTRIBUTING.md) for running the collector directly, understanding its output, and running tests.

## License

[MIT](LICENSE)

This project is not affiliated with or endorsed by Raspberry Pi Ltd.
