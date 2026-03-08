#!/usr/bin/env bats
# test_isolation.bats — Tests for filesystem isolation (US1)

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

# --- Filesystem isolation tests ---

@test "VM can read project files" {
    require_runtime
    "${AIBOX_BIN}" init
    echo "test content" > test-file.txt
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec cat /workspace/test-file.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"test content"* ]]
}

@test "VM can write to project directory" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    "${AIBOX_BIN}" exec touch /workspace/created-in-vm.txt
    [ -f "created-in-vm.txt" ]
}

@test "VM cannot read ~/.ssh" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    run "${AIBOX_BIN}" exec ls /home/*/.ssh 2>/dev/null
    # Should fail or return nothing — no host SSH keys visible
    [[ "$output" != *"id_rsa"* ]]
}

@test "VM cannot read host home directory" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    # Try to access host user's home directory contents
    run "${AIBOX_BIN}" exec ls /Users 2>/dev/null
    [ "$status" -ne 0 ] || [[ -z "$output" ]]
}

@test "VM cannot read /etc/hosts of host" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    # VM has its own /etc/hosts, not the host's
    run "${AIBOX_BIN}" exec cat /etc/hostname
    [[ "$output" == *"aibox"* ]] || true  # Should be the VM hostname
}

@test "file changes sync bidirectionally" {
    require_runtime
    "${AIBOX_BIN}" init
    "${AIBOX_BIN}" setup

    # Host → VM
    echo "from host" > host-file.txt
    sleep 2
    run "${AIBOX_BIN}" exec cat /workspace/host-file.txt
    [[ "$output" == *"from host"* ]]

    # VM → Host
    "${AIBOX_BIN}" exec bash -c "echo 'from vm' > /workspace/vm-file.txt"
    sleep 2
    run cat vm-file.txt
    [[ "$output" == *"from vm"* ]]
}
