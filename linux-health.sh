#!/usr/bin/env bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
#
# linux-health.sh — cross-distro Linux system health report
#
# Works on Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE, Alpine, Void and
# derivatives. Optional tools (sensors, smartctl, lspci, nvidia-smi, ...) are
# used when present and gracefully skipped when not.

# --------------------------------------------------------------------------
# Parse flags
# --------------------------------------------------------------------------
SHOW_IP=false
EXPORT_FILE=""
SCRIPT_NAME="$(basename "$0")"

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  --ip                Show local and public IP addresses (hidden by default)"
    echo "  -e, --export [FILE] Export report to a formatted text file (defaults to timestamped filename)"
    echo "  --install           Install 'health' command to ~/.local/bin and configure PATH"
    echo "  --uninstall         Remove 'health' symlink from ~/.local/bin"
    echo "  -h, --help          Show this help message"
    echo
    echo "Environment:"
    echo "  NO_COLOR=1          Disable colored output"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)/$(basename "${BASH_SOURCE}")"
            chmod +x "$SCRIPT_PATH"
            mkdir -p "$HOME/.local/bin"
            ln -sf "$SCRIPT_PATH" "$HOME/.local/bin/health"
            for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
                if [ -f "$rc" ] && ! grep -qE '(\$HOME|~)/\.local/bin' "$rc"; then
                    printf '
export PATH="\$HOME/.local/bin:\$PATH"
' >> "$rc"
                fi
            done
            if command -v fish >/dev/null 2>&1; then
                fish -c "fish_add_path -g "$HOME/.local/bin"" 2>/dev/null || true
            fi
            echo "Installed: $HOME/.local/bin/health -> $SCRIPT_PATH"
            case ":$PATH:" in
                *":$HOME/.local/bin:"*) echo "Ready! Type 'health' in your terminal to run." ;;
                *) echo "Note: Restart your terminal (or run: export PATH="\$HOME/.local/bin:\$PATH") and type 'health'." ;;
            esac
            exit 0
            ;;
        --uninstall)
            rm -f "$HOME/.local/bin/health"
            echo "Removed $HOME/.local/bin/health"
            exit 0
            ;;
        --ip)
            SHOW_IP=true
            shift
            ;;
        -e|--export)
            if [[ -n "${2:-}" && "$2" != -* ]]; then
                EXPORT_FILE="$2"
                shift 2
            else
                EXPORT_FILE="health-report-$(date +%Y%m%d-%H%M%S).txt"
                shift
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# --------------------------------------------------------------------------
# Colors (real escape characters; disabled when not a TTY or NO_COLOR is set)
# --------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    RESET=$'\033[0m'
else
    BOLD="" CYAN="" GREEN="" YELLOW="" RED="" RESET=""
fi

# Force a predictable locale for anything we parse
export LC_ALL=C

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

header() {
    printf '\n%s=== %s ===%s\n' "${BOLD}${CYAN}" "$1" "$RESET"
}

get_os_name() {
    local name=""
    if [ -r /etc/os-release ]; then
        name=$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-${NAME:-}}" )
    fi
    if [ -z "$name" ] && have lsb_release; then
        name=$(lsb_release -ds 2>/dev/null | tr -d '"')
    fi
    echo "${name:-$(uname -s)}"
}

get_uptime() {
    if [ -r /proc/uptime ]; then
        awk '{
            s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60)
            out=""
            if (d>0) out=out d " day" (d>1?"s":"") ", "
            if (h>0 || d>0) out=out h " hour" (h!=1?"s":"") ", "
            out=out m " minute" (m!=1?"s":"")
            print out
        }' /proc/uptime
    else
        uptime 2>/dev/null | sed 's/.*up *//; s/, *[0-9]* user.*//'
    fi
}

get_cpu_model() {
    local model=""
    if have lscpu; then
        model=$(lscpu 2>/dev/null | awk -F: '/^Model name:/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
    fi
    if [ -z "$model" ] && [ -r /proc/cpuinfo ]; then
        model=$(awk -F: '/^(model name|Model|Hardware|Processor)[ \t]*:/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)
    fi
    echo "${model:-$(uname -m)}"
}

# CPU usage sampled from /proc/stat over a short interval (locale/top independent)
get_cpu_usage() {
    [ -r /proc/stat ] || { echo "N/A"; return; }
    local _ u1 n1 s1 i1 w1 q1 sq1 st1 u2 n2 s2 i2 w2 q2 sq2 st2
    read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
    sleep 0.5 2>/dev/null || sleep 1
    read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
    local idle1=$(( ${i1:-0} + ${w1:-0} ))
    local idle2=$(( ${i2:-0} + ${w2:-0} ))
    local tot1=$(( ${u1:-0} + ${n1:-0} + ${s1:-0} + idle1 + ${q1:-0} + ${sq1:-0} + ${st1:-0} ))
    local tot2=$(( ${u2:-0} + ${n2:-0} + ${s2:-0} + idle2 + ${q2:-0} + ${sq2:-0} + ${st2:-0} ))
    local dt=$(( tot2 - tot1 )) di=$(( idle2 - idle1 ))
    if [ "$dt" -le 0 ]; then
        echo "N/A"
    else
        awk -v dt="$dt" -v di="$di" 'BEGIN {printf "%.1f%%", (dt-di)*100/dt}'
    fi
}

# Detect the package manager (first match wins)
detect_pkg_manager() {
    local pm
    for pm in pacman apt-get dnf yum zypper apk xbps-query; do
        if have "$pm"; then echo "$pm"; return; fi
    done
    echo ""
}

smartmontools_hint() {
    case "$(detect_pkg_manager)" in
        pacman)      echo "sudo pacman -S smartmontools" ;;
        apt-get)     echo "sudo apt install smartmontools" ;;
        dnf)         echo "sudo dnf install smartmontools" ;;
        yum)         echo "sudo yum install smartmontools" ;;
        zypper)      echo "sudo zypper install smartmontools" ;;
        apk)         echo "sudo apk add smartmontools" ;;
        xbps-query)  echo "sudo xbps-install smartmontools" ;;
        *)           echo "install the 'smartmontools' package" ;;
    esac
}

list_physical_disks() {
    if have lsblk; then
        lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1 !~ /^(zram|ram|loop)/ {print "/dev/"$1}'
    else
        local d name
        for d in /sys/block/*; do
            name=$(basename "$d")
            case "$name" in
                loop*|ram*|zram*|dm-*|md*|sr*|fd*|nbd*) continue ;;
            esac
            echo "/dev/$name"
        done
    fi
}

dir_size() {
    du -sh "$1" 2>/dev/null | cut -f1
}

# --------------------------------------------------------------------------
# Main report
# --------------------------------------------------------------------------
run_checks() {
    local OS_NAME
    OS_NAME=$(get_os_name)
    printf '%sSystem Health Report%s — %s — Generated on %s\n' \
        "$BOLD" "$RESET" "$OS_NAME" "$(date '+%Y-%m-%d %H:%M:%S')"

    # 1. System & Kernel Info
    header "SYSTEM & KERNEL"
    printf '%sOS:%s       %s\n'     "$BOLD" "$RESET" "$OS_NAME"
    printf '%sKernel:%s   %s\n'     "$BOLD" "$RESET" "$(uname -r)"
    printf '%sArch:%s     %s\n'     "$BOLD" "$RESET" "$(uname -m)"
    printf '%sUptime:%s   %s\n'     "$BOLD" "$RESET" "$(get_uptime)"

    # 2. CPU, Load & Temperatures
    header "CPU, LOAD & TEMPERATURES"
    local CPU_MODEL THREADS LOAD CPU_USAGE
    CPU_MODEL=$(get_cpu_model)
    THREADS=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null)
    if [ -r /proc/loadavg ]; then
        LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
    else
        LOAD=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs)
    fi
    CPU_USAGE=$(get_cpu_usage)
    printf '%sModel:%s    %s%s\n' "$BOLD" "$RESET" "$CPU_MODEL" "${THREADS:+ ($THREADS threads)}"
    printf '%sUsage:%s    %s\n'   "$BOLD" "$RESET" "$CPU_USAGE"
    printf '%sLoad Avg:%s %s (1m, 5m, 15m)\n' "$BOLD" "$RESET" "${LOAD:-N/A}"

    local found_temp=false
    if have sensors; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            printf '%sTemp:%s     %s\n' "$BOLD" "$RESET" "$line"
            found_temp=true
        done < <(sensors 2>/dev/null | grep -E "Package id|Tctl|Tdie|edge|junction|Composite|temp1" | sed 's/^[ \t]*//')
    fi
    if [ "$found_temp" = false ]; then
        local zone type temp any_zone=false
        for zone in /sys/class/thermal/thermal_zone*; do
            if [ -r "$zone/temp" ]; then
                if [ "$any_zone" = false ] && ! have sensors; then
                    printf '%slm_sensors not installed. Reading raw thermal zones:%s\n' "$YELLOW" "$RESET"
                fi
                any_zone=true
                type=$(cat "$zone/type" 2>/dev/null)
                temp=$(awk '{printf "%.1f°C", $1/1000}' "$zone/temp" 2>/dev/null)
                printf '%sTemp:%s     %s: %s\n' "$BOLD" "$RESET" "${type:-zone}" "$temp"
            fi
        done
        if [ "$any_zone" = false ]; then
            printf '%sNo temperature sensors available (common in VMs/containers).%s\n' "$YELLOW" "$RESET"
        fi
    fi

    # 3. GPU Stats
    header "GPU"
    local gpu_found=false
    if have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | \
        awk -F', ' '{printf "NVIDIA:   %s (Usage: %s%% | VRAM: %s / %s MiB | Temp: %s°C)\n", $1, $2, $3, $4, $5}'
        gpu_found=true
    fi

    local IDX=1 gpu_line CLEAN_NAME
    if have lspci; then
        while IFS= read -r gpu_line; do
            [ -z "$gpu_line" ] && continue
            CLEAN_NAME=$(echo "$gpu_line" | sed 's/^[^ ]* [^:]*: //')
            printf '%sGPU %s:%s    %s\n' "$BOLD" "$IDX" "$RESET" "$CLEAN_NAME"
            IDX=$((IDX + 1))
            gpu_found=true
        done < <(lspci 2>/dev/null | grep -iE 'vga|3d|display')
    else
        # Fallback: identify GPU vendors via sysfs
        local card vendor vname
        for card in /sys/class/drm/card[0-9]*; do
            [ -d "$card" ] || continue
            case "$card" in *-*) continue ;; esac
            [ -r "$card/device/vendor" ] || continue
            vendor=$(cat "$card/device/vendor" 2>/dev/null)
            case "$vendor" in
                0x10de) vname="NVIDIA" ;;
                0x1002) vname="AMD/ATI" ;;
                0x8086) vname="Intel" ;;
                *)      vname="Vendor $vendor" ;;
            esac
            printf '%sGPU %s:%s    %s (%s) — install pciutils for model names\n' \
                "$BOLD" "$IDX" "$RESET" "$vname" "$(basename "$card")"
            IDX=$((IDX + 1))
            gpu_found=true
        done
    fi
    if [ "$gpu_found" = false ]; then
        printf '%sNo GPU detected.%s\n' "$YELLOW" "$RESET"
    fi

    # 4. Memory & Swap / ZRAM
    header "MEMORY & SWAP"
    if [ -r /proc/meminfo ]; then
        awk '
        function hum(kb,   v, u, i) {
            v = kb * 1024; split("B K M G T", u, " "); i = 1
            while (v >= 1024 && i < 5) { v /= 1024; i++ }
            return sprintf("%.1f%s", v, u[i])
        }
        /^MemTotal:/     {mt=$2}
        /^MemAvailable:/ {ma=$2; has_ma=1}
        /^MemFree:/      {mf=$2}
        /^Buffers:/      {bu=$2}
        /^Cached:/       {ca=$2}
        /^SwapTotal:/    {st=$2}
        /^SwapFree:/     {sf=$2}
        END {
            if (!has_ma) ma = mf + bu + ca
            printf "%-10s %-10s %-10s %-10s\n", "", "Total", "Used", "Available"
            printf "%-10s %-10s %-10s %-10s\n", "RAM:", hum(mt), hum(mt-ma), hum(ma)
            printf "%-10s %-10s %-10s %-10s\n", "Swap:", hum(st), hum(st-sf), "N/A"
        }' /proc/meminfo
    else
        free -h 2>/dev/null
    fi

    if have zramctl && [ -n "$(zramctl 2>/dev/null)" ]; then
        printf '\n%sZRAM Details:%s\n' "$BOLD" "$RESET"
        zramctl
    fi

    # 5. Storage & S.M.A.R.T. Health
    header "STORAGE & S.M.A.R.T."
    local DF_OUT
    DF_OUT=$(df -hP -x tmpfs -x devtmpfs -x squashfs -x efivarfs 2>/dev/null)
    if [ -z "$DF_OUT" ]; then
        # Fallback for df implementations without -x (e.g. BusyBox)
        DF_OUT=$(df -hP 2>/dev/null | awk 'NR==1 || $1 !~ /^(tmpfs|devtmpfs|udev|none|shm|overlay)$/')
    fi
    printf '%s\n' "$DF_OUT" | grep -v "/run/user/" | awk -v show_ip="$SHOW_IP" '
    NR==1 {printf "%-28s %-8s %-8s %-8s %-6s %s\n", $1, $2, $3, $4, $5, $6}
    NR>1  {
        fs=$1
        if (show_ip != "true" && fs ~ /^\/\/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
            sub(/^\/\/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, "//[IP Hidden]", fs)
        }
        printf "%-28s %-8s %-8s %-8s %-6s %s\n", fs, $2, $3, $4, $5, $6
    }'

    printf '\n%sDrive Health (S.M.A.R.T.):%s\n' "$BOLD" "$RESET"
    if have smartctl; then
        local dev MODEL SMART_OUT STATUS TEMP WEAR HOURS STATUS_COLOR DETAILS
        local any_disk=false
        while IFS= read -r dev; do
            [ -z "$dev" ] && continue
            any_disk=true

            # Skip S.M.A.R.T. queries on SD/MMC cards
            if [[ "$dev" == /dev/mmcblk* ]]; then
                printf '  %s%s:%s N/A (SD/MMC storage - S.M.A.R.T. unsupported)\n' "$BOLD" "$dev" "$RESET"
                continue
            fi

            SMART_OUT=$(smartctl -H -A "$dev" 2>/dev/null)
            if ! echo "$SMART_OUT" | grep -qE "PASSED|OK|FAILED"; then
                if have sudo; then
                    SMART_OUT=$(sudo -n smartctl -H -A "$dev" 2>/dev/null)
                fi
            fi

            if echo "$SMART_OUT" | grep -qE "PASSED|OK|FAILED"; then
                MODEL=""
                if have lsblk; then MODEL=$(lsblk -dn -o MODEL "$dev" 2>/dev/null | xargs); fi
                [ -z "$MODEL" ] && MODEL=$(echo "$SMART_OUT" | awk -F": +" "/Device Model|Model Number|Product/ {print \$2; exit}" | xargs)
                STATUS=$(echo "$SMART_OUT" | grep -E "SMART overall-health|SMART Health Status" | awk -F': ' '{print $2}' | xargs)
                TEMP=$(echo "$SMART_OUT" | awk '/Temperature:/ {print $2"°C"; exit} /Temperature_Celsius/ {print $10"°C"; exit}')
                WEAR=$(echo "$SMART_OUT" | awk '/Percentage Used:/ {gsub(/%/,"",$3); print 100-$3"% life left"; exit} /Wear_Leveling_Count|Media_Wearout_Indicator/ {print $4+0"% life left"; exit}')
                HOURS=$(echo "$SMART_OUT" | awk '/Power On Hours:/ {gsub(/,/, "", $4); print $4"h"; exit} /Power_On_Hours/ {print $10"h"; exit}')

                if [[ "$STATUS" == "PASSED" || "$STATUS" == "OK" ]]; then
                    STATUS_COLOR="${GREEN}${STATUS}${RESET}"
                else
                    STATUS_COLOR="${RED}${STATUS}${RESET}"
                fi

                DETAILS=""
                [ -n "$TEMP" ]  && DETAILS+="Temp: $TEMP"
                [ -n "$WEAR" ]  && DETAILS+="${DETAILS:+ | }Health: $WEAR"
                [ -n "$HOURS" ] && DETAILS+="${DETAILS:+ | }Power-On: $HOURS"

                printf '  %s%s:%s %s %s\n' "$BOLD" "$dev" "$RESET" "$STATUS_COLOR" "${DETAILS:+($DETAILS)}"
            else
                printf '  %s%s:%s %sS.M.A.R.T. unavailable or unsupported (try running with sudo)%s\n' \
                    "$BOLD" "$dev" "$RESET" "$YELLOW" "$RESET"
            fi
        done < <(list_physical_disks)
        if [ "$any_disk" = false ]; then
            printf '  %sNo physical disks found.%s\n' "$YELLOW" "$RESET"
        fi
    else
        printf '  %ssmartmontools not installed (install with: %s)%s\n' "$YELLOW" "$(smartmontools_hint)" "$RESET"
    fi

    if have lsblk; then
        printf '
%sBlock Devices:%s
' "$BOLD" "$RESET"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT -e 7 2>/dev/null | sed 's/^/  /'
    fi

    # 6. Network & Internet
    header "NETWORK & INTERNET"
    local ACTIVE_IFACE=""
    if have ip; then
        ACTIVE_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    fi
    if [ -z "$ACTIVE_IFACE" ] && [ -r /proc/net/route ]; then
        ACTIVE_IFACE=$(awk '$2=="00000000" && $1!="Iface" {print $1; exit}' /proc/net/route)
    fi

    if [ -n "$ACTIVE_IFACE" ]; then
        if [ "$SHOW_IP" = true ]; then
            local LOCAL_IP="" PUBLIC_IP=""
            if have ip; then
                LOCAL_IP=$(ip -4 addr show "$ACTIVE_IFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
            elif have hostname; then
                LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi
            if have curl; then
                PUBLIC_IP=$(curl -s --max-time 2 https://ifconfig.me 2>/dev/null)
            elif have wget; then
                PUBLIC_IP=$(wget -qO- --timeout=2 https://ifconfig.me 2>/dev/null)
            fi
            printf '%sInterface:%s %s\n'  "$BOLD" "$RESET" "$ACTIVE_IFACE"
            printf '%sLocal IP:%s  %s\n'  "$BOLD" "$RESET" "${LOCAL_IP:-Unavailable}"
            printf '%sPublic IP:%s %s\n'  "$BOLD" "$RESET" "${PUBLIC_IP:-Unavailable}"
        else
            printf '%sInterface:%s %s (IP Hidden - use --ip to view)\n' "$BOLD" "$RESET" "$ACTIVE_IFACE"
        fi

        # Ping check for connectivity & latency
        if have ping; then
            local PING_MS
            PING_MS=$(ping -c 1 -W 2 1.1.1.1 2>/dev/null | awk -F'time=' '/time=/ {print $2; exit}')
            if [ -n "$PING_MS" ]; then
                printf '%sInternet:%s  %sConnected%s (Latency: %s)\n' "$BOLD" "$RESET" "$GREEN" "$RESET" "$PING_MS"
            else
                printf '%sInternet:%s  %sUnreachable (No ping response)%s\n' "$BOLD" "$RESET" "$RED" "$RESET"
            fi
        else
            printf '%sInternet:%s  %sping not installed, skipped%s\n' "$BOLD" "$RESET" "$YELLOW" "$RESET"
        fi

        # DNS resolution check
        local DNS_HOST="example.com" dns_ok=""
        if have getent; then
            getent hosts "$DNS_HOST" >/dev/null 2>&1 && dns_ok=yes || dns_ok=no
        elif have host; then
            host -W 2 "$DNS_HOST" >/dev/null 2>&1 && dns_ok=yes || dns_ok=no
        elif have nslookup; then
            nslookup "$DNS_HOST" >/dev/null 2>&1 && dns_ok=yes || dns_ok=no
        fi
        case "$dns_ok" in
            yes) printf '%sDNS:%s       %sWorking%s\n' "$BOLD" "$RESET" "$GREEN" "$RESET" ;;
            no)  printf '%sDNS:%s       %sFailed%s\n'  "$BOLD" "$RESET" "$RED" "$RESET" ;;
            *)   printf '%sDNS:%s       %sNo resolver tool available, skipped%s\n' "$BOLD" "$RESET" "$YELLOW" "$RESET" ;;
        esac
    else
        printf '%sInterface:%s %sDisconnected (No active route)%s\n' "$BOLD" "$RESET" "$RED" "$RESET"
    fi

    # 7. Init system & Package Health
    header "SERVICES & PACKAGE HEALTH"
    if have systemctl && [ -d /run/systemd/system ]; then
        local FAILED_UNITS FAILED_LIST
        FAILED_LIST=$(systemctl --failed --no-legend --plain 2>/dev/null)
        if [ -z "$FAILED_LIST" ]; then
            FAILED_UNITS=0
        else
            FAILED_UNITS=$(printf '%s\n' "$FAILED_LIST" | wc -l | tr -d ' ')
        fi
        if [ "$FAILED_UNITS" -eq 0 ]; then
            printf '%sSystemd:%s  %sAll services running cleanly (0 failed)%s\n' "$BOLD" "$RESET" "$GREEN" "$RESET"
        else
            printf '%sSystemd:%s  %s%s failed service(s) detected:%s\n' "$BOLD" "$RESET" "$RED" "$FAILED_UNITS" "$RESET"
            printf '%s\n' "$FAILED_LIST"
        fi
    else
        local INIT_NAME
        INIT_NAME=$(cat /proc/1/comm 2>/dev/null)
        printf '%sInit:%s     %s (not systemd — service check skipped)\n' "$BOLD" "$RESET" "${INIT_NAME:-unknown}"
    fi

    if have systemctl && [ -d /run/systemd/system ]; then
        local svc label state
        for svc in smbd:Samba fstrim.timer:SSD_TRIM tailscaled:Tailscale; do
            label="${svc#*:}"; label="${label//_/ }"; svc="${svc%%:*}"
            if systemctl list-unit-files "$svc*" 2>/dev/null | grep -q "^$svc"; then
                state=$(systemctl is-active "$svc" 2>/dev/null)
                if [ "$state" = "active" ]; then
                    printf '  %-14s %s%s%s
' "$label:" "$GREEN" "$state" "$RESET"
                else
                    printf '  %-14s %s%s%s
' "$label:" "$YELLOW" "${state:-inactive}" "$RESET"
                fi
            fi
        done
    fi

    if have docker && docker info >/dev/null 2>&1; then
        local CONTAINERS
        CONTAINERS=$(docker ps -a --format "table {{.Names}}	{{.Status}}" 2>/dev/null)
        if [ -n "$CONTAINERS" ] && [ "$(printf '%s
' "$CONTAINERS" | wc -l)" -gt 1 ]; then
            printf '
%sDocker Containers:%s
' "$BOLD" "$RESET"
            printf '%s
' "$CONTAINERS" | sed 's/^/  /'
        fi
    fi

    local PM ORPHANS="" CACHE_DIR=""
    PM=$(detect_pkg_manager)
    case "$PM" in
        pacman)
            ORPHANS=$(pacman -Qtdq 2>/dev/null | wc -l | tr -d ' ')
            CACHE_DIR="/var/cache/pacman/pkg/"
            ;;
        apt-get)
            ORPHANS=$(apt-get -s autoremove 2>/dev/null | grep -c '^Remv')
            CACHE_DIR="/var/cache/apt/archives/"
            ;;
        dnf)
            if ORPHANS=$(dnf -q -C repoquery --unneeded 2>/dev/null); then
                ORPHANS=$(printf '%s' "$ORPHANS" | grep -c .)
            else
                ORPHANS=""
            fi
            if [ -d /var/cache/libdnf5 ]; then CACHE_DIR="/var/cache/libdnf5/"; else CACHE_DIR="/var/cache/dnf/"; fi
            ;;
        yum)
            CACHE_DIR="/var/cache/yum/"
            ;;
        zypper)
            CACHE_DIR="/var/cache/zypp/"
            ;;
        apk)
            CACHE_DIR="/var/cache/apk/"
            ;;
        xbps-query)
            ORPHANS=$(xbps-query -O 2>/dev/null | wc -l | tr -d ' ')
            CACHE_DIR="/var/cache/xbps/"
            ;;
    esac

    if [ -n "$PM" ]; then
        local PM_LABEL="${PM%-get}"
        PM_LABEL="${PM_LABEL%-query}"
        if [ -n "$ORPHANS" ]; then
            printf '%sOrphans:%s  %s unused package(s) (%s)\n' "$BOLD" "$RESET" "$ORPHANS" "$PM_LABEL"
        else
            printf '%sOrphans:%s  N/A (%s)\n' "$BOLD" "$RESET" "$PM_LABEL"
        fi
        if [ -n "$CACHE_DIR" ]; then
            local CACHE_SIZE
            CACHE_SIZE=$(dir_size "$CACHE_DIR")
            printf '%sCache:%s    %s in %s\n' "$BOLD" "$RESET" "${CACHE_SIZE:-0B}" "$CACHE_DIR"
        fi
    else
        printf '%sPackages:%s Unsupported package manager, skipped\n' "$BOLD" "$RESET"
    fi
    echo ""
}

# --------------------------------------------------------------------------
# Execute and optionally export
# --------------------------------------------------------------------------
if [ -n "$EXPORT_FILE" ]; then
    OUTPUT=$(run_checks)
    printf '%s\n' "$OUTPUT"
    # Strip ANSI escape sequences for the exported file
    if printf '%s\n' "$OUTPUT" | sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" > "$EXPORT_FILE"; then
        printf '%s✔ Report exported to:%s %s\n' "$GREEN" "$RESET" "$EXPORT_FILE"
    else
        printf '%s✘ Failed to write report to:%s %s\n' "$RED" "$RESET" "$EXPORT_FILE" >&2
        exit 1
    fi
else
    run_checks
fi
