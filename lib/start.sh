#!/usr/bin/env bash
# start.sh — Start an existing VM and apply rules

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=network.sh
source "${LIB_DIR}/network.sh"

cmd_start() {
    local config_file="aibox.yaml"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config_file="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: aibox start [--config <path>]"
                exit 0
                ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    require_config "${config_file}"

    local start_time
    start_time=$(date +%s)

    # Detect runtime
    local config_runtime
    config_runtime=$(parse_config "${config_file}" "runtime" "auto")
    local runtime
    runtime=$(detect_runtime "${config_runtime}") || exit 1

    # Get VM name
    local project_path
    project_path=$(parse_config "${config_file}" "project_path" ".")
    project_path="$(cd "${project_path}" && pwd)"
    local vm_name
    vm_name=$(get_vm_name "${project_path}")

    # Check VM exists
    if ! vm_exists "${vm_name}" "${runtime}"; then
        log_error "VM '${vm_name}' not found. Run 'aibox setup' first."
        exit 1
    fi

    # If already running, just re-sync credentials and env vars
    if vm_is_running "${vm_name}" "${runtime}"; then
        log_info "VM '${vm_name}' is already running. Syncing credentials..."
        if [[ "${runtime}" == "orbstack" ]]; then
            _sync_claude_credentials
        fi
        _inject_env_vars "${vm_name}" "${runtime}" "${config_file}"
        log_success "Credentials synced."
        return 0
    fi

    log_info "Starting VM '${vm_name}'..."

    # Start the VM
    case "${runtime}" in
        orbstack)
            orb start "${vm_name}" 2>&1 || {
                log_error "Failed to start VM"
                exit 3
            }
            ;;
        lima)
            limactl start "${vm_name}" 2>&1 || {
                log_error "Failed to start VM"
                exit 3
            }
            ;;
    esac

    # Health check — VM may be sluggish after laptop sleep/wake
    log_info "Waiting for VM to be responsive..."
    if ! vm_health_check "${vm_name}" "${runtime}"; then
        log_error "VM started but is not responding. Try: aibox teardown && aibox setup"
        exit 3
    fi

    # Re-apply filesystem isolation (OrbStack may restore /mnt/mac on restart)
    if [[ "${runtime}" == "orbstack" ]]; then
        log_info "Applying filesystem isolation..."
        local host_mounts="${AIBOX_HOST_MOUNTS[*]}"
        orb run -m "${vm_name}" bash -c "
            # Re-mount if not already mounted
            if ! mountpoint -q /workspace 2>/dev/null; then
                sudo mount --bind '/mnt/mac${project_path}' /workspace
            fi
            # Re-mount ~/.claude if not already mounted
            if ! mountpoint -q /home/agent/.claude 2>/dev/null; then
                sudo mkdir -p /home/agent/.claude
                if [ -d '/mnt/mac/Users/${USER}/.claude' ]; then
                    sudo mount --bind '/mnt/mac/Users/${USER}/.claude' /home/agent/.claude
                fi
            fi
            # Re-hide ALL host filesystem mounts if visible
            for hostmount in ${host_mounts}; do
                if mountpoint -q \"\${hostmount}\" 2>/dev/null; then
                    # Check if it's already our tmpfs blocker
                    if ! mount | grep -q \"tmpfs on \${hostmount} type tmpfs\"; then
                        sudo mount -t tmpfs -o size=1M,mode=000 tmpfs \"\${hostmount}\"
                    fi
                fi
            done
        " 2>&1 || log_warn "Could not re-apply filesystem isolation"
    fi

    # Apply network rules
    log_info "Applying network rules..."
    apply_network_rules "${vm_name}" "${runtime}" "${config_file}"

    # Sync Claude Code OAuth credentials from macOS Keychain into ~/.claude
    # On macOS, Claude Code stores OAuth tokens in the Keychain; on Linux (inside
    # the VM), it reads from ~/.claude/.credentials.json instead.
    # Only works with OrbStack (which bind-mounts ~/.claude into the VM).
    if [[ "${runtime}" == "orbstack" ]]; then
        _sync_claude_credentials
    fi

    # Pass environment variables
    _inject_env_vars "${vm_name}" "${runtime}" "${config_file}"

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    log_success "VM ready (started in $(format_duration ${elapsed}))"
}

_inject_env_vars() {
    local vm_name="$1" runtime="$2" config_file="$3"

    local env_script="#!/bin/bash
# Set environment variables for aibox session
"

    # Pass-through vars from host env
    local passthrough_vars
    passthrough_vars=$(parse_env_passthrough "${config_file}")
    while IFS= read -r var_name; do
        [[ -z "${var_name}" ]] && continue
        local var_value="${!var_name:-}"
        if [[ -n "${var_value}" ]]; then
            env_script+="export ${var_name}='${var_value}'
"
            log_step "${var_name} (from host)"
        else
            log_warn "${var_name} not set in host environment"
        fi
    done <<< "${passthrough_vars}"

    # Static env vars
    local static_vars
    static_vars=$(parse_env_static "${config_file}")
    while IFS= read -r kv; do
        [[ -z "${kv}" ]] && continue
        env_script+="export ${kv}
"
    done <<< "${static_vars}"

    # Load from .aibox-env file
    local env_file
    env_file=$(parse_config "${config_file}" "env_file" ".aibox-env")
    if [[ -f "${env_file}" ]]; then
        local env_file_vars
        env_file_vars=$(load_env_file "${env_file}")
        while IFS= read -r kv; do
            [[ -z "${kv}" ]] && continue
            local key="${kv%%=*}"
            env_script+="export ${kv}
"
            log_step "${key} (from ${env_file})"
        done <<< "${env_file_vars}"
    fi

    # Write env file inside VM
    echo "${env_script}" | vm_exec "${vm_name}" "${runtime}" bash -c "cat > /etc/profile.d/aibox-env.sh && chmod 644 /etc/profile.d/aibox-env.sh" 2>/dev/null || {
        log_warn "Could not inject environment variables"
    }
}

_sync_claude_credentials() {
    local claude_dir="${HOME}/.claude"
    local creds_file="${claude_dir}/.credentials.json"
    local keychain_service="Claude Code-credentials"
    local keychain_account
    keychain_account="$(whoami)"

    # Extract OAuth credentials from macOS Keychain
    local creds
    creds=$(security find-generic-password -s "${keychain_service}" -a "${keychain_account}" -w 2>/dev/null) || true

    if [[ -n "${creds}" ]]; then
        mkdir -p "${claude_dir}"
        if printf '%s' "${creds}" > "${creds_file}" && chmod 600 "${creds_file}"; then
            log_step "Claude credentials synced from Keychain"
        else
            log_warn "Failed to write Claude credentials to ${creds_file}"
        fi
    else
        log_warn "No Claude Code credentials found in Keychain. Run 'claude login' on the host first."
    fi
}
