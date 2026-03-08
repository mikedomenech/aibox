# Research: VM Isolation for Claude

**Feature**: 003-vm-isolation
**Date**: 2026-03-08

## Decision 1: VM Runtime

**Decision**: OrbStack (primary), Lima (fallback)

**Rationale**: OrbStack provides the fastest startup (~2s), native VirtioFS file sharing with near-native performance, built-in resource limits, and excellent Apple Silicon support. Lima is the fallback as it's open-source, well-maintained, and supports the same VirtioFS sharing via Apple's Virtualization.framework.

**Alternatives Considered**:

| Runtime | Startup | File Sharing | Network Isolation | Resource Limits | License |
|---------|---------|-------------|-------------------|-----------------|---------|
| OrbStack | ~2s | VirtioFS (fast) | iptables in VM | CPU, memory, disk | Freemium |
| Lima | ~10-15s | VirtioFS or reverse-sshfs | iptables in VM | CPU, memory via YAML | Open source (Apache 2.0) |
| Tart | ~5s | VirtioFS | Limited | CPU, memory | Open source |
| UTM | ~10s | Shared folders (slow) | Full VM networking | CPU, memory | Open source |
| Docker | ~1s | bind mounts | Network policies | cgroups | Freemium |

**Why not Docker**: Containers share the host kernel and don't provide true isolation. A determined process can escape container boundaries. VMs provide hardware-level isolation via Apple's Hypervisor.framework.

**Why not UTM**: Slower file sharing, heavier weight, designed for full OS VMs with GUIs rather than lightweight dev environments.

## Decision 2: File Sharing Strategy

**Decision**: VirtioFS mount of project directory only

**Rationale**: VirtioFS (via Apple Virtualization.framework) provides near-native filesystem performance. Mounting only the project directory enforces FR-001 (filesystem isolation) at the hypervisor level — the VM physically cannot see other host directories.

**Implementation**:
- OrbStack: `orb run --mount /path/to/project:/workspace`
- Lima: `mounts` config in YAML with `writable: true`

**node_modules handling**: node_modules stays inside the VM. The project directory mount shares source code, but `npm install` runs inside the VM and installs to the VM's filesystem. This avoids cross-platform binary issues and keeps large dependency trees out of the mount.

## Decision 3: Network Isolation Approach

**Decision**: Default-deny with allowlist via iptables inside the VM

**Rationale**: The VM gets a NAT network interface by default (both OrbStack and Lima). We apply iptables rules inside the VM to restrict outbound traffic to only allowed destinations. This is simpler and more portable than host-side firewall rules.

**Default allowlist**:
- `registry.npmjs.org:443` — npm packages
- `github.com:443` — git operations
- `api.anthropic.com:443` — Claude API
- DNS (`53/udp`) — name resolution

**Adding custom rules**: Developer edits `vm-config.yaml` to add hosts/ports. The start script applies iptables rules from the config.

## Decision 4: Authentication Forwarding

**Decision**: Pass ANTHROPIC_API_KEY via environment variable at VM start

**Rationale**: Claude Code authenticates via API key. Passing it as an env var at start time (not baked into the VM image) means:
- No secrets stored in VM filesystem
- Key is only in memory during the session
- Different keys can be used per session

**Implementation**: `aibox-vm start` reads from host env or a `.vm-env` file (gitignored) and passes to the VM process.

## Decision 5: Testing Framework

**Decision**: bats-core (Bash Automated Testing System)

**Rationale**: The project is shell scripts, so bats-core is the natural testing framework. It supports setup/teardown, assertions, and TAP output. Tests will verify:
- VM lifecycle (setup, start, stop, teardown)
- Filesystem isolation (can't read host files)
- Network isolation (can't reach blocked hosts)
- Resource limits (memory/CPU caps enforced)

**Alternative**: ShellSpec was considered but bats-core has wider adoption and simpler syntax.

## Decision 6: Configuration Format

**Decision**: YAML configuration file (`vm-config.yaml`)

**Rationale**: YAML is human-readable and commonly used for infrastructure configuration. It supports comments (unlike JSON) and is familiar to developers. The config schema covers:
- Project path
- Resource limits (CPU cores, memory MB, disk GB)
- Network allowlist (host:port pairs)
- Environment variables to pass through
- VM runtime preference (orbstack/lima)
