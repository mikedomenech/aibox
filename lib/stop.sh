#!/usr/bin/env bash
# stop.sh — Gracefully stop the running VM

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"

cmd_stop() {
    local force=false
    local config_file="aibox.yaml"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            --config) config_file="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: aibox stop [--force] [--config <path>]"
                exit 0
                ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

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
        log_warn "VM '${vm_name}' is not running."
        exit 1
    fi

    log_info "Stopping VM '${vm_name}'..."

    case "${runtime}" in
        orbstack)
            if [[ "${force}" == true ]]; then
                orb stop --force "${vm_name}" 2>&1
            else
                orb stop "${vm_name}" 2>&1
            fi
            ;;
        lima)
            if [[ "${force}" == true ]]; then
                limactl stop -f "${vm_name}" 2>&1
            else
                limactl stop "${vm_name}" 2>&1
            fi
            ;;
    esac

    log_success "VM stopped."
}
