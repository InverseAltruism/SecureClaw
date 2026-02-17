#!/usr/bin/env bash
set -Eeuo pipefail
unset TMOUT 2>/dev/null || true

# SecureClaw Installer
# Interactive hardened deployment for OpenClaw in rootless Podman or Docker
# Copyright © 2025 SecureClaw Contributors - MIT License

# ============================================================================
# COLOR CONSTANTS
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# ============================================================================
# OUTPUT HELPERS
# ============================================================================
info() {
    echo -e "${CYAN}▸${RESET} $*"
}

warn() {
    echo -e "${YELLOW}⚠${RESET} $*"
}

err() {
    echo -e "${RED}✗${RESET} $*" >&2
}

ask() {
    echo -e "${GREEN}?${RESET} ${BOLD}$*${RESET}"
}

section() {
    echo
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  $*${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
}

dim() {
    echo -e "${DIM}  $*${RESET}"
}

die() {
    err "$*"
    exit 1
}

CURRENT_PHASE="startup"

set_phase() {
    CURRENT_PHASE="$1"
}

handle_unexpected_error() {
    local line_no="$1"
    local exit_code="${2:-1}"
    err "Unexpected failure in phase: $CURRENT_PHASE (line $line_no, exit $exit_code)."
    err "Please rerun install and share this phase/line if it fails again."
    exit "$exit_code"
}

trap 'handle_unexpected_error "$LINENO" "$?"' ERR

readonly SECURECLAW_STATE_DIR="/etc/secureclaw"
readonly SECURECLAW_INSTALL_STATE_FILE="$SECURECLAW_STATE_DIR/install.env"
readonly SECURECLAW_PUBLIC_STATE_FILE="/etc/secureclaw-public.env"
readonly OPENCLAW_REPO_URL="https://github.com/openclaw/openclaw.git"
readonly OPENCLAW_DEFAULT_REF="stable"
readonly SECURECLAW_UNINSTALL_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/uninstall.sh"
readonly SECURECLAW_PANIC_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/panic.sh"
readonly SECURECLAW_UPDATE_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/update.sh"
readonly SECURECLAW_BACKUP_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/backup.sh"
readonly SECURECLAW_CONNECT_LINUX_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/connect-openclaw-linux.sh"
readonly SECURECLAW_CONNECT_MACOS_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/connect-openclaw-macos.sh"
readonly SECURECLAW_CONNECT_WINDOWS_URL="https://raw.githubusercontent.com/InverseAltruism/SecureClaw/main/connect-openclaw-windows.ps1"

get_user_home() {
    local user_name="$1"
    local user_home=""
    user_home=$(getent passwd "$user_name" | awk -F: 'NR==1 {print $6}')
    [[ -n "$user_home" ]] || die "Unable to resolve home directory for user: $user_name"
    echo "$user_home"
}

run_user_systemctl() {
    local user_name="$1"
    shift
    sudo -u "$user_name" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        systemctl --user "$@"
}

user_systemd_available() {
    local user_name="$1"
    run_user_systemctl "$user_name" show-environment >/dev/null 2>&1
}

next_subid_start() {
    local file_path="$1"
    local max_end=100000

    if [[ -f "$file_path" ]]; then
        while IFS=: read -r _ start count; do
            [[ "$start" =~ ^[0-9]+$ ]] || continue
            [[ "$count" =~ ^[0-9]+$ ]] || continue
            local end=$((start + count))
            if (( end > max_end )); then
                max_end=$end
            fi
        done < "$file_path"
    fi

    # Align to 65536 to avoid fragmented ranges.
    echo $(( ((max_end + 65535) / 65536) * 65536 ))
}

write_install_manifest() {
    mkdir -p "$SECURECLAW_STATE_DIR"
    chmod 700 "$SECURECLAW_STATE_DIR"

    cat > "$SECURECLAW_INSTALL_STATE_FILE" << EOF
SYSTEM_USER=$SYSTEM_USER
INSTALL_DIR=$INSTALL_DIR
CONTAINER_RUNTIME=$CONTAINER_RUNTIME
SECURITY_TIER=$SECURITY_TIER
INSTALL_PROFILE=$INSTALL_PROFILE
ENABLE_SYSTEMD=$ENABLE_SYSTEMD
GATEWAY_PORT=$GATEWAY_PORT
BRIDGE_PORT=$BRIDGE_PORT
USER_CREATED_BY_SECURECLAW=$USER_CREATED_BY_SECURECLAW
LINGER_ENABLED_BY_SECURECLAW=$LINGER_ENABLED_BY_SECURECLAW
SUBUID_ADDED_BY_SECURECLAW=$SUBUID_ADDED_BY_SECURECLAW
SUBGID_ADDED_BY_SECURECLAW=$SUBGID_ADDED_BY_SECURECLAW
SUBUID_RANGE=${SUBUID_RANGE:-}
SUBGID_RANGE=${SUBGID_RANGE:-}
OPENCLAW_REF_RESOLVED=${OPENCLAW_REF_RESOLVED:-unknown}
CONTROL_UI_AUTH_MODE=${CONTROL_UI_AUTH_MODE:-strict}
PACKAGES_INSTALLED_BY_SECURECLAW=${PACKAGES_INSTALLED_BY_SECURECLAW:-}
DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW=$DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW
DOCKER_APT_KEY_ADDED_BY_SECURECLAW=$DOCKER_APT_KEY_ADDED_BY_SECURECLAW
EOF
    chmod 600 "$SECURECLAW_INSTALL_STATE_FILE"

    cat > "$SECURECLAW_PUBLIC_STATE_FILE" << EOF
GATEWAY_PORT=$GATEWAY_PORT
BRIDGE_PORT=$BRIDGE_PORT
CONTAINER_RUNTIME=$CONTAINER_RUNTIME
SECURITY_TIER=$SECURITY_TIER
INSTALL_PROFILE=$INSTALL_PROFILE
CONTROL_UI_AUTH_MODE=${CONTROL_UI_AUTH_MODE:-strict}
EOF
    chmod 644 "$SECURECLAW_PUBLIC_STATE_FILE"
}

cpu_quota_percent_from_limit() {
    local cpu_limit="$1"
    awk -v c="$cpu_limit" 'BEGIN { printf "%d", (c * 100) }'
}

mark_packages_if_missing() {
    local pkg
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            case " ${PACKAGES_INSTALLED_BY_SECURECLAW:-} " in
                *" $pkg "*) ;;
                *)
                    if [[ -n "${PACKAGES_INSTALLED_BY_SECURECLAW:-}" ]]; then
                        PACKAGES_INSTALLED_BY_SECURECLAW+=" "
                    fi
                    PACKAGES_INSTALLED_BY_SECURECLAW+="$pkg"
                    ;;
            esac
        fi
    done
}

download_url_to_file() {
    local url="$1"
    local output_path="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output_path"
        return
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO "$output_path" "$url"
        return
    fi
    return 1
}

resolve_openclaw_default_ref() {
    local requested_ref="$1"
    if [[ "$requested_ref" != "stable" ]]; then
        echo "$requested_ref"
        return 0
    fi

    local latest_tag=""
    if command -v curl >/dev/null 2>&1; then
        latest_tag="$(curl -fsSL "https://api.github.com/repos/openclaw/openclaw/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    elif command -v wget >/dev/null 2>&1; then
        latest_tag="$(wget -qO- "https://api.github.com/repos/openclaw/openclaw/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    fi

    if [[ -n "$latest_tag" ]]; then
        echo "$latest_tag"
        return 0
    fi

    warn "Could not resolve latest stable OpenClaw release tag; falling back to main."
    echo "main"
}

install_local_or_remote_script() {
    local target_path="$1"
    local local_path="$2"
    local remote_url="$3"
    local label="$4"

    if [[ -f "$local_path" ]]; then
        install -m 0755 "$local_path" "$target_path"
        info "Installed $label command: $target_path"
        return 0
    fi

    local tmp_script
    tmp_script=$(mktemp "/tmp/secureclaw-${label}-XXXXXX.sh")
    if download_url_to_file "$remote_url" "$tmp_script"; then
        install -m 0755 "$tmp_script" "$target_path"
        rm -f "$tmp_script"
        info "Downloaded and installed $label command: $target_path"
        return 0
    fi

    rm -f "$tmp_script" || true
    warn "Could not install $label command at $target_path (local file missing and download failed)."
    return 1
}

# Install metadata flags for full uninstall/revert.
USER_CREATED_BY_SECURECLAW=0
LINGER_ENABLED_BY_SECURECLAW=0
SUBUID_ADDED_BY_SECURECLAW=0
SUBGID_ADDED_BY_SECURECLAW=0
SUBUID_RANGE=""
SUBGID_RANGE=""
PACKAGES_INSTALLED_BY_SECURECLAW=""
DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW=0
DOCKER_APT_KEY_ADDED_BY_SECURECLAW=0
OPENCLAW_REF_RESOLVED="unknown"
INSTALL_PROFILE="quick"
ARG_INSTALL_PROFILE=""
CONTROL_UI_AUTH_MODE="strict"

MENU_SELECTION=""

supports_interactive_menu() {
    [[ -t 0 && -t 1 ]]
}

menu_select() {
    local prompt="$1"
    local default_value="$2"
    shift 2

    if ! supports_interactive_menu; then
        MENU_SELECTION="$default_value"
        return
    fi

    local -a values=()
    local -a labels=()
    local entry=""
    for entry in "$@"; do
        values+=("${entry%%|*}")
        labels+=("${entry#*|}")
    done

    local index=0
    local i
    for i in "${!values[@]}"; do
        if [[ "${values[$i]}" == "$default_value" ]]; then
            index=$i
            break
        fi
    done

    local key=""
    local key2=""
    local lines_to_clear=0
    while true; do
        echo -e "${BOLD}${prompt}${RESET}"
        for i in "${!labels[@]}"; do
            if (( i == index )); then
                echo -e "  ${GREEN}➤ ${labels[$i]}${RESET}"
            else
                echo -e "    ${labels[$i]}"
            fi
        done
        echo -e "${DIM}Use ↑/↓ and press Enter.${RESET}"

        IFS= read -rsn1 key || true
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 key2 || true
            case "$key2" in
                "[A")
                    index=$(( (index - 1 + ${#labels[@]}) % ${#labels[@]} ))
                    ;;
                "[B")
                    index=$(( (index + 1) % ${#labels[@]} ))
                    ;;
            esac
        elif [[ "$key" =~ [0-9A-Za-z] ]]; then
            for i in "${!values[@]}"; do
                if [[ "${values[$i]}" == "$key" ]]; then
                    MENU_SELECTION="${values[$i]}"
                    return
                fi
            done
        elif [[ -z "$key" || "$key" == $'\n' ]]; then
            MENU_SELECTION="${values[$index]}"
            break
        fi

        lines_to_clear=$(( ${#labels[@]} + 2 ))
        for (( i=0; i<lines_to_clear; i++ )); do
            printf '\033[1A\033[2K\r'
        done
    done
}

is_valid_username() {
    local user_name="$1"
    [[ "$user_name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1024 && port <= 65534 ))
}

is_port_in_use() {
    local port="$1"
    if ! command -v ss >/dev/null 2>&1; then
        return 1
    fi
    ss -ltn "sport = :$port" 2>/dev/null | awk 'NR>1 {found=1} END {exit(found ? 0 : 1)}'
}

port_listener_summary() {
    local port="$1"
    if ! command -v ss >/dev/null 2>&1; then
        return 0
    fi
    ss -ltnp "sport = :$port" 2>/dev/null | awk 'NR>1 {print $4 " " $6}'
}

find_next_free_port_pair() {
    local start_port="$1"
    local candidate="$start_port"
    local bridge=0

    while (( candidate <= 65533 )); do
        bridge=$((candidate + 1))
        if ! is_port_in_use "$candidate" && ! is_port_in_use "$bridge"; then
            echo "$candidate:$bridge"
            return 0
        fi
        ((candidate++))
    done

    return 1
}

is_valid_token() {
    local token="$1"
    [[ "$token" =~ ^[A-Fa-f0-9]{64}$ ]]
}

is_valid_cpu_limit() {
    local cpu="$1"
    [[ "$cpu" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v c="$cpu" 'BEGIN { exit(c > 0 ? 0 : 1) }'
}

is_valid_memory_limit() {
    local mem="$1"
    [[ "$mem" =~ ^[0-9]+([mMgG])$ ]]
}

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
   ____                            ____  _
  / ___|  ___  ___ _   _ _ __ ___ / ___|| | __ ___      __
  \___ \ / _ \/ __| | | | '__/ _ \ |    | |/ _` \ \ /\ / /
   ___) |  __/ (__| |_| | | |  __/ |___ | | (_| |\ V  V /
  |____/ \___|\___|\__,_|_|  \___|\_____||_|\__,_| \_/\_/

  Run OpenClaw in a fortress. Maximum isolation. Zero trust.
EOF
    echo -e "${RESET}"
    echo
}

# ============================================================================
# SYSTEM INFO & CONTAINER RUNTIME PROMPTS
# ============================================================================
prompt_system_info() {
    section "Section 1/10: System Information"

    # Detect OS
    local os_name="Unknown"
    local os_version="Unknown"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        os_name="${NAME:-Unknown}"
        os_version="${VERSION:-${VERSION_ID:-Unknown}}"
    fi

    # Detect architecture
    local arch
    arch=$(uname -m)

    # Detect RAM
    local total_ram="Unknown"
    if [[ -f /proc/meminfo ]]; then
        local mem_kb
        mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
        total_ram="$((mem_kb / 1024)) MB"
    elif command -v free &>/dev/null; then
        total_ram=$(free -h | awk '/^Mem:/ {print $2}')
    fi

    # Detect CPU cores
    local cpu_cores="Unknown"
    if command -v nproc &>/dev/null; then
        cpu_cores=$(nproc)
    fi

    # Detect existing runtimes
    local runtimes=""
    if command -v podman &>/dev/null; then
        runtimes+="podman ($(podman --version 2>/dev/null | awk '{print $NF}')) "
    fi
    if command -v docker &>/dev/null; then
        runtimes+="docker ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')) "
    fi
    if [[ -z "$runtimes" ]]; then
        runtimes="none detected"
    fi

    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}System Information${RESET}                                              ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════════╣${RESET}"
    printf "${BOLD}${CYAN}║${RESET}  %-16s %-48s ${BOLD}${CYAN}║${RESET}\n" "OS:" "$os_name $os_version"
    printf "${BOLD}${CYAN}║${RESET}  %-16s %-48s ${BOLD}${CYAN}║${RESET}\n" "Architecture:" "$arch"
    printf "${BOLD}${CYAN}║${RESET}  %-16s %-48s ${BOLD}${CYAN}║${RESET}\n" "Total RAM:" "$total_ram"
    printf "${BOLD}${CYAN}║${RESET}  %-16s %-48s ${BOLD}${CYAN}║${RESET}\n" "CPU Cores:" "$cpu_cores"
    printf "${BOLD}${CYAN}║${RESET}  %-16s %-48s ${BOLD}${CYAN}║${RESET}\n" "Runtimes:" "$runtimes"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════╝${RESET}"
    echo

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Does this look correct? [Y/n]:${RESET} ")" -r SYS_CONFIRM
    SYS_CONFIRM=${SYS_CONFIRM:-Y}
    if [[ ! "$SYS_CONFIRM" =~ ^[Yy]$ && "$SYS_CONFIRM" != "" ]]; then
        warn "Continuing anyway — you can adjust settings in the following steps"
    fi
    info "System info recorded"
}

prompt_container_runtime() {
    section "Section 2/10: Container Runtime"
    echo
    echo "Choose your container runtime:"
    echo
    echo -e "  ${BOLD}1. Podman (rootless)${RESET} — ${GREEN}Recommended${RESET} for maximum security"
    dim "No daemon, no Docker socket to exploit, rootless by default."
    dim "Container runs as unprivileged UID — a compromise cannot reach root."
    dim "Requires: podman, uidmap, slirp4netns (installed automatically)"
    echo
    echo -e "  ${BOLD}2. Docker (rootless)${RESET} — Strong security with Docker tooling"
    dim "No root daemon, user-namespace isolation like Podman."
    dim "Choose this if you prefer Docker CLI but want rootless security."
    dim "Requires: docker-ce, docker-ce-rootless-extras, uidmap, slirp4netns"
    echo
    echo -e "  ${BOLD}3. Docker (standard + hardened)${RESET} — Standard Docker with hardening"
    dim "Uses the standard root Docker daemon, but the container itself is"
    dim "hardened with all security flags (cap-drop, no-new-privileges, etc.)."
    dim "Only choose this if rootless Docker/Podman is not available on your system."
    echo
    menu_select \
        "Select runtime" \
        "1" \
        "1|Podman (rootless) — recommended" \
        "2|Docker (rootless)" \
        "3|Docker (standard + hardened)"
    RUNTIME_CHOICE="${MENU_SELECTION:-1}"

    case "$RUNTIME_CHOICE" in
        1)
            CONTAINER_RUNTIME="podman"
            info "Selected: Podman (rootless)"
            ;;
        2)
            CONTAINER_RUNTIME="docker-rootless"
            info "Selected: Docker (rootless)"
            ;;
        3)
            CONTAINER_RUNTIME="docker"
            info "Selected: Docker (standard + hardened)"
            ;;
        *)
            warn "Invalid selection, using Podman (default)"
            CONTAINER_RUNTIME="podman"
            ;;
    esac
}

prompt_operation_mode() {
    section "Select Operation"
    echo
    echo -e "  ${BOLD}1. Install SecureClaw${RESET}"
    dim "Set up OpenClaw with your selected runtime and security tier"
    echo
    echo -e "  ${BOLD}2. Uninstall SecureClaw${RESET}"
    dim "Fully revert SecureClaw artifacts, user setup, and host-level hardening"
    echo
    echo -e "  ${BOLD}3. PANIC Stop (Emergency)${RESET}"
    dim "Immediately stop OpenClaw services, containers, and related processes"
    echo
    echo -e "  ${BOLD}4. Update Existing SecureClaw Install${RESET}"
    dim "Rebuild OpenClaw image and restart your current SecureClaw deployment"
    echo
    echo -e "  ${BOLD}5. Backup / Restore Agent Data${RESET}"
    dim "Create encrypted-safe backups for migration, rollback, and disaster recovery"
    echo
    menu_select \
        "Select operation" \
        "1" \
        "1|Install SecureClaw" \
        "2|Uninstall SecureClaw" \
        "3|PANIC Stop (Emergency)" \
        "4|Update Existing SecureClaw Install" \
        "5|Backup / Restore Agent Data"
    OPERATION_CHOICE="${MENU_SELECTION:-1}"
    case "$OPERATION_CHOICE" in
        1)
            OPERATION_MODE="install"
            info "Selected: Install"
            ;;
        2)
            OPERATION_MODE="uninstall"
            info "Selected: Uninstall"
            ;;
        3)
            OPERATION_MODE="panic"
            info "Selected: PANIC Stop"
            ;;
        4)
            OPERATION_MODE="update"
            info "Selected: Update"
            ;;
        5)
            OPERATION_MODE="backup"
            info "Selected: Backup / Restore"
            ;;
        *)
            warn "Invalid selection, using Install (default)"
            OPERATION_MODE="install"
            ;;
    esac
}

prompt_install_profile() {
    section "Installation Mode"
    echo
    echo -e "  ${BOLD}1. Quick Secure Install${RESET} — ${GREEN}Recommended${RESET}"
    dim "Best for non-technical users. Uses secure defaults and minimal prompts."
    dim "Defaults: Podman rootless, Balanced tier, systemd enabled."
    echo
    echo -e "  ${BOLD}2. Advanced Guided Install${RESET}"
    dim "Full control over runtime, security tier, paths, ports, and limits."
    echo

    menu_select \
        "Select installation mode" \
        "${ARG_INSTALL_PROFILE:-1}" \
        "1|Quick Secure Install" \
        "2|Advanced Guided Install"

    case "${MENU_SELECTION:-1}" in
        1)
            INSTALL_PROFILE="quick"
            info "Selected: Quick Secure Install"
            ;;
        2)
            INSTALL_PROFILE="advanced"
            info "Selected: Advanced Guided Install"
            ;;
        *)
            INSTALL_PROFILE="quick"
            info "Selected: Quick Secure Install (default)"
            ;;
    esac
}

apply_quick_secure_defaults() {
    section "Applying Quick Secure Defaults"

    CONTAINER_RUNTIME="podman"
    SECURITY_TIER="balanced"
    INSTALL_DIR="/home/openclaw/.openclaw"
    SYSTEM_USER="openclaw"
    ENABLE_SYSTEMD=1
    MEMORY_LIMIT="2g"
    CPU_LIMIT="2.0"
    PID_LIMIT=256
    CONTROL_UI_AUTH_MODE="strict"

    GATEWAY_PORT=18789
    BRIDGE_PORT=$((GATEWAY_PORT + 1))
    while is_port_in_use "$GATEWAY_PORT" || is_port_in_use "$BRIDGE_PORT"; do
        ((GATEWAY_PORT+=2))
        BRIDGE_PORT=$((GATEWAY_PORT + 1))
        if (( BRIDGE_PORT > 65534 )); then
            die "No free gateway/bridge port pair found in range 18789-65534. Use Advanced mode."
        fi
    done

    GATEWAY_TOKEN=$(generate_token)
    ANTHROPIC_API_KEY=""
    OPENAI_API_KEY=""
    OPENROUTER_API_KEY=""
    GEMINI_API_KEY=""

    info "Runtime: $CONTAINER_RUNTIME"
    info "Tier: $SECURITY_TIER"
    info "Install dir: $INSTALL_DIR"
    info "System user: $SYSTEM_USER"
    info "Gateway port: $GATEWAY_PORT (bridge: $BRIDGE_PORT)"
    info "Systemd: enabled"

    if [[ -t 0 ]]; then
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Configure API keys now? [y/N]:${RESET} ")" -r QUICK_KEYS
        if [[ "$QUICK_KEYS" =~ ^[Yy]$ ]]; then
            prompt_api_keys
        else
            info "Skipping API key setup for now (you can add them later in $INSTALL_DIR/.env)."
        fi
    else
        info "Non-interactive mode detected; skipping API key prompts."
    fi
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================
preflight_checks() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Please use: sudo bash install.sh"
    fi

    # Check OS
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
            warn "This installer is designed for Debian 12+ or Ubuntu 22.04+"
            warn "Detected: $PRETTY_NAME"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi

    info "Preflight checks passed"
}

# ============================================================================
# TOKEN GENERATION
# ============================================================================
generate_token() {
    # Try openssl first
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
        return
    fi

    # Try python3
    if command -v python3 &> /dev/null; then
        python3 -c "import secrets; print(secrets.token_hex(32))"
        return
    fi

    # Fallback to od
    if command -v od &> /dev/null; then
        od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
        return
    fi

    # If all else fails
    die "Cannot generate token: openssl, python3, and od are all unavailable"
}

# ============================================================================
# OPENCLAW REPO DISCOVERY
# ============================================================================
discover_openclaw_repo() {
    local repo_path=""
    local requested_openclaw_ref="${ARG_OPENCLAW_REF:-${OPENCLAW_REF:-$OPENCLAW_DEFAULT_REF}}"
    local openclaw_ref
    openclaw_ref="$(resolve_openclaw_default_ref "$requested_openclaw_ref")"

    # Check OPENCLAW_REPO env var
    if [[ -n "${OPENCLAW_REPO:-}" && -d "$OPENCLAW_REPO" ]]; then
        repo_path="$OPENCLAW_REPO"
        info "Using OpenClaw repo from OPENCLAW_REPO: $repo_path" >&2
        warn "Using local OpenClaw source; remote ref selection is skipped for local repos." >&2
    # Check for --openclaw-repo argument
    elif [[ -n "${ARG_OPENCLAW_REPO:-}" && -d "$ARG_OPENCLAW_REPO" ]]; then
        repo_path="$ARG_OPENCLAW_REPO"
        info "Using OpenClaw repo from argument: $repo_path" >&2
        warn "Using local OpenClaw source; remote ref selection is skipped for local repos." >&2
    # Check sibling directory
    elif [[ -d "$(dirname "$0")/../openclaw" ]]; then
        repo_path="$(cd "$(dirname "$0")/../openclaw" && pwd)"
        info "Found OpenClaw repo in sibling directory: $repo_path" >&2
        warn "Using local OpenClaw source; remote ref selection is skipped for local repos." >&2
    # Clone it
    else
        warn "No local OpenClaw source provided; cloning upstream OpenClaw repository." >&2
        info "Using OpenClaw ref: $openclaw_ref (requested: $requested_openclaw_ref)" >&2
        repo_path=$(mktemp -d /tmp/openclaw-XXXXXX)
        # mktemp creates 0700 by default; rootless build users must be able to traverse this path.
        chmod 755 "$repo_path" || die "Failed to adjust temporary repository directory permissions"
        git clone --filter=blob:none --no-checkout "$OPENCLAW_REPO_URL" "$repo_path" >&2 || \
            die "Failed to clone OpenClaw repository"
        git -C "$repo_path" fetch --depth 1 origin "$openclaw_ref" >&2 || \
            die "Failed to fetch OpenClaw ref: $openclaw_ref"
        git -C "$repo_path" checkout --detach FETCH_HEAD >&2 || \
            die "Failed to checkout requested OpenClaw ref"
        local resolved_ref
        resolved_ref=$(git -C "$repo_path" rev-parse HEAD)
        info "Resolved OpenClaw commit: $resolved_ref" >&2
        OPENCLAW_REF_RESOLVED="$resolved_ref"
        OPENCLAW_REPO_TEMP=1
    fi

    if [[ "$OPENCLAW_REF_RESOLVED" == "unknown" ]]; then
        OPENCLAW_REF_RESOLVED=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || echo "local-unversioned")
    fi

    # Verify Dockerfile exists
    if [[ ! -f "$repo_path/Dockerfile" ]]; then
        die "Dockerfile not found in $repo_path"
    fi

    echo "$repo_path"
}

# ============================================================================
# INTERACTIVE PROMPTS
# ============================================================================
prompt_security_level() {
    section "Section 3/10: Security Level"
    echo
    echo "Choose your security tier:"
    echo
    echo -e "  ${BOLD}1. Standard${RESET} — Maximum compatibility, baseline isolation"
    dim "Rootless container (or hardened Docker), token auth, localhost host-port exposure."
    dim "Best for: Development, troubleshooting, broad compatibility."
    echo
    echo -e "  ${BOLD}2. Balanced${RESET} — Secure + full OpenClaw features ${GREEN}(recommended)${RESET}"
    dim "Read-only root filesystem, cap-drop, no-new-privileges, resource limits."
    dim "Keeps ~/.openclaw writable for channels, credentials, onboarding, and extensions."
    dim "Best for: Production where you want strong security without breaking OpenClaw features."
    echo
    echo -e "  ${BOLD}3. Hardened (strict)${RESET} — Highest app-level restriction"
    dim "All Balanced controls plus workspace-only tool restrictions and read-only ~/.openclaw mount."
    dim "May limit OpenClaw features that need writes outside workspace (onboarding/channels/credentials)."
    echo
    echo -e "  ${BOLD}4. Paranoid${RESET} — Maximum isolation"
    dim "All Hardened (strict) features plus:"
    dim "  • Host egress firewall via nftables (blocks cloud metadata,"
    dim "    RFC1918 private networks, and lateral movement)"
    dim "  • Audit logging via auditd (monitors all process execution)"
    dim "  • Cron-based network anomaly detection (alerts on suspicious connections)"
    dim "  • Per-agent sandboxing (double containerization)"
    dim "Can impact browser/nodes/channels depending on network policy and sandbox settings."
    dim "Best for: Untrusted networks, high-security environments with accepted feature trade-offs."
    warn "Modifies host firewall (nftables) and installs audit monitoring"
    echo
    menu_select \
        "Select security tier" \
        "2" \
        "1|Standard — baseline compatibility" \
        "2|Balanced — secure + full-feature (recommended)" \
        "3|Hardened (strict) — restrictive profile" \
        "4|Paranoid — maximum isolation"
    SECURITY_LEVEL="${MENU_SELECTION:-2}"

    case "$SECURITY_LEVEL" in
        1)
            SECURITY_TIER="standard"
            info "Selected: Standard tier"
            ;;
        2)
            SECURITY_TIER="balanced"
            info "Selected: Balanced tier (recommended)"
            ;;
        3)
            SECURITY_TIER="hardened"
            info "Selected: Hardened (strict) tier"
            ;;
        4)
            SECURITY_TIER="paranoid"
            info "Selected: Paranoid tier"
            ;;
        *)
            warn "Invalid selection, using Balanced (default)"
            SECURITY_TIER="balanced"
            ;;
    esac
}

prompt_install_dir() {
    section "Section 4/10: Installation Directory"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Install directory:${RESET} ")" -r -i "/home/openclaw/.openclaw" -e INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/home/openclaw/.openclaw}
    
    CONFIG_DIR="$INSTALL_DIR"
    WORKSPACE_DIR="$INSTALL_DIR/workspace"
    
    info "Configuration: $CONFIG_DIR"
    info "Workspace: $WORKSPACE_DIR"
}

prompt_username() {
    section "Section 5/10: System User"
    echo
    while true; do
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}System username:${RESET} ")" -r -i "openclaw" -e SYSTEM_USER
        SYSTEM_USER=${SYSTEM_USER:-openclaw}
        if is_valid_username "$SYSTEM_USER"; then
            info "Will create system user: $SYSTEM_USER"
            break
        fi
        warn "Invalid username. Use lowercase Linux username format (e.g., openclaw, claw_user)."
    done
}

prompt_ports() {
    section "Section 6/10: Gateway Port"
    echo
    while true; do
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Gateway port:${RESET} ")" -r -i "18789" -e GATEWAY_PORT
        GATEWAY_PORT=${GATEWAY_PORT:-18789}
        if ! is_valid_port "$GATEWAY_PORT"; then
            warn "Gateway port must be a number between 1024 and 65534."
            continue
        fi

        BRIDGE_PORT=$((GATEWAY_PORT + 1))
        if ! is_valid_port "$BRIDGE_PORT"; then
            warn "Gateway port is too high. Choose 65533 or lower."
            continue
        fi

        if is_port_in_use "$GATEWAY_PORT"; then
            warn "Port $GATEWAY_PORT is already in use."
            local listener_lines=""
            listener_lines="$(port_listener_summary "$GATEWAY_PORT" || true)"
            if [[ -n "$listener_lines" ]]; then
                dim "Current listener(s):"
                while IFS= read -r line; do
                    [[ -n "$line" ]] || continue
                    dim "  $line"
                done <<< "$listener_lines"
            fi
            local suggested_pair=""
            suggested_pair="$(find_next_free_port_pair "$GATEWAY_PORT" || true)"
            if [[ -n "$suggested_pair" ]]; then
                local suggested_gateway="${suggested_pair%%:*}"
                local suggested_bridge="${suggested_pair##*:}"
                read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Use next free pair $suggested_gateway/$suggested_bridge? [Y/n]:${RESET} ")" -r USE_SUGGESTED
                USE_SUGGESTED=${USE_SUGGESTED:-Y}
                if [[ "$USE_SUGGESTED" =~ ^[Yy]$ ]]; then
                    GATEWAY_PORT="$suggested_gateway"
                    BRIDGE_PORT="$suggested_bridge"
                    info "Gateway port: $GATEWAY_PORT"
                    info "Bridge port: $BRIDGE_PORT"
                    break
                fi
            fi
            continue
        fi
        if is_port_in_use "$BRIDGE_PORT"; then
            warn "Bridge port $BRIDGE_PORT is already in use."
            local listener_lines=""
            listener_lines="$(port_listener_summary "$BRIDGE_PORT" || true)"
            if [[ -n "$listener_lines" ]]; then
                dim "Current listener(s):"
                while IFS= read -r line; do
                    [[ -n "$line" ]] || continue
                    dim "  $line"
                done <<< "$listener_lines"
            fi
            local suggested_pair=""
            suggested_pair="$(find_next_free_port_pair "$GATEWAY_PORT" || true)"
            if [[ -n "$suggested_pair" ]]; then
                local suggested_gateway="${suggested_pair%%:*}"
                local suggested_bridge="${suggested_pair##*:}"
                read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Use next free pair $suggested_gateway/$suggested_bridge? [Y/n]:${RESET} ")" -r USE_SUGGESTED
                USE_SUGGESTED=${USE_SUGGESTED:-Y}
                if [[ "$USE_SUGGESTED" =~ ^[Yy]$ ]]; then
                    GATEWAY_PORT="$suggested_gateway"
                    BRIDGE_PORT="$suggested_bridge"
                    info "Gateway port: $GATEWAY_PORT"
                    info "Bridge port: $BRIDGE_PORT"
                    break
                fi
            fi
            continue
        fi

        info "Gateway port: $GATEWAY_PORT"
        info "Bridge port: $BRIDGE_PORT"
        break
    done
}

prompt_token() {
    echo
    info "Generating 256-bit gateway token..."
    AUTO_TOKEN=$(generate_token)
    echo
    while true; do
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Gateway token:${RESET} ")" -r -i "$AUTO_TOKEN" -e GATEWAY_TOKEN
        GATEWAY_TOKEN=${GATEWAY_TOKEN:-$AUTO_TOKEN}
        if is_valid_token "$GATEWAY_TOKEN"; then
            dim "Token: ${GATEWAY_TOKEN:0:16}...${GATEWAY_TOKEN: -8}"
            break
        fi
        warn "Gateway token must be exactly 64 hex characters (256-bit)."
    done
}

prompt_control_ui_auth_mode() {
    section "Section 7/10: Control UI Access Mode"
    echo
    echo "Choose how dashboard/control UI access is handled:"
    echo
    echo -e "  ${BOLD}A. Strict pairing (recommended)${RESET}"
    dim "Secure default: token auth + device/client pairing approvals."
    dim "Best for production and remote access over SSH tunnel/Tailscale."
    echo
    echo -e "  ${BOLD}B. Compatibility mode (allow insecure UI auth)${RESET}"
    dim "Fallback for environments where pairing flow cannot be completed."
    dim "Use only behind SSH tunnel/Tailscale; do not expose gateway directly."
    warn "Compatibility mode weakens UI authentication protections."
    echo
    menu_select \
        "Select control UI access mode" \
        "A" \
        "A|Strict pairing (recommended)" \
        "B|Compatibility (allowInsecureAuth)"

    case "${MENU_SELECTION:-A}" in
        A|a)
            CONTROL_UI_AUTH_MODE="strict"
            info "Selected: Strict pairing (recommended)"
            ;;
        B|b)
            CONTROL_UI_AUTH_MODE="compatibility"
            warn "Selected: Compatibility mode (allowInsecureAuth enabled)"
            ;;
        *)
            CONTROL_UI_AUTH_MODE="strict"
            info "Selected: Strict pairing (default)"
            ;;
    esac
}

prompt_api_keys() {
    section "Section 8/10: API Keys (optional)"
    echo
    dim "Configure API keys for the LLM providers you plan to use."
    dim "Keys are stored in a protected .env file (mode 600)."
    echo

    # Initialize all keys as empty
    ANTHROPIC_API_KEY=""
    OPENAI_API_KEY=""
    OPENROUTER_API_KEY=""
    GEMINI_API_KEY=""

    while true; do
        echo
        echo "  Which API keys would you like to configure?"
        echo
        local anthro_status="not set"
        local openai_status="not set"
        local openrouter_status="not set"
        local gemini_status="not set"
        [[ -n "$ANTHROPIC_API_KEY" ]] && anthro_status="${GREEN}configured${RESET}"
        [[ -n "$OPENAI_API_KEY" ]] && openai_status="${GREEN}configured${RESET}"
        [[ -n "$OPENROUTER_API_KEY" ]] && openrouter_status="${GREEN}configured${RESET}"
        [[ -n "$GEMINI_API_KEY" ]] && gemini_status="${GREEN}configured${RESET}"

        echo -e "  ${BOLD}1.${RESET} Anthropic (Claude)     [$anthro_status]"
        echo -e "  ${BOLD}2.${RESET} OpenAI (GPT)           [$openai_status]"
        echo -e "  ${BOLD}3.${RESET} OpenRouter             [$openrouter_status]"
        echo -e "  ${BOLD}4.${RESET} Google Gemini          [$gemini_status]"
        echo -e "  ${BOLD}d.${RESET} Done — continue to next step"
        echo

        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Select a key to configure [1/2/3/4/d]:${RESET} ")" -r key_choice
        key_choice=${key_choice:-d}

        case "$key_choice" in
            1)
                read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}ANTHROPIC_API_KEY:${RESET} ")" -rs ANTHROPIC_API_KEY || true
                echo
                if [[ -n "$ANTHROPIC_API_KEY" ]]; then
                    info "Anthropic key configured"
                else
                    dim "Anthropic key cleared"
                fi
                ;;
            2)
                read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}OPENAI_API_KEY:${RESET} ")" -rs OPENAI_API_KEY || true
                echo
                if [[ -n "$OPENAI_API_KEY" ]]; then
                    info "OpenAI key configured"
                else
                    dim "OpenAI key cleared"
                fi
                ;;
            3)
                read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}OPENROUTER_API_KEY:${RESET} ")" -rs OPENROUTER_API_KEY || true
                echo
                if [[ -n "$OPENROUTER_API_KEY" ]]; then
                    info "OpenRouter key configured"
                else
                    dim "OpenRouter key cleared"
                fi
                ;;
            4)
                read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}GEMINI_API_KEY:${RESET} ")" -rs GEMINI_API_KEY || true
                echo
                if [[ -n "$GEMINI_API_KEY" ]]; then
                    info "Gemini key configured"
                else
                    dim "Gemini key cleared"
                fi
                ;;
            [dD])
                break
                ;;
            *)
                warn "Invalid selection. Enter 1-4 to configure a key, or d to continue."
                ;;
        esac
    done

    local key_count=0
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && key_count=$((key_count + 1))
    [[ -n "${OPENAI_API_KEY:-}" ]] && key_count=$((key_count + 1))
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && key_count=$((key_count + 1))
    [[ -n "${GEMINI_API_KEY:-}" ]] && key_count=$((key_count + 1))

    echo
    info "Configured $key_count API key(s)"
}

prompt_systemd() {
    section "Section 9/10: Systemd Auto-Start"
    echo
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Enable systemd Quadlet for auto-start? [Y/n]:${RESET} ")" -r ENABLE_SYSTEMD
    else
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Enable systemd service for auto-start? [Y/n]:${RESET} ")" -r ENABLE_SYSTEMD
    fi
    ENABLE_SYSTEMD=${ENABLE_SYSTEMD:-Y}
    if [[ "$ENABLE_SYSTEMD" =~ ^[Yy]$ || "$ENABLE_SYSTEMD" == "" ]]; then
        ENABLE_SYSTEMD=1
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            info "Systemd Quadlet will be configured"
        else
            info "Systemd service will be configured"
        fi
    else
        ENABLE_SYSTEMD=0
        info "Manual start only"
    fi
}

prompt_resource_limits() {
    if [[ "$SECURITY_TIER" == "standard" ]]; then
        MEMORY_LIMIT=""
        CPU_LIMIT=""
        PID_LIMIT=""
        return
    fi

    section "Section 10/10: Resource Limits"
    echo
    while true; do
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Memory limit:${RESET} ")" -r -i "2g" -e MEMORY_LIMIT
        MEMORY_LIMIT=${MEMORY_LIMIT:-2g}
        if is_valid_memory_limit "$MEMORY_LIMIT"; then
            break
        fi
        warn "Memory limit must be like 512m, 2g, 4G."
    done

    while true; do
        read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}CPU limit:${RESET} ")" -r -i "2.0" -e CPU_LIMIT
        CPU_LIMIT=${CPU_LIMIT:-2.0}
        if is_valid_cpu_limit "$CPU_LIMIT"; then
            break
        fi
        warn "CPU limit must be a positive number (e.g., 1, 1.5, 2.0)."
    done

    PID_LIMIT=256
    
    info "Memory: $MEMORY_LIMIT"
    info "CPUs: $CPU_LIMIT"
    info "PIDs: $PID_LIMIT"
}

show_summary() {
    section "Configuration Summary"
    echo
    echo -e "${BOLD}Install Mode:${RESET}        $INSTALL_PROFILE"
    echo -e "${BOLD}Container Runtime:${RESET}   $CONTAINER_RUNTIME"
    echo -e "${BOLD}Security Tier:${RESET}       $SECURITY_TIER"
    echo -e "${BOLD}Install Directory:${RESET}   $INSTALL_DIR"
    echo -e "${BOLD}System User:${RESET}         $SYSTEM_USER"
    echo -e "${BOLD}Gateway Port:${RESET}        $GATEWAY_PORT"
    echo -e "${BOLD}Bridge Port:${RESET}         $BRIDGE_PORT"
    echo -e "${BOLD}Control UI Mode:${RESET}     $CONTROL_UI_AUTH_MODE"
    echo -e "${BOLD}Gateway Token:${RESET}       ${GATEWAY_TOKEN:0:16}...${GATEWAY_TOKEN: -8}"
    
    local key_count=0
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && key_count=$((key_count + 1))
    [[ -n "${OPENAI_API_KEY:-}" ]] && key_count=$((key_count + 1))
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && key_count=$((key_count + 1))
    [[ -n "${GEMINI_API_KEY:-}" ]] && key_count=$((key_count + 1))
    echo -e "${BOLD}API Keys:${RESET}            $key_count configured"
    
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
        echo -e "${BOLD}Systemd:${RESET}             Enabled"
    else
        echo -e "${BOLD}Systemd:${RESET}             Disabled"
    fi
    
    if [[ "$SECURITY_TIER" != "standard" ]]; then
        echo -e "${BOLD}Memory Limit:${RESET}        $MEMORY_LIMIT"
        echo -e "${BOLD}CPU Limit:${RESET}           $CPU_LIMIT"
        echo -e "${BOLD}PID Limit:${RESET}           $PID_LIMIT"
    fi
    
    echo
    if [[ "$SECURITY_TIER" == "hardened" ]]; then
        warn "Hardened (strict) tier may limit some OpenClaw features requiring writable ~/.openclaw paths"
    elif [[ "$SECURITY_TIER" == "paranoid" ]]; then
        warn "Paranoid tier will modify host firewall (nftables) and install audit monitoring"
        warn "Paranoid tier may impact browser/nodes/channels depending on network and sandbox policies"
    fi
    if [[ "$CONTROL_UI_AUTH_MODE" == "compatibility" ]]; then
        warn "Compatibility mode enables controlUi.allowInsecureAuth for easier UI access."
        warn "Use only through SSH tunnel/Tailscale and rotate gateway tokens regularly."
    fi
    
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Proceed with installation? [Y/n]:${RESET} ")" -r CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ && "$CONFIRM" != "" ]]; then
        echo
        info "Installation cancelled"
        exit 0
    fi
}

# ============================================================================
# LAYER 1: SYSTEM USER & DEPENDENCIES
# ============================================================================
layer1_system_setup() {
    section "Layer 1: System User & Dependencies"
    
    # Install dependencies
    info "Installing dependencies..."
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        mark_packages_if_missing podman uidmap slirp4netns git
        apt-get update -qq
        apt-get install -y -qq podman uidmap slirp4netns git >/dev/null 2>&1 || \
            die "Failed to install dependencies"
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        mark_packages_if_missing ca-certificates curl gnupg git uidmap slirp4netns
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg git uidmap slirp4netns >/dev/null 2>&1 || \
            die "Failed to install base dependencies"
        if ! command -v docker &>/dev/null; then
            info "Installing Docker CE..."
            mark_packages_if_missing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-ce-rootless-extras
            install -m 0755 -d /etc/apt/keyrings
            # shellcheck source=/dev/null
            source /etc/os-release
            if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
                DOCKER_APT_KEY_ADDED_BY_SECURECLAW=1
            fi
            curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
                DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW=1
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-ce-rootless-extras >/dev/null 2>&1 || \
                die "Failed to install Docker CE"
        else
            mark_packages_if_missing docker-ce-rootless-extras uidmap slirp4netns
            apt-get install -y -qq docker-ce-rootless-extras uidmap slirp4netns >/dev/null 2>&1 || \
                die "Failed to install Docker rootless extras"
        fi
    elif [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
        mark_packages_if_missing ca-certificates curl gnupg git
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg git >/dev/null 2>&1 || \
            die "Failed to install base dependencies"
        if ! command -v docker &>/dev/null; then
            info "Installing Docker CE..."
            mark_packages_if_missing docker-ce docker-ce-cli containerd.io docker-buildx-plugin
            install -m 0755 -d /etc/apt/keyrings
            # shellcheck source=/dev/null
            source /etc/os-release
            if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
                DOCKER_APT_KEY_ADDED_BY_SECURECLAW=1
            fi
            curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
                DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW=1
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin >/dev/null 2>&1 || \
                die "Failed to install Docker CE"
        fi
    fi
    
    # Create system user
    if ! id "$SYSTEM_USER" &>/dev/null; then
        info "Creating system user: $SYSTEM_USER"
        useradd --system --create-home --shell /usr/sbin/nologin "$SYSTEM_USER" || \
            die "Failed to create user"
        USER_CREATED_BY_SECURECLAW=1
    else
        info "User $SYSTEM_USER already exists"
    fi
    
    # Get user info
    USER_UID=$(id -u "$SYSTEM_USER")
    USER_GID=$(id -g "$SYSTEM_USER")
    USER_HOME=$(get_user_home "$SYSTEM_USER")
    
    # Enable linger (needed for rootless runtimes)
    if [[ "$CONTAINER_RUNTIME" != "docker" ]]; then
        local linger_state="no"
        linger_state=$(loginctl show-user "$SYSTEM_USER" -p Linger --value 2>/dev/null || echo "no")
        info "Enabling systemd linger for $SYSTEM_USER"
        loginctl enable-linger "$SYSTEM_USER" || \
            warn "Failed to enable linger (non-fatal)"
        if [[ "$linger_state" != "yes" ]]; then
            LINGER_ENABLED_BY_SECURECLAW=1
        fi
    fi
    
    # Configure subuid/subgid (needed for rootless runtimes)
    if [[ "$CONTAINER_RUNTIME" != "docker" ]]; then
        touch /etc/subuid /etc/subgid

        if ! awk -F: -v u="$SYSTEM_USER" '$1==u {found=1} END {exit(found ? 0 : 1)}' /etc/subuid; then
            local subuid_start
            subuid_start=$(next_subid_start /etc/subuid)
            info "Configuring subuid mapping"
            echo "$SYSTEM_USER:$subuid_start:65536" >> /etc/subuid
            SUBUID_ADDED_BY_SECURECLAW=1
            SUBUID_RANGE="$subuid_start:65536"
        fi
        
        if ! awk -F: -v u="$SYSTEM_USER" '$1==u {found=1} END {exit(found ? 0 : 1)}' /etc/subgid; then
            local subgid_start
            subgid_start=$(next_subid_start /etc/subgid)
            info "Configuring subgid mapping"
            echo "$SYSTEM_USER:$subgid_start:65536" >> /etc/subgid
            SUBGID_ADDED_BY_SECURECLAW=1
            SUBGID_RANGE="$subgid_start:65536"
        fi
    fi
    
    # Ensure XDG_RUNTIME_DIR exists
    XDG_RUNTIME_DIR="/run/user/$USER_UID"
    if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
        info "Creating XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
        mkdir -p "$XDG_RUNTIME_DIR"
        chown "$SYSTEM_USER:$SYSTEM_USER" "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
    fi
    
    # Set up Docker rootless for the user
    if [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        info "Setting up Docker rootless for $SYSTEM_USER..."
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            dockerd-rootless-setuptool.sh install || \
            die "Failed to set up Docker rootless"

        # Wait for Docker rootless socket to become available
        local docker_sock="$XDG_RUNTIME_DIR/docker.sock"
        info "Waiting for Docker rootless socket at $docker_sock..."
        local retries=0
        while [[ ! -S "$docker_sock" && $retries -lt 30 ]]; do
            sleep 1
            ((retries++))
        done
        if [[ ! -S "$docker_sock" ]]; then
            die "Docker rootless socket not found at $docker_sock after 30s. Check logs with: sudo -u $SYSTEM_USER journalctl --user -u docker"
        fi
        info "Docker rootless socket is ready"
    fi
    
    info "Layer 1 complete"
}

# ============================================================================
# LAYER 2: CONTAINER IMAGE
# ============================================================================
layer2_container_image() {
    section "Layer 2: Container Image"
    
    # Discover OpenClaw repo
    OPENCLAW_PATH=$(discover_openclaw_repo)

    # Ensure rootless runtime user can read cloned source.
    if [[ "$CONTAINER_RUNTIME" == "podman" || "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        if ! sudo -u "$SYSTEM_USER" test -r "$OPENCLAW_PATH/Dockerfile" 2>/dev/null; then
            info "Adjusting source tree permissions for rootless build user..."
            chmod -R a+rX "$OPENCLAW_PATH" || die "Failed to make OpenClaw source readable for $SYSTEM_USER"
        fi
    fi
    
    info "Building OpenClaw image from $OPENCLAW_PATH..."
    
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        # Build image in the service user's rootless store.
        sudo -u "$SYSTEM_USER" \
            XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            podman --log-level=error build -t openclaw:local -f "$OPENCLAW_PATH/Dockerfile" "$OPENCLAW_PATH" || \
            die "Failed to build container image"
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        # Build as user using rootless docker
        sudo -u "$SYSTEM_USER" \
            XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" \
            docker build -t openclaw:local -f "$OPENCLAW_PATH/Dockerfile" "$OPENCLAW_PATH" || \
            die "Failed to build container image"
    else
        # Standard Docker build
        docker build -t openclaw:local -f "$OPENCLAW_PATH/Dockerfile" "$OPENCLAW_PATH" || \
            die "Failed to build container image"
    fi
    
    # Cleanup temp repo if we cloned it
    if [[ -n "${OPENCLAW_REPO_TEMP:-}" ]]; then
        info "Cleaning up temporary OpenClaw clone"
        rm -rf "$OPENCLAW_PATH"
    fi
    
    info "Layer 2 complete"
}

# ============================================================================
# LAYER 6: CONFIGURATION (done before layer 3)
# ============================================================================
layer6_configuration() {
    section "Layer 6: Configuration"
    
    # Adjust install dir path if it's relative to user home
    if [[ "$INSTALL_DIR" =~ ^/home/$SYSTEM_USER/ ]]; then
        # Already absolute
        true
    elif [[ "$INSTALL_DIR" =~ ^\~ ]]; then
        INSTALL_DIR="${USER_HOME}/${INSTALL_DIR#\~/}"
    elif [[ ! "$INSTALL_DIR" =~ ^/ ]]; then
        INSTALL_DIR="${USER_HOME}/$INSTALL_DIR"
    fi
    
    CONFIG_DIR="$INSTALL_DIR"
    WORKSPACE_DIR="$INSTALL_DIR/workspace"
    
    # Ensure ownership before writing files (important on retries/reinstalls).
    mkdir -p "$CONFIG_DIR" || die "Failed to create config directory: $CONFIG_DIR"
    chown -R "$SYSTEM_USER:$SYSTEM_USER" "$CONFIG_DIR" || die "Failed to set ownership on $CONFIG_DIR"

    # Create directories as user
    info "Creating directory structure..."
    sudo -u "$SYSTEM_USER" mkdir -p "$CONFIG_DIR/canvas" || die "Failed to create $CONFIG_DIR/canvas"
    sudo -u "$SYSTEM_USER" mkdir -p "$CONFIG_DIR/cron" || die "Failed to create $CONFIG_DIR/cron"
    sudo -u "$SYSTEM_USER" mkdir -p "$WORKSPACE_DIR" || die "Failed to create workspace directory: $WORKSPACE_DIR"
    sudo -u "$SYSTEM_USER" chmod 700 "$CONFIG_DIR" || die "Failed to set permissions on $CONFIG_DIR"
    sudo -u "$SYSTEM_USER" chmod 700 "$WORKSPACE_DIR" || die "Failed to set permissions on $WORKSPACE_DIR"
    
    # Write .env file
    info "Writing .env file..."
    local env_file="$CONFIG_DIR/.env"
    local env_tmp
    env_tmp=$(mktemp /tmp/secureclaw-env-XXXXXX)
    {
        echo "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN"
        [[ -n "${ANTHROPIC_API_KEY:-}" ]] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
        [[ -n "${OPENAI_API_KEY:-}" ]] && echo "OPENAI_API_KEY=$OPENAI_API_KEY"
        [[ -n "${OPENROUTER_API_KEY:-}" ]] && echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
        [[ -n "${GEMINI_API_KEY:-}" ]] && echo "GEMINI_API_KEY=$GEMINI_API_KEY"
    } > "$env_tmp"
    install -o "$SYSTEM_USER" -g "$SYSTEM_USER" -m 600 "$env_tmp" "$env_file" || die "Failed to write .env at $env_file"
    rm -f "$env_tmp"
    
    # Write openclaw.json
    info "Writing openclaw.json..."
    local config_file="$CONFIG_DIR/openclaw.json"
    
    local config_tmp
    config_tmp=$(mktemp /tmp/secureclaw-config-XXXXXX)
    local control_ui_allow_insecure="false"
    if [[ "$CONTROL_UI_AUTH_MODE" == "compatibility" ]]; then
        control_ui_allow_insecure="true"
    fi
    if [[ "$SECURITY_TIER" == "standard" ]]; then
        # Standard tier - compatibility-first
        cat > "$config_tmp" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "loopback",
    "auth": {
      "mode": "token"
    }
  },
  "controlUi": {
    "allowInsecureAuth": $control_ui_allow_insecure
  }
}
EOF
    elif [[ "$SECURITY_TIER" == "balanced" ]]; then
        # Balanced tier - secure defaults with full feature compatibility
        cat > "$config_tmp" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "lan",
    "auth": {
      "mode": "token"
    }
  },
  "controlUi": {
    "allowInsecureAuth": $control_ui_allow_insecure
  }
}
EOF
    elif [[ "$SECURITY_TIER" == "hardened" ]]; then
        # Hardened strict tier - lan binding + restrictions
        cat > "$config_tmp" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "lan",
    "auth": {
      "mode": "token"
    }
  },
  "controlUi": {
    "allowInsecureAuth": $control_ui_allow_insecure
  },
  "tools": {
    "exec": {
      "applyPatch": {
        "workspaceOnly": true
      }
    },
    "fs": {
      "workspaceOnly": true
    },
    "elevated": {
      "allowFrom": []
    }
  }
}
EOF
    else
        # Paranoid tier - all hardened + sandboxing
        cat > "$config_tmp" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "lan",
    "auth": {
      "mode": "token"
    }
  },
  "controlUi": {
    "allowInsecureAuth": $control_ui_allow_insecure
  },
  "tools": {
    "exec": {
      "applyPatch": {
        "workspaceOnly": true
      }
    },
    "fs": {
      "workspaceOnly": true
    },
    "elevated": {
      "allowFrom": []
    }
  },
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "session",
        "workspaceAccess": "rw",
        "docker": {
          "readOnlyRoot": true,
          "network": "none",
          "capDrop": ["ALL"],
          "pidsLimit": 64,
          "memory": "512m"
        }
      }
    }
  }
}
EOF
    fi

    install -o "$SYSTEM_USER" -g "$SYSTEM_USER" -m 600 "$config_tmp" "$config_file" || die "Failed to write config file: $config_file"
    rm -f "$config_tmp"
    
    info "Layer 6 complete"
}

# ============================================================================
# LAYER 3: CONTAINER HARDENING
# ============================================================================
build_podman_args() {
    PODMAN_ARGS=()
    
    # Base args for all tiers
    PODMAN_ARGS+=(--name openclaw)
    PODMAN_ARGS+=(--init)  # Proper signal handling and zombie reaping
    PODMAN_ARGS+=(--userns=keep-id)  # Map container UID to host user
    PODMAN_ARGS+=(--user "$USER_UID:$USER_GID")
    
    # Environment
    PODMAN_ARGS+=(-e HOME=/home/node)
    PODMAN_ARGS+=(-e TERM=xterm-256color)
    PODMAN_ARGS+=(--env-file "$CONFIG_DIR/.env")  # API keys from .env file
    
    # Port publishing (localhost only for security)
    PODMAN_ARGS+=(-p "127.0.0.1:$GATEWAY_PORT:$GATEWAY_PORT")
    PODMAN_ARGS+=(-p "127.0.0.1:$BRIDGE_PORT:$BRIDGE_PORT")
    
    # Tier-specific hardening
    if [[ "$SECURITY_TIER" == "standard" ]]; then
        # Standard: Compatibility-first, writable config/workspace.
        PODMAN_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:rw")
        PODMAN_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    elif [[ "$SECURITY_TIER" == "balanced" ]]; then
        # Balanced: Strong container hardening while preserving full OpenClaw features.
        PODMAN_ARGS+=(--read-only)  # Immutable root filesystem
        # shellcheck disable=SC2054
        PODMAN_ARGS+=(--tmpfs /tmp:size=256m,noexec,nosuid,nodev)
        # shellcheck disable=SC2054
        PODMAN_ARGS+=(--tmpfs /home/node/.cache:size=128m,noexec,nosuid,nodev)
        PODMAN_ARGS+=(--cap-drop=ALL)
        PODMAN_ARGS+=(--security-opt=no-new-privileges:true)
        [[ -n "$MEMORY_LIMIT" ]] && PODMAN_ARGS+=(--memory="$MEMORY_LIMIT")
        [[ -n "$MEMORY_LIMIT" ]] && PODMAN_ARGS+=(--memory-swap="$MEMORY_LIMIT")
        [[ -n "$CPU_LIMIT" ]] && PODMAN_ARGS+=(--cpus="$CPU_LIMIT")
        [[ -n "$PID_LIMIT" ]] && PODMAN_ARGS+=(--pids-limit="$PID_LIMIT")
        PODMAN_ARGS+=(--network=slirp4netns:allow_host_loopback=false)
        PODMAN_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:rw")
        PODMAN_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    else
        # Hardened strict / Paranoid: Maximum lockdown and workspace-only writes.
        PODMAN_ARGS+=(--read-only)  # Immutable root filesystem
        # shellcheck disable=SC2054
        PODMAN_ARGS+=(--tmpfs /tmp:size=256m,noexec,nosuid,nodev)  # Writable /tmp
        # shellcheck disable=SC2054
        PODMAN_ARGS+=(--tmpfs /home/node/.cache:size=128m,noexec,nosuid,nodev)  # Cache dir
        PODMAN_ARGS+=(--cap-drop=ALL)  # Drop all Linux capabilities
        PODMAN_ARGS+=(--security-opt=no-new-privileges:true)  # Prevent privilege escalation
        # Resource limits - only add if set (not empty for standard tier)
        [[ -n "$MEMORY_LIMIT" ]] && PODMAN_ARGS+=(--memory="$MEMORY_LIMIT")
        [[ -n "$MEMORY_LIMIT" ]] && PODMAN_ARGS+=(--memory-swap="$MEMORY_LIMIT")
        [[ -n "$CPU_LIMIT" ]] && PODMAN_ARGS+=(--cpus="$CPU_LIMIT")
        [[ -n "$PID_LIMIT" ]] && PODMAN_ARGS+=(--pids-limit="$PID_LIMIT")
        PODMAN_ARGS+=(--network=slirp4netns:allow_host_loopback=false)  # Isolated network
        
        # Read-only config, read-write workspace only.
        PODMAN_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:ro")
        PODMAN_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    fi
    
    # Image (use upstream default command for version compatibility)
    PODMAN_ARGS+=(openclaw:local)
}

build_docker_args() {
    DOCKER_ARGS=()
    
    # Base args for all tiers
    DOCKER_ARGS+=(--name openclaw)
    DOCKER_ARGS+=(--init)  # Proper signal handling and zombie reaping
    
    # Environment
    DOCKER_ARGS+=(-e HOME=/home/node)
    DOCKER_ARGS+=(-e TERM=xterm-256color)
    DOCKER_ARGS+=(--env-file "$CONFIG_DIR/.env")  # API keys from .env file
    
    # Port publishing (localhost only for security)
    DOCKER_ARGS+=(-p "127.0.0.1:$GATEWAY_PORT:$GATEWAY_PORT")
    DOCKER_ARGS+=(-p "127.0.0.1:$BRIDGE_PORT:$BRIDGE_PORT")
    
    if [[ "$SECURITY_TIER" == "standard" ]]; then
        # Standard: Compatibility-first, writable config/workspace.
        DOCKER_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:rw")
        DOCKER_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    elif [[ "$SECURITY_TIER" == "balanced" ]]; then
        # Balanced: Strong container hardening while preserving full OpenClaw features.
        DOCKER_ARGS+=(--read-only)
        # shellcheck disable=SC2054
        DOCKER_ARGS+=(--tmpfs /tmp:size=256m,noexec,nosuid,nodev)
        # shellcheck disable=SC2054
        DOCKER_ARGS+=(--tmpfs /home/node/.cache:size=128m,noexec,nosuid,nodev)
        DOCKER_ARGS+=(--cap-drop=ALL)
        DOCKER_ARGS+=(--security-opt=no-new-privileges:true)
        [[ -n "$MEMORY_LIMIT" ]] && DOCKER_ARGS+=(--memory="$MEMORY_LIMIT")
        [[ -n "$MEMORY_LIMIT" ]] && DOCKER_ARGS+=(--memory-swap="$MEMORY_LIMIT")
        [[ -n "$CPU_LIMIT" ]] && DOCKER_ARGS+=(--cpus="$CPU_LIMIT")
        [[ -n "$PID_LIMIT" ]] && DOCKER_ARGS+=(--pids-limit="$PID_LIMIT")
        DOCKER_ARGS+=(--network=bridge)
        DOCKER_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:rw")
        DOCKER_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    else
        # Hardened strict / Paranoid: Maximum lockdown and workspace-only writes.
        DOCKER_ARGS+=(--read-only)  # Immutable root filesystem
        # shellcheck disable=SC2054
        DOCKER_ARGS+=(--tmpfs /tmp:size=256m,noexec,nosuid,nodev)  # Writable /tmp
        # shellcheck disable=SC2054
        DOCKER_ARGS+=(--tmpfs /home/node/.cache:size=128m,noexec,nosuid,nodev)  # Cache dir
        DOCKER_ARGS+=(--cap-drop=ALL)  # Drop all Linux capabilities
        DOCKER_ARGS+=(--security-opt=no-new-privileges:true)  # Prevent privilege escalation
        # Resource limits - only add if set (not empty for standard tier)
        [[ -n "$MEMORY_LIMIT" ]] && DOCKER_ARGS+=(--memory="$MEMORY_LIMIT")
        [[ -n "$MEMORY_LIMIT" ]] && DOCKER_ARGS+=(--memory-swap="$MEMORY_LIMIT")
        [[ -n "$CPU_LIMIT" ]] && DOCKER_ARGS+=(--cpus="$CPU_LIMIT")
        [[ -n "$PID_LIMIT" ]] && DOCKER_ARGS+=(--pids-limit="$PID_LIMIT")
        
        # User mapping for standard Docker
        if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
            DOCKER_ARGS+=(--user "$(id -u "$SYSTEM_USER"):$(id -g "$SYSTEM_USER")")
        fi
        
        # Network
        DOCKER_ARGS+=(--network=bridge)
        
        DOCKER_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:ro")
        DOCKER_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    fi
    
    # Image (use upstream default command for version compatibility)
    DOCKER_ARGS+=(openclaw:local)
}

layer3_container_hardening() {
    section "Layer 3: Container Hardening"
    
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        build_podman_args
    else
        build_docker_args
    fi
    info "Container configured with $SECURITY_TIER tier security ($CONTAINER_RUNTIME runtime)"
    info "Layer 3 complete"
}

# ============================================================================
# LAYER 4: HOST FIREWALL (PARANOID ONLY)
# ============================================================================
layer4_firewall() {
    if [[ "$SECURITY_TIER" != "paranoid" ]]; then
        return
    fi
    
    section "Layer 4: Host Firewall (nftables)"
    
    # Install nftables
    if ! command -v nft &> /dev/null; then
        info "Installing nftables..."
        apt-get install -y -qq nftables >/dev/null 2>&1 || \
            die "Failed to install nftables"
    fi
    
    # Create nftables.d directory
    mkdir -p /etc/nftables.d
    
    # Write egress rules
    info "Configuring egress firewall for UID $USER_UID..."
    cat > /etc/nftables.d/openclaw-egress.conf << EOF
#!/usr/sbin/nft -f

table inet openclaw_egress {
    chain output {
        type filter hook output priority 0; policy accept;
        
        # Skip non-openclaw traffic
        meta skuid != $USER_UID accept
        
        # Allow loopback
        oif "lo" accept
        
        # Allow DNS
        udp dport 53 accept
        tcp dport 53 accept
        
        # Allow established/related
        ct state established,related accept
        
        # Block and log cloud metadata
        ip daddr 169.254.0.0/16 log prefix "openclaw-blocked-meta: " drop
        
        # Block and log RFC1918 (lateral movement)
        ip daddr 10.0.0.0/8 log prefix "openclaw-blocked-rfc1918: " drop
        ip daddr 172.16.0.0/12 log prefix "openclaw-blocked-rfc1918: " drop
        ip daddr 192.168.0.0/16 log prefix "openclaw-blocked-rfc1918: " drop
        
        # Allow HTTPS for LLM APIs
        tcp dport 443 accept
        
        # Drop and log everything else
        log prefix "openclaw-blocked: " drop
    }
}
EOF
    
    chmod +x /etc/nftables.d/openclaw-egress.conf
    
    # Apply rules
    info "Applying nftables rules..."
    nft -f /etc/nftables.d/openclaw-egress.conf || \
        die "Failed to apply nftables rules"
    
    # Add include to main config if not present
    if [[ -f /etc/nftables.conf ]]; then
        if ! grep -q "openclaw-egress.conf" /etc/nftables.conf; then
            echo "include \"/etc/nftables.d/openclaw-egress.conf\"" >> /etc/nftables.conf
        fi
    else
        echo "include \"/etc/nftables.d/openclaw-egress.conf\"" > /etc/nftables.conf
    fi
    
    # Enable nftables service
    info "Enabling nftables service..."
    systemctl enable nftables >/dev/null 2>&1 || warn "Failed to enable nftables service"
    systemctl restart nftables >/dev/null 2>&1 || warn "Failed to restart nftables service"
    
    info "Layer 4 complete"
}

# ============================================================================
# LAYER 5: MONITORING (PARANOID ONLY)
# ============================================================================
layer5_monitoring() {
    if [[ "$SECURITY_TIER" != "paranoid" ]]; then
        return
    fi
    
    section "Layer 5: Audit Monitoring"
    
    # Install auditd
    if ! command -v auditctl &> /dev/null; then
        info "Installing auditd..."
        apt-get install -y -qq auditd >/dev/null 2>&1 || \
            die "Failed to install auditd"
    fi
    
    # Write audit rules
    info "Configuring audit rules for UID $USER_UID..."
    cat > /etc/audit/rules.d/openclaw.rules << EOF
# OpenClaw audit rules
-a always,exit -F arch=b64 -F uid=$USER_UID -S execve -k openclaw_exec
-w $INSTALL_DIR -p wa -k openclaw_writes
EOF
    
    # Restart auditd
    info "Restarting auditd..."
    service auditd restart >/dev/null 2>&1 || \
        warn "Failed to restart auditd"
    
    # Create network check script
    info "Installing network anomaly detection..."
    cat > /usr/local/bin/openclaw-netcheck.sh << 'NETCHECK_SCRIPT'
#!/bin/bash
# Network anomaly detection for OpenClaw container
USER_UID=USER_UID_PLACEHOLDER

# Check for connections from openclaw UID that aren't localhost
# NOTE: Must use grep without -q first, then pipe to grep -qv
# Using grep -q first would suppress output before the second grep
if ss -tunp 2>/dev/null | grep "uid:$USER_UID" | grep -qv "127.0.0.1\|::1"; then
    logger -t openclaw-alert -p auth.crit "Suspicious network connection detected from UID $USER_UID"
fi
NETCHECK_SCRIPT
    
    # Replace placeholder
    sed -i "s|USER_UID_PLACEHOLDER|$USER_UID|" /usr/local/bin/openclaw-netcheck.sh
    chmod +x /usr/local/bin/openclaw-netcheck.sh
    
    # Install cron job
    cat > /etc/cron.d/openclaw-netcheck << EOF
# OpenClaw network anomaly detection
* * * * * root /usr/local/bin/openclaw-netcheck.sh
EOF
    
    info "Layer 5 complete"
}

# ============================================================================
# LAYER 7: QUADLET & LAUNCH
# ============================================================================
layer7_launch() {
    section "Layer 7: Systemd & Launch"
    
    # Determine the runtime command
    local runtime_cmd
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        runtime_cmd="podman"
    else
        runtime_cmd="docker"
    fi

    # Proactively detect whether user systemd is reachable for rootless runtimes.
    if [[ $ENABLE_SYSTEMD -eq 1 && "$CONTAINER_RUNTIME" != "docker" ]]; then
        if ! user_systemd_available "$SYSTEM_USER"; then
            warn "User systemd is not reachable for $SYSTEM_USER on this host/session."
            warn "Proceeding with direct launch (no auto-start service for this run)."
            ENABLE_SYSTEMD=0
        fi
    fi
    
    # Always create launch script
    info "Creating launch script ($runtime_cmd)..."
    local launch_script="$INSTALL_DIR/launch-openclaw.sh"
    
    cat > "$launch_script" << 'LAUNCH_EOF'
#!/bin/bash
# OpenClaw Launch Script
# Generated by SecureClaw installer

set -euo pipefail

LAUNCH_EOF
    
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        # Podman launch
        echo "podman run -d \\" >> "$launch_script"
        for arg in "${PODMAN_ARGS[@]}"; do
            echo "  \"$arg\" \\" >> "$launch_script"
        done
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        # Docker rootless launch (needs DOCKER_HOST)
        echo "export DOCKER_HOST=\"unix://$XDG_RUNTIME_DIR/docker.sock\"" >> "$launch_script"
        echo "docker run -d \\" >> "$launch_script"
        for arg in "${DOCKER_ARGS[@]}"; do
            echo "  \"$arg\" \\" >> "$launch_script"
        done
    else
        # Standard Docker launch
        echo "docker run -d \\" >> "$launch_script"
        for arg in "${DOCKER_ARGS[@]}"; do
            echo "  \"$arg\" \\" >> "$launch_script"
        done
    fi
    # Remove trailing backslash from last line
    sed -i '$ s/ \\$//' "$launch_script"
    
    chown "$SYSTEM_USER:$SYSTEM_USER" "$launch_script"
    chmod +x "$launch_script"
    
    # Create systemd unit if enabled
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            # Podman Quadlet (user-level)
            info "Creating systemd Quadlet unit..."
            
            local quadlet_dir="$USER_HOME/.config/containers/systemd"
            sudo -u "$SYSTEM_USER" mkdir -p "$quadlet_dir"
            
            local quadlet_file="$quadlet_dir/openclaw.container"
            
            cat > "$quadlet_file" << EOF
[Unit]
Description=OpenClaw Secure Container
After=network-online.target
Wants=network-online.target

[Container]
Image=openclaw:local
ContainerName=openclaw
AutoUpdate=registry

# User and namespaces
User=$USER_UID:$USER_GID
UserNS=keep-id

# Environment
Environment=HOME=/home/node
Environment=TERM=xterm-256color
EnvironmentFile=$CONFIG_DIR/.env

# Ports (localhost only)
PublishPort=127.0.0.1:$GATEWAY_PORT:$GATEWAY_PORT
PublishPort=127.0.0.1:$BRIDGE_PORT:$BRIDGE_PORT

# Volumes
EOF
            
            if [[ "$SECURITY_TIER" == "standard" || "$SECURITY_TIER" == "balanced" ]]; then
                cat >> "$quadlet_file" << EOF
Volume=$CONFIG_DIR:/home/node/.openclaw:rw
Volume=$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw
EOF
            else
                cat >> "$quadlet_file" << EOF
Volume=$CONFIG_DIR:/home/node/.openclaw:ro
Volume=$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw
EOF
            fi
            
            # Add hardened/paranoid flags
            if [[ "$SECURITY_TIER" != "standard" ]]; then
                cat >> "$quadlet_file" << EOF

# Security hardening
ReadOnly=true
Tmpfs=/tmp:size=256m,noexec,nosuid,nodev
Tmpfs=/home/node/.cache:size=128m,noexec,nosuid,nodev
DropCapability=ALL
SecurityLabelDisable=true
NoNewPrivileges=true

# Resource limits
Memory=$MEMORY_LIMIT
MemorySwap=$MEMORY_LIMIT
CPUQuota=$(cpu_quota_percent_from_limit "$CPU_LIMIT")%
PidsLimit=$PID_LIMIT

# Network
Network=slirp4netns:allow_host_loopback=false
EOF
            fi
            
            cat >> "$quadlet_file" << EOF
[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF
            
            chown "$SYSTEM_USER:$SYSTEM_USER" "$quadlet_file"
            
            # Reload and enable
            info "Enabling and starting systemd service..."
            run_user_systemctl "$SYSTEM_USER" daemon-reload || die "Failed to reload user systemd daemon"
            if ! run_user_systemctl "$SYSTEM_USER" cat openclaw.service >/dev/null 2>&1; then
                warn "Quadlet generator did not expose openclaw.service on this host."
                warn "Falling back to direct launch (service auto-start disabled for now)."
                ENABLE_SYSTEMD=0
            else
                if ! run_user_systemctl "$SYSTEM_USER" enable openclaw.service; then
                    warn "Could not enable openclaw.service in user systemd; falling back to direct launch."
                    ENABLE_SYSTEMD=0
                elif ! run_user_systemctl "$SYSTEM_USER" start openclaw.service; then
                    warn "Could not start openclaw.service in user systemd; falling back to direct launch."
                    ENABLE_SYSTEMD=0
                fi
            fi
        
        elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
            # Docker rootless systemd unit (user-level)
            info "Creating systemd user service for Docker rootless..."
            
            local user_unit_dir="$USER_HOME/.config/systemd/user"
            sudo -u "$SYSTEM_USER" mkdir -p "$user_unit_dir"
            
            local unit_file="$user_unit_dir/openclaw.service"
            
            # Build docker run args string for ExecStart
            local docker_run_args=""
            for arg in "${DOCKER_ARGS[@]}"; do
                docker_run_args+=" \"$arg\""
            done
            
            cat > "$unit_file" << EOF
[Unit]
Description=OpenClaw Secure Container (Docker Rootless)
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
ExecStartPre=-/usr/bin/docker rm -f openclaw
ExecStart=/usr/bin/docker run -d $docker_run_args
ExecStop=/usr/bin/docker stop openclaw
ExecStopPost=-/usr/bin/docker rm openclaw

[Install]
WantedBy=default.target
EOF
            
            chown "$SYSTEM_USER:$SYSTEM_USER" "$unit_file"
            
            info "Enabling and starting systemd service..."
            run_user_systemctl "$SYSTEM_USER" daemon-reload || die "Failed to reload user systemd daemon"
            if ! run_user_systemctl "$SYSTEM_USER" enable openclaw.service; then
                warn "Could not enable user systemd service; falling back to direct launch."
                ENABLE_SYSTEMD=0
            elif ! run_user_systemctl "$SYSTEM_USER" start openclaw.service; then
                warn "Could not start user systemd service; falling back to direct launch."
                ENABLE_SYSTEMD=0
            fi
        
        else
            # Standard Docker systemd unit (system-level)
            info "Creating system-level systemd service for Docker..."
            
            local unit_file="/etc/systemd/system/openclaw.service"
            
            # Build docker run args string for ExecStart
            local docker_run_args=""
            for arg in "${DOCKER_ARGS[@]}"; do
                docker_run_args+=" \"$arg\""
            done
            
            cat > "$unit_file" << EOF
[Unit]
Description=OpenClaw Secure Container (Docker)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/docker rm -f openclaw
ExecStart=/usr/bin/docker run -d $docker_run_args
ExecStop=/usr/bin/docker stop openclaw
ExecStopPost=-/usr/bin/docker rm openclaw

[Install]
WantedBy=multi-user.target
EOF
            
            info "Enabling and starting systemd service..."
            systemctl daemon-reload
            systemctl enable openclaw.service >/dev/null 2>&1
            systemctl start openclaw.service || \
                die "Failed to start service"
        fi
    fi

    if [[ $ENABLE_SYSTEMD -eq 0 ]]; then
        # Launch directly
        info "Starting container..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            info "Rootless Podman first launch can take a few minutes while user namespace mappings are prepared."
        fi
        cd "$USER_HOME"
        if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
            bash "$launch_script" || die "Failed to start container"
        else
            if command -v timeout >/dev/null 2>&1; then
                timeout 900 sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" bash "$launch_script" || {
                    local launch_exit=$?
                    if [[ "$launch_exit" -eq 124 ]]; then
                        die "Container start timed out after 15 minutes. Check for stuck rootless mapping with: ps -ef | rg storage-chown-by-maps"
                    fi
                    die "Failed to start container"
                }
            else
                sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" bash "$launch_script" || \
                    die "Failed to start container"
            fi
        fi
    fi
    
    # Wait and verify
    sleep 3
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" podman ps | grep -q openclaw; then
            info "Container started successfully"
        else
            warn "Container may not have started properly"
        fi
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker ps | grep -q openclaw; then
            info "Container started successfully"
        else
            warn "Container may not have started properly"
        fi
    else
        if docker ps | grep -q openclaw; then
            info "Container started successfully"
        else
            warn "Container may not have started properly"
        fi
    fi
    
    info "Layer 7 complete"
}

# ============================================================================
# LAYER 8: OPERATIONAL COMMANDS
# ============================================================================
layer8_install_operational_commands() {
    section "Layer 8: Operational Commands"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    install_local_or_remote_script \
        "/usr/local/bin/secureclaw-uninstall" \
        "$script_dir/uninstall.sh" \
        "$SECURECLAW_UNINSTALL_URL" \
        "uninstall" || \
        warn "You can still uninstall by running uninstall.sh from this repository."

    install_local_or_remote_script \
        "/usr/local/bin/secureclaw-panic" \
        "$script_dir/panic.sh" \
        "$SECURECLAW_PANIC_URL" \
        "panic" || \
        warn "PANIC command installation failed; keep panic.sh available from this repository."

    install_local_or_remote_script \
        "/usr/local/bin/secureclaw-update" \
        "$script_dir/update.sh" \
        "$SECURECLAW_UPDATE_URL" \
        "update" || \
        warn "Update command installation failed; keep update.sh available from this repository."

    install_local_or_remote_script \
        "/usr/local/bin/secureclaw-backup" \
        "$script_dir/backup.sh" \
        "$SECURECLAW_BACKUP_URL" \
        "backup" || \
        warn "Backup command installation failed; keep backup.sh available from this repository."
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================
show_final_summary() {
    section "🎉 Installation Complete!"
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}  ${BOLD}SecureClaw Installation Successful${RESET}                              ${GREEN}║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "${BOLD}Dashboard URL:${RESET}"
    echo -e "  http://localhost:$GATEWAY_PORT"
    echo
    echo -e "${BOLD}Container Runtime:${RESET}"
    echo -e "  $CONTAINER_RUNTIME"
    echo
    echo -e "${BOLD}Control UI Access Mode:${RESET}"
    if [[ "$CONTROL_UI_AUTH_MODE" == "strict" ]]; then
        echo -e "  Strict pairing (recommended)"
    else
        echo -e "  Compatibility (allowInsecureAuth enabled)"
    fi
    echo
    echo -e "${BOLD}Gateway Token:${RESET}"
    echo -e "  ${GATEWAY_TOKEN:0:16}...${GATEWAY_TOKEN: -8}"
    echo
    echo -e "${BOLD}SSH Tunnel Command:${RESET}"
    echo -e "  ${CYAN}ssh -L $GATEWAY_PORT:127.0.0.1:$GATEWAY_PORT user@your-vps-ip${RESET}"
    echo
    echo -e "${BOLD}PC Connection Helpers:${RESET}"
    echo -e "  Linux:"
    echo -e "    curl -fsSL $SECURECLAW_CONNECT_LINUX_URL -o connect-openclaw-linux.sh"
    echo -e "    bash connect-openclaw-linux.sh"
    echo -e "  macOS:"
    echo -e "    curl -fsSL $SECURECLAW_CONNECT_MACOS_URL -o connect-openclaw-macos.sh"
    echo -e "    bash connect-openclaw-macos.sh"
    echo -e "  Windows (PowerShell):"
    echo -e "    iwr -UseBasicParsing $SECURECLAW_CONNECT_WINDOWS_URL -OutFile connect-openclaw-windows.ps1"
    echo "    powershell -ExecutionPolicy Bypass -File .\\connect-openclaw-windows.ps1"
    echo
    echo -e "${BOLD}View Logs:${RESET}"
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
        if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
            echo -e "  systemctl status openclaw"
            echo -e "  journalctl -u openclaw -f"
        else
            echo -e "  sudo -u $SYSTEM_USER systemctl --user status openclaw"
            echo -e "  sudo -u $SYSTEM_USER journalctl --user -u openclaw -f"
        fi
    else
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            echo -e "  sudo -u $SYSTEM_USER podman logs -f openclaw"
        elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
            echo -e "  sudo -u $SYSTEM_USER DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock docker logs -f openclaw"
        else
            echo -e "  docker logs -f openclaw"
        fi
    fi
    echo
    echo -e "${BOLD}Stop/Restart:${RESET}"
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
        if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
            echo -e "  systemctl stop openclaw"
            echo -e "  systemctl start openclaw"
        else
            echo -e "  sudo -u $SYSTEM_USER systemctl --user stop openclaw"
            echo -e "  sudo -u $SYSTEM_USER systemctl --user start openclaw"
        fi
    else
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            echo -e "  sudo -u $SYSTEM_USER podman stop openclaw"
            echo -e "  sudo -u $SYSTEM_USER podman start openclaw"
        elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
            echo -e "  sudo -u $SYSTEM_USER DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock docker stop openclaw"
            echo -e "  sudo -u $SYSTEM_USER DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock docker start openclaw"
        else
            echo -e "  docker stop openclaw"
            echo -e "  docker start openclaw"
        fi
    fi
    echo
    echo -e "${BOLD}Uninstall:${RESET}"
    echo -e "  sudo secureclaw-uninstall"
    echo -e "  # or: sudo bash uninstall.sh (from this repository)"
    echo
    echo -e "${BOLD}Update:${RESET}"
    echo -e "  sudo secureclaw-update"
    echo -e "  # or: sudo bash update.sh (from this repository)"
    echo -e "  # Note: SecureClaw uses container image updates; this differs from native 'openclaw update'"
    echo
    echo -e "${BOLD}Backup / Restore:${RESET}"
    echo -e "  sudo secureclaw-backup"
    echo -e "  # restore: sudo secureclaw-backup --restore /path/to/backup.tar.gz"
    echo
    echo -e "${BOLD}Emergency PANIC Stop:${RESET}"
    echo -e "  sudo secureclaw-panic"
    echo -e "  # or: sudo bash panic.sh (from this repository)"
    echo
    echo -e "${BOLD}Configuration:${RESET}"
    echo -e "  Config: $CONFIG_DIR/openclaw.json"
    echo -e "  API Keys: $CONFIG_DIR/.env"
    echo -e "  Workspace: $WORKSPACE_DIR"
    echo
    local pair_list_cmd=""
    local pair_approve_cmd=""
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        pair_list_cmd="sudo -u $SYSTEM_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR podman exec openclaw sh -lc 'if [ -f openclaw.mjs ]; then node openclaw.mjs devices list --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; else node dist/index.js devices list --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; fi'"
        pair_approve_cmd="sudo -u $SYSTEM_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR podman exec openclaw sh -lc 'if [ -f openclaw.mjs ]; then node openclaw.mjs devices approve <device-id> --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; else node dist/index.js devices approve <device-id> --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; fi'"
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        pair_list_cmd="sudo -u $SYSTEM_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock docker exec openclaw sh -lc 'if [ -f openclaw.mjs ]; then node openclaw.mjs devices list --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; else node dist/index.js devices list --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; fi'"
        pair_approve_cmd="sudo -u $SYSTEM_USER XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock docker exec openclaw sh -lc 'if [ -f openclaw.mjs ]; then node openclaw.mjs devices approve <device-id> --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; else node dist/index.js devices approve <device-id> --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; fi'"
    else
        pair_list_cmd="docker exec openclaw sh -lc 'if [ -f openclaw.mjs ]; then node openclaw.mjs devices list --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; else node dist/index.js devices list --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; fi'"
        pair_approve_cmd="docker exec openclaw sh -lc 'if [ -f openclaw.mjs ]; then node openclaw.mjs devices approve <device-id> --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; else node dist/index.js devices approve <device-id> --url ws://127.0.0.1:$GATEWAY_PORT --token \"\$OPENCLAW_GATEWAY_TOKEN\"; fi'"
    fi

    echo -e "${BOLD}Post-Install Access Checklist:${RESET}"
    if [[ "$CONTROL_UI_AUTH_MODE" == "strict" ]]; then
        echo -e "  1. Open dashboard: http://localhost:$GATEWAY_PORT"
        echo -e "  2. Enter your gateway token"
        echo -e "  3. If you see pairing required (1008), run:"
        echo -e "     $pair_list_cmd"
        echo -e "     $pair_approve_cmd"
        echo -e "  4. Reconnect dashboard after approval"
    else
        echo -e "  1. Open dashboard: http://localhost:$GATEWAY_PORT"
        echo -e "  2. Enter your gateway token"
        echo -e "  3. Compatibility mode is enabled (allowInsecureAuth=true)"
        echo -e "  4. Keep gateway behind SSH tunnel/Tailscale only"
        echo -e "  5. Rotate OPENCLAW_GATEWAY_TOKEN regularly"
    fi
    echo
    echo -e "${BOLD}Active Security Layers (${SECURITY_TIER} tier, ${CONTAINER_RUNTIME} runtime):${RESET}"
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        echo -e "  ✅ Rootless Podman"
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        echo -e "  ✅ Rootless Docker"
    else
        echo -e "  ✅ Docker (hardened)"
    fi
    echo -e "  ✅ Gateway token authentication"
    echo -e "  ✅ Localhost-only binding"
    
    if [[ "$SECURITY_TIER" != "standard" ]]; then
        echo -e "  ✅ Read-only root filesystem"
        echo -e "  ✅ All capabilities dropped"
        echo -e "  ✅ No new privileges"
        echo -e "  ✅ Resource limits (CPU/RAM/PIDs)"
        echo -e "  ✅ Network isolation"
    fi
    
    if [[ "$SECURITY_TIER" == "paranoid" ]]; then
        echo -e "  ✅ Host egress firewall (nftables)"
        echo -e "  ✅ Audit logging (auditd + cron)"
        echo -e "  ✅ Agent-level sandboxing"
    fi

    if [[ "$SECURITY_TIER" == "hardened" ]]; then
        echo
        warn "Hardened (strict): Some OpenClaw features may be limited by workspace-only and read-only config restrictions."
    elif [[ "$SECURITY_TIER" == "paranoid" ]]; then
        echo
        warn "Paranoid: Maximum isolation can impact browser/nodes/channels due sandbox and egress restrictions."
    fi
    
    echo
    echo -e "${YELLOW}⚠  Security Reminders:${RESET}"
    echo -e "  • IP-restrict API keys at provider dashboards"
    echo -e "  • Set spending limits on all LLM API accounts"
    echo -e "  • Use dedicated API keys (don't reuse from other projects)"
    echo -e "  • Monitor usage regularly for anomalies"
    if [[ "$CONTROL_UI_AUTH_MODE" == "compatibility" ]]; then
        echo -e "  • Compatibility mode weakens UI auth; do not expose gateway publicly"
    fi
    
    if [[ "$SECURITY_TIER" == "paranoid" ]]; then
        echo
        echo -e "${BOLD}Paranoid Tier Monitoring:${RESET}"
        echo -e "  sudo journalctl -t openclaw-alert -f    # Network anomalies"
        echo -e "  sudo journalctl -k | grep openclaw      # Firewall blocks"
        echo -e "  sudo ausearch -k openclaw_exec          # Audit logs"
    fi
    
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET}  ${DIM}SecureClaw reduces risk but cannot eliminate it.${RESET}              ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET}  ${DIM}Always assume compromise and plan accordingly.${RESET}                ${GREEN}║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# ============================================================================
# UNINSTALL (delegates to uninstall.sh)
# ============================================================================
uninstall_openclaw() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local uninstall_script="$script_dir/uninstall.sh"

    if [[ -f "$uninstall_script" ]]; then
        exec bash "$uninstall_script"
    fi

    if [[ -x /usr/local/bin/secureclaw-uninstall ]]; then
        exec /usr/local/bin/secureclaw-uninstall
    fi

    local temp_uninstall
    temp_uninstall=$(mktemp /tmp/secureclaw-uninstall-XXXXXX.sh)
    if download_url_to_file "$SECURECLAW_UNINSTALL_URL" "$temp_uninstall"; then
        chmod 700 "$temp_uninstall"
        exec bash "$temp_uninstall"
    fi

    rm -f "$temp_uninstall" || true
    die "Uninstall script not found locally and failed to download fallback uninstaller."
}

panic_openclaw() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local panic_script="$script_dir/panic.sh"

    if [[ -f "$panic_script" ]]; then
        exec bash "$panic_script"
    fi

    if [[ -x /usr/local/bin/secureclaw-panic ]]; then
        exec /usr/local/bin/secureclaw-panic
    fi

    local temp_panic
    temp_panic=$(mktemp /tmp/secureclaw-panic-XXXXXX.sh)
    if download_url_to_file "$SECURECLAW_PANIC_URL" "$temp_panic"; then
        chmod 700 "$temp_panic"
        exec bash "$temp_panic"
    fi

    rm -f "$temp_panic" || true
    die "Panic script not found locally and failed to download fallback panic script."
}

update_openclaw() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local update_script="$script_dir/update.sh"

    if [[ -f "$update_script" ]]; then
        exec bash "$update_script"
    fi

    if [[ -x /usr/local/bin/secureclaw-update ]]; then
        exec /usr/local/bin/secureclaw-update
    fi

    local temp_update
    temp_update=$(mktemp /tmp/secureclaw-update-XXXXXX.sh)
    if download_url_to_file "$SECURECLAW_UPDATE_URL" "$temp_update"; then
        chmod 700 "$temp_update"
        exec bash "$temp_update"
    fi

    rm -f "$temp_update" || true
    die "Update script not found locally and failed to download fallback update script."
}

backup_openclaw() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local backup_script="$script_dir/backup.sh"

    if [[ -f "$backup_script" ]]; then
        exec bash "$backup_script"
    fi

    if [[ -x /usr/local/bin/secureclaw-backup ]]; then
        exec /usr/local/bin/secureclaw-backup
    fi

    local temp_backup
    temp_backup=$(mktemp /tmp/secureclaw-backup-XXXXXX.sh)
    if download_url_to_file "$SECURECLAW_BACKUP_URL" "$temp_backup"; then
        chmod 700 "$temp_backup"
        exec bash "$temp_backup"
    fi

    rm -f "$temp_backup" || true
    die "Backup script not found locally and failed to download fallback backup script."
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    set_phase "startup"
    show_banner
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --openclaw-repo)
                [[ $# -ge 2 ]] || die "--openclaw-repo requires a path"
                ARG_OPENCLAW_REPO="$2"
                shift 2
                ;;
            --openclaw-ref)
                [[ $# -ge 2 ]] || die "--openclaw-ref requires a git ref"
                ARG_OPENCLAW_REF="$2"
                shift 2
                ;;
            --quick)
                ARG_INSTALL_PROFILE="1"
                shift
                ;;
            --advanced)
                ARG_INSTALL_PROFILE="2"
                shift
                ;;
            *)
                warn "Unknown argument: $1"
                shift
                ;;
        esac
    done

    set_phase "preflight checks"
    preflight_checks
    set_phase "operation selection"
    prompt_operation_mode
    if [[ "$OPERATION_MODE" == "uninstall" ]]; then
        uninstall_openclaw
        exit 0
    fi
    if [[ "$OPERATION_MODE" == "panic" ]]; then
        panic_openclaw
        exit 0
    fi
    if [[ "$OPERATION_MODE" == "update" ]]; then
        update_openclaw
        exit 0
    fi
    if [[ "$OPERATION_MODE" == "backup" ]]; then
        backup_openclaw
        exit 0
    fi

    set_phase "install profile selection"
    prompt_install_profile

    # Interactive prompts
    set_phase "system information prompt"
    prompt_system_info
    if [[ "$INSTALL_PROFILE" == "quick" ]]; then
        set_phase "quick defaults"
        apply_quick_secure_defaults
        set_phase "control ui auth mode prompt"
        prompt_control_ui_auth_mode
    else
        set_phase "runtime prompt"
        prompt_container_runtime
        set_phase "security tier prompt"
        prompt_security_level
        set_phase "install directory prompt"
        prompt_install_dir
        set_phase "system user prompt"
        prompt_username
        set_phase "port prompt"
        prompt_ports
        set_phase "token prompt"
        prompt_token
        set_phase "control ui auth mode prompt"
        prompt_control_ui_auth_mode
        set_phase "api keys prompt"
        prompt_api_keys
        set_phase "systemd prompt"
        prompt_systemd
        set_phase "resource limits prompt"
        prompt_resource_limits
    fi
    
    # Review and confirm
    set_phase "configuration summary"
    show_summary
    
    # Execute installation layers
    set_phase "layer1 system setup"
    layer1_system_setup
    set_phase "layer2 container image build"
    layer2_container_image
    set_phase "layer6 configuration"
    layer6_configuration
    set_phase "layer3 container hardening"
    layer3_container_hardening
    set_phase "layer4 firewall"
    layer4_firewall
    set_phase "layer5 monitoring"
    layer5_monitoring
    set_phase "layer7 launch"
    layer7_launch
    set_phase "layer8 operational commands"
    layer8_install_operational_commands
    set_phase "writing install manifest"
    write_install_manifest
    
    # Show final summary
    set_phase "final summary"
    show_final_summary
}

# Run main function
main "$@"
