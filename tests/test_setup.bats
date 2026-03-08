#!/usr/bin/env bats
# test_setup.bats — Tests for aibox init, setup, teardown lifecycle

load test_helper

setup() {
    setup_test_project
}

teardown() {
    # Clean up any VMs created during tests
    if [[ -f "${TEST_PROJECT_DIR}/aibox.yaml" ]]; then
        cd "${TEST_PROJECT_DIR}"
        "${AIBOX_BIN}" teardown --yes 2>/dev/null || true
    fi
    teardown_test_project
}

# --- Init tests ---

@test "init creates aibox.yaml" {
    run "${AIBOX_BIN}" init
    [ "$status" -eq 0 ]
    [ -f "aibox.yaml" ]
}

@test "init creates .aibox-env.example" {
    run "${AIBOX_BIN}" init
    [ "$status" -eq 0 ]
    [ -f ".aibox-env.example" ]
}

@test "init adds .aibox-env to .gitignore" {
    run "${AIBOX_BIN}" init
    [ "$status" -eq 0 ]
    grep -q ".aibox-env" .gitignore
}

@test "init fails if config already exists" {
    "${AIBOX_BIN}" init
    run "${AIBOX_BIN}" init
    [ "$status" -eq 1 ]
}

@test "init --force overwrites existing config" {
    "${AIBOX_BIN}" init
    run "${AIBOX_BIN}" init --force
    [ "$status" -eq 0 ]
}

@test "init --preset node keeps node enabled" {
    run "${AIBOX_BIN}" init --preset node
    [ "$status" -eq 0 ]
    grep -q 'node: "22"' aibox.yaml
}

@test "init --preset python enables python" {
    run "${AIBOX_BIN}" init --preset python
    [ "$status" -eq 0 ]
    grep -q 'python: "3.12"' aibox.yaml
}

# --- Setup tests (require runtime) ---

@test "setup creates VM" {
    require_runtime
    "${AIBOX_BIN}" init
    run "${AIBOX_BIN}" setup
    [ "$status" -eq 0 ]
    [[ "$output" == *"VM ready"* ]]
}

@test "setup fails without config" {
    run "${AIBOX_BIN}" setup
    [ "$status" -eq 1 ]
}

@test "setup fails if VM already exists" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup
    run "${AIBOX_BIN}" setup
    [ "$status" -eq 1 ]
}

# --- Teardown tests ---

@test "teardown destroys VM" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup
    run "${AIBOX_BIN}" teardown --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"destroyed"* ]]
}

@test "teardown fails if VM not found" {
    "${AIBOX_BIN}" init
    run "${AIBOX_BIN}" teardown --yes
    [ "$status" -eq 1 ]
}

# --- Start/Stop tests ---

@test "start brings VM up in under 30 seconds" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup
    "${AIBOX_BIN}" stop 2>/dev/null || true

    local start_time=$(date +%s)
    run "${AIBOX_BIN}" start
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 30 ]
}

@test "stop shuts down running VM" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup
    run "${AIBOX_BIN}" stop
    [ "$status" -eq 0 ]
}

# --- Version/Help tests ---

@test "version shows version string" {
    run "${AIBOX_BIN}" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"aibox v"* ]]
}

@test "help shows usage" {
    run "${AIBOX_BIN}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unknown command shows error" {
    run "${AIBOX_BIN}" foobar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}
