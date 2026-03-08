# Feature Specification: VM Isolation for Claude

**Feature Branch**: `003-vm-isolation`
**Created**: 2026-03-08
**Status**: Complete
**Input**: User description: "Run AI coding agents (Claude Code, etc.) inside a VM to sandbox their access — limit filesystem, network, and system access so agents can operate more autonomously without risk of affecting the host system or leaking sensitive data. This is a general-purpose tool for any project, not tied to a specific codebase."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sandboxed Development Environment (Priority: P1)

As a developer, I want AI coding agents (Claude Code, Cursor, Copilot, etc.) to run inside an isolated VM so that I can give them broader autonomy (e.g., "let it loose" on tasks) without worrying that they will access, modify, or leak files outside the project, affect my host system, or reach sensitive services.

**Why this priority**: This is the core value — containment. Without isolation, giving AI agents broader permissions is risky. Personal machines hold SSH keys, cloud credentials, browser sessions, and sensitive data across many projects. The VM creates a trust boundary that protects the entire host.

**Independent Test**: Can be tested by launching Claude Code inside the VM, verifying it can access the project files, and confirming it cannot access host filesystem, host network services, or secrets outside the VM.

**Acceptance Scenarios**:

1. **Given** the VM is configured and running, **When** Claude Code is launched inside it, **Then** Claude can read and write files only within the designated project directory
2. **Given** Claude is running inside the VM, **When** it attempts to access files outside the project directory (e.g., ~/.ssh, ~/.env, ~/Documents), **Then** access is denied
3. **Given** Claude is running inside the VM, **When** it attempts to access host network services (e.g., localhost databases, other local services), **Then** access is blocked unless explicitly allowed
4. **Given** Claude is running inside the VM, **When** it completes work on project files, **Then** changes are visible to the developer on the host system

---

### User Story 2 - Controlled Network Access (Priority: P2)

As a developer, I want to control what network resources AI agents can access from inside the VM so that they can install packages and make API calls but cannot reach internal services, company networks, or exfiltrate data to unauthorized destinations.

**Why this priority**: Network isolation prevents data exfiltration and limits blast radius. AI agents need outbound internet for package installs and API calls, but should not access internal services unless explicitly allowed.

**Independent Test**: Can be tested by attempting network connections from inside the VM to allowed destinations (npm registry, GitHub) and blocked destinations (internal services, arbitrary hosts).

**Acceptance Scenarios**:

1. **Given** the VM has network rules configured, **When** Claude runs `npm install` inside the VM, **Then** package installation succeeds (outbound HTTPS to npm registry allowed)
2. **Given** the VM has network rules configured, **When** Claude attempts to connect to the host's PostgreSQL (localhost:5432), **Then** the connection is blocked by default
3. **Given** the developer has explicitly allowed a service, **When** Claude attempts to connect to that service, **Then** the connection succeeds

---

### User Story 3 - Easy Setup and Teardown (Priority: P2)

As a developer, I want to create, start, and destroy the VM environment with simple commands so that the overhead of using isolation does not slow down my workflow.

**Why this priority**: If the VM is hard to set up or slow to start, it won't be used. The isolation must be frictionless to be practical.

**Independent Test**: Can be tested by timing the setup, start, and teardown commands and verifying they complete within acceptable limits.

**Acceptance Scenarios**:

1. **Given** no VM exists, **When** the developer runs a setup command, **Then** a configured VM is created with developer-specified tools and AI agent CLI
2. **Given** a VM exists, **When** the developer runs a start command, **Then** the VM is ready for use within 30 seconds
3. **Given** a running VM, **When** the developer runs a teardown command, **Then** the VM is destroyed and all resources are freed
4. **Given** a VM was destroyed, **When** the developer runs setup again, **Then** a fresh VM is created from scratch

---

### User Story 4 - Resource Limits (Priority: P3)

As a developer, I want to set resource limits (CPU, memory, disk) on the VM so that Claude cannot consume excessive host resources even if a task goes wrong.

**Why this priority**: Prevents runaway processes from affecting host system performance. Lower priority because macOS already provides some process isolation, but important for long-running autonomous tasks.

**Independent Test**: Can be tested by running a resource-intensive task inside the VM and verifying it is constrained to the configured limits.

**Acceptance Scenarios**:

1. **Given** the VM has a memory limit configured, **When** a process inside the VM tries to allocate more memory than the limit, **Then** the process is killed or constrained, not the host
2. **Given** the VM has a CPU limit configured, **When** a process inside the VM uses 100% CPU, **Then** host system performance is not significantly affected
3. **Given** the VM has a disk limit configured, **When** the agent generates files that exceed the disk limit, **Then** writes fail gracefully inside the VM without affecting host storage

---

### Edge Cases

- What happens if the VM crashes or is killed mid-task — are changes to project files preserved or lost?
- What happens if the developer's laptop goes to sleep/hibernates while the VM is running?
- What happens if the AI agent needs to access a tool not installed in the VM (e.g., Docker, a specific CLI tool)?
- How are environment variables (non-secret) passed into the VM for project configuration?
- What happens when the project has large node_modules that need to be shared between host and VM?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The VM MUST provide filesystem isolation — the AI agent can only access the designated project directory and its contents
- **FR-002**: The VM MUST sync file changes bidirectionally between the host project directory and the VM's working directory
- **FR-003**: The VM MUST provide network isolation by default — only explicitly allowed outbound connections (package registries, version control) are permitted
- **FR-004**: The developer MUST be able to configure a list of allowed network destinations (hosts/ports) that the AI agent can access from inside the VM
- **FR-005**: The VM MUST support configurable provisioning of development tools (e.g., Node.js, Python, Go, Rust, git) based on project needs
- **FR-006**: The VM MUST support installing and authenticating AI coding agent CLIs (e.g., Claude Code, Cursor) via environment variables
- **FR-007**: The developer MUST be able to start and stop the VM with single commands
- **FR-008**: The VM MUST support configurable resource limits for CPU, memory, and disk space
- **FR-009**: The VM MUST run on macOS (Apple Silicon / ARM64)
- **FR-010**: File changes made inside the VM MUST survive VM restarts (persistent project directory)
- **FR-011**: The VM MUST NOT have access to host SSH keys, cloud credentials, browser cookies, or any files outside the project directory
- **FR-012**: The developer MUST be able to pass specific environment variables into the VM without exposing the host's full environment

### Assumptions

- The developer is running macOS on Apple Silicon (M-series chip)
- This is a general-purpose tool — works with any project, any language, any AI agent
- AI agent authentication tokens are passed into the VM via environment variables
- The VM does not need a GUI — terminal/CLI access only
- The tool itself is standalone (not part of any specific application codebase)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: VM starts and is ready for use within 30 seconds of running the start command
- **SC-002**: File changes made by Claude inside the VM are visible on the host within 5 seconds
- **SC-003**: The AI agent running inside the VM cannot access any file outside the project directory (verified by attempting to read ~/.ssh/id_rsa, ~/.zshrc, etc.)
- **SC-004**: The AI agent running inside the VM cannot connect to host-only services (localhost:5432, localhost:3000) unless explicitly allowed
- **SC-005**: The developer can set up a new VM from scratch in under 5 minutes including tool installation
- **SC-006**: VM resource consumption does not exceed configured limits (memory, CPU, disk)
