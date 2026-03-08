#!/usr/bin/env bash
# config.sh — Parse and validate aibox.yaml configuration

# Parse a YAML value (simple key: value pairs, no nesting beyond one level)
# Uses grep/sed for portability — no python/ruby dependency
# For nested keys, use dot notation: parse_config "resources.cpu"
parse_config() {
    local config_file="$1"
    local key="$2"
    local default="${3:-}"

    if [[ ! -f "${config_file}" ]]; then
        echo "${default}"
        return
    fi

    local value=""

    # Handle dot notation for nested keys (e.g., resources.cpu, provision.languages.node)
    if [[ "${key}" == *.* ]]; then
        # Count depth
        local depth
        depth=$(echo "${key}" | tr -cd '.' | wc -c | tr -d ' ')

        if [[ "${depth}" -eq 1 ]]; then
            # Two levels: parent.child (e.g., resources.cpu)
            local parent="${key%%.*}"
            local child="${key#*.}"

            value=$(awk -v parent="${parent}" -v child="${child}" '
                /^[a-z]/ { section = $0; sub(/:.*/, "", section) }
                section == parent && $0 ~ "^  " child ":" {
                    val = $0
                    sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", val)
                    sub(/[[:space:]]*#.*$/, "", val)
                    gsub(/^["'"'"']|["'"'"']$/, "", val)
                    print val
                    exit
                }
            ' "${config_file}")
        elif [[ "${depth}" -eq 2 ]]; then
            # Three levels: grandparent.parent.child (e.g., provision.languages.node)
            local gp="${key%%.*}"
            local rest="${key#*.}"
            local par="${rest%%.*}"
            local child="${rest#*.}"

            value=$(awk -v gp="${gp}" -v par="${par}" -v child="${child}" '
                /^[a-z]/ { section = $0; sub(/:.*/, "", section); subsection = "" }
                section == gp && /^  [a-z]/ { sub(/^  /, ""); sub(/:.*/, ""); subsection = $0 }
                section == gp && subsection == par && $0 ~ "^    " child ":" {
                    val = $0
                    sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", val)
                    sub(/[[:space:]]*#.*$/, "", val)
                    gsub(/^["'"'"']|["'"'"']$/, "", val)
                    print val
                    exit
                }
            ' "${config_file}")
        fi
    else
        # Top-level key
        value=$(awk -v key="${key}" '
            /^[a-z]/ && $0 ~ "^" key ":" {
                val = $0
                sub(/^[^:]+:[[:space:]]*/, "", val)
                sub(/[[:space:]]*#.*$/, "", val)
                gsub(/^["'"'"']|["'"'"']$/, "", val)
                print val
                exit
            }
        ' "${config_file}")
    fi

    echo "${value:-${default}}"
}

# Parse a YAML list (returns newline-separated values)
parse_config_list() {
    local config_file="$1"
    local section="$2"
    local subsection="${3:-}"

    if [[ ! -f "${config_file}" ]]; then
        return
    fi

    if [[ -n "${subsection}" ]]; then
        # Nested list: section.subsection
        awk -v section="${section}" -v subsection="${subsection}" '
            /^[a-z]/ { current_section = $0; sub(/:.*/, "", current_section); in_sub = 0 }
            current_section == section && $0 ~ "^  " subsection ":" { in_sub = 1; next }
            current_section == section && in_sub && /^    - / {
                val = $0
                sub(/^[[:space:]]*- [[:space:]]*/, "", val)
                sub(/[[:space:]]*#.*$/, "", val)
                gsub(/^["'"'"']|["'"'"']$/, "", val)
                print val
            }
            current_section == section && in_sub && /^  [a-z]/ { in_sub = 0 }
            /^[a-z]/ && current_section != section { in_sub = 0 }
        ' "${config_file}"
    else
        # Top-level list
        awk -v section="${section}" '
            /^[a-z]/ { current_section = $0; sub(/:.*/, "", current_section) }
            current_section == section && /^  - / {
                val = $0
                sub(/^[[:space:]]*- [[:space:]]*/, "", val)
                sub(/[[:space:]]*#.*$/, "", val)
                gsub(/^["'"'"']|["'"'"']$/, "", val)
                print val
            }
        ' "${config_file}"
    fi
}

# Parse network allow rules (returns host:port pairs)
parse_network_rules() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        return
    fi

    awk '
        /^network:/ { in_network = 1; next }
        /^[a-z]/ && !/^network:/ { in_network = 0 }
        in_network && /^  allow:/ { in_allow = 1; next }
        in_network && /^  [a-z]/ && !/^  allow:/ { in_allow = 0 }
        in_allow && /host:/ {
            host = $0
            sub(/.*host:[[:space:]]*/, "", host)
            sub(/[[:space:]]*#.*$/, "", host)
            gsub(/["'"'"']/, "", host)
        }
        in_allow && /port:/ {
            port = $0
            sub(/.*port:[[:space:]]*/, "", port)
            sub(/[[:space:]]*#.*$/, "", port)
            if (host != "" && port != "") {
                print host ":" port
            }
        }
    ' "${config_file}"
}

# Parse host_services (returns port numbers)
parse_host_services() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        return
    fi

    awk '
        /^network:/ { in_network = 1; next }
        /^[a-z]/ && !/^network:/ { in_network = 0 }
        in_network && /host_services:/ { in_hs = 1; next }
        in_network && /^  [a-z]/ && !/host_services:/ { in_hs = 0 }
        in_hs && /port:/ {
            port = $0
            sub(/.*port:[[:space:]]*/, "", port)
            sub(/[[:space:]]*#.*$/, "", port)
            print port
        }
    ' "${config_file}"
}

# Parse environment pass_through list
parse_env_passthrough() {
    local config_file="$1"
    parse_config_list "${config_file}" "env" "pass_through"
}

# Parse static env vars (returns KEY=VALUE pairs)
parse_env_static() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        return
    fi

    awk '
        /^env:/ { in_env = 1; next }
        /^[a-z]/ && !/^env:/ { in_env = 0 }
        in_env && /^  static:/ { in_static = 1; next }
        in_env && /^  [a-z]/ && !/^  static:/ { in_static = 0 }
        in_static && /^    [A-Z]/ {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*#.*$/, "", line)
            # Convert "KEY: value" to "KEY=value"
            sub(/:[[:space:]]*/, "=", line)
            gsub(/["'"'"']/, "", line)
            print line
        }
    ' "${config_file}"
}

# Load env vars from .aibox-env file
load_env_file() {
    local env_file="$1"

    if [[ ! -f "${env_file}" ]]; then
        return
    fi

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        echo "${line}"
    done < "${env_file}"
}

# Validate config file
validate_config() {
    local config_file="$1"
    local errors=0

    if [[ ! -f "${config_file}" ]]; then
        log_error "Config file not found: ${config_file}"
        return 1
    fi

    # Validate runtime
    local runtime
    runtime=$(parse_config "${config_file}" "runtime" "auto")
    if [[ "${runtime}" != "auto" && "${runtime}" != "orbstack" && "${runtime}" != "lima" ]]; then
        log_error "Invalid runtime: ${runtime}. Must be 'orbstack', 'lima', or omit for auto."
        ((errors++))
    fi

    # Validate resource limits
    local cpu memory disk
    cpu=$(parse_config "${config_file}" "resources.cpu" "4")
    memory=$(parse_config "${config_file}" "resources.memory" "4096")
    disk=$(parse_config "${config_file}" "resources.disk" "20")

    if [[ "${cpu}" -lt 1 || "${cpu}" -gt 8 ]] 2>/dev/null; then
        log_error "Invalid CPU count: ${cpu}. Must be 1-8."
        ((errors++))
    fi

    if [[ "${memory}" -lt 512 || "${memory}" -gt 16384 ]] 2>/dev/null; then
        log_error "Invalid memory: ${memory}MB. Must be 512-16384."
        ((errors++))
    fi

    if [[ "${disk}" -lt 5 || "${disk}" -gt 100 ]] 2>/dev/null; then
        log_error "Invalid disk: ${disk}GB. Must be 5-100."
        ((errors++))
    fi

    # Validate project path
    local project_path
    project_path=$(parse_config "${config_file}" "project_path" ".")
    if [[ ! -d "${project_path}" ]]; then
        log_error "Project path not found: ${project_path}"
        ((errors++))
    fi

    return "${errors}"
}
