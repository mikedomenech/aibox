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
    if [[ "${exit_code}" -ne 0 ]]; then
        if ! vm_is_running "${vm_name}" "${runtime}"; then
            log_error "VM '${vm_name}' stopped unexpectedly during execution."
            log_error "Run 'aibox start' to restart, or 'aibox setup' to recreate."
            exit 3
        fi
        exit "${exit_code}"
    fi
}
