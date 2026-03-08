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

apply_network_rules() {
    local vm_name="$1"
    local runtime="$2"
    local config_file="$3"

    local allow_defaults
    allow_defaults=$(parse_config "${config_file}" "network.allow_defaults" "true")

    # Build iptables script
    local iptables_script="#!/bin/bash
set -euo pipefail

# Flush existing rules
sudo iptables -F OUTPUT 2>/dev/null || true

# Allow loopback
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (needed for hostname resolution)
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
"

    # Add default allowed hosts
    if [[ "${allow_defaults}" == "true" ]]; then
        for entry in "${DEFAULT_ALLOWED_HOSTS[@]}"; do
            local host="${entry%%:*}"
            local port="${entry##*:}"
            iptables_script+="
# Default: ${host}
for ip in \$(dig +short ${host} 2>/dev/null || echo ''); do
    sudo iptables -A OUTPUT -p tcp -d \"\${ip}\" --dport ${port} -j ACCEPT
done
"
        done
    fi

    # Add custom allowed hosts from config
    local custom_rules
    custom_rules=$(parse_network_rules "${config_file}")
    while IFS= read -r rule; do
        [[ -z "${rule}" ]] && continue
        local host="${rule%%:*}"
        local port="${rule##*:}"
        iptables_script+="
# Custom: ${host}:${port}
for ip in \$(dig +short ${host} 2>/dev/null || echo ''); do
    sudo iptables -A OUTPUT -p tcp -d \"\${ip}\" --dport ${port} -j ACCEPT
done
"
    done <<< "${custom_rules}"

    # Add host service forwarding
    local host_services
    host_services=$(parse_host_services "${config_file}")
    while IFS= read -r port; do
        [[ -z "${port}" ]] && continue
        # The VM gateway IP is typically the default gateway
        iptables_script+="
# Host service: port ${port}
GATEWAY=\$(ip route | grep default | awk '{print \$3}')
sudo iptables -A OUTPUT -p tcp -d \"\${GATEWAY}\" --dport ${port} -j ACCEPT
"
    done <<< "${host_services}"

    # Default deny all other outbound
    iptables_script+="
# Default deny
sudo iptables -A OUTPUT -p tcp -j DROP
sudo iptables -A OUTPUT -p udp -j DROP

echo 'Network rules applied.'
"

    # Apply inside VM
    echo "${iptables_script}" | vm_exec "${vm_name}" "${runtime}" bash 2>/dev/null || {
        log_warn "Could not apply network rules (iptables may not be available)"
    }
}
