# Quickstart: VM Isolation for Claude

**Feature**: 003-vm-isolation

## Prerequisites

- macOS on Apple Silicon (M1/M2/M3/M4)
- OrbStack installed (`brew install orbstack`) or Lima (`brew install lima`)
- Claude Code CLI API key (ANTHROPIC_API_KEY)

## Setup

### 1. Initialize Configuration

```bash
cd /path/to/your/project
aibox init
```

This creates `aibox.yaml` and `.aibox-env.example`.

### 2. Configure Environment

```bash
cp .aibox-env.example .aibox-env
# Edit .aibox-env and add your ANTHROPIC_API_KEY
```

### 3. Create the VM

```bash
aibox setup
```

Provisions a VM with Node.js, npm, git, and Claude Code CLI (~2-5 minutes first time).

### 4. Start the VM

```bash
aibox start
```

VM is ready in <30 seconds.

### 5. Run Claude Inside the VM

```bash
aibox exec claude "your task here"
```

Or get a shell:
```bash
aibox exec bash
```

## Testing the Isolation

### Filesystem Isolation (SC-003)

```bash
# Inside the VM — these should all fail:
aibox exec cat /host-home/.ssh/id_rsa        # Should fail
aibox exec ls /host-home/Documents            # Should fail
aibox exec cat /host-home/.zshrc              # Should fail

# This should work:
aibox exec ls /workspace                       # Project files visible
aibox exec touch /workspace/test-file.txt      # Can write to project
ls ./test-file.txt                                     # Visible on host
```

### Network Isolation (SC-004)

```bash
# Inside the VM — allowed traffic:
aibox exec curl -s https://registry.npmjs.org  # Should succeed
aibox exec curl -s https://api.anthropic.com   # Should succeed

# Blocked traffic:
aibox exec curl -s http://localhost:5432        # Should fail (unless allowed)
aibox exec curl -s https://evil.example.com    # Should fail
```

### Resource Limits (SC-006)

```bash
# Check VM resource usage:
aibox status

# Inside the VM — should be constrained:
aibox exec stress --vm 1 --vm-bytes 8G         # Should be killed at memory limit
```

### File Sync Latency (SC-002)

```bash
# Create file inside VM, check host within 5 seconds:
aibox exec touch /workspace/sync-test.txt
sleep 5
ls -la sync-test.txt  # Should exist

# Create file on host, check VM:
touch host-sync-test.txt
sleep 5
aibox exec ls /workspace/host-sync-test.txt  # Should exist
```

## Lifecycle Commands

```bash
aibox status     # Check VM state
aibox stop       # Graceful shutdown
aibox start      # Restart
aibox teardown   # Destroy VM completely
aibox setup      # Recreate from scratch
```

## Troubleshooting

- **VM won't start**: Check `aibox status`, ensure runtime is installed
- **npm install fails**: Check network rules in aibox.yaml, ensure `registry.npmjs.org:443` is allowed
- **Claude can't authenticate**: Verify ANTHROPIC_API_KEY is in `.aibox-env` or host environment
- **File changes not syncing**: VirtioFS should be instant; restart VM if stale
- **Out of disk space**: Increase `resources.disk` in config, run `aibox teardown && aibox setup`
