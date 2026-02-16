<div align="center">

# 🛡️ SecureClaw

### *Run OpenClaw in a fortress. Maximum isolation. Zero trust.*

<br>

```
   ____                            ____  _
  / ___|  ___  ___ _   _ _ __ ___ / ___|| | __ ___      __
  \___ \ / _ \/ __| | | | '__/ _ \ |    | |/ _` \ \ /\ / /
   ___) |  __/ (__| |_| | | |  __/ |___ | | (_| |\ V  V /
  |____/ \___|\___|\__,_|_|  \___|\_____||_|\__,_| \_/\_/
```

<br>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](install.sh)
[![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)](#-requirements)
[![Runtime](https://img.shields.io/badge/Runtime-Podman%20%7C%20Docker-blue.svg)](#-container-runtime-options)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Developed by [Granus Labs](https://granuslabs.com)**

---

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-security-tiers">Security Tiers</a> •
  <a href="#%EF%B8%8F-why-you-need-secureclaw">Why Secure?</a> •
  <a href="#-what-the-installer-does">How It Works</a> •
  <a href="#-post-install">Post-Install</a> •
  <a href="#-contributing">Contributing</a>
</p>

</div>

---

## 📖 What is SecureClaw?

**SecureClaw** is an interactive hardened installer that deploys [OpenClaw](https://github.com/openclaw/openclaw) inside a **hardened container (rootless by default)** with **7 layers of defense-in-depth security**.

It supports both **Podman** (rootless) and **Docker** (rootless or standard+hardened), giving you full control over your container runtime while maintaining maximum security.

Designed for VPS deployments where you assume **complete hostile takeover** of the container, SecureClaw implements multiple security boundaries to minimize blast radius and protect your host system, API keys, and data.

---

## 🚀 Quick Start

### Install (recommended defaults)

```bash
git clone https://github.com/InverseAltruism/SecureClaw.git
cd SecureClaw
sudo bash install.sh
```

- Choose **Podman (rootless)** for maximum isolation.
- Choose **Hardened** security tier for production by default.
- Use **↑/↓ + Enter** for guided runtime/tier menus, or press the number key directly.
- Press **Enter** to accept secure defaults unless you have a reason to customize.
- By default, SecureClaw pins OpenClaw to a reviewed commit. You can override with `--openclaw-ref <ref>`.

### Full Uninstall / Revert

```bash
cd SecureClaw
sudo bash uninstall.sh
```

The uninstaller removes SecureClaw-generated services, containers/images, install directories, paranoid-tier host artifacts, and (when it was created by SecureClaw) the dedicated system user plus namespace mappings. It can also purge runtime packages that were installed by SecureClaw.

---

## ⚠️ Why You Need SecureClaw

Running OpenClaw (or any AI coding agent) without proper isolation is **dangerous**. Here's what can go wrong:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ❌  INSECURE DEPLOYMENT                          │
│                                                                     │
│   ┌───────────┐     Full Access      ┌──────────────────────┐      │
│   │  OpenClaw │ ──────────────────── │  Your Host System    │      │
│   │  (AI Agent)│                      │  • Root filesystem   │      │
│   │           │     No Limits         │  • All network       │      │
│   │           │ ──────────────────── │  • SSH keys          │      │
│   │           │                      │  • All API keys      │      │
│   │           │     Unrestricted     │  • Other services    │      │
│   │           │ ──────────────────── │  • Cloud metadata    │      │
│   └───────────┘                      └──────────────────────┘      │
│                                                                     │
│   🔓 Container escape = full host compromise                        │
│   🔓 Malicious code runs with your privileges                       │
│   🔓 API keys exposed in environment variables                      │
│   🔓 Network access to cloud metadata (169.254.x.x)                │
│   🔓 Lateral movement to other services on your network             │
│   🔓 No resource limits = denial of service                         │
└─────────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ✅  SECURECLAW DEPLOYMENT                        │
│                                                                     │
│   ┌───────────┐                      ┌──────────────────────┐      │
│   │  OpenClaw │ ─── 7 Security ───── │  Protected Host      │      │
│   │  (Isolated)│     Layers           │                      │      │
│   │           │                      │  ✅ Read-only root   │      │
│   │  Rootless │ ─── Egress ───────── │  ✅ Egress firewall  │      │
│   │  Container│     Firewall         │  ✅ Audit logging    │      │
│   │           │                      │  ✅ No capabilities  │      │
│   │  No caps  │ ─── Resource ─────── │  ✅ Resource limits  │      │
│   │  No privs │     Limits           │  ✅ User namespace   │      │
│   └───────────┘                      └──────────────────────┘      │
│                                                                     │
│   🔒 Container runs as unprivileged user (no root daemon*)          │
│   🔒 Read-only filesystem prevents persistence                      │
│   🔒 Egress firewall blocks cloud metadata & lateral movement       │
│   🔒 All capabilities dropped + no-new-privileges                   │
│   🔒 Resource limits prevent denial of service                      │
│   🔒 Audit monitoring catches suspicious behavior                   │
│                                                                     │
│   * Podman and Docker rootless mode — no root daemon at all         │
└─────────────────────────────────────────────────────────────────────┘
```

> **Bottom line:** Without SecureClaw, a single prompt injection or malicious code execution
> gives an attacker full access to your system, API keys, and network. With SecureClaw,
> even a complete container compromise is contained within multiple security boundaries.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔒 **Rootless-First Runtime** | Podman/Docker rootless supported; hardened fallback for standard Docker |
| 🐳 **Runtime Choice** | Choose Podman, Docker rootless, or Docker standard+hardened |
| 📦 **Read-only Filesystem** | Prevents persistence of malicious modifications |
| 🚫 **All Capabilities Dropped** | `cap-drop=ALL` — minimal privileges |
| 🛡️ **No New Privileges** | `no-new-privileges` — cannot escalate access |
| 🌐 **Egress Firewall** | nftables rules block cloud metadata & RFC1918 |
| 📊 **Audit Monitoring** | auditd + cron network anomaly detection |
| 🏗️ **Agent Sandboxing** | Per-agent isolation with double containerization |
| ⚡ **3 Security Tiers** | Standard → Hardened → Paranoid |
| 🔑 **Auto-generated Tokens** | Cryptographically secure 256-bit gateway tokens |
| 🔄 **Systemd Integration** | Quadlet (Podman) or systemd service (Docker) auto-start |
| 🖥️ **System Detection** | Auto-detects OS, architecture, RAM, CPU cores |

---

## 🐳 Container Runtime Options

SecureClaw lets you choose your preferred container runtime during installation:

| Runtime | Security Level | Root Daemon? | Best For |
|---------|---------------|-------------|----------|
| **Podman (rootless)** | 🟢 Highest | No | Maximum security, VPS deployments |
| **Docker (rootless)** | 🟢 High | No | Docker familiarity + strong security |
| **Docker (standard+hardened)** | 🟡 Good | Yes | Compatibility, existing Docker setups |

### Why Rootless Matters

```
  Root Daemon (Traditional Docker)         Rootless (Podman / Docker Rootless)
  ─────────────────────────────────       ──────────────────────────────────────
  
  ┌─────────┐                             ┌─────────┐
  │ docker  │  Talks to root daemon       │ podman/ │  No daemon at all
  │   CLI   │ ──────────┐                 │ docker  │ ─── Direct process
  └─────────┘            │                 └─────────┘
                         ▼                  
              ┌──────────────────┐             User Namespace
              │  dockerd (ROOT)  │         ┌──────────────────┐
              │                  │         │  Container runs   │
              │  Full host       │         │  as UID 100000+   │
              │  access possible │         │  No host access   │
              └──────────────────┘         └──────────────────┘
  
  ⚠ Exploit in daemon = root on host     ✅ Exploit = unprivileged user
  ⚠ Docker socket = root shell           ✅ No socket to exploit
```

> **Recommendation:** Use **Podman (rootless)** for maximum security. Use **Docker (rootless)** if you prefer Docker's tooling. Only use Docker standard if rootless isn't an option on your system.

---

## 🔐 Security Tiers

Choose your security posture during installation:

| Layer | Standard | Hardened | Paranoid |
|-------|:--------:|:--------:|:--------:|
| Container user isolation (rootless on supported runtimes) | ✅ | ✅ | ✅ |
| Gateway token auth | ✅ | ✅ | ✅ |
| Host port binding to `127.0.0.1` | ✅ | ✅ | ✅ |
| Read-only root filesystem | ❌ | ✅ | ✅ |
| All capabilities dropped | ❌ | ✅ | ✅ |
| No new privileges | ❌ | ✅ | ✅ |
| Resource limits (CPU/RAM/PIDs) | ❌ | ✅ | ✅ |
| Workspace-only file access | ❌ | ✅ | ✅ |
| Network isolation | ❌ | ✅ | ✅ |
| **Host egress firewall (nftables)** | ❌ | ❌ | ✅ |
| **Audit logging (auditd + cron)** | ❌ | ❌ | ✅ |
| **Agent-level sandboxing** | ❌ | ❌ | ✅ |

> 💡 **Recommendation:** Start with **Hardened** (default) for production deployments. Use **Paranoid** for maximum security on untrusted networks.

---

## 🧭 Interactive Setup Flow

The installer will guide you through **9 interactive setup sections**:

<div align="center">

```
┌─────────────────────────────────────────────────────────────────┐
│                    INSTALLATION WORKFLOW                        │
├─────────────────────────────────────────────────────────────────┤
│  📊 Section 1/9  System Information                             │
│     └─ Auto-detected OS, RAM, CPUs                              │
│  🐳 Section 2/9  Container Runtime                              │
│     └─ Podman / Docker rootless / Docker                        │
│  🔐 Section 3/9  Security Level                                 │
│     └─ Standard / Hardened / Paranoid                           │
│  📁 Section 4/9  Installation Directory                         │
│     └─ Where to install OpenClaw                                │
│  👤 Section 5/9  System User                                    │
│     └─ Dedicated service user                                   │
│  🌐 Section 6/9  Gateway Port & Token                           │
│     └─ Network port + auth token                                │
│  🔑 Section 7/9  API Keys                                       │
│     └─ LLM provider keys (optional)                             │
│  ⚙️  Section 8/9  Systemd Auto-Start                            │
│     └─ Boot persistence                                         │
│  💾 Section 9/9  Resource Limits                                │
│     └─ CPU/RAM/PID constraints                                  │
└─────────────────────────────────────────────────────────────────┘
```

</div>

> **💡 Tip:** Default choices are optimized for security. Use **↑/↓ + Enter** in menu screens, or type the numeric choice directly.

---

## 📋 Requirements

| Requirement | Details |
|------------|---------|
| **OS** | Debian 12+ or Ubuntu 22.04+ |
| **Privileges** | Root or sudo access (only during installation) |
| **Hardware** | VPS with 2GB+ RAM, 2+ CPU cores recommended |
| **Network** | Internet access for package installation and LLM API calls |
| **Runtime** | Podman or Docker (installed automatically if not present) |

---

## 🏗️ What the Installer Does

The installer implements **7 layers of defense-in-depth security**:

<details open>
<summary><b>🔧 Layer 1: System User & Dependencies</b></summary>

<br>

- ✅ Installs your chosen runtime (Podman or Docker) and required tools
- ✅ For Docker rootless: sets up `dockerd-rootless-setuptool.sh`
- ✅ Creates dedicated `openclaw` system user (no shell, no sudo)
- ✅ Configures subuid/subgid mappings for user namespace isolation
- ✅ Enables systemd linger for rootless container persistence

</details>

<details open>
<summary><b>📦 Layer 2: Container Image</b></summary>

<br>

- ✅ Uses local OpenClaw source or clones a pinned upstream OpenClaw ref
- ✅ Builds OpenClaw container image using official Dockerfile
- ✅ Builds image directly in the service user's rootless store
- ✅ Ensures proper XDG_RUNTIME_DIR setup

</details>

<details open>
<summary><b>🛡️ Layer 3: Container Hardening</b></summary>

<br>

Configures container with tier-appropriate security flags:

**All tiers:**
- 🔒 Rootless user namespace isolation
- 🔒 Localhost-only port binding
- 🔒 Init process (proper signal handling)

**Hardened/Paranoid:**
- 🔒 Read-only root filesystem
- 🔒 tmpfs for writable directories
- 🔒 All capabilities dropped (`cap-drop=ALL`)
- 🔒 Memory/CPU/PID limits
- 🔒 Network isolation

</details>

<details open>
<summary><b>🔥 Layer 4: Host Firewall</b> <i>(Paranoid only)</i></summary>

<br>

- ✅ Installs and configures nftables egress filtering
- ✅ Blocks cloud metadata endpoints (169.254.0.0/16)
- ✅ Blocks RFC1918 private networks (lateral movement prevention)
- ✅ Allows only DNS, HTTPS (443), and established connections

</details>

<details open>
<summary><b>📊 Layer 5: Monitoring</b> <i>(Paranoid only)</i></summary>

<br>

- ✅ Installs auditd and adds syscall monitoring rules
- ✅ Watches all process execution from openclaw UID
- ✅ Cron job checks for unauthorized network connections every minute

</details>

<details open>
<summary><b>⚙️ Layer 6: Configuration</b></summary>

<br>

- ✅ Generates `.env` file with gateway token and API keys (mode 600)
- ✅ Creates `openclaw.json` with tier-specific security settings
- ✅ Creates workspace directory structure with proper permissions

</details>

<details open>
<summary><b>🚀 Layer 7: Systemd & Launch</b></summary>

<br>

**Podman:**
- ✅ Creates systemd Quadlet unit for auto-start

**Docker rootless:**
- ✅ Creates user-level systemd service

**Docker standard:**
- ✅ Creates system-level systemd service

**All runtimes:**
- ✅ Generates `launch-openclaw.sh` helper script
- ✅ Starts the container and verifies successful launch

</details>

---

## 🎯 Threat Model

SecureClaw defends against common attack vectors:

| Attack Vector | Standard | Hardened | Paranoid | Mitigation |
|---------------|:--------:|:--------:|:--------:|------------|
| **Container escape** | 🟡 | 🟢 | 🟢🟢 | Rootless user namespace + capability drop |
| **API key theft** | 🟡 | 🟢 | 🟢🟢 | Memory limits + read-only config + egress filtering |
| **Lateral movement** | 🔴 | 🟡 | 🟢 | Network isolation + RFC1918 blocking |
| **Cloud metadata access** | 🔴 | 🔴 | 🟢 | Nftables egress rules |
| **Resource exhaustion** | 🔴 | 🟢 | 🟢 | CPU/memory/PID limits |
| **Privilege escalation** | 🟡 | 🟢 | 🟢 | no-new-privileges + capability drop |
| **Filesystem persistence** | 🔴 | 🟢 | 🟢 | Read-only root + tmpfs |
| **Unauthorized network** | 🔴 | 🔴 | 🟢 | Audit monitoring + cron checks |

> 🟢🟢 = Strongest · 🟢 = Strong · 🟡 = Moderate · 🔴 = Weak

---

## 📡 Post-Install

### 🌐 Access the Dashboard

SecureClaw binds to `127.0.0.1` only for security. Access it via SSH tunnel:

```bash
# From your local machine, create an SSH tunnel
ssh -L 18789:127.0.0.1:18789 user@your-vps-ip

# Then open in your browser
http://localhost:18789
```

> 🔑 **Important:** Your gateway token is stored in `$INSTALL_DIR/.env` with mode `600`. Save it securely - you'll need it to authenticate.

---

### 📋 View Logs

<details>
<summary><b>Podman</b></summary>

```bash
# With systemd
sudo -u openclaw systemctl --user status openclaw

# Direct logs
sudo -u openclaw podman logs -f openclaw
```
</details>

<details>
<summary><b>Docker (rootless)</b></summary>

```bash
# With systemd
sudo -u openclaw systemctl --user status openclaw

# Direct logs
sudo -u openclaw DOCKER_HOST=unix:///run/user/$(id -u openclaw)/docker.sock docker logs -f openclaw
```
</details>

<details>
<summary><b>Docker (standard)</b></summary>

```bash
# With systemd
systemctl status openclaw

# Direct logs
docker logs -f openclaw
```
</details>

---

### 🔄 Stop/Restart

<details>
<summary><b>Podman / Docker (rootless)</b></summary>

```bash
sudo -u openclaw systemctl --user stop openclaw
sudo -u openclaw systemctl --user start openclaw
```
</details>

<details>
<summary><b>Docker (standard)</b></summary>

```bash
systemctl stop openclaw
systemctl start openclaw
```
</details>

---

### 🔍 Paranoid Tier: Monitor Threats

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

1. 🔑 **IP-restrict your API keys** at provider dashboards (OpenAI, Anthropic, etc.)
2. 💰 **Set spending limits** on all LLM API accounts
3. 🔐 **Use dedicated API keys** — Don't reuse keys from other projects
4. 📊 **Monitor usage** via provider dashboards for anomalies
5. 🔄 **Keep OpenClaw updated** — Watch the [OpenClaw repo](https://github.com/openclaw/openclaw) for security patches
6. 📋 **Review logs regularly** (especially on paranoid tier)
7. 🏠 **Use SSH tunnels** — Never expose the gateway port to the internet

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Areas for improvement:**
- Additional Linux distro support (Fedora, Arch, Alpine)
- SELinux policy integration
- Automated security testing
- Documentation improvements
- Docker Compose support

---

## 📄 License

MIT License — see [LICENSE](LICENSE) file for details.

Copyright © 2025 SecureClaw Contributors

---

## 🙏 Credits

- **[OpenClaw](https://github.com/openclaw/openclaw)** — The AI coding agent we're securing
- **[Granus Labs](https://granuslabs.com)** — Development and maintenance of SecureClaw
- Built with 🛡️ by security-conscious developers who believe in defense-in-depth

---

<div align="center">

**⚠️ Remember:** SecureClaw reduces risk but cannot eliminate it. Always assume compromise and plan accordingly.

*"Security is a journey, not a destination."*

**[Granus Labs](https://granuslabs.com)** · [Report an Issue](https://github.com/InverseAltruism/SecureClaw/issues) · [Contributing](CONTRIBUTING.md)

</div>