#!/bin/sh

# Read-only Raspberry Pi and Linux status collector.
# stdout is reserved for one schema-versioned JSON document.

LC_ALL=C
export LC_ALL

if [ "$#" -ne 0 ]; then
    printf '%s\n' "status.sh does not accept arguments" >&2
    exit 2
fi

json_escape() {
    awk '
        BEGIN { first = 1 }
        {
            if (!first) {
                printf "\\n"
            }
            first = 0
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\t/, "\\t")
            gsub(/\r/, "\\r")
            printf "%s", $0
        }
    '
}

json_string() {
    printf '"'
    printf '%s' "$1" | json_escape
    printf '"'
}

json_string_or_null() {
    if [ -n "$1" ]; then
        json_string "$1"
    else
        printf 'null'
    fi
}

json_number_or_null() {
    if [ -n "$1" ]; then
        printf '%s' "$1"
    else
        printf 'null'
    fi
}

json_bool_or_null() {
    case "$1" in
        true|false) printf '%s' "$1" ;;
        *) printf 'null' ;;
    esac
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

is_number() {
    awk -v value="$1" 'BEGIN {
        exit(value ~ /^-?[0-9]+([.][0-9]+)?$/ ? 0 : 1)
    }'
}

first_line() {
    awk 'NR == 1 { print; exit }' "$1" 2>/dev/null
}

add_runtime_evidence() {
    if [ -n "$runtime_evidence" ]; then
        runtime_evidence="$runtime_evidence, \"$1\""
    else
        runtime_evidence="\"$1\""
    fi
}

read_os_release_value() {
    key=$1
    file=$2
    value=$(awk -v wanted="$key" '
        index($0, wanted "=") == 1 {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$file" 2>/dev/null)

    case "$value" in
        \"*\")
            value=${value#\"}
            value=${value%\"}
            value=$(printf '%s' "$value" | sed 's/\\"/"/g; s/\\\\/\\/g')
            ;;
    esac
    printf '%s' "$value"
}

count_cpuset() {
    awk -v list="$1" 'BEGIN {
        if (list == "") exit 1
        count = 0
        parts = split(list, ranges, ",")
        for (i = 1; i <= parts; i++) {
            if (ranges[i] ~ /^[0-9]+$/) {
                count++
            } else if (ranges[i] ~ /^[0-9]+-[0-9]+$/) {
                split(ranges[i], limits, "-")
                if (limits[2] < limits[1]) exit 1
                count += limits[2] - limits[1] + 1
            } else {
                exit 1
            }
        }
        print count
    }'
}

set_throttling_value() {
    throttling_value=$1
    throttling_value_source=$2

    case "$throttling_value" in
        0x*) throttling_hex=${throttling_value#0x} ;;
        0X*) throttling_hex=${throttling_value#0X} ;;
        *) throttling_hex='' ;;
    esac

    if [ -n "$throttling_hex" ]; then
        case "$throttling_hex" in
            *[!0-9A-Fa-f]*) return 1 ;;
            *) throttling_decimal=$((0x$throttling_hex)) ;;
        esac
    elif is_uint "$throttling_value"; then
        throttling_decimal=$throttling_value
    else
        return 1
    fi

    throttling_raw=$throttling_value
    throttling_available=true
    throttling_scope=host
    throttling_source=$throttling_value_source
    throttling_reason=''
    current_undervoltage=false
    current_frequency_capped=false
    current_throttled=false
    current_soft_temperature_limit=false
    occurred_undervoltage=false
    occurred_frequency_capped=false
    occurred_throttled=false
    occurred_soft_temperature_limit=false
    [ $((throttling_decimal & 1)) -ne 0 ] && current_undervoltage=true
    [ $((throttling_decimal & 2)) -ne 0 ] && current_frequency_capped=true
    [ $((throttling_decimal & 4)) -ne 0 ] && current_throttled=true
    [ $((throttling_decimal & 8)) -ne 0 ] && current_soft_temperature_limit=true
    [ $((throttling_decimal & 65536)) -ne 0 ] && occurred_undervoltage=true
    [ $((throttling_decimal & 131072)) -ne 0 ] && occurred_frequency_capped=true
    [ $((throttling_decimal & 262144)) -ne 0 ] && occurred_throttled=true
    [ $((throttling_decimal & 524288)) -ne 0 ] && occurred_soft_temperature_limit=true
    return 0
}

cgroup_v2_file() {
    name=$1
    relative=$2
    relative=${relative#/}

    if [ -n "$relative" ] && [ -r "/sys/fs/cgroup/$relative/$name" ]; then
        printf '%s' "/sys/fs/cgroup/$relative/$name"
    elif [ -r "/sys/fs/cgroup/$name" ]; then
        printf '%s' "/sys/fs/cgroup/$name"
    fi
}

cgroup_v1_relative() {
    controller=$1
    awk -F: -v wanted="$controller" '
        {
            count = split($2, controllers, ",")
            for (i = 1; i <= count; i++) {
                if (controllers[i] == wanted) {
                    print $3
                    exit
                }
            }
        }
    ' /proc/self/cgroup 2>/dev/null
}

cgroup_v1_file() {
    controller=$1
    name=$2
    relative=$(cgroup_v1_relative "$controller")
    relative=${relative#/}

    case "$controller" in
        cpu) roots="/sys/fs/cgroup/cpu /sys/fs/cgroup/cpu,cpuacct" ;;
        *) roots="/sys/fs/cgroup/$controller" ;;
    esac

    # Word splitting is intentional: roots is a fixed internal path list.
    # shellcheck disable=SC2086
    for root in $roots; do
        if [ -n "$relative" ] && [ -r "$root/$relative/$name" ]; then
            printf '%s' "$root/$relative/$name"
            return
        fi
        if [ -r "$root/$name" ]; then
            printf '%s' "$root/$name"
            return
        fi
    done
}

collected_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '')
system_name=$(uname -s 2>/dev/null || printf '')
architecture=$(uname -m 2>/dev/null || printf '')
kernel_release=$(uname -r 2>/dev/null || printf '')

supported=true
unsupported_reason=''
if [ "$system_name" != "Linux" ]; then
    supported=false
    unsupported_reason=non_linux_operating_system
fi

hardware_available=false
is_raspberry_pi=''
hardware_model=''
hardware_source=''
hardware_reason=not_found

os_available=false
os_name=''
os_version=''
os_pretty_name=''
os_source=''
os_reason=not_found

kernel_available=false
kernel_reason=not_found
kernel_source=''
if [ -n "$kernel_release" ]; then
    kernel_available=true
    kernel_reason=''
    kernel_source='uname'
fi

architecture_available=false
architecture_reason=not_found
architecture_source=''
if [ -n "$architecture" ]; then
    architecture_available=true
    architecture_reason=''
    architecture_source='uname'
fi

runtime_environment=unknown
runtime_confidence=low
runtime_evidence=''
runtime_warning=''

uptime_available=false
uptime_seconds=''
uptime_scope=unknown
uptime_source=''
uptime_reason=not_supported

cpu_count_available=false
cpu_count=''
cpu_count_scope=unknown
cpu_count_source=''
cpu_count_reason=not_supported

load_available=false
load_1m=''
load_5m=''
load_15m=''
load_scope=unknown
load_source=''
load_reason=not_supported

cgroup_cpu_available=false
cgroup_cpu_quota=''
cgroup_cpu_cpuset_count=''
cgroup_cpu_scope=unknown
cgroup_cpu_source=''
cgroup_cpu_reason=not_supported

memory_system_available=false
memory_total_bytes=''
memory_available_bytes=''
memory_used_bytes=''
memory_system_scope=unknown
memory_system_source=''
memory_system_reason=not_supported

memory_cgroup_available=false
memory_cgroup_used_bytes=''
memory_cgroup_limit_bytes=''
memory_cgroup_scope=unknown
memory_cgroup_source=''
memory_cgroup_reason=not_supported

disk_available=false
disk_total_bytes=''
disk_used_bytes=''
disk_available_bytes=''
disk_used_percent=''
disk_scope=unknown
disk_source=''
disk_reason=not_supported

temperature_available=false
temperature_celsius=''
temperature_sensor_type=''
temperature_scope=unknown
temperature_source=''
temperature_reason=not_supported

throttling_available=false
throttling_raw=''
throttling_scope=unknown
throttling_source=''
throttling_reason=not_supported
current_undervoltage=''
current_frequency_capped=''
current_throttled=''
current_soft_temperature_limit=''
occurred_undervoltage=''
occurred_frequency_capped=''
occurred_throttled=''
occurred_soft_temperature_limit=''

if [ "$supported" = true ]; then
    # Hardware identity: accept only explicit Raspberry Pi model evidence.
    for model_path in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
        if [ -r "$model_path" ]; then
            candidate=$(tr -d '\000\r\n' < "$model_path" 2>/dev/null)
            if [ -n "$candidate" ]; then
                hardware_model=$candidate
                hardware_source=device_tree
                hardware_available=true
                hardware_reason=''
                case "$candidate" in
                    *Raspberry\ Pi*) is_raspberry_pi=true ;;
                    *) is_raspberry_pi=false ;;
                esac
                break
            fi
        fi
    done

    if [ "$hardware_available" = false ] && [ -r /proc/cpuinfo ]; then
        candidate=$(awk -F: '
            /^[Mm]odel[[:space:]]*:/ {
                sub(/^[^:]*:[[:space:]]*/, "")
                if ($0 ~ /Raspberry Pi/) { print; exit }
            }
        ' /proc/cpuinfo 2>/dev/null)
        if [ -n "$candidate" ]; then
            hardware_model=$candidate
            hardware_source=proc_cpuinfo
            hardware_available=true
            hardware_reason=''
            is_raspberry_pi=true
        fi
    fi

    if [ "$hardware_available" = false ]; then
        case "$architecture" in
            x86_64|i386|i486|i586|i686)
                is_raspberry_pi=false
                hardware_available=true
                hardware_source=architecture
                hardware_reason=not_raspberry_pi
                ;;
        esac
    fi

    # Distribution identity without sourcing executable shell content.
    if [ -r /etc/os-release ]; then
        os_name=$(read_os_release_value NAME /etc/os-release)
        os_version=$(read_os_release_value VERSION_ID /etc/os-release)
        os_pretty_name=$(read_os_release_value PRETTY_NAME /etc/os-release)
        if [ -n "$os_name$os_version$os_pretty_name" ]; then
            os_available=true
            os_source=os_release
            os_reason=''
        fi
    fi
    if [ "$os_available" = false ] && [ -n "$system_name" ]; then
        os_available=true
        os_name=$system_name
        os_pretty_name=$system_name
        os_source='uname'
        os_reason=''
    fi

    # Container detection uses positive markers and one explicit negative probe.
    if [ -e /.dockerenv ]; then
        runtime_environment=container
        runtime_confidence=high
        add_runtime_evidence dockerenv_marker
    fi
    if [ -e /run/.containerenv ]; then
        runtime_environment=container
        runtime_confidence=high
        add_runtime_evidence containerenv_marker
    fi
    if [ -r /proc/1/cgroup ] && grep -Eiq '(docker|containerd|kubepods|libpod|lxc)' /proc/1/cgroup 2>/dev/null; then
        runtime_environment=container
        runtime_confidence=high
        add_runtime_evidence cgroup_marker
    fi
    # A Docker Host can see overlay mounts belonging to its containers. Only
    # the current process root mount is useful evidence for this runtime.
    if [ -r /proc/self/mountinfo ] && awk '
        $5 == "/" {
            for (i = 1; i < NF; i++) {
                if ($i == "-" && ($(i + 1) == "overlay" || $(i + 1) == "aufs")) {
                    root_is_container_overlay = 1
                }
            }
        }
        END { exit(root_is_container_overlay ? 0 : 1) }
    ' /proc/self/mountinfo 2>/dev/null; then
        runtime_environment=container
        if [ "$runtime_confidence" = low ]; then
            runtime_confidence=medium
        fi
        add_runtime_evidence mountinfo_marker
    fi

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        detected_virt=$(systemd-detect-virt --container 2>/dev/null)
        detect_status=$?
        if [ "$detect_status" -eq 0 ] && [ -n "$detected_virt" ] && [ "$detected_virt" != none ]; then
            runtime_environment=container
            runtime_confidence=high
            add_runtime_evidence systemd_detect_virt
        elif [ "$runtime_environment" = unknown ] && [ "$detected_virt" = none ]; then
            runtime_environment=host
            runtime_confidence=medium
            add_runtime_evidence systemd_no_container
        fi
    fi

    if [ "$runtime_environment" = container ]; then
        runtime_warning='Some metrics may describe the Agent container rather than the Raspberry Pi host.'
    fi

    case "$runtime_environment" in
        host)
            runtime_metric_scope=host
            system_view_scope=host
            cgroup_scope=unknown
            ;;
        container)
            runtime_metric_scope=container
            system_view_scope=unknown
            cgroup_scope=container
            ;;
        *)
            runtime_metric_scope=unknown
            system_view_scope=unknown
            cgroup_scope=unknown
            ;;
    esac
    load_scope=$system_view_scope

    # Uptime and load average.
    uptime_reason=not_found
    if [ -r /proc/uptime ]; then
        uptime_raw=$(first_line /proc/uptime | awk '{ print $1 }')
        if is_number "$uptime_raw"; then
            uptime_seconds=$(awk -v value="$uptime_raw" 'BEGIN { printf "%.0f", value }')
            uptime_available=true
            uptime_scope=$system_view_scope
            uptime_source=proc_uptime
            uptime_reason=''
        else
            uptime_reason=parse_error
        fi
    fi

    load_reason=not_found
    if [ -r /proc/loadavg ]; then
        load_values=$(first_line /proc/loadavg | awk '{ print $1, $2, $3 }')
        # Word splitting is intentional for three validated numeric fields.
        # shellcheck disable=SC2086
        set -- $load_values
        if [ "$#" -eq 3 ] && is_number "$1" && is_number "$2" && is_number "$3"; then
            load_1m=$1
            load_5m=$2
            load_15m=$3
            load_available=true
            load_source=proc_loadavg
            load_reason=''
        else
            load_reason=parse_error
        fi
    fi

    # CPU count visible to this runtime.
    cpu_count_reason=not_found
    if command -v nproc >/dev/null 2>&1; then
        candidate=$(nproc 2>/dev/null)
        if is_uint "$candidate" && [ "$candidate" -gt 0 ]; then
            cpu_count=$candidate
            cpu_count_available=true
            cpu_count_source=nproc
        fi
    fi
    if [ "$cpu_count_available" = false ] && command -v getconf >/dev/null 2>&1; then
        candidate=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
        if is_uint "$candidate" && [ "$candidate" -gt 0 ]; then
            cpu_count=$candidate
            cpu_count_available=true
            cpu_count_source='getconf'
        fi
    fi
    if [ "$cpu_count_available" = false ] && [ -r /proc/cpuinfo ]; then
        candidate=$(awk '/^processor[[:space:]]*:/ { count++ } END { if (count > 0) print count }' /proc/cpuinfo)
        if is_uint "$candidate" && [ "$candidate" -gt 0 ]; then
            cpu_count=$candidate
            cpu_count_available=true
            cpu_count_source=proc_cpuinfo
        fi
    fi
    if [ "$cpu_count_available" = true ]; then
        cpu_count_scope=$runtime_metric_scope
        cpu_count_reason=''
    fi

    # cgroup v2 or v1 CPU constraints.
    cgroup_cpu_reason=not_found
    cgroup_relative=''
    if [ -r /sys/fs/cgroup/cgroup.controllers ]; then
        cgroup_relative=$(awk -F: '$1 == "0" { print $3; exit }' /proc/self/cgroup 2>/dev/null)
        cpu_max_file=$(cgroup_v2_file cpu.max "$cgroup_relative")
        cpuset_file=$(cgroup_v2_file cpuset.cpus.effective "$cgroup_relative")
        [ -n "$cpuset_file" ] || cpuset_file=$(cgroup_v2_file cpuset.cpus "$cgroup_relative")

        if [ -n "$cpu_max_file" ]; then
            cpu_max=$(first_line "$cpu_max_file")
            # Word splitting is intentional for the cgroup quota and period.
            # shellcheck disable=SC2086
            set -- $cpu_max
            if [ "$#" -ge 2 ] && [ "$1" != max ] && is_uint "$1" && is_uint "$2" && [ "$2" -gt 0 ]; then
                cgroup_cpu_quota=$(awk -v quota="$1" -v period="$2" 'BEGIN {
                    value = quota / period
                    printf "%.6f", value
                }' | sed 's/0*$//; s/[.]$//')
            fi
        fi
        if [ -n "$cpuset_file" ]; then
            cpuset_value=$(first_line "$cpuset_file")
            cgroup_cpu_cpuset_count=$(count_cpuset "$cpuset_value" 2>/dev/null || printf '')
        fi
        if [ -n "$cgroup_cpu_quota$cgroup_cpu_cpuset_count" ]; then
            cgroup_cpu_available=true
            cgroup_cpu_source=cgroup_v2
        fi
    else
        quota_file=$(cgroup_v1_file cpu cpu.cfs_quota_us)
        period_file=$(cgroup_v1_file cpu cpu.cfs_period_us)
        cpuset_file=$(cgroup_v1_file cpuset cpuset.cpus)

        if [ -n "$quota_file" ] && [ -n "$period_file" ]; then
            quota=$(first_line "$quota_file")
            period=$(first_line "$period_file")
            if is_number "$quota" && is_uint "$period" && [ "$period" -gt 0 ] && awk -v q="$quota" 'BEGIN { exit(q >= 0 ? 0 : 1) }'; then
                cgroup_cpu_quota=$(awk -v quota="$quota" -v period="$period" 'BEGIN {
                    value = quota / period
                    printf "%.6f", value
                }' | sed 's/0*$//; s/[.]$//')
            fi
        fi
        if [ -n "$cpuset_file" ]; then
            cpuset_value=$(first_line "$cpuset_file")
            cgroup_cpu_cpuset_count=$(count_cpuset "$cpuset_value" 2>/dev/null || printf '')
        fi
        if [ -n "$cgroup_cpu_quota$cgroup_cpu_cpuset_count" ]; then
            cgroup_cpu_available=true
            cgroup_cpu_source=cgroup_v1
        fi
    fi
    if [ "$cgroup_cpu_available" = true ]; then
        cgroup_cpu_scope=$cgroup_scope
        cgroup_cpu_reason=''
    fi

    # System-visible memory from procfs.
    memory_system_reason=not_found
    if [ -r /proc/meminfo ]; then
        mem_total_kb=$(awk '$1 == "MemTotal:" { print $2; exit }' /proc/meminfo)
        mem_available_kb=$(awk '$1 == "MemAvailable:" { print $2; exit }' /proc/meminfo)
        if is_uint "$mem_total_kb" && is_uint "$mem_available_kb"; then
            memory_total_bytes=$(awk -v value="$mem_total_kb" 'BEGIN { printf "%.0f", value * 1024 }')
            memory_available_bytes=$(awk -v value="$mem_available_kb" 'BEGIN { printf "%.0f", value * 1024 }')
            memory_used_bytes=$(awk -v total="$memory_total_bytes" -v available="$memory_available_bytes" 'BEGIN {
                used = total - available
                if (used < 0) used = 0
                printf "%.0f", used
            }')
            memory_system_available=true
            memory_system_scope=$system_view_scope
            memory_system_source=proc_meminfo
            memory_system_reason=''
        else
            memory_system_reason=parse_error
        fi
    fi

    # cgroup memory usage and limit, independent of whether a container was detected.
    memory_cgroup_reason=not_found
    memory_usage_file=''
    memory_limit_file=''
    if [ -r /sys/fs/cgroup/cgroup.controllers ]; then
        memory_usage_file=$(cgroup_v2_file memory.current "$cgroup_relative")
        memory_limit_file=$(cgroup_v2_file memory.max "$cgroup_relative")
        memory_cgroup_source=cgroup_v2
    else
        memory_usage_file=$(cgroup_v1_file memory memory.usage_in_bytes)
        memory_limit_file=$(cgroup_v1_file memory memory.limit_in_bytes)
        memory_cgroup_source=cgroup_v1
    fi

    if [ -n "$memory_usage_file" ]; then
        candidate=$(first_line "$memory_usage_file")
        if is_uint "$candidate"; then
            memory_cgroup_used_bytes=$candidate
        fi
    fi
    if [ -n "$memory_limit_file" ]; then
        candidate=$(first_line "$memory_limit_file")
        if is_uint "$candidate" && awk -v value="$candidate" 'BEGIN { exit(value < 1152921504606846976 ? 0 : 1) }'; then
            memory_cgroup_limit_bytes=$candidate
        fi
    fi
    if [ -n "$memory_cgroup_used_bytes$memory_cgroup_limit_bytes" ]; then
        memory_cgroup_available=true
        memory_cgroup_scope=$cgroup_scope
        memory_cgroup_reason=''
    else
        memory_cgroup_source=''
    fi

    # Root filesystem as visible to the current runtime.
    disk_reason=not_found
    disk_values=$(df -Pk / 2>/dev/null | awk 'NR == 2 { print $2, $3, $4 }')
    # Word splitting is intentional for three validated numeric fields.
    # shellcheck disable=SC2086
    set -- $disk_values
    if [ "$#" -eq 3 ] && is_uint "$1" && is_uint "$2" && is_uint "$3"; then
        disk_total_bytes=$(awk -v value="$1" 'BEGIN { printf "%.0f", value * 1024 }')
        disk_used_bytes=$(awk -v value="$2" 'BEGIN { printf "%.0f", value * 1024 }')
        disk_available_bytes=$(awk -v value="$3" 'BEGIN { printf "%.0f", value * 1024 }')
        disk_used_percent=$(awk -v used="$disk_used_bytes" -v total="$disk_total_bytes" 'BEGIN {
            if (total <= 0) exit 1
            printf "%.2f", (used / total) * 100
        }' | sed 's/0*$//; s/[.]$//')
        if [ -n "$disk_used_percent" ]; then
            disk_available=true
            disk_scope=$runtime_metric_scope
            disk_source=df_posix
            disk_reason=''
        else
            disk_reason=parse_error
        fi
    fi

    # CPU/SoC thermal zone, with vcgencmd as an optional fallback.
    temperature_reason=not_found
    thermal_candidate_seen=false
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -d "$zone" ] || continue
        zone_type=$(first_line "$zone/type")
        zone_type_lower=$(printf '%s' "$zone_type" | tr '[:upper:]' '[:lower:]')
        case "$zone_type_lower" in
            *cpu*|*soc*|*bcm2835*|*bcm2711*|*bcm2712*) ;;
            *) continue ;;
        esac
        thermal_candidate_seen=true

        if [ ! -r "$zone/temp" ]; then
            temperature_reason=permission_denied
            continue
        fi

        raw_temperature=$(first_line "$zone/temp")
        if is_number "$raw_temperature"; then
            candidate=$(awk -v value="$raw_temperature" 'BEGIN {
                if (value > 1000 || value < -1000) value = value / 1000
                if (value < -40 || value > 150) exit 1
                printf "%.3f", value
            }' | sed 's/0*$//; s/[.]$//')
            if [ -n "$candidate" ]; then
                temperature_available=true
                temperature_celsius=$candidate
                temperature_sensor_type=$zone_type
                temperature_scope=host
                temperature_source=linux_thermal_zone
                temperature_reason=''
                break
            fi
        fi
        temperature_reason=parse_error
    done

    if [ "$temperature_available" = false ] && command -v vcgencmd >/dev/null 2>&1; then
        vcgencmd_temperature=$(vcgencmd measure_temp 2>/dev/null)
        vcgencmd_temperature_status=$?
        if [ "$vcgencmd_temperature_status" -ne 0 ]; then
            temperature_reason=not_exposed
        else
            candidate=$(printf '%s' "$vcgencmd_temperature" | sed -n "s/^temp=\([-0-9.][0-9.]*\)'C$/\1/p")
            if is_number "$candidate" && awk -v value="$candidate" 'BEGIN { exit(value >= -40 && value <= 150 ? 0 : 1) }'; then
                temperature_available=true
                temperature_celsius=$candidate
                temperature_sensor_type=soc
                temperature_scope=host
                temperature_source=vcgencmd
                temperature_reason=''
            else
                temperature_reason=parse_error
            fi
        fi
    elif [ "$temperature_available" = false ] && [ "$thermal_candidate_seen" = true ] && [ "$temperature_reason" = not_found ]; then
        temperature_reason=not_exposed
    fi

    # Raspberry Pi firmware throttling bitmask. Prefer the kernel sysfs view;
    # vcgencmd requires a firmware mailbox device that some distributions do
    # not expose even when the utility itself is installed.
    throttling_reason=not_found
    for throttling_path in \
        /sys/devices/platform/soc/soc:firmware/get_throttled \
        /sys/devices/platform/*/*:firmware/get_throttled
    do
        [ -e "$throttling_path" ] || continue
        if [ ! -r "$throttling_path" ]; then
            throttling_reason=permission_denied
            continue
        fi

        throttling_candidate=$(first_line "$throttling_path")
        if set_throttling_value "$throttling_candidate" linux_firmware_sysfs; then
            break
        fi
        throttling_reason=parse_error
    done

    if [ "$throttling_available" = false ] && command -v vcgencmd >/dev/null 2>&1; then
        throttling_output=$(vcgencmd get_throttled 2>/dev/null)
        vcgencmd_throttling_status=$?
        if [ "$vcgencmd_throttling_status" -ne 0 ]; then
            throttling_reason=not_exposed
        else
            throttling_candidate=${throttling_output#throttled=}
            if ! set_throttling_value "$throttling_candidate" vcgencmd; then
                throttling_reason=parse_error
            fi
        fi
    elif [ "$throttling_available" = false ] && [ "$throttling_reason" = not_found ]; then
        throttling_reason=command_unavailable
    fi
else
    hardware_reason=not_supported
    if [ -n "$system_name" ]; then
        os_available=true
        os_name=$system_name
        os_pretty_name=$system_name
        os_source='uname'
        os_reason=''
    else
        os_reason=not_supported
    fi
fi

printf '{\n'
printf '  "schema_version": 1,\n'
printf '  "collected_at": '; json_string_or_null "$collected_at"; printf ',\n'
printf '  "supported": %s,\n' "$supported"
printf '  "unsupported_reason": '; json_string_or_null "$unsupported_reason"; printf ',\n'

printf '  "hardware": {\n'
printf '    "available": %s,\n' "$hardware_available"
printf '    "is_raspberry_pi": '; json_bool_or_null "$is_raspberry_pi"; printf ',\n'
printf '    "model": '; json_string_or_null "$hardware_model"; printf ',\n'
printf '    "architecture": {"available": %s, "value": ' "$architecture_available"; json_string_or_null "$architecture"; printf ', "source": '; json_string_or_null "$architecture_source"; printf ', "reason": '; json_string_or_null "$architecture_reason"; printf '},\n'
printf '    "source": '; json_string_or_null "$hardware_source"; printf ',\n'
printf '    "reason": '; json_string_or_null "$hardware_reason"; printf '\n'
printf '  },\n'

printf '  "operating_system": {\n'
printf '    "available": %s,\n' "$os_available"
printf '    "name": '; json_string_or_null "$os_name"; printf ',\n'
printf '    "version": '; json_string_or_null "$os_version"; printf ',\n'
printf '    "pretty_name": '; json_string_or_null "$os_pretty_name"; printf ',\n'
printf '    "source": '; json_string_or_null "$os_source"; printf ',\n'
printf '    "reason": '; json_string_or_null "$os_reason"; printf '\n'
printf '  },\n'

printf '  "kernel": {"available": %s, "release": ' "$kernel_available"; json_string_or_null "$kernel_release"; printf ', "source": '; json_string_or_null "$kernel_source"; printf ', "reason": '; json_string_or_null "$kernel_reason"; printf '},\n'

printf '  "runtime": {\n'
printf '    "environment": '; json_string "$runtime_environment"; printf ',\n'
printf '    "confidence": '; json_string "$runtime_confidence"; printf ',\n'
printf '    "evidence": [%s],\n' "$runtime_evidence"
printf '    "warning": '; json_string_or_null "$runtime_warning"; printf '\n'
printf '  },\n'

printf '  "uptime": {"available": %s, "seconds": ' "$uptime_available"; json_number_or_null "$uptime_seconds"; printf ', "scope": '; json_string "$uptime_scope"; printf ', "source": '; json_string_or_null "$uptime_source"; printf ', "reason": '; json_string_or_null "$uptime_reason"; printf '},\n'

printf '  "cpu": {\n'
printf '    "logical_count_visible": {"available": %s, "value": ' "$cpu_count_available"; json_number_or_null "$cpu_count"; printf ', "scope": '; json_string "$cpu_count_scope"; printf ', "source": '; json_string_or_null "$cpu_count_source"; printf ', "reason": '; json_string_or_null "$cpu_count_reason"; printf '},\n'
printf '    "load_average": {"available": %s, "one_minute": ' "$load_available"; json_number_or_null "$load_1m"; printf ', "five_minutes": '; json_number_or_null "$load_5m"; printf ', "fifteen_minutes": '; json_number_or_null "$load_15m"; printf ', "scope": '; json_string "$load_scope"; printf ', "source": '; json_string_or_null "$load_source"; printf ', "reason": '; json_string_or_null "$load_reason"; printf '},\n'
printf '    "cgroup_constraints": {"available": %s, "quota_cores": ' "$cgroup_cpu_available"; json_number_or_null "$cgroup_cpu_quota"; printf ', "cpuset_count": '; json_number_or_null "$cgroup_cpu_cpuset_count"; printf ', "scope": '; json_string "$cgroup_cpu_scope"; printf ', "source": '; json_string_or_null "$cgroup_cpu_source"; printf ', "reason": '; json_string_or_null "$cgroup_cpu_reason"; printf '}\n'
printf '  },\n'

printf '  "memory": {\n'
printf '    "system_visible": {"available": %s, "total_bytes": ' "$memory_system_available"; json_number_or_null "$memory_total_bytes"; printf ', "available_bytes": '; json_number_or_null "$memory_available_bytes"; printf ', "used_bytes": '; json_number_or_null "$memory_used_bytes"; printf ', "scope": '; json_string "$memory_system_scope"; printf ', "source": '; json_string_or_null "$memory_system_source"; printf ', "reason": '; json_string_or_null "$memory_system_reason"; printf '},\n'
printf '    "cgroup": {"available": %s, "used_bytes": ' "$memory_cgroup_available"; json_number_or_null "$memory_cgroup_used_bytes"; printf ', "limit_bytes": '; json_number_or_null "$memory_cgroup_limit_bytes"; printf ', "scope": '; json_string "$memory_cgroup_scope"; printf ', "source": '; json_string_or_null "$memory_cgroup_source"; printf ', "reason": '; json_string_or_null "$memory_cgroup_reason"; printf '}\n'
printf '  },\n'

printf '  "root_filesystem": {"available": %s, "total_bytes": ' "$disk_available"; json_number_or_null "$disk_total_bytes"; printf ', "used_bytes": '; json_number_or_null "$disk_used_bytes"; printf ', "available_bytes": '; json_number_or_null "$disk_available_bytes"; printf ', "used_percent": '; json_number_or_null "$disk_used_percent"; printf ', "scope": '; json_string "$disk_scope"; printf ', "source": '; json_string_or_null "$disk_source"; printf ', "reason": '; json_string_or_null "$disk_reason"; printf '},\n'

printf '  "temperature": {"available": %s, "celsius": ' "$temperature_available"; json_number_or_null "$temperature_celsius"; printf ', "sensor_type": '; json_string_or_null "$temperature_sensor_type"; printf ', "scope": '; json_string "$temperature_scope"; printf ', "source": '; json_string_or_null "$temperature_source"; printf ', "reason": '; json_string_or_null "$temperature_reason"; printf '},\n'

printf '  "throttling": {\n'
printf '    "available": %s,\n' "$throttling_available"
printf '    "raw": '; json_string_or_null "$throttling_raw"; printf ',\n'
printf '    "current": {"undervoltage": '; json_bool_or_null "$current_undervoltage"; printf ', "frequency_capped": '; json_bool_or_null "$current_frequency_capped"; printf ', "throttled": '; json_bool_or_null "$current_throttled"; printf ', "soft_temperature_limit": '; json_bool_or_null "$current_soft_temperature_limit"; printf '},\n'
printf '    "occurred_since_boot": {"undervoltage": '; json_bool_or_null "$occurred_undervoltage"; printf ', "frequency_capped": '; json_bool_or_null "$occurred_frequency_capped"; printf ', "throttled": '; json_bool_or_null "$occurred_throttled"; printf ', "soft_temperature_limit": '; json_bool_or_null "$occurred_soft_temperature_limit"; printf '},\n'
printf '    "scope": '; json_string "$throttling_scope"; printf ',\n'
printf '    "source": '; json_string_or_null "$throttling_source"; printf ',\n'
printf '    "reason": '; json_string_or_null "$throttling_reason"; printf '\n'
printf '  }\n'
printf '}\n'

exit 0
