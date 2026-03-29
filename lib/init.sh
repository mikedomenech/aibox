#!/usr/bin/env bash
# init.sh — Generate default aibox.yaml in current directory

cmd_init() {
    local force=false
    local preset=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            --preset) preset="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: aibox init [--force] [--preset <name>]"
                echo ""
                echo "Options:"
                echo "  --force           Overwrite existing config"
                echo "  --preset <name>   Use a preset (node, python, fullstack, go, rust)"
                exit 0
                ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    local config_file="aibox.yaml"
    local env_example=".aibox-env.example"

    # Check for existing config
    if [[ -f "${config_file}" && "${force}" != true ]]; then
        log_error "Config already exists: ${config_file}"
        log_error "Use --force to overwrite."
        exit 1
    fi

    # Copy template
    local template_dir="${AIBOX_DIR}/templates"

    if [[ -n "${preset}" ]]; then
        _apply_preset "${preset}" "${config_file}" "${template_dir}"
    else
        cp "${template_dir}/aibox.yaml" "${config_file}"
    fi

    # Create .aibox-env.example
    cat > "${env_example}" <<'EOF'
# aibox environment variables
# Copy to .aibox-env and fill in your values
# IMPORTANT: .aibox-env should be gitignored

ANTHROPIC_API_KEY=your-api-key-here
# OPENAI_API_KEY=your-key-here
# DATABASE_URL=postgres://...
EOF

    # Add .aibox-env to .gitignore if not present
    if [[ -f ".gitignore" ]]; then
        if ! grep -q "^\.aibox-env$" .gitignore 2>/dev/null; then
            {
                echo ""
                echo "# aibox environment (contains secrets)"
                echo ".aibox-env"
            } >> .gitignore
            log_info "Added .aibox-env to .gitignore"
        fi
    else
        echo ".aibox-env" > .gitignore
        log_info "Created .gitignore with .aibox-env"
    fi

    log_success "Created ${config_file}"
    log_success "Created ${env_example}"
    echo ""
    log_info "Next steps:"
    log_step "1. Edit ${config_file} to configure your VM"
    log_step "2. Authenticate (pick one):"
    log_step "   a. claude login  (OAuth — credentials sync automatically)"
    log_step "   b. cp ${env_example} .aibox-env && add your API key"
    log_step "3. aibox setup"
}

_apply_preset() {
    local preset="$1"
    local config_file="$2"
    local template_dir="$3"

    # Start with base template
    cp "${template_dir}/aibox.yaml" "${config_file}"

    case "${preset}" in
        node)
            log_info "Applying Node.js preset"
            # Default template already has node, just ensure it
            ;;
        python)
            log_info "Applying Python preset"
            sed -i '' 's/node: "22"/# node: "22"/' "${config_file}"
            sed -i '' 's/# python: "3.12"/python: "3.12"/' "${config_file}"
            ;;
        go)
            log_info "Applying Go preset"
            sed -i '' 's/node: "22"/# node: "22"/' "${config_file}"
            sed -i '' 's/# go: "1.22"/go: "1.22"/' "${config_file}"
            ;;
        rust)
            log_info "Applying Rust preset"
            sed -i '' 's/node: "22"/# node: "22"/' "${config_file}"
            sed -i '' 's/# rust: "stable"/rust: "stable"/' "${config_file}"
            sed -i '' 's/memory: 4096/memory: 8192/' "${config_file}"
            ;;
        fullstack)
            log_info "Applying Fullstack preset"
            sed -i '' 's/# python: "3.12"/python: "3.12"/' "${config_file}"
            sed -i '' 's/memory: 4096/memory: 8192/' "${config_file}"
            ;;
        *)
            log_error "Unknown preset: ${preset}"
            log_error "Available: node, python, go, rust, fullstack"
            exit 1
            ;;
    esac
}
