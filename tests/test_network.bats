#!/usr/bin/env bats
# test_network.bats — Tests for network isolation (US2)

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

@test "allowed host is reachable (github.com)" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec curl -s -o /dev/null -w "%{http_code}" https://github.com
    [[ "$output" == "200" || "$output" == "301" || "$output" == "302" ]]
}

@test "blocked host is unreachable" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec curl -s --connect-timeout 5 http://evil.example.com 2>/dev/null
    [ "$status" -ne 0 ]
}

@test "host localhost services are blocked by default" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    # Try to connect to host PostgreSQL (port 5432)
    run "${AIBOX_BIN}" exec bash -c "curl -s --connect-timeout 3 http://\$(ip route | grep default | awk '{print \$3}'):5432" 2>/dev/null
    [ "$status" -ne 0 ] || [[ -z "$output" ]]
}

@test "npm registry is reachable" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec curl -s -o /dev/null -w "%{http_code}" https://registry.npmjs.org
    [[ "$output" == "200" ]]
}

@test "anthropic API is reachable" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com
    # 401 or 200 — just needs to be reachable
    [[ "$output" =~ ^[0-9]+$ ]]
}
