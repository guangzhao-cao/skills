# Metric interpretation

Use this reference when interpreting schema version `1` output from `scripts/status.sh`.

## Availability, source, and scope

Standard metrics remain present even when collection fails. An unavailable value is `null`, with one of these normalized reasons:

- `not_supported`: the current operating system is outside the collector's Linux scope.
- `not_found`: no usable interface or value was found.
- `not_exposed`: an expected kernel or firmware interface exists but is not usable from this runtime.
- `permission_denied`: the interface is present but unreadable.
- `command_unavailable`: an optional command is not installed.
- `parse_error`: a source returned an unexpected value.
- `not_raspberry_pi`: available evidence identifies different hardware.
- `unknown`: no more specific reason is reliable.

Interpret scope conservatively:

- `host`: evidence describes the physical or host Linux system.
- `container`: evidence describes the Agent container or its cgroup.
- `unknown`: the collector cannot prove which environment the value represents.

Container detection is heuristic. Positive markers can provide high confidence; a lack of markers does not prove a Host runtime. Never promote `unknown` to `host` in the report.

## CPU and load average

`logical_count_visible` is the number of logical CPUs available to the running process according to the best available interface. It is not necessarily the Raspberry Pi's physical core count.

`cgroup_constraints.quota_cores` is CPU time quota divided by its period and can be fractional. `cpuset_count` is the number of logical CPUs allowed by a cgroup CPU set. These values are separate constraints, not alternative names for physical cores.

Linux load average counts runnable or uninterruptible tasks; it is not a CPU percentage. Compare sustained load, especially the 15-minute value, with the most restrictive known CPU capacity:

1. finite cgroup quota;
2. cgroup cpuset count;
3. visible logical CPU count.

A sustained load near capacity can be normal for a busy system. A sustained load above capacity indicates queued work and deserves context, but a single high one-minute value does not prove a fault. In a container, load average often cannot be attributed exclusively to that container.

## Memory

`memory.system_visible` comes from `/proc/meminfo`. `available_bytes` uses Linux `MemAvailable`, which estimates memory usable without swapping. It is more meaningful than `MemFree` because Linux deliberately uses otherwise idle memory for cache.

`used_bytes` is the deterministic calculation:

```text
total_bytes - available_bytes
```

`memory.cgroup` describes the current cgroup when exposed. In a container, its finite `limit_bytes` is usually the effective memory ceiling even when `/proc/meminfo` displays a larger Host-visible total. A `null` cgroup limit can mean no finite limit was exposed; it does not mean a zero-byte limit.

As conservative guidance, available memory below roughly 10% deserves attention and below roughly 5% deserves stronger attention. Do not label a system critical from one memory snapshot alone; workload behavior and swap activity are outside v0.1.

## Root filesystem

The collector measures `/` as visible to its runtime. In a container this is normally the container root or overlay filesystem, not the Raspberry Pi Host root filesystem.

Interpret both percentage and absolute free bytes. As general guidance:

- below 80% used is usually comfortable;
- 80–89% is worth monitoring;
- 90% or more deserves attention;
- 95% or more presents a material risk of operational failures.

These are reporting guidelines, not hard guarantees. Small filesystems and workloads with rapid growth need additional context.

## Temperature

The collector only accepts a thermal zone whose type identifies a CPU, SoC, or known Raspberry Pi thermal driver. It falls back to `vcgencmd measure_temp` when available. It does not use an unrelated sensor merely because it is `thermal_zone0`.

Temperature limits vary by Raspberry Pi model, firmware, cooling, and workload. As cautious guidance:

- below 70°C is generally comfortable;
- 70–79°C is elevated but can be expected under sustained load;
- 80°C or above deserves attention and should be interpreted with throttling data.

Prefer explicit current thermal throttling or soft-limit flags over a universal temperature threshold.

## Throttling and undervoltage

When available, the Linux firmware sysfs interface returns a decimal bitmask and `vcgencmd get_throttled` returns a hexadecimal bitmask. The collector prefers the read-only sysfs interface, falls back to optional `vcgencmd`, preserves the source value, and decodes these documented positions as factual booleans:

| Bit | Meaning |
| --- | --- |
| 0 | Undervoltage is currently detected |
| 1 | ARM frequency is currently capped |
| 2 | Throttling is currently active |
| 3 | Soft temperature limit is currently active |
| 16 | Undervoltage has occurred since boot |
| 17 | ARM frequency capping has occurred since boot |
| 18 | Throttling has occurred since boot |
| 19 | Soft temperature limiting has occurred since boot |

Current flags describe the present condition. Historical flags mean the condition occurred at least once since boot, even if it is no longer active. Current undervoltage or throttling deserves attention. Historical-only flags should be reported as past evidence rather than a current failure.

## Health and assessment coverage

Report health and coverage separately.

- `Normal`: observed, available metrics show no clear problem.
- `Needs attention`: one or more observations warrant user review.
- `Critical`: available evidence shows an immediate and severe resource, thermal, or power condition.
- `Unknown`: too little evidence is available to judge observed health.

Coverage is `Sufficient` only when key Host-scoped identity, CPU/load, memory, root storage, temperature, and throttling data are available. Use `Partial` when useful evidence exists but important Host metrics are missing. Use `Insufficient` when the available data cannot support a meaningful Host assessment.

`Normal` with `Partial` coverage must be phrased as “no issue was found in the observed metrics,” not “the Raspberry Pi is definitely healthy.”
