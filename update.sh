#!/usr/bin/env bash
set -euo pipefail
unset TMOUT 2>/dev/null || true

# SecureClaw updater
# Rebuilds OpenClaw image and restarts the existing SecureClaw deployment.

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

readonly SECURECLAW_STATE_DIR="/etc/secureclaw"
readonly SECURECLAW_INSTALL_STATE_FILE="$SECURECLAW_STATE_DIR/install.env"
readonly OPENCLAW_REPO_URL="https://github.com/openclaw/openclaw.git"
readonly OPENCLAW_DEFAULT_REF="main"
readonly OPENCLAW_LATEST_RELEASE_API="https://api.github.com/repos/openclaw/openclaw/releases/latest"
readonly OPENCLAW_RELEASES_API="https://api.github.com/repos/openclaw/openclaw/releases"

ARG_OPENCLAW_REF=""
ARG_CHANNEL="stable"
ASSUME_YES=0

SYSTEM_USER="openclaw"
INSTALL_DIR=""
CONTAINER_RUNTIME="podman"
ENABLE_SYSTEMD=1
OPENCLAW_REF_RESOLVED="unknown"
USER_UID=""
USER_HOME=""
XDG_RUNTIME_DIR=""
TARGET_REF=""

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
  sudo bash update.sh [options]

Options:
  --channel <stable|beta|dev>
                           Select OpenClaw channel style (default: stable)
                           stable -> latest release tag
                           beta   -> latest prerelease tag
                           dev    -> main branch head
  --openclaw-ref <ref>    Update to a specific OpenClaw git ref/tag/commit
  -y, --yes               Non-interactive mode (accept defaults)
  -h, --help              Show this help
EOF
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root: sudo bash update.sh"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --openclaw-ref)
                [[ $# -ge 2 ]] || die "--openclaw-ref requires a value"
                ARG_OPENCLAW_REF="$2"
                shift 2
                ;;
            --channel)
                [[ $# -ge 2 ]] || die "--channel requires a value"
                ARG_CHANNEL="$2"
                shift 2
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

load_install_state() {
    [[ -f "$SECURECLAW_INSTALL_STATE_FILE" ]] || \
        die "SecureClaw install state not found: $SECURECLAW_INSTALL_STATE_FILE"

    while IFS='=' read -r key value; do
        [[ -n "$key" ]] || continue
        case "$key" in
            SYSTEM_USER) SYSTEM_USER="$value" ;;
            INSTALL_DIR) INSTALL_DIR="$value" ;;
            CONTAINER_RUNTIME) CONTAINER_RUNTIME="$value" ;;
            ENABLE_SYSTEMD) ENABLE_SYSTEMD="$value" ;;
            OPENCLAW_REF_RESOLVED) OPENCLAW_REF_RESOLVED="$value" ;;
            *) ;;
        esac
    done < "$SECURECLAW_INSTALL_STATE_FILE"

    id "$SYSTEM_USER" >/dev/null 2>&1 || die "System user not found: $SYSTEM_USER"
    USER_UID="$(id -u "$SYSTEM_USER")"
    USER_HOME="$(getent passwd "$SYSTEM_USER" | awk -F: 'NR==1 {print $6}')"
    [[ -n "$USER_HOME" ]] || die "Unable to resolve home directory for $SYSTEM_USER"
    XDG_RUNTIME_DIR="/run/user/$USER_UID"

    [[ -n "$INSTALL_DIR" ]] || INSTALL_DIR="$USER_HOME/.openclaw"
    [[ -d "$INSTALL_DIR" ]] || die "Install directory not found: $INSTALL_DIR"
    [[ -f "$INSTALL_DIR/launch-openclaw.sh" ]] || die "Launch script missing: $INSTALL_DIR/launch-openclaw.sh"
}

latest_release_ref() {
    if command -v curl >/dev/null 2>&1; then
        local tag=""
        tag="$(curl -fsSL "$OPENCLAW_LATEST_RELEASE_API" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
        if [[ -n "$tag" ]]; then
            echo "$tag"
            return 0
        fi
    fi
    return 1
}

latest_beta_ref() {
    if command -v curl >/dev/null 2>&1; then
        local tag=""
        tag="$(
            curl -fsSL "$OPENCLAW_RELEASES_API" | awk '
                /"tag_name"[[:space:]]*:/ {
                    line=$0
                    sub(/.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
                    sub(/".*/, "", line)
                    current_tag=line
                }
                /"prerelease"[[:space:]]*:[[:space:]]*true/ {
                    if (current_tag != "") {
                        print current_tag
                        exit
                    }
                }
            '
        )"
        if [[ -n "$tag" ]]; then
            echo "$tag"
            return 0
        fi
    fi
    return 1
}

choose_target_ref() {
    section "Update Target"

    if [[ -n "$ARG_OPENCLAW_REF" ]]; then
        TARGET_REF="$ARG_OPENCLAW_REF"
        info "Using explicit ref: $TARGET_REF"
        return
    fi

    local default_ref=""
    local latest_tag=""
    local latest_beta=""
    case "$ARG_CHANNEL" in
        stable)
            latest_tag="$(latest_release_ref || true)"
            default_ref="${latest_tag:-$OPENCLAW_DEFAULT_REF}"
            ;;
        beta)
            latest_beta="$(latest_beta_ref || true)"
            if [[ -n "$latest_beta" ]]; then
                default_ref="$latest_beta"
            else
                warn "Could not detect beta prerelease tag; falling back to stable release."
                latest_tag="$(latest_release_ref || true)"
                default_ref="${latest_tag:-$OPENCLAW_DEFAULT_REF}"
            fi
            ;;
        dev)
            default_ref="main"
            ;;
        *)
            die "Invalid --channel value: $ARG_CHANNEL (expected stable|beta|dev)"
            ;;
    esac

    if [[ $ASSUME_YES -eq 1 ]]; then
        TARGET_REF="$default_ref"
        info "Non-interactive mode selected ref: $TARGET_REF"
        return
    fi

    echo "Current installed OpenClaw ref: $OPENCLAW_REF_RESOLVED"
    if [[ -n "$latest_tag" ]]; then
        echo "Latest GitHub release tag:      $latest_tag"
    else
        warn "Could not detect latest stable release tag automatically."
    fi
    if [[ -n "$latest_beta" ]]; then
        echo "Latest GitHub beta tag:         $latest_beta"
    fi
    echo "Selected channel:               $ARG_CHANNEL"
    echo "Recommended default ref:        $default_ref"
    echo
    read -r -p "OpenClaw ref/tag/commit to install [$default_ref]: " TARGET_REF
    TARGET_REF="${TARGET_REF:-$default_ref}"
    [[ -n "$TARGET_REF" ]] || die "Empty ref not allowed"
}

confirm_plan() {
    section "Update Plan"
    echo "System user:       $SYSTEM_USER"
    echo "Install directory: $INSTALL_DIR"
    echo "Runtime:           $CONTAINER_RUNTIME"
    echo "Systemd managed:   $ENABLE_SYSTEMD"
    echo "Target ref:        $TARGET_REF"
    echo
    if [[ $ASSUME_YES -eq 1 ]]; then
        return
    fi
    read -r -p "Proceed with update? [Y/n]: " reply
    reply="${reply:-Y}"
    [[ "$reply" =~ ^[Yy]$ ]] || die "Update cancelled."
}

backup_current_image() {
    local backup_tag="openclaw:backup-$(date +%Y%m%d%H%M%S)"
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" podman image exists openclaw:local; then
            info "Creating Podman backup image tag: $backup_tag"
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" podman tag openclaw:local "$backup_tag" || true
        fi
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker image inspect openclaw:local >/dev/null 2>&1; then
            info "Creating rootless Docker backup image tag: $backup_tag"
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker tag openclaw:local "$backup_tag" || true
        fi
    else
        if docker image inspect openclaw:local >/dev/null 2>&1; then
            info "Creating Docker backup image tag: $backup_tag"
            docker tag openclaw:local "$backup_tag" || true
        fi
    fi
}

checkout_openclaw_ref() {
    local workdir
    workdir="$(mktemp -d /tmp/openclaw-update-XXXXXX)"
    git clone --filter=blob:none --no-checkout "$OPENCLAW_REPO_URL" "$workdir" >/dev/null 2>&1 || die "Failed to clone OpenClaw"
    git -C "$workdir" fetch --depth 1 origin "$TARGET_REF" >/dev/null 2>&1 || die "Failed to fetch ref: $TARGET_REF"
    git -C "$workdir" checkout --detach FETCH_HEAD >/dev/null 2>&1 || die "Failed to checkout ref: $TARGET_REF"
    echo "$workdir"
}

build_new_image() {
    section "Building Updated Image"
    local source_dir="$1"
    local resolved_ref
    resolved_ref="$(git -C "$source_dir" rev-parse HEAD)"
    info "Resolved ref: $resolved_ref"

    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            podman build -t openclaw:local -f "$source_dir/Dockerfile" "$source_dir" || die "Podman build failed"
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" \
            docker build -t openclaw:local -f "$source_dir/Dockerfile" "$source_dir" || die "Docker rootless build failed"
    else
        docker build -t openclaw:local -f "$source_dir/Dockerfile" "$source_dir" || die "Docker build failed"
    fi

    OPENCLAW_REF_RESOLVED="$resolved_ref"
}

restart_openclaw() {
    section "Restarting OpenClaw"

    if [[ "$ENABLE_SYSTEMD" -eq 1 ]]; then
        if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
            systemctl restart openclaw.service || die "Failed to restart openclaw.service"
        else
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
                systemctl --user restart openclaw.service || die "Failed to restart user openclaw.service"
        fi
    else
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" podman rm -f openclaw >/dev/null 2>&1 || true
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" bash "$INSTALL_DIR/launch-openclaw.sh" || die "Failed to relaunch with Podman"
        elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker rm -f openclaw >/dev/null 2>&1 || true
            sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" bash "$INSTALL_DIR/launch-openclaw.sh" || die "Failed to relaunch with rootless Docker"
        else
            docker rm -f openclaw >/dev/null 2>&1 || true
            bash "$INSTALL_DIR/launch-openclaw.sh" || die "Failed to relaunch with Docker"
        fi
    fi
}

verify_running() {
    section "Verification"
    local ok=0
    if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" podman ps --format '{{.Names}}' | grep -qx 'openclaw'; then
            ok=1
        fi
    elif [[ "$CONTAINER_RUNTIME" == "docker-rootless" ]]; then
        if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker ps --format '{{.Names}}' | grep -qx 'openclaw'; then
            ok=1
        fi
    else
        if docker ps --format '{{.Names}}' | grep -qx 'openclaw'; then
            ok=1
        fi
    fi

    [[ "$ok" -eq 1 ]] || die "Update finished but container is not running."
    info "OpenClaw container is running."
}

update_install_manifest_ref() {
    if [[ -f "$SECURECLAW_INSTALL_STATE_FILE" ]]; then
        sed -i "s|^OPENCLAW_REF_RESOLVED=.*|OPENCLAW_REF_RESOLVED=$OPENCLAW_REF_RESOLVED|" "$SECURECLAW_INSTALL_STATE_FILE" || true
    fi
}

main() {
    require_root
    parse_args "$@"
    load_install_state
    choose_target_ref
    confirm_plan
    backup_current_image

    local source_dir=""
    source_dir="$(checkout_openclaw_ref)"
    trap 'rm -rf "$source_dir" >/dev/null 2>&1 || true' EXIT

    build_new_image "$source_dir"
    restart_openclaw
    verify_running
    update_install_manifest_ref

    section "Update Complete"
    info "OpenClaw updated to ref: $OPENCLAW_REF_RESOLVED"
    info "If needed, rollback by re-tagging a backup image and restarting."
}

main "$@"
