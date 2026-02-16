#!/usr/bin/env bash
set -euo pipefail
unset TMOUT 2>/dev/null || true

# SecureClaw Uninstaller
# Fully removes SecureClaw-generated OpenClaw deployment artifacts.

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

readonly SECURECLAW_STATE_DIR="/etc/secureclaw"
readonly SECURECLAW_INSTALL_STATE_FILE="$SECURECLAW_STATE_DIR/install.env"
readonly SECURECLAW_PUBLIC_STATE_FILE="/etc/secureclaw-public.env"

info() {
    echo -e "${CYAN}▸${RESET} $*"
}

warn() {
    echo -e "${YELLOW}⚠${RESET} $*"
}

err() {
    echo -e "${RED}✗${RESET} $*" >&2
}

die() {
    err "$*"
    exit 1
}

section() {
    echo
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  $*${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
}

prompt_confirm() {
    local message="$1"
    local default_answer="${2:-N}"
    local reply=""
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}${message}${RESET} ")" -r reply
    reply="${reply:-$default_answer}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Please use: sudo bash uninstall.sh"
    fi
}

safe_get_user_home() {
    local user_name="$1"
    getent passwd "$user_name" | awk -F: 'NR==1 {print $6}'
}

load_install_state() {
    INSTALL_STATE_FOUND=1
    SYSTEM_USER="openclaw"
    INSTALL_DIR=""
    CONTAINER_RUNTIME=""
    SECURITY_TIER=""
    ENABLE_SYSTEMD=0
    GATEWAY_PORT=""
    BRIDGE_PORT=""
    USER_CREATED_BY_SECURECLAW=0
    LINGER_ENABLED_BY_SECURECLAW=0
    SUBUID_ADDED_BY_SECURECLAW=0
    SUBGID_ADDED_BY_SECURECLAW=0
    SUBUID_RANGE=""
    SUBGID_RANGE=""
    PACKAGES_INSTALLED_BY_SECURECLAW=""
    DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW=0
    DOCKER_APT_KEY_ADDED_BY_SECURECLAW=0

    if [[ ! -f "$SECURECLAW_INSTALL_STATE_FILE" ]]; then
        INSTALL_STATE_FOUND=0
        warn "Install state not found at $SECURECLAW_INSTALL_STATE_FILE"
        warn "Falling back to interactive best-effort cleanup."
        return
    fi

    while IFS='=' read -r key value; do
        [[ -n "$key" ]] || continue
        case "$key" in
            SYSTEM_USER) SYSTEM_USER="$value" ;;
            INSTALL_DIR) INSTALL_DIR="$value" ;;
            CONTAINER_RUNTIME) CONTAINER_RUNTIME="$value" ;;
            SECURITY_TIER) SECURITY_TIER="$value" ;;
            ENABLE_SYSTEMD) ENABLE_SYSTEMD="$value" ;;
            GATEWAY_PORT) GATEWAY_PORT="$value" ;;
            BRIDGE_PORT) BRIDGE_PORT="$value" ;;
            USER_CREATED_BY_SECURECLAW) USER_CREATED_BY_SECURECLAW="$value" ;;
            LINGER_ENABLED_BY_SECURECLAW) LINGER_ENABLED_BY_SECURECLAW="$value" ;;
            SUBUID_ADDED_BY_SECURECLAW) SUBUID_ADDED_BY_SECURECLAW="$value" ;;
            SUBGID_ADDED_BY_SECURECLAW) SUBGID_ADDED_BY_SECURECLAW="$value" ;;
            SUBUID_RANGE) SUBUID_RANGE="$value" ;;
            SUBGID_RANGE) SUBGID_RANGE="$value" ;;
            PACKAGES_INSTALLED_BY_SECURECLAW) PACKAGES_INSTALLED_BY_SECURECLAW="$value" ;;
            DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW) DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW="$value" ;;
            DOCKER_APT_KEY_ADDED_BY_SECURECLAW) DOCKER_APT_KEY_ADDED_BY_SECURECLAW="$value" ;;
            *) ;;
        esac
    done < "$SECURECLAW_INSTALL_STATE_FILE"
}

prompt_fallback_state() {
    section "Fallback Configuration"

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}System username used by SecureClaw:${RESET} ")" -r -i "openclaw" -e SYSTEM_USER
    SYSTEM_USER="${SYSTEM_USER:-openclaw}"

    local default_install_dir="/home/$SYSTEM_USER/.openclaw"
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Install directory used by SecureClaw:${RESET} ")" -r -i "$default_install_dir" -e INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR:-$default_install_dir}"

    info "Using fallback values: user=$SYSTEM_USER install_dir=$INSTALL_DIR"
}

resolve_runtime_context() {
    USER_EXISTS=0
    USER_UID=""
    USER_HOME=""
    USER_RUNTIME_DIR=""

    if id "$SYSTEM_USER" >/dev/null 2>&1; then
        USER_EXISTS=1
        USER_UID=$(id -u "$SYSTEM_USER")
        USER_HOME=$(safe_get_user_home "$SYSTEM_USER")
        USER_RUNTIME_DIR="/run/user/$USER_UID"
    fi

    if [[ -z "${INSTALL_DIR:-}" ]]; then
        if [[ $USER_EXISTS -eq 1 && -n "$USER_HOME" ]]; then
            INSTALL_DIR="$USER_HOME/.openclaw"
        else
            INSTALL_DIR="/home/$SYSTEM_USER/.openclaw"
        fi
    fi
}

cleanup_systemd_units() {
    section "Uninstall: systemd units"

    if [[ $USER_EXISTS -eq 1 && -n "$USER_HOME" ]]; then
        info "Stopping user-level OpenClaw service (if present)..."
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            systemctl --user disable --now openclaw.service >/dev/null 2>&1 || true
        rm -f "$USER_HOME/.config/systemd/user/openclaw.service"
        rm -f "$USER_HOME/.config/containers/systemd/openclaw.container"
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi

    info "Stopping system-level OpenClaw service (if present)..."
    systemctl disable --now openclaw.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/openclaw.service
    systemctl daemon-reload >/dev/null 2>&1 || true
}

cleanup_containers_and_images() {
    section "Uninstall: containers and images"

    if command -v podman >/dev/null 2>&1 && [[ $USER_EXISTS -eq 1 ]]; then
        info "Removing rootless Podman container/image (if present)..."
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            podman rm -f openclaw >/dev/null 2>&1 || true
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            podman image rm openclaw:local >/dev/null 2>&1 || true
    fi

    if command -v docker >/dev/null 2>&1 && [[ $USER_EXISTS -eq 1 ]]; then
        info "Removing rootless Docker container/image (if present)..."
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            DOCKER_HOST="unix://$USER_RUNTIME_DIR/docker.sock" \
            docker rm -f openclaw >/dev/null 2>&1 || true
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            DOCKER_HOST="unix://$USER_RUNTIME_DIR/docker.sock" \
            docker image rm openclaw:local >/dev/null 2>&1 || true
    fi

    if command -v docker >/dev/null 2>&1; then
        info "Removing standard Docker container/image (if present)..."
        docker rm -f openclaw >/dev/null 2>&1 || true
        docker image rm openclaw:local >/dev/null 2>&1 || true
    fi
}

cleanup_install_dir() {
    section "Uninstall: generated directories and files"

    if [[ -d "$INSTALL_DIR" ]]; then
        info "Removing install directory: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    else
        info "Install directory not found, skipping: $INSTALL_DIR"
    fi
}

cleanup_paranoid_artifacts() {
    section "Uninstall: paranoid-tier host artifacts"

    rm -f /etc/nftables.d/openclaw-egress.conf
    if [[ -f /etc/nftables.conf ]]; then
        sed -i '\|/etc/nftables.d/openclaw-egress.conf|d' /etc/nftables.conf
    fi
    nft delete table inet openclaw_egress >/dev/null 2>&1 || true
    systemctl restart nftables >/dev/null 2>&1 || true

    rm -f /etc/audit/rules.d/openclaw.rules
    rm -f /usr/local/bin/openclaw-netcheck.sh
    rm -f /etc/cron.d/openclaw-netcheck
    service auditd restart >/dev/null 2>&1 || true
}

cleanup_subid_mappings() {
    section "Uninstall: user namespace mappings"

    local remove_all_for_user=0
    if [[ "${USER_CREATED_BY_SECURECLAW:-0}" -eq 1 ]]; then
        remove_all_for_user=1
    fi

    if [[ -f /etc/subuid ]]; then
        if [[ "${SUBUID_ADDED_BY_SECURECLAW:-0}" -eq 1 && -n "${SUBUID_RANGE:-}" ]]; then
            info "Removing /etc/subuid mapping: $SYSTEM_USER:$SUBUID_RANGE"
            sed -i "\|^$SYSTEM_USER:$SUBUID_RANGE\$|d" /etc/subuid
        elif [[ $remove_all_for_user -eq 1 ]]; then
            info "Removing /etc/subuid entries for $SYSTEM_USER"
            sed -i "\|^$SYSTEM_USER:|d" /etc/subuid
        fi
    fi

    if [[ -f /etc/subgid ]]; then
        if [[ "${SUBGID_ADDED_BY_SECURECLAW:-0}" -eq 1 && -n "${SUBGID_RANGE:-}" ]]; then
            info "Removing /etc/subgid mapping: $SYSTEM_USER:$SUBGID_RANGE"
            sed -i "\|^$SYSTEM_USER:$SUBGID_RANGE\$|d" /etc/subgid
        elif [[ $remove_all_for_user -eq 1 ]]; then
            info "Removing /etc/subgid entries for $SYSTEM_USER"
            sed -i "\|^$SYSTEM_USER:|d" /etc/subgid
        fi
    fi
}

cleanup_linger() {
    section "Uninstall: systemd linger"

    if [[ $USER_EXISTS -eq 1 && "${LINGER_ENABLED_BY_SECURECLAW:-0}" -eq 1 ]]; then
        info "Disabling linger for $SYSTEM_USER"
        loginctl disable-linger "$SYSTEM_USER" >/dev/null 2>&1 || true
    else
        info "No SecureClaw-managed linger setting to remove"
    fi
}

cleanup_packages() {
    section "Uninstall: packages and apt sources"

    if [[ "${DOCKER_APT_SOURCE_ADDED_BY_SECURECLAW:-0}" -eq 1 ]]; then
        info "Removing SecureClaw-added Docker apt source"
        rm -f /etc/apt/sources.list.d/docker.list
    fi

    if [[ "${DOCKER_APT_KEY_ADDED_BY_SECURECLAW:-0}" -eq 1 ]]; then
        info "Removing SecureClaw-added Docker apt key"
        rm -f /etc/apt/keyrings/docker.asc
    fi

    if [[ -z "${PACKAGES_INSTALLED_BY_SECURECLAW:-}" ]]; then
        info "No tracked SecureClaw-installed packages found"
        return
    fi

    warn "Tracked packages installed by SecureClaw:"
    echo "  $PACKAGES_INSTALLED_BY_SECURECLAW"
    if ! prompt_confirm "Purge these packages as part of full rollback? [y/N]:" "N"; then
        info "Keeping installed packages"
        return
    fi

    local packages=()
    # shellcheck disable=SC2206
    packages=($PACKAGES_INSTALLED_BY_SECURECLAW)
    if [[ ${#packages[@]} -eq 0 ]]; then
        info "No packages to purge"
        return
    fi

    info "Purging tracked packages..."
    apt-get purge -y "${packages[@]}" >/dev/null 2>&1 || warn "Package purge encountered issues"
    apt-get autoremove -y >/dev/null 2>&1 || warn "Autoremove encountered issues"
    apt-get update -qq >/dev/null 2>&1 || true
}

cleanup_system_user() {
    section "Uninstall: system user"

    if [[ $USER_EXISTS -ne 1 ]]; then
        info "System user not present, skipping user deletion"
        return
    fi

    if [[ "${USER_CREATED_BY_SECURECLAW:-0}" -eq 1 ]]; then
        info "Removing SecureClaw-created user: $SYSTEM_USER"
        userdel --remove "$SYSTEM_USER" >/dev/null 2>&1 || userdel "$SYSTEM_USER" >/dev/null 2>&1 || true
        sed -i "\|^$SYSTEM_USER:|d" /etc/subuid 2>/dev/null || true
        sed -i "\|^$SYSTEM_USER:|d" /etc/subgid 2>/dev/null || true
    else
        warn "User $SYSTEM_USER was not marked as SecureClaw-created."
        if prompt_confirm "Delete this user anyway? [y/N]:" "N"; then
            userdel --remove "$SYSTEM_USER" >/dev/null 2>&1 || userdel "$SYSTEM_USER" >/dev/null 2>&1 || true
            sed -i "\|^$SYSTEM_USER:|d" /etc/subuid 2>/dev/null || true
            sed -i "\|^$SYSTEM_USER:|d" /etc/subgid 2>/dev/null || true
            info "User removed: $SYSTEM_USER"
        else
            info "Keeping system user: $SYSTEM_USER"
        fi
    fi
}

cleanup_install_state() {
    section "Uninstall: install state"

    rm -f "$SECURECLAW_INSTALL_STATE_FILE"
    rm -f "$SECURECLAW_PUBLIC_STATE_FILE"
    rmdir "$SECURECLAW_STATE_DIR" >/dev/null 2>&1 || true
}

main() {
    require_root
    load_install_state
    if [[ "${INSTALL_STATE_FOUND:-0}" -eq 0 ]]; then
        prompt_fallback_state
    fi

    section "SecureClaw Uninstall"
    resolve_runtime_context

    echo -e "${BOLD}Detected configuration${RESET}"
    echo "  System user:        $SYSTEM_USER"
    echo "  Install directory:  $INSTALL_DIR"
    [[ -n "$CONTAINER_RUNTIME" ]] && echo "  Runtime:            $CONTAINER_RUNTIME"
    [[ -n "$SECURITY_TIER" ]] && echo "  Security tier:      $SECURITY_TIER"
    echo
    warn "This will fully remove SecureClaw artifacts, services, containers, and user setup."
    echo

    if ! prompt_confirm "Proceed with uninstall? [y/N]:" "N"; then
        info "Uninstall cancelled"
        exit 0
    fi

    cleanup_systemd_units
    cleanup_containers_and_images
    cleanup_install_dir
    cleanup_paranoid_artifacts
    cleanup_subid_mappings
    cleanup_linger
    cleanup_packages
    cleanup_system_user
    cleanup_install_state

    section "Uninstall Complete"
    info "SecureClaw uninstall finished."
}

main "$@"
