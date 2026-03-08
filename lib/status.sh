#!/usr/bin/env bash
# status.sh — Show VM status and configuration

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"

cmd_status() {
    local json_output=false
    local config_file="aibox.yaml"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=true; shift ;;
            --config) config_file="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: aibox status [--json] [--config <path>]"
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
        log_error "VM '${vm_name}' not found. Run 'aibox setup' first."
        exit 1
    fi

    local status="stopped"
    if vm_is_running "${vm_name}" "${runtime}"; then
        status="running"
        # Verify VM is actually responsive (might be hung after sleep)
        if ! vm_health_check "${vm_name}" "${runtime}"; then
            status="unresponsive"
        fi
    fi

    # Read config values
    local cpu memory disk
    cpu=$(parse_config "${config_file}" "resources.cpu" "4")
    memory=$(parse_config "${config_file}" "resources.memory" "4096")
    disk=$(parse_config "${config_file}" "resources.disk" "20")

    if [[ "${json_output}" == true ]]; then
        cat <<JSON
{
  "name": "${vm_name}",
  "status": "${status}",
  "runtime": "${runtime}",
  "project": "${project_path}",
  "resources": {
    "cpu": ${cpu},
    "memory_mb": ${memory},
    "disk_gb": ${disk}
  }
}
JSON
        return
    fi

    echo ""
    echo -e "${BOLD}VM: ${vm_name}${NC}"
    case "${status}" in
        running)
            echo -e "  Status: ${GREEN}running${NC}" ;;
        unresponsive)
            echo -e "  Status: ${RED}unresponsive${NC} (try 'aibox stop && aibox start')" ;;
        *)
            echo -e "  Status: ${YELLOW}stopped${NC}" ;;
    esac
    echo "  Runtime: ${runtime}"
    echo "  Project: ${project_path} → /workspace"
    echo ""
    echo "  Resources:"
    echo "    CPU: ${cpu} cores"
    echo "    Memory: ${memory} MB"
    echo "    Disk: ${disk} GB"

    # Show network rules if running
    if [[ "${status}" == "running" ]]; then
        echo ""
        echo "  Network:"
        local rules
        rules=$(parse_network_rules "${config_file}")
        local allow_defaults
        allow_defaults=$(parse_config "${config_file}" "network.allow_defaults" "true")
        if [[ "${allow_defaults}" == "true" ]]; then
            echo "    Defaults: npm, pypi, github, anthropic (enabled)"
        fi
        while IFS= read -r rule; do
            [[ -z "${rule}" ]] && continue
            echo "    Allowed: ${rule}"
        done <<< "${rules}"
        local host_svcs
        host_svcs=$(parse_host_services "${config_file}")
        while IFS= read -r port; do
            [[ -z "${port}" ]] && continue
            echo "    Host service: localhost:${port}"
        done <<< "${host_svcs}"
    fi

    # Show env vars (names only, not values)
    echo ""
    echo "  Environment:"
    local passthrough
    passthrough=$(parse_env_passthrough "${config_file}")
    while IFS= read -r var; do
        [[ -z "${var}" ]] && continue
        echo "    ${var} (pass-through)"
    done <<< "${passthrough}"
    local static
    static=$(parse_env_static "${config_file}")
    while IFS= read -r kv; do
        [[ -z "${kv}" ]] && continue
        echo "    ${kv%%=*} (static)"
    done <<< "${static}"

    echo ""
}
