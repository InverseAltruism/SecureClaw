# Contributing to SecureClaw

Thank you for your interest in contributing to SecureClaw! We welcome contributions from the community.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue using the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) with:

- A clear description of the problem
- Steps to reproduce the issue
- Your OS version and environment details
- Relevant log output or error messages
- Expected vs actual behavior

### Suggesting Features

Have an idea for a new feature? Open an issue using the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md) with:

- A clear description of the feature
- The problem it solves or use case it addresses
- Any potential implementation considerations
- Examples of how it would work

### Submitting Pull Requests

We love pull requests! Here's how to contribute code:

1. **Fork the repository** and create a new branch from `main`
2. **Make your changes** following our coding standards
3. **Test thoroughly** - ensure your changes work on Debian 12 and Ubuntu 22.04+
4. **Update documentation** if you're adding features or changing behavior
5. **Submit a pull request** with a clear description of your changes

#### Code Standards

- **Shell scripts** must pass [ShellCheck](https://www.shellcheck.net/) with no warnings
- Use consistent indentation (4 spaces)
- Include comments for complex logic
- Follow the existing code style
- Keep functions focused and modular

#### Testing Your Changes

Before submitting:

- Test on a clean Debian 12 or Ubuntu 22.04+ installation
- Verify all three security tiers work correctly
- Test with and without systemd Quadlet
- Ensure no regressions in existing functionality
- Check that all files are created with correct permissions

### Development Setup

To test your changes:

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/SecureClaw.git
cd SecureClaw

# Make your changes
vim install.sh

# Run ShellCheck
shellcheck install.sh

# Test in a VM or container
vagrant up  # or use your preferred testing method
```

## Code Review Process

1. All PRs require review before merging
2. Address review feedback promptly
3. Keep PRs focused on a single issue or feature
4. Maintainers will merge approved PRs

## Security Issues

**Do not open public issues for security vulnerabilities.**

If you discover a security issue, please email the maintainers privately. We'll work with you to address the issue before public disclosure.

## Areas for Contribution

We're especially interested in contributions in these areas:

- **Distribution support**: Add support for Fedora, Arch, Alpine, etc.
- **SELinux policies**: Integration with SELinux for enhanced security
- **Automated testing**: CI/CD pipeline, integration tests
- **Documentation**: Tutorials, troubleshooting guides, best practices
- **Monitoring**: Additional security monitoring tools and dashboards
- **Performance**: Optimization and resource tuning

## Community Guidelines

- Be respectful and constructive
- Follow the [Code of Conduct](https://www.contributor-covenant.org/version/2/0/code_of_conduct/)
- Help others learn and grow
- Focus on what's best for the project and community

## Questions?

If you have questions about contributing, feel free to:

- Open a discussion on GitHub
- Comment on relevant issues
- Reach out to maintainers

Thank you for helping make SecureClaw better! 🛡️
