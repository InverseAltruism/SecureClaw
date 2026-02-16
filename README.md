<div align="center">

# 🛡️ SecureClaw

### *Run OpenClaw in a fortress. Maximum isolation. Zero trust.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](install.sh)
[![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)](#requirements)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

</div>

---

## What is SecureClaw?

**SecureClaw** is an interactive hardened installer that deploys [OpenClaw](https://github.com/openclaw/openclaw) inside a **rootless Podman container** with **7 layers of defense-in-depth security**. 

Designed for VPS deployments where you assume **complete hostile takeover** of the container, SecureClaw implements multiple security boundaries to minimize blast radius and protect your host system, API keys, and data.

Unlike traditional Docker deployments, SecureClaw provides a **zero-trust architecture** with graduated security tiers, egress filtering, audit logging, and complete isolation from the Docker daemon.

---

## ✨ Features

- 🔒 **Rootless Podman** — No root daemon, no Docker socket exposure
- 📦 **Read-only container filesystem** — Prevents persistence of malicious modifications
- 🚫 **All Linux capabilities dropped** (`cap-drop=ALL`) — Minimal privileges
- 🛡️ **Privilege escalation blocked** (`no-new-privileges`) — Cannot gain elevated access
- 🌐 **Egress firewall (nftables)** — Only LLM API traffic allowed, blocks cloud metadata & RFC1918
- 📊 **Audit monitoring** (auditd + cron network anomaly detection) — Real-time threat detection
- 🏗️ **OpenClaw internal sandbox** — Double containerization with per-agent isolation
- ⚡ **Interactive setup** with 3 security tiers: **Standard → Hardened → Paranoid**
- 🔑 **Auto-generated 256-bit gateway tokens** — Cryptographically secure authentication
- 🔄 **Optional systemd Quadlet** — Auto-start on boot with proper lifecycle management

---

## 🔐 Security Tiers

Choose your security posture during installation:

| Layer | Standard | Hardened | Paranoid |
|-------|----------|----------|----------|
| Rootless Podman | ✅ | ✅ | ✅ |
| Gateway token auth | ✅ | ✅ | ✅ |
| Localhost-only binding | ✅ | ✅ | ✅ |
| Read-only root filesystem | ❌ | ✅ | ✅ |
| All capabilities dropped | ❌ | ✅ | ✅ |
| No new privileges | ❌ | ✅ | ✅ |
| Resource limits (CPU/RAM/PIDs) | ❌ | ✅ | ✅ |
| Workspace-only file access | ❌ | ✅ | ✅ |
| Network isolation (slirp4netns) | ❌ | ✅ | ✅ |
| **Host egress firewall (nftables)** | ❌ | ❌ | ✅ |
| **Audit logging (auditd + cron)** | ❌ | ❌ | ✅ |
| **Agent-level sandboxing** | ❌ | ❌ | ✅ |

**Recommendation:** Start with **Hardened** (default) for production deployments. Use **Paranoid** for maximum security on untrusted networks.

---

## 🚀 Quick Start

```bash
git clone https://github.com/InverseAltruism/SecureClaw.git
cd SecureClaw
chmod +x install.sh
sudo bash install.sh
```

The installer will guide you through 7 interactive setup sections. Default choices are optimized for security.

---

## 📋 Requirements

- **OS:** Debian 12+ or Ubuntu 22.04+
- **Privileges:** Root or sudo access (only during installation)
- **Hardware:** VPS with 2GB+ RAM, 2+ CPU cores recommended
- **Network:** Internet access for package installation and LLM API calls

---

## 🏗️ What the Installer Does

The installer implements **7 layers of security**:

### **Layer 1: System User & Dependencies**
- Installs Podman, uidmap, slirp4netns (rootless requirements)
- Creates dedicated `openclaw` system user (no shell, no sudo)
- Configures subuid/subgid mappings for user namespace isolation
- Enables systemd linger for rootless container persistence

### **Layer 2: Container Image**
- Discovers or clones the OpenClaw repository
- Builds OpenClaw container image using official Dockerfile
- Transfers image to the openclaw user's rootless Podman storage
- Ensures proper XDG_RUNTIME_DIR setup for rootless operation

### **Layer 3: Container Hardening**
- Configures container with tier-appropriate security flags:
  - **All tiers:** Rootless userns, localhost-only port binding, init process
  - **Hardened/Paranoid:** Read-only root, tmpfs for writable dirs, capability drop, memory/CPU/PID limits, network isolation
- Mounts configuration as read-only (hardened+)
- Mounts workspace as read-write with size limits

### **Layer 4: Host Firewall** *(Paranoid only)*
- Installs and configures nftables egress filtering
- Blocks cloud metadata endpoints (169.254.0.0/16)
- Blocks RFC1918 private networks (lateral movement prevention)
- Allows only DNS, HTTPS (443), and established connections
- Logs all blocked traffic with `openclaw-blocked:` prefix

### **Layer 5: Monitoring** *(Paranoid only)*
- Installs auditd and adds syscall monitoring rules
- Watches all process execution from openclaw UID
- Cron job checks for unauthorized network connections every minute
- Logs anomalies to syslog with `openclaw-alert` tag

### **Layer 6: Configuration**
- Generates `.env` file with gateway token and API keys (mode 600)
- Creates `openclaw.json` with tier-specific security settings:
  - **Standard:** Loopback binding, basic auth
  - **Hardened:** LAN binding (container-internal), workspace restrictions, disabled elevated tools
  - **Paranoid:** All hardened settings + per-agent sandboxing with docker-in-docker isolation
- Creates workspace directory structure with proper permissions

### **Layer 7: Quadlet & Launch**
- Optionally creates systemd Quadlet unit for auto-start
- Generates `launch-openclaw.sh` helper script
- Starts the container and verifies successful launch
- Displays connection info and security checklist

---

## 🎯 Threat Model

SecureClaw defends against common attack vectors:

| Attack Vector | Standard | Hardened | Paranoid | Mitigation |
|---------------|----------|----------|----------|------------|
| **Container escape** | Partial | Strong | Strongest | Rootless user namespace + capability drop |
| **API key theft** | Moderate | Strong | Strongest | Memory limits + read-only config + egress filtering |
| **Lateral movement** | Weak | Moderate | Strong | Network isolation + RFC1918 blocking |
| **Cloud metadata access** | Weak | Weak | Strong | Nftables egress rules |
| **Resource exhaustion** | Weak | Strong | Strong | CPU/memory/PID limits |
| **Privilege escalation** | Moderate | Strong | Strong | no-new-privileges + capability drop |
| **Filesystem persistence** | Weak | Strong | Strong | Read-only root + tmpfs |
| **Unauthorized network** | Weak | Weak | Strong | Audit monitoring + cron checks |

---

## 📡 Post-Install

### Access the Dashboard

SecureClaw binds to `127.0.0.1` only. Access via SSH tunnel:

```bash
# From your local machine
ssh -L 18789:127.0.0.1:18789 user@your-vps-ip

# Then open in browser
http://localhost:18789
```

**Gateway Token:** Displayed in the installer output. Save it securely!

### View Logs

```bash
# Container logs (if using systemd)
sudo -u openclaw systemctl --user status openclaw

# Or direct Podman logs
sudo -u openclaw podman logs -f openclaw
```

### Stop/Restart

```bash
# With systemd
sudo -u openclaw systemctl --user stop openclaw
sudo -u openclaw systemctl --user start openclaw

# Without systemd
sudo -u openclaw podman stop openclaw
sudo -u openclaw podman start openclaw
```

### Paranoid Tier: Monitor Threats

```bash
# View blocked network attempts
sudo journalctl -t openclaw-alert -f

# View nftables logs
sudo journalctl -k | grep openclaw-blocked

# Audit logs
sudo ausearch -k openclaw_exec
```

---

## ⚙️ Configuration

SecureClaw generates two configuration files:

### `.env` (API Keys & Token)

Location: `$INSTALL_DIR/.env`

```bash
OPENCLAW_GATEWAY_TOKEN=your-256-bit-hex-token
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
# ... other API keys
```

**Security:** Mode 600, owned by openclaw user. Never commit to version control.

### `openclaw.json` (OpenClaw Settings)

Location: `$INSTALL_DIR/openclaw.json`

Configures OpenClaw behavior based on security tier:

- **Gateway settings:** Port, bind mode (loopback/lan), token authentication
- **Tool restrictions:** Workspace-only file access, disabled elevated tools (hardened+)
- **Sandbox settings:** Per-agent containerization, resource limits (paranoid)

**Tip:** You can manually edit this file and restart the container to adjust settings.

---

## 🔒 Security Best Practices

After installation:

1. **IP-restrict your API keys** at provider dashboards (OpenAI, Anthropic, etc.)
2. **Set spending limits** on all LLM API accounts
3. **Use dedicated API keys** — Don't reuse keys from other projects
4. **Monitor usage** via provider dashboards for anomalies
5. **Keep OpenClaw updated** — Watch the [OpenClaw repo](https://github.com/openclaw/openclaw) for security patches
6. **Review logs regularly** (especially on paranoid tier)

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Areas for improvement:**
- Additional Linux distro support (Fedora, Arch, Alpine)
- SELinux policy integration
- Automated security testing
- Documentation improvements

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

Copyright © 2025 SecureClaw Contributors

---

## 🙏 Credits

- **[OpenClaw](https://github.com/openclaw/openclaw)** — The amazing AI coding agent we're securing
- **SecureClaw** is a community-driven hardening wrapper, not an official OpenClaw project
- Built with ❤️ by security-conscious developers who believe in defense-in-depth

---

<div align="center">

**⚠️ Remember:** SecureClaw reduces risk but cannot eliminate it. Always assume compromise and plan accordingly.

*"Security is a journey, not a destination."*

</div>