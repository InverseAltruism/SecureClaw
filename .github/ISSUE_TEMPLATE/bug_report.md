---
name: Bug Report
about: Report a bug or issue with SecureClaw
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

A clear and concise description of what the bug is.

## Steps to Reproduce

1. Run installer with '...'
2. Choose security tier '...'
3. See error '...'

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Environment

- **OS**: (e.g., Debian 12, Ubuntu 22.04)
- **Security Tier**: (standard/hardened/paranoid)
- **Installation Method**: (fresh install/upgrade/custom)
- **Podman Version**: (run `podman --version`)

## Logs

Please provide relevant logs:

```
# If using systemd:
sudo -u openclaw journalctl --user -u openclaw -n 50

# Or direct podman logs:
sudo -u openclaw podman logs openclaw
```

## Additional Context

Add any other context about the problem here (screenshots, configuration files, etc.).

## Checklist

- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have included all relevant environment information
- [ ] I have included log output showing the error
- [ ] I have tested on a clean installation (if possible)
