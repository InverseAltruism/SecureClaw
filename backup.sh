#!/usr/bin/env bash
set -euo pipefail
unset TMOUT 2>/dev/null || true

# SecureClaw backup and restore utility.
# Creates portable backups of SecureClaw/OpenClaw agent state and restores them.

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

readonly SECURECLAW_STATE_DIR="/etc/secureclaw"
readonly SECURECLAW_INSTALL_STATE_FILE="$SECURECLAW_STATE_DIR/install.env"
readonly SECURECLAW_PUBLIC_STATE_FILE="/etc/secureclaw-public.env"

MODE="backup"
ARCHIVE_PATH=""
BACKUP_DIR="/var/backups/secureclaw"
NO_RESTART=0
ASSUME_YES=0

SYSTEM_USER="openclaw"
INSTALL_DIR=""
CONTAINER_RUNTIME=""

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

usage() {
    cat <<'EOF'
Usage:
  sudo bash backup.sh [options]

Backup mode (default):
  sudo bash backup.sh [--output-dir <dir>] [-y]

Restore mode:
  sudo bash backup.sh --restore <archive.tar.gz> [--no-restart] [-y]

Options:
  --output-dir <dir>      Backup output directory (default: /var/backups/secureclaw)
  --restore <archive>     Restore from backup archive path
  --no-restart            Do not restart OpenClaw service after restore
  -y, --yes               Non-interactive mode (accept prompts)
  -h, --help              Show help
EOF
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root: sudo bash backup.sh"
}

confirm_or_die() {
    local prompt="$1"
    if [[ $ASSUME_YES -eq 1 ]]; then
        return
    fi
    local reply=""
    read -r -p "$prompt [Y/n]: " reply
    reply="${reply:-Y}"
    [[ "$reply" =~ ^[Yy]$ ]] || die "Cancelled."
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)
                [[ $# -ge 2 ]] || die "--output-dir requires a value"
                BACKUP_DIR="$2"
                shift 2
                ;;
            --restore)
                [[ $# -ge 2 ]] || die "--restore requires a value"
                MODE="restore"
                ARCHIVE_PATH="$2"
                shift 2
                ;;
            --no-restart)
                NO_RESTART=1
                shift
                ;;
            -y|--yes)
                ASSUME_YES=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

load_state_if_present() {
    if [[ -f "$SECURECLAW_INSTALL_STATE_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -n "$key" ]] || continue
            case "$key" in
                SYSTEM_USER) SYSTEM_USER="$value" ;;
                INSTALL_DIR) INSTALL_DIR="$value" ;;
                CONTAINER_RUNTIME) CONTAINER_RUNTIME="$value" ;;
                *) ;;
            esac
        done < "$SECURECLAW_INSTALL_STATE_FILE"
    fi

    if [[ -z "$INSTALL_DIR" ]]; then
        local maybe_home=""
        maybe_home="$(getent passwd "$SYSTEM_USER" | awk -F: 'NR==1 {print $6}')"
        [[ -n "$maybe_home" ]] && INSTALL_DIR="$maybe_home/.openclaw"
    fi
}

create_backup() {
    section "SecureClaw Backup"
    load_state_if_present

    [[ -n "$INSTALL_DIR" ]] || die "Could not determine install directory."
    [[ -d "$INSTALL_DIR" ]] || die "Install directory not found: $INSTALL_DIR"

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/secureclaw-backup-XXXXXX)"
    local bundle_dir="$tmp_dir/secureclaw-backup-$ts"
    mkdir -p "$bundle_dir/meta" "$bundle_dir/state"

    info "Collecting SecureClaw metadata..."
    cat > "$bundle_dir/meta/manifest.env" <<EOF
BACKUP_CREATED_AT=$ts
SYSTEM_USER=$SYSTEM_USER
INSTALL_DIR=$INSTALL_DIR
CONTAINER_RUNTIME=$CONTAINER_RUNTIME
HOSTNAME=$(hostname)
EOF

    if [[ -f "$SECURECLAW_INSTALL_STATE_FILE" ]]; then
        cp "$SECURECLAW_INSTALL_STATE_FILE" "$bundle_dir/state/install.env"
    fi
    if [[ -f "$SECURECLAW_PUBLIC_STATE_FILE" ]]; then
        cp "$SECURECLAW_PUBLIC_STATE_FILE" "$bundle_dir/state/secureclaw-public.env"
    fi

    info "Backing up OpenClaw agent data from $INSTALL_DIR..."
    tar -czf "$bundle_dir/agent-data.tar.gz" -C "$INSTALL_DIR" .

    if [[ -f "/etc/systemd/system/openclaw.service" ]]; then
        cp "/etc/systemd/system/openclaw.service" "$bundle_dir/state/openclaw.system.service"
    fi
    if id "$SYSTEM_USER" >/dev/null 2>&1; then
        local user_home
        user_home="$(getent passwd "$SYSTEM_USER" | awk -F: 'NR==1 {print $6}')"
        if [[ -n "$user_home" && -f "$user_home/.config/systemd/user/openclaw.service" ]]; then
            cp "$user_home/.config/systemd/user/openclaw.service" "$bundle_dir/state/openclaw.user.service"
        fi
        if [[ -n "$user_home" && -f "$user_home/.config/containers/systemd/openclaw.container" ]]; then
            cp "$user_home/.config/containers/systemd/openclaw.container" "$bundle_dir/state/openclaw.container"
        fi
    fi

    (cd "$bundle_dir" && sha256sum agent-data.tar.gz > meta/agent-data.sha256)

    local archive="$BACKUP_DIR/secureclaw-backup-$ts.tar.gz"
    info "Creating backup archive: $archive"
    tar -czf "$archive" -C "$tmp_dir" "secureclaw-backup-$ts"
    chmod 600 "$archive"

    rm -rf "$tmp_dir"

    info "Backup completed successfully."
    info "Archive: $archive"
    warn "Archive contains secrets (.env keys/tokens). Store it encrypted and offline."
}

ensure_system_user_exists() {
    local user_name="$1"
    if id "$user_name" >/dev/null 2>&1; then
        return
    fi
    info "Creating missing system user: $user_name"
    useradd --system --create-home --shell /usr/sbin/nologin "$user_name" || die "Failed to create user $user_name"
}

restart_service_best_effort() {
    local system_user="$1"
    local runtime="${2:-}"
    if [[ "$NO_RESTART" -eq 1 ]]; then
        return
    fi

    info "Restarting OpenClaw service (best effort)..."
    if [[ -f "/etc/systemd/system/openclaw.service" ]]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl restart openclaw.service >/dev/null 2>&1 || true
        return
    fi

    local uid
    uid="$(id -u "$system_user" 2>/dev/null || true)"
    if [[ -n "$uid" ]]; then
        local runtime_dir="/run/user/$uid"
        sudo -u "$system_user" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user daemon-reload >/dev/null 2>&1 || true
        sudo -u "$system_user" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user restart openclaw.service >/dev/null 2>&1 || true
        if [[ "$runtime" == "podman" ]]; then
            sudo -u "$system_user" XDG_RUNTIME_DIR="$runtime_dir" podman rm -f openclaw >/dev/null 2>&1 || true
        fi
    fi
}

restore_backup() {
    section "SecureClaw Restore"
    [[ -n "$ARCHIVE_PATH" ]] || die "Missing --restore <archive>"
    [[ -f "$ARCHIVE_PATH" ]] || die "Archive not found: $ARCHIVE_PATH"

    confirm_or_die "Restore will overwrite current SecureClaw state. Continue?"

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/secureclaw-restore-XXXXXX)"
    trap 'rm -rf "$tmp_dir" >/dev/null 2>&1 || true' EXIT

    tar -xzf "$ARCHIVE_PATH" -C "$tmp_dir"
    local bundle_dir
    bundle_dir="$(ls -d "$tmp_dir"/secureclaw-backup-* 2>/dev/null | head -n1 || true)"
    [[ -n "$bundle_dir" ]] || die "Invalid backup archive structure."

    [[ -f "$bundle_dir/meta/manifest.env" ]] || die "Missing manifest.env in backup."
    # shellcheck disable=SC1090
    source "$bundle_dir/meta/manifest.env"

    local restore_user="${SYSTEM_USER:-openclaw}"
    local restore_dir="${INSTALL_DIR:-}"
    local restore_runtime="${CONTAINER_RUNTIME:-}"
    [[ -n "$restore_dir" ]] || die "Restore manifest missing INSTALL_DIR."

    info "Backup metadata:"
    info "  System user: $restore_user"
    info "  Install dir: $restore_dir"
    info "  Runtime    : $restore_runtime"

    ensure_system_user_exists "$restore_user"
    mkdir -p "$restore_dir"

    if [[ -f "$bundle_dir/meta/agent-data.sha256" ]]; then
        (cd "$bundle_dir" && sha256sum -c meta/agent-data.sha256) || die "Backup checksum validation failed."
    fi

    info "Restoring agent data into $restore_dir..."
    tar -xzf "$bundle_dir/agent-data.tar.gz" -C "$restore_dir"
    chown -R "$restore_user:$restore_user" "$restore_dir"
    chmod 700 "$restore_dir" || true

    mkdir -p "$SECURECLAW_STATE_DIR"
    chmod 700 "$SECURECLAW_STATE_DIR"
    if [[ -f "$bundle_dir/state/install.env" ]]; then
        cp "$bundle_dir/state/install.env" "$SECURECLAW_INSTALL_STATE_FILE"
        chmod 600 "$SECURECLAW_INSTALL_STATE_FILE"
    fi
    if [[ -f "$bundle_dir/state/secureclaw-public.env" ]]; then
        cp "$bundle_dir/state/secureclaw-public.env" "$SECURECLAW_PUBLIC_STATE_FILE"
        chmod 644 "$SECURECLAW_PUBLIC_STATE_FILE"
    fi

    if [[ -f "$bundle_dir/state/openclaw.system.service" ]]; then
        cp "$bundle_dir/state/openclaw.system.service" /etc/systemd/system/openclaw.service
    fi

    local user_home
    user_home="$(getent passwd "$restore_user" | awk -F: 'NR==1 {print $6}')"
    if [[ -n "$user_home" ]]; then
        if [[ -f "$bundle_dir/state/openclaw.user.service" ]]; then
            mkdir -p "$user_home/.config/systemd/user"
            cp "$bundle_dir/state/openclaw.user.service" "$user_home/.config/systemd/user/openclaw.service"
        fi
        if [[ -f "$bundle_dir/state/openclaw.container" ]]; then
            mkdir -p "$user_home/.config/containers/systemd"
            cp "$bundle_dir/state/openclaw.container" "$user_home/.config/containers/systemd/openclaw.container"
        fi
        chown -R "$restore_user:$restore_user" "$user_home/.config/systemd" "$user_home/.config/containers" 2>/dev/null || true
    fi

    restart_service_best_effort "$restore_user" "$restore_runtime"

    info "Restore completed."
    if [[ "$NO_RESTART" -eq 1 ]]; then
        warn "Service restart skipped (--no-restart). Start OpenClaw manually."
    fi
}

main() {
    require_root
    parse_args "$@"

    if [[ "$MODE" == "backup" ]]; then
        create_backup
    else
        restore_backup
    fi
}

main "$@"
