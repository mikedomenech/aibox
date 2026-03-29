# aibox

VM isolation for AI coding agents on macOS. Run Claude, Cursor, or other AI agents inside a sandboxed Linux VM with network allowlisting and filesystem isolation.

## Why

AI coding agents need broad system access to be useful — shell, filesystem, network. But giving an agent unrestricted access to your host machine is risky. aibox creates an isolated VM where agents can work freely without accessing your SSH keys, credentials, or host filesystem.

## Quick Start

```bash
# Install (requires OrbStack or Lima)
git clone https://github.com/mikedomenech/aibox.git
cd aibox && ./install.sh

# Authenticate (one-time, on the host)
claude login

# In your project directory
aibox init          # creates aibox.yaml
aibox setup         # creates and provisions the VM
aibox start         # starts VM and syncs credentials
aibox exec claude   # run Claude Code inside the VM
```

`aibox start` automatically syncs your OAuth credentials from the macOS Keychain into the VM so Claude Code works without any API key setup.

## How It Works

aibox creates a lightweight Linux VM (via OrbStack or Lima), mounts only your project directory, provisions the tools you need, and applies iptables-based network rules so the agent can only reach allowlisted hosts.

```
┌─────────────────────────────────────────┐
│  Host (macOS)                           │
│                                         │
│  ~/.ssh/  ✗ blocked                     │
│  ~/Documents/  ✗ blocked                │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │  aibox VM (Linux)                 │  │
│  │                                   │  │
│  │  /workspace  ← project mounted    │  │
│  │                                   │  │
│  │  Network: allowlist only          │  │
│  │   ✓ github.com                    │  │
│  │   ✓ registry.npmjs.org            │  │
│  │   ✓ api.anthropic.com             │  │
│  │   ✗ everything else               │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Configuration

Drop an `aibox.yaml` in your project root (or run `aibox init`):

```yaml
resources:
  cpu: 4
  memory: 4096
  disk: 20

network:
  allow_defaults: true    # npm, pypi, github, anthropic API, etc.
  # allow:
  #   - host: "my-api.company.com"
  #     port: 443

env:
  pass_through:
    - ANTHROPIC_API_KEY   # optional — OAuth is synced automatically
  static:
    TERM: "xterm-256color"

provision:
  languages:
    node: "22"
    # python: "3.12"
    # go: "1.22"
  agents:
    - claude
```

### Network Defaults

When `allow_defaults: true`, these hosts are reachable:

| Host | Purpose |
|------|---------|
| registry.npmjs.org | npm packages |
| pypi.org, files.pythonhosted.org | Python packages |
| github.com, api.github.com | Git + GitHub API |
| api.anthropic.com | Claude API |
| deb.nodesource.com | Node.js install |
| go.dev | Go install |
| sh.rustup.rs, static.rust-lang.org | Rust install |

Everything else is blocked by default via iptables OUTPUT chain rules.

### Host Services

Expose host ports to the VM (e.g., local databases):

```yaml
network:
  host_services:
    - port: 5432
      description: "PostgreSQL"
    - port: 3000
      description: "Dev server"
```

## Commands

| Command | Description |
|---------|-------------|
| `aibox init` | Generate `aibox.yaml` in current directory |
| `aibox setup` | Create and provision a new VM |
| `aibox start` | Start an existing VM |
| `aibox stop` | Stop the running VM |
| `aibox status` | Show VM status and configuration |
| `aibox exec <cmd>` | Execute a command inside the VM |
| `aibox teardown` | Destroy the VM and free resources |

### Examples

```bash
aibox exec claude "fix the failing tests"
aibox exec bash                    # interactive shell
aibox exec npm test                # run tests in sandbox
aibox status                       # check VM state
aibox stop && aibox teardown       # clean up
```

## Prerequisites

One of:
- [OrbStack](https://orbstack.dev/) (recommended) — `brew install orbstack`
- [Lima](https://lima-vm.io/) — `brew install lima`

## Authentication

Claude Code inside the VM can't open a browser or access the macOS Keychain, so OAuth login doesn't work directly. aibox handles this automatically:

1. Run `claude login` on the host (one-time)
2. `aibox start` extracts the OAuth token from the macOS Keychain and writes it to `~/.claude/.credentials.json`
3. Since `~/.claude` is bind-mounted into the VM, Claude Code picks up the credentials

If you prefer API keys, you can also set `ANTHROPIC_API_KEY` via environment pass-through or `.aibox-env`.

## Security Model

**What's isolated:**
- Host filesystem — only the project directory is mounted
- Network — default-deny with allowlist
- Environment — only explicitly listed env vars are passed through

**What's shared:**
- CPU/memory within configured limits
- DNS resolution (required for allowlisted hosts)
- Project directory (read-write mount)

## Known Limitations

- macOS only (Apple Silicon and Intel)
- OrbStack's default filesystem passthrough must be disabled for full isolation — aibox handles this during `setup`
- Network rules use iptables inside the VM; resolved IPs are cached at setup time

## License

MIT
