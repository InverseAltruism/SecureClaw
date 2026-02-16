#!/usr/bin/env bash
set -euo pipefail

# SecureClaw Installer
# Interactive hardened deployment for OpenClaw in rootless Podman
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

# ============================================================================
# BANNER
# ============================================================================
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
   ____                           ____ _               
  / ___|  ___  ___ _   _ _ __ ___|  _ \ | __ ___      __
  \___ \ / _ \/ __| | | | '__/ _ \ |_) | |/ _` \ \ /\ / /
   ___) |  __/ (__| |_| | | |  __/  __/| | (_| |\ V  V / 
  |____/ \___|\___|\__,_|_|  \___|_|   |_|\__,_| \_/\_/  
                                                          
  Run OpenClaw in a fortress. Maximum isolation. Zero trust.
EOF
    echo -e "${RESET}"
    echo
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

    # Check OPENCLAW_REPO env var
    if [[ -n "${OPENCLAW_REPO:-}" && -d "$OPENCLAW_REPO" ]]; then
        repo_path="$OPENCLAW_REPO"
        info "Using OpenClaw repo from OPENCLAW_REPO: $repo_path"
    # Check for --openclaw-repo argument
    elif [[ -n "${ARG_OPENCLAW_REPO:-}" && -d "$ARG_OPENCLAW_REPO" ]]; then
        repo_path="$ARG_OPENCLAW_REPO"
        info "Using OpenClaw repo from argument: $repo_path"
    # Check sibling directory
    elif [[ -d "$(dirname "$0")/../openclaw" ]]; then
        repo_path="$(cd "$(dirname "$0")/../openclaw" && pwd)"
        info "Found OpenClaw repo in sibling directory: $repo_path"
    # Clone it
    else
        warn "OpenClaw repository not found"
        info "Cloning from https://github.com/openclaw/openclaw.git..."
        repo_path="/tmp/openclaw-$$"
        git clone --depth 1 https://github.com/openclaw/openclaw.git "$repo_path" || \
            die "Failed to clone OpenClaw repository"
        OPENCLAW_REPO_TEMP=1
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
    section "Section 1/7: Security Level"
    echo
    echo "Choose your security tier:"
    echo
    echo "  ${BOLD}1. Standard${RESET} — Basic rootless isolation"
    dim "Localhost binding, token auth, user namespaces"
    echo
    echo "  ${BOLD}2. Hardened${RESET} — Production-grade security ${GREEN}(default)${RESET}"
    dim "Read-only root, capability drop, resource limits, network isolation"
    echo
    echo "  ${BOLD}3. Paranoid${RESET} — Maximum isolation"
    dim "All hardened features + host firewall + audit logging + per-agent sandboxing"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Select tier [1/2/3]:${RESET} ")" -r SECURITY_LEVEL
    SECURITY_LEVEL=${SECURITY_LEVEL:-2}

    case "$SECURITY_LEVEL" in
        1)
            SECURITY_TIER="standard"
            info "Selected: Standard tier"
            ;;
        2)
            SECURITY_TIER="hardened"
            info "Selected: Hardened tier (recommended)"
            ;;
        3)
            SECURITY_TIER="paranoid"
            info "Selected: Paranoid tier"
            ;;
        *)
            warn "Invalid selection, using Hardened (default)"
            SECURITY_TIER="hardened"
            ;;
    esac
}

prompt_install_dir() {
    section "Section 2/7: Installation Directory"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Install directory:${RESET} ")" -r -i "/home/openclaw/.openclaw" -e INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/home/openclaw/.openclaw}
    
    CONFIG_DIR="$INSTALL_DIR"
    WORKSPACE_DIR="$INSTALL_DIR/workspace"
    
    info "Configuration: $CONFIG_DIR"
    info "Workspace: $WORKSPACE_DIR"
}

prompt_username() {
    section "Section 3/7: System User"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}System username:${RESET} ")" -r -i "openclaw" -e SYSTEM_USER
    SYSTEM_USER=${SYSTEM_USER:-openclaw}
    info "Will create system user: $SYSTEM_USER"
}

prompt_ports() {
    section "Section 4/7: Gateway Port"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Gateway port:${RESET} ")" -r -i "18789" -e GATEWAY_PORT
    GATEWAY_PORT=${GATEWAY_PORT:-18789}
    BRIDGE_PORT=$((GATEWAY_PORT + 1))
    info "Gateway port: $GATEWAY_PORT"
    info "Bridge port: $BRIDGE_PORT"
}

prompt_token() {
    echo
    info "Generating 256-bit gateway token..."
    AUTO_TOKEN=$(generate_token)
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Gateway token:${RESET} ")" -r -i "$AUTO_TOKEN" -e GATEWAY_TOKEN
    GATEWAY_TOKEN=${GATEWAY_TOKEN:-$AUTO_TOKEN}
    dim "Token: ${GATEWAY_TOKEN:0:16}...${GATEWAY_TOKEN: -8}"
}

prompt_api_keys() {
    section "Section 5/7: API Keys (optional)"
    echo
    dim "Press Enter to skip any key"
    echo

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}ANTHROPIC_API_KEY:${RESET} ")" -rs ANTHROPIC_API_KEY || true
    echo
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        dim "Anthropic key configured"
    fi

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}OPENAI_API_KEY:${RESET} ")" -rs OPENAI_API_KEY || true
    echo
    if [[ -n "$OPENAI_API_KEY" ]]; then
        dim "OpenAI key configured"
    fi

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}OPENROUTER_API_KEY:${RESET} ")" -rs OPENROUTER_API_KEY || true
    echo
    if [[ -n "$OPENROUTER_API_KEY" ]]; then
        dim "OpenRouter key configured"
    fi

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}GEMINI_API_KEY:${RESET} ")" -rs GEMINI_API_KEY || true
    echo
    if [[ -n "$GEMINI_API_KEY" ]]; then
        dim "Gemini key configured"
    fi

    local key_count=0
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && ((key_count++))
    [[ -n "${OPENAI_API_KEY:-}" ]] && ((key_count++))
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && ((key_count++))
    [[ -n "${GEMINI_API_KEY:-}" ]] && ((key_count++))

    echo
    info "Configured $key_count API key(s)"
}

prompt_systemd() {
    section "Section 6/7: Systemd Auto-Start"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Enable systemd Quadlet for auto-start? [Y/n]:${RESET} ")" -r ENABLE_SYSTEMD
    ENABLE_SYSTEMD=${ENABLE_SYSTEMD:-Y}
    if [[ "$ENABLE_SYSTEMD" =~ ^[Yy]$ || "$ENABLE_SYSTEMD" == "" ]]; then
        ENABLE_SYSTEMD=1
        info "Systemd Quadlet will be configured"
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

    section "Section 7/7: Resource Limits"
    echo
    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}Memory limit:${RESET} ")" -r -i "2g" -e MEMORY_LIMIT
    MEMORY_LIMIT=${MEMORY_LIMIT:-2g}

    read -p "$(echo -e "${GREEN}?${RESET} ${BOLD}CPU limit:${RESET} ")" -r -i "2.0" -e CPU_LIMIT
    CPU_LIMIT=${CPU_LIMIT:-2.0}

    PID_LIMIT=256
    
    info "Memory: $MEMORY_LIMIT"
    info "CPUs: $CPU_LIMIT"
    info "PIDs: $PID_LIMIT"
}

show_summary() {
    section "Configuration Summary"
    echo
    echo -e "${BOLD}Security Tier:${RESET}       $SECURITY_TIER"
    echo -e "${BOLD}Install Directory:${RESET}   $INSTALL_DIR"
    echo -e "${BOLD}System User:${RESET}         $SYSTEM_USER"
    echo -e "${BOLD}Gateway Port:${RESET}        $GATEWAY_PORT"
    echo -e "${BOLD}Bridge Port:${RESET}         $BRIDGE_PORT"
    echo -e "${BOLD}Gateway Token:${RESET}       ${GATEWAY_TOKEN:0:16}...${GATEWAY_TOKEN: -8}"
    
    local key_count=0
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && ((key_count++))
    [[ -n "${OPENAI_API_KEY:-}" ]] && ((key_count++))
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && ((key_count++))
    [[ -n "${GEMINI_API_KEY:-}" ]] && ((key_count++))
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
    if [[ "$SECURITY_TIER" == "paranoid" ]]; then
        warn "Paranoid tier will modify host firewall (nftables) and install audit monitoring"
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
    apt-get update -qq
    apt-get install -y -qq podman uidmap slirp4netns git >/dev/null 2>&1 || \
        die "Failed to install dependencies"
    
    # Create system user
    if ! id "$SYSTEM_USER" &>/dev/null; then
        info "Creating system user: $SYSTEM_USER"
        useradd --system --create-home --shell /usr/sbin/nologin "$SYSTEM_USER" || \
            die "Failed to create user"
    else
        info "User $SYSTEM_USER already exists"
    fi
    
    # Get user info
    USER_UID=$(id -u "$SYSTEM_USER")
    USER_GID=$(id -g "$SYSTEM_USER")
    USER_HOME=$(eval echo "~$SYSTEM_USER")
    
    # Enable linger
    info "Enabling systemd linger for $SYSTEM_USER"
    loginctl enable-linger "$SYSTEM_USER" || \
        warn "Failed to enable linger (non-fatal)"
    
    # Configure subuid/subgid
    if ! grep -q "^$SYSTEM_USER:" /etc/subuid; then
        info "Configuring subuid mapping"
        echo "$SYSTEM_USER:100000:65536" >> /etc/subuid
    fi
    
    if ! grep -q "^$SYSTEM_USER:" /etc/subgid; then
        info "Configuring subgid mapping"
        echo "$SYSTEM_USER:100000:65536" >> /etc/subgid
    fi
    
    # Ensure XDG_RUNTIME_DIR exists
    XDG_RUNTIME_DIR="/run/user/$USER_UID"
    if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
        info "Creating XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
        mkdir -p "$XDG_RUNTIME_DIR"
        chown "$SYSTEM_USER:$SYSTEM_USER" "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
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
    
    info "Building OpenClaw image from $OPENCLAW_PATH..."
    podman build -t openclaw:local -f "$OPENCLAW_PATH/Dockerfile" "$OPENCLAW_PATH" || \
        die "Failed to build container image"
    
    # Save and load into user's rootless store
    info "Transferring image to $SYSTEM_USER's rootless store..."
    local tmp_image="/tmp/openclaw-image-$$.tar"
    podman save -o "$tmp_image" openclaw:local || \
        die "Failed to save image"
    
    # Load as user
    sudo -u "$SYSTEM_USER" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        podman load -i "$tmp_image" || \
        die "Failed to load image into user store"
    
    rm -f "$tmp_image"
    
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
    
    # Create directories as user
    info "Creating directory structure..."
    sudo -u "$SYSTEM_USER" mkdir -p "$CONFIG_DIR/canvas"
    sudo -u "$SYSTEM_USER" mkdir -p "$CONFIG_DIR/cron"
    sudo -u "$SYSTEM_USER" mkdir -p "$WORKSPACE_DIR"
    sudo -u "$SYSTEM_USER" chmod 700 "$CONFIG_DIR"
    sudo -u "$SYSTEM_USER" chmod 700 "$WORKSPACE_DIR"
    
    # Write .env file
    info "Writing .env file..."
    local env_file="$CONFIG_DIR/.env"
    {
        echo "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN"
        [[ -n "${ANTHROPIC_API_KEY:-}" ]] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
        [[ -n "${OPENAI_API_KEY:-}" ]] && echo "OPENAI_API_KEY=$OPENAI_API_KEY"
        [[ -n "${OPENROUTER_API_KEY:-}" ]] && echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
        [[ -n "${GEMINI_API_KEY:-}" ]] && echo "GEMINI_API_KEY=$GEMINI_API_KEY"
    } | sudo -u "$SYSTEM_USER" tee "$env_file" > /dev/null
    
    sudo -u "$SYSTEM_USER" chmod 600 "$env_file"
    
    # Write openclaw.json
    info "Writing openclaw.json..."
    local config_file="$CONFIG_DIR/openclaw.json"
    
    if [[ "$SECURITY_TIER" == "standard" ]]; then
        # Standard tier - loopback binding
        cat > "$config_file" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "loopback",
    "auth": {
      "mode": "token"
    }
  }
}
EOF
    elif [[ "$SECURITY_TIER" == "hardened" ]]; then
        # Hardened tier - lan binding + restrictions
        cat > "$config_file" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "lan",
    "auth": {
      "mode": "token"
    }
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
        cat > "$config_file" << EOF
{
  "gateway": {
    "mode": "local",
    "port": $GATEWAY_PORT,
    "bind": "lan",
    "auth": {
      "mode": "token"
    }
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
    
    chown "$SYSTEM_USER:$SYSTEM_USER" "$config_file"
    chmod 600 "$config_file"
    
    info "Layer 6 complete"
}

# ============================================================================
# LAYER 3: CONTAINER HARDENING
# ============================================================================
build_podman_args() {
    PODMAN_ARGS=()
    
    # Base args for all tiers
    PODMAN_ARGS+=(--name openclaw)
    PODMAN_ARGS+=(--init)
    PODMAN_ARGS+=(--userns=keep-id)
    PODMAN_ARGS+=(--user "$USER_UID:$USER_GID")
    
    # Environment
    PODMAN_ARGS+=(-e HOME=/home/node)
    PODMAN_ARGS+=(-e TERM=xterm-256color)
    PODMAN_ARGS+=(-e "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN")
    PODMAN_ARGS+=(--env-file "$CONFIG_DIR/.env")
    
    # Port publishing (localhost only)
    PODMAN_ARGS+=(-p "127.0.0.1:$GATEWAY_PORT:$GATEWAY_PORT")
    PODMAN_ARGS+=(-p "127.0.0.1:$BRIDGE_PORT:$BRIDGE_PORT")
    
    # Tier-specific hardening
    if [[ "$SECURITY_TIER" == "standard" ]]; then
        # Standard: RW mounts
        PODMAN_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:rw")
        PODMAN_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="loopback"
    else
        # Hardened/Paranoid: Enhanced security
        PODMAN_ARGS+=(--read-only)
        # shellcheck disable=SC2054
        PODMAN_ARGS+=(--tmpfs /tmp:size=256m,noexec,nosuid,nodev)
        # shellcheck disable=SC2054
        PODMAN_ARGS+=(--tmpfs /home/node/.cache:size=128m,noexec,nosuid,nodev)
        PODMAN_ARGS+=(--cap-drop=ALL)
        PODMAN_ARGS+=(--security-opt=no-new-privileges:true)
        PODMAN_ARGS+=(--memory="$MEMORY_LIMIT")
        PODMAN_ARGS+=(--memory-swap="$MEMORY_LIMIT")
        PODMAN_ARGS+=(--cpus="$CPU_LIMIT")
        PODMAN_ARGS+=(--pids-limit="$PID_LIMIT")
        PODMAN_ARGS+=(--network=slirp4netns:allow_host_loopback=false)
        
        # RO config, RW workspace
        PODMAN_ARGS+=(-v "$CONFIG_DIR:/home/node/.openclaw:ro")
        PODMAN_ARGS+=(-v "$WORKSPACE_DIR:/home/node/.openclaw/workspace:rw")
        BIND_MODE="lan"
    fi
    
    # Image and command
    PODMAN_ARGS+=(openclaw:local)
    PODMAN_ARGS+=(node dist/index.js gateway --bind "$BIND_MODE" --port "$GATEWAY_PORT")
}

layer3_container_hardening() {
    section "Layer 3: Container Hardening"
    
    build_podman_args
    info "Container configured with $SECURITY_TIER tier security"
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
if ss -tunp 2>/dev/null | grep -q "uid:$USER_UID" | grep -v "127.0.0.1\|::1"; then
    logger -t openclaw-alert -p auth.crit "Suspicious network connection detected from UID $USER_UID"
fi
NETCHECK_SCRIPT
    
    # Replace placeholder
    sed -i "s/USER_UID_PLACEHOLDER/$USER_UID/" /usr/local/bin/openclaw-netcheck.sh
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
    section "Layer 7: Systemd Quadlet & Launch"
    
    # Always create launch script
    info "Creating launch script..."
    local launch_script="$INSTALL_DIR/launch-openclaw.sh"
    
    cat > "$launch_script" << 'LAUNCH_EOF'
#!/bin/bash
# OpenClaw Launch Script
# Generated by SecureClaw installer

set -euo pipefail

LAUNCH_EOF
    
    # Add podman run command
    echo "podman run -d \\" >> "$launch_script"
    for arg in "${PODMAN_ARGS[@]}"; do
        # Escape and quote arguments properly
        echo "  \"$arg\" \\" >> "$launch_script"
    done
    # Remove trailing backslash from last line
    sed -i '$ s/ \\$//' "$launch_script"
    
    chown "$SYSTEM_USER:$SYSTEM_USER" "$launch_script"
    chmod +x "$launch_script"
    
    # Create Quadlet unit if enabled
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
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
Environment=OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
EnvironmentFile=$CONFIG_DIR/.env

# Ports (localhost only)
PublishPort=127.0.0.1:$GATEWAY_PORT:$GATEWAY_PORT
PublishPort=127.0.0.1:$BRIDGE_PORT:$BRIDGE_PORT

# Volumes
EOF
        
        if [[ "$SECURITY_TIER" == "standard" ]]; then
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
CPUQuota=$((${CPU_LIMIT%.*}00))%
PidsLimit=$PID_LIMIT

# Network
Network=slirp4netns:allow_host_loopback=false
EOF
        fi
        
        # Add command
        cat >> "$quadlet_file" << EOF

# Command
Exec=node dist/index.js gateway --bind $BIND_MODE --port $GATEWAY_PORT

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF
        
        chown "$SYSTEM_USER:$SYSTEM_USER" "$quadlet_file"
        
        # Reload and enable
        info "Enabling and starting systemd service..."
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user enable openclaw.service >/dev/null 2>&1
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user start openclaw.service || \
            die "Failed to start service"
    else
        # Launch directly
        info "Starting container..."
        cd "$USER_HOME"
        sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" bash "$launch_script" || \
            die "Failed to start container"
    fi
    
    # Wait and verify
    sleep 3
    if sudo -u "$SYSTEM_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" podman ps | grep -q openclaw; then
        info "Container started successfully"
    else
        warn "Container may not have started properly"
    fi
    
    info "Layer 7 complete"
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
    echo -e "${BOLD}Gateway Token:${RESET}"
    echo -e "  $GATEWAY_TOKEN"
    echo
    echo -e "${BOLD}SSH Tunnel Command:${RESET}"
    echo -e "  ${CYAN}ssh -L $GATEWAY_PORT:127.0.0.1:$GATEWAY_PORT user@your-vps-ip${RESET}"
    echo
    echo -e "${BOLD}View Logs:${RESET}"
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
        echo -e "  sudo -u $SYSTEM_USER systemctl --user status openclaw"
        echo -e "  sudo -u $SYSTEM_USER journalctl --user -u openclaw -f"
    else
        echo -e "  sudo -u $SYSTEM_USER podman logs -f openclaw"
    fi
    echo
    echo -e "${BOLD}Stop/Restart:${RESET}"
    if [[ $ENABLE_SYSTEMD -eq 1 ]]; then
        echo -e "  sudo -u $SYSTEM_USER systemctl --user stop openclaw"
        echo -e "  sudo -u $SYSTEM_USER systemctl --user start openclaw"
    else
        echo -e "  sudo -u $SYSTEM_USER podman stop openclaw"
        echo -e "  sudo -u $SYSTEM_USER podman start openclaw"
    fi
    echo
    echo -e "${BOLD}Configuration:${RESET}"
    echo -e "  Config: $CONFIG_DIR/openclaw.json"
    echo -e "  API Keys: $CONFIG_DIR/.env"
    echo -e "  Workspace: $WORKSPACE_DIR"
    echo
    echo -e "${BOLD}Active Security Layers (${SECURITY_TIER} tier):${RESET}"
    echo -e "  ✅ Rootless Podman"
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
    
    echo
    echo -e "${YELLOW}⚠  Security Reminders:${RESET}"
    echo -e "  • IP-restrict API keys at provider dashboards"
    echo -e "  • Set spending limits on all LLM API accounts"
    echo -e "  • Use dedicated API keys (don't reuse from other projects)"
    echo -e "  • Monitor usage regularly for anomalies"
    
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
# MAIN
# ============================================================================
main() {
    show_banner
    preflight_checks
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --openclaw-repo)
                ARG_OPENCLAW_REPO="$2"
                shift 2
                ;;
            *)
                warn "Unknown argument: $1"
                shift
                ;;
        esac
    done
    
    # Interactive prompts
    prompt_security_level
    prompt_install_dir
    prompt_username
    prompt_ports
    prompt_token
    prompt_api_keys
    prompt_systemd
    prompt_resource_limits
    
    # Review and confirm
    show_summary
    
    # Execute installation layers
    layer1_system_setup
    layer2_container_image
    layer6_configuration
    layer3_container_hardening
    layer4_firewall
    layer5_monitoring
    layer7_launch
    
    # Show final summary
    show_final_summary
}

# Run main function
main "$@"
