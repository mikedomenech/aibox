#!/usr/bin/env bash
# setup.sh — Create and provision a new VM

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=start.sh
source "${LIB_DIR}/start.sh"

cmd_setup() {
    local config_file="aibox.yaml"
    local runtime_pref="auto"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config_file="$2"; shift 2 ;;
            --runtime) runtime_pref="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: aibox setup [--config <path>] [--runtime <orbstack|lima>]"
                exit 0
                ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_config "${config_file}"

    # Validate config
    if ! validate_config "${config_file}"; then
        log_error "Fix config errors before setup."
        exit 1
    fi

    local start_time
    start_time=$(date +%s)

    # Detect runtime
    local config_runtime
    config_runtime=$(parse_config "${config_file}" "runtime" "auto")
    [[ "${runtime_pref}" != "auto" ]] && config_runtime="${runtime_pref}"

    local runtime
    runtime=$(detect_runtime "${config_runtime}") || exit 2

    # Get VM name
    local project_path
    project_path=$(parse_config "${config_file}" "project_path" ".")
    project_path="$(cd "${project_path}" && pwd)"
    local vm_name
    vm_name=$(get_vm_name "${project_path}")

    # Check if already exists
    if vm_exists "${vm_name}" "${runtime}"; then
        log_warn "VM '${vm_name}' already exists."
        log_warn "Run 'aibox teardown' first, or 'aibox start' to use existing VM."
        exit 1
    fi

    log_info "Setting up VM '${vm_name}'..."
    log_step "Runtime: ${runtime}"
    log_step "Project: ${project_path} → /workspace"

    # Read resource limits
    local cpu memory disk
    cpu=$(parse_config "${config_file}" "resources.cpu" "4")
    memory=$(parse_config "${config_file}" "resources.memory" "4096")
    disk=$(parse_config "${config_file}" "resources.disk" "20")

    log_step "Resources: ${cpu} CPU, ${memory}MB RAM, ${disk}GB disk"

    # Create VM
    case "${runtime}" in
        orbstack)
            _setup_orbstack "${vm_name}" "${project_path}" "${cpu}" "${memory}" "${disk}"
            ;;
        lima)
            _setup_lima "${vm_name}" "${project_path}" "${cpu}" "${memory}" "${disk}" "${config_file}"
            ;;
    esac

    # Run provisioning
    log_info "Provisioning VM..."
    _provision_vm "${vm_name}" "${runtime}" "${config_file}"

    # Apply network rules
    log_info "Applying network rules..."
    apply_network_rules "${vm_name}" "${runtime}" "${config_file}"

    # Sync Claude OAuth credentials (OrbStack only)
    if [[ "${runtime}" == "orbstack" ]]; then
        _sync_claude_credentials "${vm_name}" "${runtime}"
    fi

    # Pass environment variables
    _inject_env_vars "${vm_name}" "${runtime}" "${config_file}"

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    log_success "VM ready (setup took $(format_duration ${elapsed}))"
}

_setup_orbstack() {
    local vm_name="$1" project_path="$2" cpu="$3" memory="$4" disk="$5"

    # Create Ubuntu VM with OrbStack
    # Note: OrbStack manages resources at the engine level, not per-machine.
    # CPU/memory limits are advisory — OrbStack shares host resources efficiently.
    orb create ubuntu "${vm_name}" 2>&1 || {
        log_error "Failed to create OrbStack VM"
        exit 3
    }

    # Set up workspace with filesystem isolation (defense in depth)
    #
    # SECURITY MODEL:
    # OrbStack auto-mounts the ENTIRE host filesystem at /mnt/mac. An AI agent
    # with sudo could unmount any overlay. OrbStack's shared kernel architecture
    # means there's no way to fully prevent this at the VM level.
    #
    # Our approach (sufficient for AI agent isolation, not for adversarial threats):
    # 1. Create a non-root "agent" user with NO sudo access
    # 2. Bind-mount only the project dir to /workspace
    # 3. Mount tmpfs over /mnt/mac (non-root can't unmount)
    # 4. aibox exec runs commands as "agent" user
    #
    # For stronger isolation, use Lima runtime (--runtime lima) which only mounts
    # the project directory — no host filesystem access at all.

    log_step "Configuring filesystem isolation..."
    local host_mounts="${AIBOX_HOST_MOUNTS[*]}"
    orb run -m "${vm_name}" bash -c "
        # Create the agent user — no sudo, no password, restricted shell
        sudo useradd -m -s /bin/bash -G video,staff agent 2>/dev/null || true
        # Ensure agent is NOT in sudo/admin groups
        sudo deluser agent sudo 2>/dev/null || true
        sudo deluser agent admin 2>/dev/null || true

        # Create workspace and bind-mount the project directory
        sudo mkdir -p /workspace
        sudo mount --bind '/mnt/mac${project_path}' /workspace
        sudo chown agent:agent /workspace

        # Mount host ~/.claude into the agent home for conversation history / resume
        sudo mkdir -p /home/agent/.claude
        if [ -d '/mnt/mac/Users/${USER}/.claude' ]; then
            sudo mount --bind '/mnt/mac/Users/${USER}/.claude' /home/agent/.claude
            sudo chown agent:agent /home/agent/.claude
        fi

        # Hide ALL host filesystem mounts — OrbStack exposes the host at
        # /mnt/mac AND at native macOS paths (/Users, /Volumes, /Applications, etc.)
        # The agent user cannot unmount these without root/sudo
        for hostmount in ${host_mounts}; do
            if mountpoint -q \"\${hostmount}\" 2>/dev/null || [ -d \"\${hostmount}\" ]; then
                sudo mount -t tmpfs -o size=1M,mode=000 tmpfs \"\${hostmount}\"
            fi
        done

        # Persist mounts across VM restarts (idempotent — each entry checked individually)
        _fstab_add() { grep -qF \"\$1\" /etc/fstab 2>/dev/null || echo \"\$1\" | sudo tee -a /etc/fstab >/dev/null; }
        _fstab_add '/mnt/mac${project_path} /workspace none bind 0 0'
        _fstab_add '/mnt/mac/Users/${USER}/.claude /home/agent/.claude none bind 0 0'
        for hostmount in ${host_mounts}; do
            _fstab_add \"tmpfs \${hostmount} tmpfs size=1M,mode=000 0 0\"
        done

        # Set up agent home directory
        sudo mkdir -p /home/agent/.config
        sudo chown -R agent:agent /home/agent
    " 2>&1 || {
        log_error "Failed to set up workspace mount"
        exit 3
    }
}

_setup_lima() {
    local vm_name="$1" project_path="$2" cpu="$3" memory="$4" disk="$5" config_file="$6"

    # Generate Lima YAML config
    local lima_config="/tmp/${vm_name}.yaml"
    cat > "${lima_config}" <<YAML
# Generated by aibox
arch: aarch64
images:
  - location: "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-arm64.img"
    arch: "aarch64"

cpus: ${cpu}
memory: "${memory}MiB"
disk: "${disk}GiB"

mounts:
  - location: "${project_path}"
    mountPoint: "/workspace"
    writable: true
    virtiofs: true

# No other mounts — filesystem isolation
mountType: "virtiofs"

# Minimal SSH forwarding
ssh:
  localPort: 0
  forwardAgent: false
YAML

    limactl create --name "${vm_name}" "${lima_config}" 2>&1 || {
        log_error "Failed to create Lima VM"
        rm -f "${lima_config}"
        exit 3
    }

    limactl start "${vm_name}" 2>&1 || {
        log_error "Failed to start Lima VM"
        exit 3
    }

    rm -f "${lima_config}"
}

_provision_vm() {
    local vm_name="$1" runtime="$2" config_file="$3"

    # Build provisioning commands based on config
    local provision_script="#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo '>>> Updating packages...'
sudo apt-get update -qq

echo '>>> Installing base tools...'
sudo apt-get install -y -qq curl git build-essential ca-certificates iptables

echo '>>> Installing GitHub CLI...'
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
ARCH=\$(dpkg --print-architecture)
echo \"deb [arch=\${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq gh
"

    # Add language runtimes from config
    local node_ver python_ver go_ver rust_ver
    node_ver=$(parse_config "${config_file}" "provision.languages.node" "")
    python_ver=$(parse_config "${config_file}" "provision.languages.python" "")
    go_ver=$(parse_config "${config_file}" "provision.languages.go" "")
    rust_ver=$(parse_config "${config_file}" "provision.languages.rust" "")

    if [[ -n "${node_ver}" ]]; then
        provision_script+="
echo '>>> Installing Node.js ${node_ver}...'
curl -fsSL https://deb.nodesource.com/setup_${node_ver}.x | sudo -E bash -
sudo apt-get install -y -qq nodejs
"
    fi

    if [[ -n "${python_ver}" ]]; then
        provision_script+="
echo '>>> Installing Python ${python_ver}...'
sudo apt-get install -y -qq python${python_ver} python3-pip python3-venv
"
    fi

    if [[ -n "${go_ver}" ]]; then
        provision_script+="
echo '>>> Installing Go ${go_ver}...'
curl -fsSL https://go.dev/dl/go${go_ver}.linux-arm64.tar.gz | sudo tar -C /usr/local -xzf -
echo 'export PATH=\$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh
"
    fi

    if [[ -n "${rust_ver}" ]]; then
        provision_script+="
echo '>>> Installing Rust ${rust_ver}...'
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${rust_ver}
echo 'source \$HOME/.cargo/env' >> ~/.bashrc
"
    fi

    # Add AI agent CLIs
    local agents
    agents=$(parse_config_list "${config_file}" "provision" "agents")
    while IFS= read -r agent; do
        [[ -z "${agent}" ]] && continue
        case "${agent}" in
            claude)
                provision_script+="
echo '>>> Installing Claude Code CLI...'
if command -v npm &>/dev/null; then
    sudo npm install -g @anthropic-ai/claude-code 2>/dev/null || echo 'Claude Code install skipped (may need API key)'
else
    echo 'Skipping Claude Code — npm not available. Add node to provision.languages.'
fi
"
                ;;
            *)
                provision_script+="
echo '>>> Agent \"${agent}\" — manual installation required'
"
                ;;
        esac
    done <<< "${agents}"

    # Add extra packages
    local extra_pkgs
    extra_pkgs=$(parse_config_list "${config_file}" "provision" "extra_packages")
    if [[ -n "${extra_pkgs}" ]]; then
        local pkg_list
        pkg_list=$(echo "${extra_pkgs}" | tr '\n' ' ')
        provision_script+="
echo '>>> Installing extra packages: ${pkg_list}'
sudo apt-get install -y -qq ${pkg_list}
"
    fi

    provision_script+="
echo '>>> Provisioning complete!'
"

    # Execute provisioning inside the VM
    echo "${provision_script}" | vm_exec "${vm_name}" "${runtime}" bash || {
        log_error "Provisioning failed"
        exit 3
    }
}
