#!/usr/bin/env bats
# test_resources.bats — Tests for resource limits (US4)

load test_helper

setup() {
    setup_test_project
}

teardown() {
    if [[ -f "${TEST_PROJECT_DIR}/aibox.yaml" ]]; then
        cd "${TEST_PROJECT_DIR}"
        "${AIBOX_BIN}" teardown --yes 2>/dev/null || true
    fi
    teardown_test_project
}

@test "VM respects CPU limit" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec nproc
    [ "$status" -eq 0 ]
    # Default is 4 CPUs
    [ "$output" -le 4 ]
}

@test "VM respects memory limit" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    # Check total memory is close to configured limit (4096 MB default)
    run "${AIBOX_BIN}" exec bash -c "free -m | awk '/^Mem:/{print \$2}'"
    [ "$status" -eq 0 ]
    # Allow some overhead — should be within ~500MB of configured limit
    [ "$output" -le 4600 ]
}

@test "status shows resource configuration" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"CPU:"* ]]
    [[ "$output" == *"Memory:"* ]]
    [[ "$output" == *"Disk:"* ]]
}

@test "status --json returns valid JSON" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" status --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name"'* ]]
    [[ "$output" == *'"status"'* ]]
    [[ "$output" == *'"resources"'* ]]
}
