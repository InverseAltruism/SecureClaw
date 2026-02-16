#!/usr/bin/env bash
set -euo pipefail
unset TMOUT 2>/dev/null || true

# SecureClaw PANIC script
# Emergency stop for OpenClaw workloads and related services/processes.

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

readonly SECURECLAW_STATE_DIR="/etc/secureclaw"
readonly SECURECLAW_INSTALL_STATE_FILE="$SECURECLAW_STATE_DIR/install.env"

SYSTEM_USER="openclaw"
INSTALL_DIR=""
USER_EXISTS=0
USER_UID=""
USER_RUNTIME_DIR=""

info() {
    echo -e "${CYAN}▸${RESET} $*"
}

warn() {
    echo -e "${YELLOW}⚠${RESET} $*"
}

die() {
    echo -e "${RED}✗${RESET} $*" >&2
    exit 1
}

section() {
    echo
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  $*${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Run as root: sudo bash panic.sh"
    fi
}

load_state() {
    if [[ ! -f "$SECURECLAW_INSTALL_STATE_FILE" ]]; then
        warn "Install state not found at $SECURECLAW_INSTALL_STATE_FILE; using defaults."
        return
    fi

    while IFS='=' read -r key value; do
        [[ -n "$key" ]] || continue
        case "$key" in
            SYSTEM_USER) SYSTEM_USER="$value" ;;
            INSTALL_DIR) INSTALL_DIR="$value" ;;
            *) ;;
        esac
    done < "$SECURECLAW_INSTALL_STATE_FILE"
}

resolve_user_context() {
    if id "$SYSTEM_USER" >/dev/null 2>&1; then
        USER_EXISTS=1
        USER_UID=$(id -u "$SYSTEM_USER")
        USER_RUNTIME_DIR="/run/user/$USER_UID"
        return
    fi

    USER_EXISTS=0
    USER_UID=""
    USER_RUNTIME_DIR=""
}

panic_stop_systemd() {
    section "PANIC: systemd services"

    info "Stopping system-level openclaw.service (if present)..."
    systemctl stop openclaw.service >/dev/null 2>&1 || true
    systemctl disable openclaw.service >/dev/null 2>&1 || true
    systemctl mask openclaw.service >/dev/null 2>&1 || true

    if [[ $USER_EXISTS -eq 1 ]]; then
        info "Stopping user-level openclaw.service for $SYSTEM_USER (if present)..."
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            systemctl --user stop openclaw.service >/dev/null 2>&1 || true
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            systemctl --user disable openclaw.service >/dev/null 2>&1 || true
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
            systemctl --user mask openclaw.service >/dev/null 2>&1 || true
    fi
}

panic_stop_containers() {
    section "PANIC: containers"

    if command -v docker >/dev/null 2>&1; then
        info "Stopping/removing root Docker container (if present)..."
        docker rm -f openclaw >/dev/null 2>&1 || true
    fi

    if [[ $USER_EXISTS -eq 1 ]]; then
        if command -v podman >/dev/null 2>&1; then
            info "Stopping/removing rootless Podman container for $SYSTEM_USER (if present)..."
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
                podman rm -f openclaw >/dev/null 2>&1 || true
        fi

        if command -v docker >/dev/null 2>&1; then
            info "Stopping/removing rootless Docker container for $SYSTEM_USER (if present)..."
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
                DOCKER_HOST="unix://$USER_RUNTIME_DIR/docker.sock" \
                docker rm -f openclaw >/dev/null 2>&1 || true
        fi
    fi
}

panic_kill_processes() {
    section "PANIC: processes"

    info "Killing OpenClaw gateway processes (if present)..."
    pkill -f "node dist/index.js gateway" >/dev/null 2>&1 || true
    pkill -f "openclaw:local" >/dev/null 2>&1 || true
    pkill -f "openclaw" >/dev/null 2>&1 || true

    if [[ $USER_EXISTS -eq 1 ]]; then
        pkill -u "$SYSTEM_USER" -f "node dist/index.js" >/dev/null 2>&1 || true
        pkill -u "$SYSTEM_USER" -f "openclaw" >/dev/null 2>&1 || true
    fi
}

panic_show_next_steps() {
    section "PANIC Complete"

    echo -e "${GREEN}OpenClaw services and workloads have been force-stopped.${RESET}"
    echo
    echo -e "${BOLD}Recommended immediate actions:${RESET}"
    echo "  1) Rotate all LLM API keys used by this host."
    echo "  2) Inspect logs: journalctl -u openclaw -n 200"
    echo "  3) Run full rollback if needed: sudo secureclaw-uninstall"
    echo "  4) If you masked the service, unmask after incident response:"
    echo "     sudo systemctl unmask openclaw.service"
    if [[ $USER_EXISTS -eq 1 ]]; then
        echo "     sudo -u $SYSTEM_USER systemctl --user unmask openclaw.service"
    fi
    if [[ -n "${INSTALL_DIR:-}" ]]; then
        echo
        echo "  Install dir: $INSTALL_DIR"
    fi
}

main() {
    require_root
    load_state
    resolve_user_context

    section "SecureClaw PANIC Stop"
    warn "Emergency stop activated. Attempting to halt all OpenClaw activity now."

    panic_stop_systemd
    panic_stop_containers
    panic_kill_processes
    panic_show_next_steps
}

main "$@"
