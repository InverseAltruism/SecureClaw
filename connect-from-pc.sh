#!/usr/bin/env bash
set -euo pipefail

# SecureClaw PC access helper
# Run this on your local PC to create an SSH tunnel to your VPS OpenClaw gateway.

readonly DEFAULT_GATEWAY_PORT=18789
readonly SECURECLAW_PUBLIC_STATE_FILE="/etc/secureclaw-public.env"

SSH_HOST=""
SSH_USER="${USER:-}"
SSH_PORT="22"
REMOTE_PORT=""
LOCAL_PORT=""
IDENTITY_FILE=""
NO_OPEN=0
FOREGROUND=0

info() {
    echo "[secureclaw-connect] $*"
}

warn() {
    echo "[secureclaw-connect] WARNING: $*" >&2
}

die() {
    echo "[secureclaw-connect] ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  bash connect-from-pc.sh --host <vps-host-or-ip> [options]

Required:
  --host <host>               VPS host or IP address

Optional:
  --user <ssh-user>           SSH username (default: current local user)
  --ssh-port <port>           SSH port (default: 22)
  --remote-port <port>        Remote OpenClaw gateway port on VPS
  --local-port <port>         Local forwarded port on your PC
  --identity <path>           SSH private key path
  --no-open                   Do not open browser automatically
  --foreground                Keep SSH process in foreground (default: background)
  -h, --help                  Show this help

Examples:
  bash connect-from-pc.sh --host 203.0.113.10 --user ubuntu
  bash connect-from-pc.sh --host vps.example.com --user root --identity ~/.ssh/id_ed25519
  bash connect-from-pc.sh --host vps.example.com --remote-port 18801 --local-port 18801
EOF
}

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

open_browser() {
    local url="$1"
    if [[ $NO_OPEN -eq 1 ]]; then
        return
    fi

    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 || true
    elif command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1 || true
    fi
}

detect_remote_port() {
    local -a detect_cmd=(ssh -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8)
    [[ -n "$IDENTITY_FILE" ]] && detect_cmd+=(-i "$IDENTITY_FILE")
    detect_cmd+=("$SSH_USER@$SSH_HOST" "awk -F= '/^GATEWAY_PORT=/{print \$2; exit}' $SECURECLAW_PUBLIC_STATE_FILE 2>/dev/null")

    local detected=""
    detected="$("${detect_cmd[@]}" 2>/dev/null || true)"
    if [[ -n "$detected" ]] && is_valid_port "$detected"; then
        REMOTE_PORT="$detected"
        info "Detected remote gateway port from $SECURECLAW_PUBLIC_STATE_FILE: $REMOTE_PORT"
        return
    fi

    REMOTE_PORT="$DEFAULT_GATEWAY_PORT"
    warn "Could not auto-detect remote port. Falling back to $REMOTE_PORT."
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                [[ $# -ge 2 ]] || die "--host requires a value"
                SSH_HOST="$2"
                shift 2
                ;;
            --user)
                [[ $# -ge 2 ]] || die "--user requires a value"
                SSH_USER="$2"
                shift 2
                ;;
            --ssh-port)
                [[ $# -ge 2 ]] || die "--ssh-port requires a value"
                SSH_PORT="$2"
                shift 2
                ;;
            --remote-port)
                [[ $# -ge 2 ]] || die "--remote-port requires a value"
                REMOTE_PORT="$2"
                shift 2
                ;;
            --local-port)
                [[ $# -ge 2 ]] || die "--local-port requires a value"
                LOCAL_PORT="$2"
                shift 2
                ;;
            --identity)
                [[ $# -ge 2 ]] || die "--identity requires a value"
                IDENTITY_FILE="$2"
                shift 2
                ;;
            --no-open)
                NO_OPEN=1
                shift
                ;;
            --foreground)
                FOREGROUND=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1 (use --help for usage)"
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    [[ -n "$SSH_HOST" ]] || die "--host is required"
    [[ -n "$SSH_USER" ]] || die "Could not infer local username; pass --user explicitly"
    is_valid_port "$SSH_PORT" || die "Invalid --ssh-port: $SSH_PORT"
    [[ -z "$IDENTITY_FILE" || -f "$IDENTITY_FILE" ]] || die "Identity file not found: $IDENTITY_FILE"

    if [[ -z "$REMOTE_PORT" ]]; then
        detect_remote_port
    else
        is_valid_port "$REMOTE_PORT" || die "Invalid --remote-port: $REMOTE_PORT"
    fi

    if [[ -z "$LOCAL_PORT" ]]; then
        LOCAL_PORT="$REMOTE_PORT"
    else
        is_valid_port "$LOCAL_PORT" || die "Invalid --local-port: $LOCAL_PORT"
    fi

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

    info "Starting SSH tunnel: localhost:$LOCAL_PORT -> $SSH_HOST:127.0.0.1:$REMOTE_PORT"
    "${ssh_cmd[@]}"

    local url="http://localhost:$LOCAL_PORT"
    info "Tunnel active. Open: $url"
    open_browser "$url"

    if [[ $FOREGROUND -eq 0 ]]; then
        info "To stop the tunnel later, kill the matching ssh process (or use your terminal/process manager)."
    fi
}

main "$@"
