#!/usr/bin/env bash
# network.sh — Network isolation via iptables inside the VM

# shellcheck source=config.sh
source "${LIB_DIR}/config.sh"

# Default allowed hosts (when allow_defaults: true)
DEFAULT_ALLOWED_HOSTS=(
    "registry.npmjs.org:443"
    "pypi.org:443"
    "files.pythonhosted.org:443"
    "github.com:443"
    "api.github.com:443"
    "api.anthropic.com:443"
    "deb.nodesource.com:443"
    "go.dev:443"
    "sh.rustup.rs:443"
    "static.rust-lang.org:443"
)

# Resolve hostname to IPs on the host side (macOS or Linux)
_resolve_host() {
    local host="$1"
    if command -v host &>/dev/null; then
        host "${host}" 2>/dev/null | awk '/has address/{print $NF}' | sort -u
    elif command -v getent &>/dev/null; then
        getent ahosts "${host}" 2>/dev/null | awk '{print $1}' | sort -u
    fi
}

apply_network_rules() {
    local vm_name="$1"
    local runtime="$2"
    local config_file="$3"

    local allow_defaults
    allow_defaults=$(parse_config "${config_file}" "network.allow_defaults" "true")

    # Build a flat list of iptables commands — no subshells, no dynamic resolution inside VM
    local rules=()

    # Base rules
    rules+=("sudo iptables -F OUTPUT 2>/dev/null || true")
    rules+=("sudo iptables -A OUTPUT -o lo -j ACCEPT")
    rules+=("sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT")
    rules+=("sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT")
    rules+=("sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT")

    # Resolve and add default allowed hosts
    if [[ "${allow_defaults}" == "true" ]]; then
        for entry in "${DEFAULT_ALLOWED_HOSTS[@]}"; do
            local host="${entry%%:*}"
            local port="${entry##*:}"
            local ips
            ips=$(_resolve_host "${host}")
            while IFS= read -r ip; do
                [[ -z "${ip}" ]] && continue
                rules+=("sudo iptables -A OUTPUT -p tcp -d ${ip} --dport ${port} -j ACCEPT")
            done <<< "${ips}"
        done
    fi

    # Custom allowed hosts from config
    local custom_rules
    custom_rules=$(parse_network_rules "${config_file}")
    while IFS= read -r rule; do
        [[ -z "${rule}" ]] && continue
        local host="${rule%%:*}"
        local port="${rule##*:}"
        local ips
        ips=$(_resolve_host "${host}")
        while IFS= read -r ip; do
            [[ -z "${ip}" ]] && continue
            rules+=("sudo iptables -A OUTPUT -p tcp -d ${ip} --dport ${port} -j ACCEPT")
        done <<< "${ips}"
    done <<< "${custom_rules}"

    # Host service forwarding — resolve gateway inside VM
    local host_services
    host_services=$(parse_host_services "${config_file}")
    local gateway=""
    while IFS= read -r port; do
        [[ -z "${port}" ]] && continue
        if [[ -z "${gateway}" ]]; then
            gateway=$(vm_exec "${vm_name}" "${runtime}" bash -c "ip route | grep default | head -1" 2>/dev/null | awk '{print $3}')
        fi
        if [[ -n "${gateway}" ]]; then
            rules+=("sudo iptables -A OUTPUT -p tcp -d ${gateway} --dport ${port} -j ACCEPT")
        fi
    done <<< "${host_services}"

    # Default deny
    rules+=("sudo iptables -A OUTPUT -p tcp -j DROP")
    rules+=("sudo iptables -A OUTPUT -p udp -j DROP")

    # Join all rules with semicolons and execute as one command
    local joined
    joined=$(printf '%s; ' "${rules[@]}")
    joined+="echo 'Network rules applied.'"

    vm_exec "${vm_name}" "${runtime}" bash -c "${joined}" 2>/dev/null || {
        log_warn "Could not apply network rules (iptables may not be available)"
    }
}
