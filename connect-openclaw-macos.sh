#!/usr/bin/env bash
set -euo pipefail

# SecureClaw macOS connection helper.
# Run on macOS to open an SSH tunnel to a SecureClaw VPS.

readonly SCRIPT_NAME="secureclaw-connect-macos"
readonly DEFAULT_GATEWAY_PORT=18789
readonly SECURECLAW_PUBLIC_STATE_FILE="/etc/secureclaw-public.env"

SSH_HOST=""
SSH_USER="${USER:-}"
SSH_PORT="22"
REMOTE_PORT=""
LOCAL_PORT=""
IDENTITY_FILE=""
FOREGROUND=0
NO_OPEN=0
AUTO_DETECT_REMOTE=1
ASSUME_YES=0

info() {
    echo "[$SCRIPT_NAME] $*"
}

warn() {
    echo "[$SCRIPT_NAME] WARNING: $*" >&2
}

die() {
    echo "[$SCRIPT_NAME] ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  bash connect-openclaw-macos.sh [options]

Options:
  --host <vps-host-or-ip>     VPS host/IP for SSH
  --user <ssh-user>           SSH username (default: local user)
  --ssh-port <port>           SSH port (default: 22)
  --remote-port <port>        Remote OpenClaw gateway port (auto-detect by default)
  --local-port <port>         Local port to open in browser (default: same as remote)
  --identity <path>           SSH private key file
  --foreground                Keep SSH in foreground
  --no-open                   Do not open browser
  --no-detect                 Disable remote port auto-detection
  -y, --yes                   Skip final confirmation prompt
  -h, --help                  Show this help
EOF
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

prompt_text() {
    local label="$1"
    local default_value="${2:-}"
    local value=""
    if [[ -n "$default_value" ]]; then
        read -r -p "$label [$default_value]: " value
        value="${value:-$default_value}"
    else
        read -r -p "$label: " value
    fi
    echo "$value"
}

prompt_yes_no() {
    local label="$1"
    local default_choice="${2:-Y}"
    local reply=""
    read -r -p "$label [$default_choice]: " reply
    reply="${reply:-$default_choice}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

open_browser() {
    local url="$1"
    if [[ $NO_OPEN -eq 1 ]]; then
        return
    fi
    open "$url" >/dev/null 2>&1 || true
}

copy_to_clipboard() {
    local value="$1"
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$value" | pbcopy
        info "Dashboard URL copied to clipboard."
    fi
}

wait_for_local_tunnel() {
    local retries=0
    while (( retries < 10 )); do
        if (echo >"/dev/tcp/127.0.0.1/$LOCAL_PORT") >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        retries=$((retries + 1))
    done
    return 1
}

detect_remote_port() {
    local -a detect_cmd=(ssh -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8)
    [[ -n "$IDENTITY_FILE" ]] && detect_cmd+=(-i "$IDENTITY_FILE")
    detect_cmd+=("$SSH_USER@$SSH_HOST" "awk -F= '/^GATEWAY_PORT=/{print \$2; exit}' $SECURECLAW_PUBLIC_STATE_FILE 2>/dev/null")

    local detected=""
    detected="$("${detect_cmd[@]}" 2>/dev/null || true)"
    if [[ -n "$detected" ]] && is_valid_port "$detected"; then
        REMOTE_PORT="$detected"
        info "Detected remote gateway port: $REMOTE_PORT"
        return 0
    fi
    return 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host) SSH_HOST="${2:-}"; shift 2 ;;
            --user) SSH_USER="${2:-}"; shift 2 ;;
            --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
            --remote-port) REMOTE_PORT="${2:-}"; AUTO_DETECT_REMOTE=0; shift 2 ;;
            --local-port) LOCAL_PORT="${2:-}"; shift 2 ;;
            --identity) IDENTITY_FILE="${2:-}"; shift 2 ;;
            --foreground) FOREGROUND=1; shift ;;
            --no-open) NO_OPEN=1; shift ;;
            --no-detect) AUTO_DETECT_REMOTE=0; shift ;;
            -y|--yes) ASSUME_YES=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
}

interactive_prompts() {
    echo
    info "SecureClaw macOS connection wizard"
    echo

    [[ -n "$SSH_HOST" ]] || SSH_HOST="$(prompt_text "VPS host or IP")"
    [[ -n "$SSH_USER" ]] || SSH_USER="$(prompt_text "SSH username" "root")"
    [[ -n "$SSH_PORT" ]] || SSH_PORT="$(prompt_text "SSH port" "22")"

    if [[ -z "$IDENTITY_FILE" ]]; then
        local use_key
        if prompt_yes_no "Use a custom SSH private key file?" "N"; then
            use_key=1
        else
            use_key=0
        fi
        if [[ "$use_key" -eq 1 ]]; then
            IDENTITY_FILE="$(prompt_text "SSH private key path" "$HOME/.ssh/id_ed25519")"
        fi
    fi
}

validate_inputs() {
    [[ -n "$SSH_HOST" ]] || die "VPS host is required."
    [[ -n "$SSH_USER" ]] || die "SSH user is required."
    command -v ssh >/dev/null 2>&1 || die "ssh command not found."
    is_valid_port "$SSH_PORT" || die "Invalid SSH port: $SSH_PORT"
    if [[ -n "$IDENTITY_FILE" && ! -f "$IDENTITY_FILE" ]]; then
        die "Identity file not found: $IDENTITY_FILE"
    fi
}

resolve_ports() {
    if [[ -z "$REMOTE_PORT" ]]; then
        if [[ $AUTO_DETECT_REMOTE -eq 1 ]] && detect_remote_port; then
            :
        else
            warn "Could not auto-detect remote gateway port from VPS."
            REMOTE_PORT="$(prompt_text "Remote OpenClaw gateway port" "$DEFAULT_GATEWAY_PORT")"
        fi
    fi
    is_valid_port "$REMOTE_PORT" || die "Invalid remote port: $REMOTE_PORT"

    if [[ -z "$LOCAL_PORT" ]]; then
        LOCAL_PORT="$(prompt_text "Local browser port" "$REMOTE_PORT")"
    fi
    is_valid_port "$LOCAL_PORT" || die "Invalid local port: $LOCAL_PORT"
}

start_tunnel() {
    local -a ssh_cmd=(
        ssh
        -p "$SSH_PORT"
        -o ExitOnForwardFailure=yes
        -o ServerAliveInterval=30
        -o ServerAliveCountMax=3
    )
    [[ -n "$IDENTITY_FILE" ]] && ssh_cmd+=(-i "$IDENTITY_FILE")
    [[ $FOREGROUND -eq 0 ]] && ssh_cmd+=(-f)
    ssh_cmd+=(
        -N
        -L "$LOCAL_PORT:127.0.0.1:$REMOTE_PORT"
        "$SSH_USER@$SSH_HOST"
    )

    info "Starting tunnel localhost:$LOCAL_PORT -> $SSH_HOST:127.0.0.1:$REMOTE_PORT"
    "${ssh_cmd[@]}"
}

main() {
    parse_args "$@"
    interactive_prompts
    validate_inputs
    resolve_ports

    local url="http://localhost:$LOCAL_PORT"
    echo
    info "Summary:"
    info "  SSH target : $SSH_USER@$SSH_HOST:$SSH_PORT"
    info "  Forwarding : localhost:$LOCAL_PORT -> 127.0.0.1:$REMOTE_PORT on VPS"
    info "  Dashboard  : $url"
    echo
    if [[ $ASSUME_YES -eq 0 ]]; then
        prompt_yes_no "Start the tunnel now?" "Y" || die "Cancelled."
    fi

    start_tunnel
    if ! wait_for_local_tunnel; then
        die "SSH process started but local tunnel port $LOCAL_PORT did not become reachable."
    fi
    info "Tunnel active. Open this URL: $url"
    copy_to_clipboard "$url"
    open_browser "$url"

    if [[ $FOREGROUND -eq 0 ]]; then
        info "To close the tunnel later, stop the matching ssh process."
    fi
}

main "$@"
