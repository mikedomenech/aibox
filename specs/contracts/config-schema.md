# Configuration Schema: aibox.yaml

**Feature**: 003-vm-isolation

## Schema

```yaml
# VM Isolation Configuration
# Place this file in your project root as aibox.yaml

# VM runtime preference
runtime: orbstack  # orbstack | lima (auto-detects if omitted)

# Project directory to mount into the VM
# Defaults to current directory if omitted
project_path: .

# Resource limits
resources:
  cpu: 4          # Number of CPU cores (default: 4)
  memory: 4096    # Memory in MB (default: 4096)
  disk: 20        # Disk size in GB (default: 20)

# Network rules (default-deny, allowlist only)
network:
  # Pre-configured defaults (can be disabled)
  allow_defaults: true  # Enables npm, github, anthropic API

  # Additional allowed destinations
  allow:
    - host: "registry.npmjs.org"
      port: 443
      description: "npm packages"
    - host: "github.com"
      port: 443
      description: "git operations"
    - host: "api.anthropic.com"
      port: 443
      description: "Claude API"
    # Add custom rules:
    # - host: "my-api.company.com"
    #   port: 443
    #   description: "Internal API"

  # Allow access to host services (mapped via VM gateway)
  host_services: []
    # - port: 5432
    #   description: "PostgreSQL"
    # - port: 3000
    #   description: "Auth service"

# Environment variables to pass into the VM
# Values are read from host environment at start time
env:
  pass_through:
    - ANTHROPIC_API_KEY    # Required for Claude Code
    - NODE_ENV

  # Static values (not from host env)
  static:
    TERM: "xterm-256color"
    LANG: "en_US.UTF-8"

# Environment file (alternative to pass_through)
# Reads key=value pairs from this file, gitignored
env_file: .aibox-env

# Provisioning — configure what tools to install in the VM
provision:
  # Language runtimes (install any combination)
  languages:
    node: "22"             # Node.js major version (omit to skip)
    # python: "3.12"       # Python version
    # go: "1.22"           # Go version
    # rust: "stable"       # Rust toolchain

  # AI agent CLIs to install
  agents:
    - claude               # Claude Code CLI
    # - cursor             # Cursor CLI
    # - aider              # Aider CLI

  # Additional apt packages
  extra_packages: []
    # - docker.io
    # - postgresql-client
    # - ripgrep
```

## Field Validation Rules

| Field | Type | Required | Default | Validation |
|-------|------|----------|---------|------------|
| `runtime` | string | no | auto | Must be `orbstack` or `lima` |
| `project_path` | string | no | `.` | Must be valid directory |
| `resources.cpu` | integer | no | 4 | 1-8 |
| `resources.memory` | integer | no | 4096 | 512-16384 |
| `resources.disk` | integer | no | 20 | 5-100 |
| `network.allow_defaults` | boolean | no | true | — |
| `network.allow[].host` | string | yes* | — | Valid hostname or IP |
| `network.allow[].port` | integer | yes* | — | 1-65535 |
| `network.host_services[].port` | integer | yes* | — | 1-65535 |
| `env.pass_through[]` | string | no | `[ANTHROPIC_API_KEY]` | Valid env var name |
| `env.static` | map | no | `{}` | Key=valid env var name |
| `env_file` | string | no | `.aibox-env` | Valid file path |
| `provision.languages.*` | string | no | — | Valid version string per language |
| `provision.agents[]` | string | no | `[claude]` | Supported agent name |
| `provision.extra_packages[]` | string | no | `[]` | Valid apt package name |

## Example: Minimal Config

```yaml
# Just mount current directory with defaults
resources:
  memory: 2048
env:
  pass_through:
    - ANTHROPIC_API_KEY
```

## Example: With Host Service Access

```yaml
resources:
  cpu: 4
  memory: 4096

network:
  host_services:
    - port: 5432
      description: "PostgreSQL"
    - port: 3000
      description: "Auth service"

env:
  pass_through:
    - ANTHROPIC_API_KEY
    - DATABASE_URL
```
