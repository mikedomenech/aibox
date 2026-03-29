#!/usr/bin/env bash
# exec.sh — Execute a command inside the running VM

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"

cmd_exec() {
    local config_file="aibox.yaml"

    # Check for --config before the command
    if [[ "${1:-}" == "--config" ]]; then
        config_file="$2"
        shift 2
    fi

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: aibox exec [--config <path>] <command> [args...]"
        echo ""
        echo "Examples:"
        echo "  aibox exec bash                      # Interactive shell"
        echo "  aibox exec claude 'fix the bug'      # Run Claude Code"
        echo "  aibox exec npm install               # Install packages"
        echo "  aibox exec cat /etc/os-release       # Run any command"
        exit 0
    fi

    if [[ $# -eq 0 ]]; then
        log_error "No command specified."
        echo "Usage: aibox exec <command> [args...]"
        exit 1
    fi

    require_config "${config_file}"

    local config_runtime
    config_runtime=$(parse_config "${config_file}" "runtime" "auto")
    local runtime
    runtime=$(detect_runtime "${config_runtime}") || exit 1

    local project_path
    project_path=$(parse_config "${config_file}" "project_path" ".")
    project_path="$(cd "${project_path}" && pwd)"
    local vm_name
    vm_name=$(get_vm_name "${project_path}")

    if ! vm_is_running "${vm_name}" "${runtime}"; then
        log_error "VM '${vm_name}' is not running. Run 'aibox start' first."
        exit 1
    fi

    # Pre-flight: warn if running Claude Code without an API key
    # OAuth login won't work inside the VM (no browser, no macOS Keychain)
    if [[ "$1" == "claude" ]]; then
        _check_claude_auth "${config_file}" "pre" "${vm_name}" "${runtime}"
    fi

    # Execute command inside VM as the unprivileged "agent" user
    # The agent user has no sudo access — cannot unmount /mnt/mac or escalate privileges
    local exit_code=0
    case "${runtime}" in
        orbstack)
            orb run -m "${vm_name}" -u agent -w /workspace "$@" || exit_code=$?
            ;;
        lima)
            limactl shell --workdir /workspace "${vm_name}" -- sudo -u agent "$@" || exit_code=$?
            ;;
    esac

    # If command failed, check if the VM crashed vs the command itself failing
    # If Claude Code exited, check if it was an auth failure
    if [[ "${exit_code}" -ne 0 && "${1:-}" == "claude" ]]; then
        _check_claude_auth "${config_file}" "post" "${vm_name}" "${runtime}"
    fi
    if [[ "${exit_code}" -ne 0 ]]; then
        if ! vm_is_running "${vm_name}" "${runtime}"; then
            log_error "VM '${vm_name}' stopped unexpectedly during execution."
            log_error "Run 'aibox start' to restart, or 'aibox setup' to recreate."
            exit 3
        fi
        exit "${exit_code}"
    fi
}

_check_claude_auth() {
    local config_file="$1"
    local phase="${2:-pre}"  # "pre" (before exec) or "post" (after failure)
    local vm_name="${3:-}"
    local runtime="${4:-}"

    local has_key=false

    if [[ "${phase}" == "post" ]]; then
        # Post-failure: check what's actually available inside the VM

        # Check OAuth credentials file inside the VM (OrbStack only — Lima doesn't mount ~/.claude)
        if [[ "${runtime}" == "orbstack" ]]; then
            local vm_creds
            vm_creds=$(vm_exec "${vm_name}" "${runtime}" sudo -u agent bash -c 'cat /home/agent/.claude/.credentials.json 2>/dev/null' 2>/dev/null) || true
            if [[ -n "${vm_creds}" ]]; then
                has_key=true
            fi
        fi

        # Check ANTHROPIC_API_KEY in the VM environment
        if [[ "${has_key}" == "false" ]]; then
            local vm_key
            vm_key=$(vm_exec "${vm_name}" "${runtime}" sudo -u agent bash -lc 'echo $ANTHROPIC_API_KEY' 2>/dev/null) || true
            if [[ -n "${vm_key}" ]]; then
                has_key=true
            fi
        fi
    else
        # Pre-flight: check host-side config to predict availability

        # Check 1: OAuth credentials file (only useful for OrbStack which mounts ~/.claude)
        if [[ "${runtime}" == "orbstack" ]]; then
            local creds_file="${HOME}/.claude/.credentials.json"
            if [[ -f "${creds_file}" ]] && [[ -s "${creds_file}" ]]; then
                has_key=true
            fi
        fi

        # Check 2: ANTHROPIC_API_KEY in host environment (will be passed through)
        if [[ "${has_key}" == "false" ]]; then
            local passthrough_vars
            passthrough_vars=$(parse_env_passthrough "${config_file}")
            if echo "${passthrough_vars}" | grep -qx "ANTHROPIC_API_KEY" && [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
                has_key=true
            fi
        fi

        # Check 3: ANTHROPIC_API_KEY in .aibox-env file
        if [[ "${has_key}" == "false" ]]; then
            local env_file
            env_file=$(parse_config "${config_file}" "env_file" ".aibox-env")
            if [[ -f "${env_file}" ]] && grep -q "^ANTHROPIC_API_KEY=" "${env_file}" 2>/dev/null; then
                has_key=true
            fi
        fi

        # Check 4: ANTHROPIC_API_KEY in static env vars
        if [[ "${has_key}" == "false" ]]; then
            local static_vars
            static_vars=$(parse_env_static "${config_file}")
            if echo "${static_vars}" | grep -q "^ANTHROPIC_API_KEY="; then
                has_key=true
            fi
        fi
    fi

    if [[ "${has_key}" == "false" ]]; then
        if [[ "${phase}" == "pre" ]]; then
            log_warn "No Claude credentials found. OAuth login will not work inside the VM"
            log_warn "(the VM cannot open a browser or access the macOS Keychain)."
            echo ""
            echo "  To fix:"
            echo ""
            echo "    1. Run 'claude login' on the host, then 'aibox start' (syncs OAuth)"
            echo "    2. Or set ANTHROPIC_API_KEY in .aibox-env or your shell environment"
            echo ""
        else
            log_error "Claude Code failed — this may be an authentication issue."
            echo ""
            echo "  Run 'claude login' on the host, then 'aibox start' to sync credentials."
            echo "  Or set ANTHROPIC_API_KEY in .aibox-env and restart."
            echo ""
        fi
    fi
}
