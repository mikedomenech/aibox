# CLI Command Contracts: aibox

**Feature**: 003-vm-isolation
**Tool**: aibox — General-purpose VM isolation for AI coding agents

**Feature**: 003-vm-isolation

## Command: `aibox setup`

**Purpose**: Create and provision a new VM with development tools

**Usage**: `aibox setup [--config <path>] [--runtime <orbstack|lima>]`

**Options**:
- `--config <path>` — Path to vm-config.yaml (default: `./vm-config.yaml`)
- `--runtime <orbstack|lima>` — VM runtime to use (default: auto-detect)

**Behavior**:
1. Validates config file exists and is valid
2. Checks that the chosen runtime is installed
3. Creates a new VM instance (Ubuntu 22.04 ARM64)
4. Mounts project directory as `/workspace`
5. Runs provisioning script (installs Node.js 18+, npm, git, Claude Code CLI)
6. Reports success with VM name and status

**Exit codes**: 0 success, 1 config error, 2 runtime not found, 3 provisioning failed

**Example output**:
```
Setting up VM 'noonstack-dev'...
  Runtime: orbstack
  Project: /Users/dev/noonstack → /workspace
  Provisioning: Node.js 22.x, npm, git, claude-code
  ✓ VM ready (setup took 2m 34s)
```

---

## Command: `aibox start`

**Purpose**: Start an existing VM and apply network/resource rules

**Usage**: `aibox start [--config <path>]`

**Behavior**:
1. Starts the VM instance
2. Mounts project directory
3. Applies network rules (iptables allowlist)
4. Applies resource limits
5. Passes configured environment variables
6. Reports ready status

**Exit codes**: 0 success, 1 VM not found (run setup first), 2 already running, 3 start failed

**Performance**: Must be ready within 30 seconds (SC-001)

---

## Command: `aibox stop`

**Purpose**: Gracefully stop the running VM

**Usage**: `aibox stop [--force]`

**Options**:
- `--force` — Force stop without graceful shutdown

**Behavior**:
1. Sends shutdown signal to VM
2. Waits for graceful shutdown (30s timeout)
3. Force-kills if timeout exceeded
4. Reports stopped status

**Exit codes**: 0 success, 1 VM not running

---

## Command: `aibox teardown`

**Purpose**: Destroy the VM and free all resources

**Usage**: `aibox teardown [--yes]`

**Options**:
- `--yes` — Skip confirmation prompt

**Behavior**:
1. Prompts for confirmation (unless --yes)
2. Stops VM if running
3. Deletes VM instance
4. Removes VM-local data (node_modules, caches)
5. Preserves project files (they're on host)

**Exit codes**: 0 success, 1 VM not found, 2 user cancelled

---

## Command: `aibox status`

**Purpose**: Show current VM status and configuration

**Usage**: `aibox status [--json]`

**Options**:
- `--json` — Output as JSON

**Output**:
```
VM: noonstack-dev
  Status: running
  Runtime: orbstack
  Uptime: 2h 15m
  Project: /Users/dev/noonstack → /workspace
  Resources:
    CPU: 4 cores (limit: 4)
    Memory: 1.2 GB / 4 GB
    Disk: 3.8 GB / 20 GB
  Network:
    Allowed: registry.npmjs.org:443, github.com:443, api.anthropic.com:443
    Blocked: all other outbound
  Environment: ANTHROPIC_API_KEY (set), NODE_ENV=development
```

**Exit codes**: 0 success, 1 VM not found

---

## Command: `aibox exec`

**Purpose**: Execute a command inside the running VM

**Usage**: `aibox exec <command> [args...]`

**Behavior**:
1. Validates VM is running
2. Executes command in VM as non-root user
3. Working directory is /workspace
4. Streams stdout/stderr to host terminal
5. Returns command's exit code

**Example**: `aibox exec claude "fix the login bug"`

**Exit codes**: Passes through the executed command's exit code, or 1 if VM not running

---

## Command: `aibox init`

**Purpose**: Generate a default vm-config.yaml in the current directory

**Usage**: `aibox init [--force]`

**Options**:
- `--force` — Overwrite existing config

**Behavior**:
1. Creates `vm-config.yaml` with sensible defaults
2. Creates `.vm-env.example` template for environment variables
3. Adds `.vm-env` to `.gitignore` if not present

**Exit codes**: 0 success, 1 config already exists (without --force)
