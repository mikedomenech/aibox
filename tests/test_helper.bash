#!/usr/bin/env bash
# test_helper.bash — Shared test utilities for aibox bats tests

AIBOX_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
AIBOX_BIN="${AIBOX_DIR}/bin/aibox"

# Create a temporary project directory for testing
setup_test_project() {
    TEST_PROJECT_DIR="$(mktemp -d)"
    cd "${TEST_PROJECT_DIR}" || exit 1
}

# Clean up temporary project directory
teardown_test_project() {
    if [[ -n "${TEST_PROJECT_DIR:-}" && -d "${TEST_PROJECT_DIR}" ]]; then
        rm -rf "${TEST_PROJECT_DIR}"
    fi
}

# Initialize aibox in test project
init_test_project() {
    setup_test_project
    "${AIBOX_BIN}" init --force
}

# Check if a VM runtime is available (skip test if not)
require_runtime() {
    if ! command -v orb &>/dev/null && ! command -v limactl &>/dev/null; then
        skip "No VM runtime installed (need orbstack or lima)"
    fi
}

# Check if a VM is running for the test project
require_running_vm() {
    require_runtime
    local vm_name
    vm_name=$("${AIBOX_BIN}" status --json 2>/dev/null | grep '"name"' | sed 's/.*: "//;s/".*//')
    if [[ -z "${vm_name}" ]]; then
        skip "No VM set up for testing"
    fi
}
