#!/usr/bin/env bash
# common.sh — Shared utilities for aibox

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

log_info() {
    echo -e "${BLUE}▸${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*" >&2
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_step() {
    echo -e "  ${BOLD}$*${NC}"
}

# Derive a stable VM name from the project directory
# e.g., /Users/dev/my-project → aibox-my-project
get_vm_name() {
    local project_path="${1:-.}"
    local abs_path
    abs_path="$(cd "${project_path}" && pwd)"
    local dir_name
    dir_name="$(basename "${abs_path}")"
    # Sanitize: lowercase, replace non-alphanumeric with hyphens
    echo "aibox-$(echo "${dir_name}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
}

# Detect which VM runtime is available
# Returns: "orbstack", "lima", or exits with error
detect_runtime() {
    local preferred="${1:-auto}"

    if [[ "${preferred}" != "auto" ]]; then
        case "${preferred}" in
            orbstack)
                if command -v orb &>/dev/null; then
                    echo "orbstack"
                    return 0
                fi
                log_error "OrbStack not found. Install: brew install orbstack"
                return 1
                ;;
            lima)
                if command -v limactl &>/dev/null; then
                    echo "lima"
                    return 0
                fi
                log_error "Lima not found. Install: brew install lima"
                return 1
                ;;
            *)
                log_error "Unknown runtime: ${preferred}. Use 'orbstack' or 'lima'."
                return 1
                ;;
        esac
    fi

    # Auto-detect: prefer OrbStack
    if command -v orb &>/dev/null; then
        if ! orb list &>/dev/null; then
            log_error "OrbStack is installed but not running. Open OrbStack.app first."
            return 1
        fi
        echo "orbstack"
        return 0
    fi

    if command -v limactl &>/dev/null; then
        if ! limactl list &>/dev/null; then
            log_error "Lima is installed but the daemon isn't running. Run: limactl start"
            return 1
        fi
        echo "lima"
        return 0
    fi

    log_error "No VM runtime found. Install one of:"
    log_error "  brew install orbstack    (recommended — faster startup)"
    log_error "  brew install lima        (open source alternative)"
    return 1
}

# Check if VM exists
# Note: uses grep without -q to avoid SIGPIPE with pipefail
vm_exists() {
    local vm_name="$1"
    local runtime="$2"

    case "${runtime}" in
        orbstack)
            orb list 2>/dev/null | grep "^${vm_name}" >/dev/null 2>&1
            ;;
        lima)
            limactl list 2>/dev/null | grep "^${vm_name}" >/dev/null 2>&1
            ;;
    esac
}

# Check if VM is running
vm_is_running() {
    local vm_name="$1"
    local runtime="$2"

    case "${runtime}" in
        orbstack)
            orb list 2>/dev/null | grep "^${vm_name}" 2>/dev/null | grep "running" >/dev/null 2>&1
            ;;
        lima)
            limactl list 2>/dev/null | grep "^${vm_name}" 2>/dev/null | grep "Running" >/dev/null 2>&1
            ;;
    esac
}

# Execute a command inside the VM
vm_exec() {
    local vm_name="$1"
    local runtime="$2"
    shift 2

    case "${runtime}" in
        orbstack)
            orb run -m "${vm_name}" "$@"
            ;;
        lima)
            limactl shell "${vm_name}" "$@"
            ;;
    esac
}

# Check VM is responsive (handles post-sleep, crash recovery)
# Retries a few times since VMs may need a moment after wake
vm_health_check() {
    local vm_name="$1"
    local runtime="$2"
    local retries=3
    local delay=2

    for ((i = 1; i <= retries; i++)); do
        if vm_exec "${vm_name}" "${runtime}" true 2>/dev/null; then
            return 0
        fi
        if [[ "${i}" -lt "${retries}" ]]; then
            sleep "${delay}"
        fi
    done
    return 1
}

# Get elapsed time in human-readable format
format_duration() {
    local seconds="$1"
    if [[ "${seconds}" -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ "${seconds}" -lt 3600 ]]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

# Require a config file, exit if not found
require_config() {
    local config_path="${1:-aibox.yaml}"
    if [[ ! -f "${config_path}" ]]; then
        log_error "Config file not found: ${config_path}"
        log_error "Run 'aibox init' to create one."
        exit 1
    fi
}
