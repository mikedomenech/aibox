#!/usr/bin/env bash
# teardown.sh — Destroy the VM and free all resources

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"

cmd_teardown() {
    local skip_confirm=false
    local config_file="aibox.yaml"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y) skip_confirm=true; shift ;;
            --config) config_file="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: aibox teardown [--yes] [--config <path>]"
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

    if ! vm_exists "${vm_name}" "${runtime}"; then
        log_error "VM '${vm_name}' not found."
        exit 1
    fi

    # Confirm
    if [[ "${skip_confirm}" != true ]]; then
        echo ""
        log_warn "This will destroy VM '${vm_name}' and all data inside it."
        log_warn "Project files on the host will NOT be affected."
        echo ""
        read -rp "Are you sure? [y/N] " confirm
        if [[ "${confirm}" != [yY] && "${confirm}" != [yY][eE][sS] ]]; then
            log_info "Cancelled."
            exit 2
        fi
    fi

    log_info "Tearing down VM '${vm_name}'..."

    # Stop if running
    if vm_is_running "${vm_name}" "${runtime}"; then
        log_step "Stopping VM..."
        case "${runtime}" in
            orbstack) orb stop --force "${vm_name}" 2>&1 ;;
            lima) limactl stop -f "${vm_name}" 2>&1 ;;
        esac
    fi

    # Delete VM
    log_step "Deleting VM..."
    case "${runtime}" in
        orbstack)
            orb delete --force "${vm_name}" 2>&1 || {
                log_error "Failed to delete VM"
                exit 1
            }
            ;;
        lima)
            limactl delete "${vm_name}" 2>&1 || {
                log_error "Failed to delete VM"
                exit 1
            }
            ;;
    esac

    log_success "VM '${vm_name}' destroyed. Project files preserved on host."
}
