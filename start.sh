#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# rust-sniper start.sh
# Interactive setup and launch script for the Solana sniper bot.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="config.toml"
CONFIG_EXAMPLE="config.example.toml"
NONCE_FILE=".durable_nonce.json"
NONCE_SCRIPT="setup_nonce.sh"
BINARY_NAME="shredcore-sniper-bot"

# GitHub repository URL for auto-updates (set this for public releases)
REPO_URL="https://github.com/Shredcore-Blockchain-Tools/solana-sniper-bot.git"

# ============================================================================
# Git Auto-Update System
# ============================================================================

# Ensure git is installed, install if missing
ensure_git() {
    if command -v git &>/dev/null; then
        return 0
    fi
    
    echo ""
    echo "Git is not installed. Installing git..."
    
    # Detect package manager and install git
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq git
    elif command -v yum &>/dev/null; then
        sudo yum install -y -q git
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y -q git
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm git
    elif command -v apk &>/dev/null; then
        sudo apk add --quiet git
    elif command -v brew &>/dev/null; then
        brew install git
    else
        echo "ERROR: Could not detect package manager to install git." >&2
        echo "Please install git manually and run this script again." >&2
        return 1
    fi
    
    if command -v git &>/dev/null; then
        echo "Git installed successfully."
        return 0
    else
        echo "ERROR: Git installation failed." >&2
        return 1
    fi
}

# Setup git repository if downloaded via zip (no .git folder)
setup_git_repo() {
    # Skip if already a git repo
    if [[ -d ".git" ]]; then
        return 0
    fi
    
    # Skip if no repo URL configured
    if [[ -z "${REPO_URL:-}" ]]; then
        return 0
    fi
    
    echo ""
    echo "Initializing git repository for auto-updates..."
    
    # Disable all credential prompts (public repos don't need auth)
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=""
    export GIT_SSH_COMMAND="ssh -oBatchMode=yes"
    
    # Initialize git repo with main as default branch
    git init -q -b main 2>/dev/null || git init -q
    
    # Add origin remote
    git remote add origin "$REPO_URL"
    
    # Fetch from remote (try main first, then master)
    local remote_branch="main"
    if ! git -c credential.helper= fetch origin main 2>/dev/null; then
        if ! git -c credential.helper= fetch origin master 2>/dev/null; then
            echo "Warning: Could not fetch from remote. Auto-updates may not work."
            return 0
        fi
        remote_branch="master"
    fi
    
    # Checkout the fetched branch as main locally
    git checkout -b main "origin/${remote_branch}" 2>/dev/null || \
    git checkout main 2>/dev/null || \
    git checkout -B main "origin/${remote_branch}" 2>/dev/null || true
    
    # Reset to match remote (preserves local files not in repo)
    git reset --mixed "origin/${remote_branch}" 2>/dev/null || true
    
    echo "Git repository initialized."
}

# Auto-update from git repository
auto_update() {
    # Skip if no repo URL configured
    if [[ -z "${REPO_URL:-}" ]]; then
        return 0
    fi
    
    # Ensure git is available
    if ! ensure_git; then
        echo "Warning: Cannot check for updates without git."
        return 0
    fi
    
    # Disable all credential prompts (public repos don't need auth)
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=""
    export GIT_SSH_COMMAND="ssh -oBatchMode=yes"
    
    # Setup git repo if needed (for zip downloads)
    setup_git_repo
    
    # Skip if still not a git repo
    if [[ ! -d ".git" ]]; then
        return 0
    fi
    
    # Ensure origin remote matches REPO_URL (for users upgrading from older releases)
    if [[ -n "${REPO_URL:-}" ]]; then
        if git remote get-url origin &>/dev/null; then
            current_url=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ "$current_url" != "$REPO_URL" ]]; then
                git -c credential.helper= remote set-url origin "$REPO_URL" 2>/dev/null || true
            fi
        else
            git remote add origin "$REPO_URL" 2>/dev/null || true
        fi
    fi
    
    echo ""
    echo "=== Checking for updates ==="
    
    # Fetch latest changes
    if ! git -c credential.helper= fetch origin 2>/dev/null; then
        echo "Warning: Could not fetch updates. Continuing with current version."
        return 0
    fi
    
    # Determine which remote branch to use (prefer main, fallback to master)
    local remote_branch=""
    if git rev-parse "origin/main" &>/dev/null; then
        remote_branch="main"
    elif git rev-parse "origin/master" &>/dev/null; then
        remote_branch="master"
    else
        echo "Warning: No remote branch (main or master) found."
        return 0
    fi
    
    # Ensure we're on main branch locally
    git checkout main 2>/dev/null || git checkout -b main "origin/${remote_branch}" 2>/dev/null || true
    
    # Check if there are updates
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
    remote_commit=$(git rev-parse "origin/${remote_branch}" 2>/dev/null || echo "")
    
    if [[ -z "$local_commit" ]] || [[ -z "$remote_commit" ]]; then
        echo "Warning: Could not determine commit status."
        return 0
    fi
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        echo "Bot is up to date."
        return 0
    fi
    
    echo "Updates available. Updating..."
    
    # Pull updates
    if git -c credential.helper= pull origin "$remote_branch" 2>/dev/null; then
        echo ""
        echo "=== Update successful! ==="
        
        # Show recent changes
        echo ""
        echo "Recent changes:"
        echo "----------------------------------------"
        git log --oneline "${local_commit}..HEAD" 2>/dev/null | head -3
        echo "----------------------------------------"
        
        # Ensure binaries and scripts are executable
        chmod +x "$BINARY_NAME" 2>/dev/null || true
        chmod +x "$0" 2>/dev/null || true
        chmod +x "$NONCE_SCRIPT" 2>/dev/null || true
    else
        echo "Warning: Update failed. Continuing with current version."
    fi
}

# ============================================================================
# TOML Editing Helpers
# ============================================================================

# Escape special characters for sed replacement
escape_sed() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g' -e 's/"/\\"/g'
}

# Escape special characters for TOML string values
escape_toml_string() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Set a TOML string value: KEY = "VALUE"
set_toml_string() {
    local key="$1"
    local value="$2"
    local escaped_value
    escaped_value=$(escape_toml_string "$value")
    
    if ! grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
        echo "ERROR: Key '$key' not found in $CONFIG_FILE" >&2
        return 1
    fi
    
    sed -i -E "s|^([[:space:]]*)${key}[[:space:]]*=.*|\1${key} = \"${escaped_value}\"|" "$CONFIG_FILE"
}

# Set a TOML boolean value: KEY = true/false
set_toml_bool() {
    local key="$1"
    local value="$2"
    
    if ! grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
        echo "ERROR: Key '$key' not found in $CONFIG_FILE" >&2
        return 1
    fi
    
    sed -i -E "s|^([[:space:]]*)${key}[[:space:]]*=.*|\1${key} = ${value}|" "$CONFIG_FILE"
}

# Set a TOML integer value: KEY = VALUE
set_toml_int() {
    local key="$1"
    local value="$2"
    
    if ! grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
        echo "ERROR: Key '$key' not found in $CONFIG_FILE" >&2
        return 1
    fi
    
    sed -i -E "s|^([[:space:]]*)${key}[[:space:]]*=.*|\1${key} = ${value}|" "$CONFIG_FILE"
}

# Set a TOML inline string array from comma-separated input
# Usage: set_toml_string_array KEY "item1,item2,item3"
set_toml_string_array() {
    local key="$1"
    local csv="$2"
    local array_content=""
    
    if [[ -n "$csv" ]]; then
        IFS=',' read -ra items <<< "$csv"
        local first=true
        for item in "${items[@]}"; do
            # Trim whitespace
            item=$(echo "$item" | xargs)
            if [[ -n "$item" ]]; then
                local escaped_item
                escaped_item=$(escape_toml_string "$item")
                if $first; then
                    array_content="\"${escaped_item}\""
                    first=false
                else
                    array_content="${array_content}, \"${escaped_item}\""
                fi
            fi
        done
    fi
    
    # Use awk to replace the array (handles multi-line arrays)
    awk -v key="$key" -v content="$array_content" '
    BEGIN { in_array = 0; found = 0 }
    {
        if (match($0, "^[[:space:]]*" key "[[:space:]]*=")) {
            found = 1
            # Check if this is a single-line array
            if (match($0, /\]$/)) {
                print key " = [" content "]"
                next
            }
            # Multi-line array starts here
            in_array = 1
            print key " = [" content "]"
            next
        }
        if (in_array) {
            # Skip lines until we find the closing bracket
            if (match($0, /^[[:space:]]*\]/)) {
                in_array = 0
                next
            }
            # Skip array content lines
            next
        }
        print
    }
    END { if (!found) { print "ERROR: Key " key " not found" > "/dev/stderr"; exit 1 } }
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

# ============================================================================
# Prompt Helpers
# ============================================================================

# Prompt for a required (non-empty) value
prompt_required() {
    local prompt_text="$1"
    local var_name="$2"
    local value=""
    
    while [[ -z "$value" ]]; do
        read -rp "$prompt_text: " value
        if [[ -z "$value" ]]; then
            printf "This field is required. Please enter a value.\n" >/dev/tty
        fi
    done
    
    eval "$var_name=\"\$value\""
}

# Prompt for an optional value with a default
prompt_optional() {
    local prompt_text="$1"
    local default_value="$2"
    local var_name="$3"
    local value=""
    
    read -rp "$prompt_text [$default_value]: " value
    if [[ -z "$value" ]]; then
        value="$default_value"
    fi
    
    eval "$var_name=\"\$value\""
}

# Prompt for a selection from numbered options
# Returns the selected value (not the number)
prompt_selection() {
    local prompt_text="$1"
    shift
    local options=("$@")
    local choice=""
    
    # Print to /dev/tty so it's always visible when function is called in subshell
    printf "%s\n" "$prompt_text" >/dev/tty
    for i in "${!options[@]}"; do
        printf "  [%d] %s\n" $((i+1)) "${options[$i]}" >/dev/tty
    done
    printf "\n" >/dev/tty
    
    while true; do
        read -rp "Select option (1-${#options[@]}): " choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        printf "Invalid choice. Please enter a number between 1 and %d.\n" "${#options[@]}" >/dev/tty
    done
}

# ============================================================================
# Base Configuration (shared across all bots)
# ============================================================================

configure_base_config() {
    echo ""
    echo "=== Base Configuration ==="
    echo ""
    
    # License Key (required)
    local license_key
    prompt_required "Enter your license key" license_key
    set_toml_string "LICENSE_KEY" "$license_key"
    
    # RPC URL (required)
    local rpc_url
    prompt_required "Enter RPC URL" rpc_url
    set_toml_string "RPC_URL" "$rpc_url"
    
    # Stream Transport
    echo ""
    local transport
    transport=$(prompt_selection "Select stream transport mode:" "gRPC (recommended)" "WebSocket")
    
    if [[ "$transport" == "gRPC (recommended)" ]]; then
        set_toml_string "STREAM_TRANSPORT" "grpc"
        
        # gRPC URL (required)
        local grpc_url
        prompt_required "Enter gRPC URL" grpc_url
        set_toml_string "GRPC_URL" "$grpc_url"
        
        # gRPC Token (optional)
        local grpc_token
        read -rp "Enter gRPC token (optional, press Enter to skip): " grpc_token
        if [[ -n "$grpc_token" ]]; then
            set_toml_string "GRPC_TOKEN" "$grpc_token"
        fi
    else
        set_toml_string "STREAM_TRANSPORT" "ws"
        
        # WebSocket URL (required)
        local ws_url
        prompt_required "Enter WebSocket URL" ws_url
        set_toml_string "WS_URL" "$ws_url"
    fi
    
    # Wallet Private Key (required)
    echo ""
    local wallet_key
    prompt_required "Enter wallet private key (Base58)" wallet_key
    set_toml_string "WALLET_PRIVATE_KEY_B58" "$wallet_key"
    
    # Preferred Region (optional with default)
    local region
    prompt_optional "Enter preferred region (NewYork, Frankfurt, Amsterdam, SLC, Tokyo, London, LosAngeles, Default)" "NewYork" region
    set_toml_string "PREFERRED_REGION" "$region"
}

# ============================================================================
# Sniper-Specific Configuration
# ============================================================================

configure_sniper_config() {
    echo ""
    echo "=== Sniper Configuration ==="
    echo ""
    
    # Snipe Mode
    local snipe_mode
    snipe_mode=$(prompt_selection "Select snipe mode:" "launch" "migration")
    set_toml_string "SNIPE_MODE" "$snipe_mode"
    
    # Deployer Wallets (only for launch mode)
    if [[ "$snipe_mode" == "launch" ]]; then
        echo ""
        echo "Enter deployer wallet addresses to monitor (comma-separated)."
        echo "These are the wallets that will deploy tokens you want to snipe."
        local deployer_wallets
        prompt_required "Deployer wallets" deployer_wallets
        set_toml_string_array "SNIPE_DEPLOYER_WALLETS" "$deployer_wallets"
    fi
    
    echo ""
    echo "Sniper configuration complete!"
    echo "You can tune advanced settings (stop loss, DTSL, DCA, etc.) in config.toml"
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    echo "========================================"
    echo "  shredcore-sniper-bot Start Script"
    echo "========================================"
    
    # Auto-update from git repository
    auto_update
    
    # Check if config.toml exists
    if [[ -f "$CONFIG_FILE" ]]; then
        echo ""
        echo "Config file found: $CONFIG_FILE"
        echo "Using existing configuration. Edit config.toml directly to make changes."
    else
        # Check for config.example.toml
        if [[ ! -f "$CONFIG_EXAMPLE" ]]; then
            echo "ERROR: $CONFIG_EXAMPLE not found. Cannot initialize configuration." >&2
            exit 1
        fi
        
        echo ""
        echo "No config.toml found. Creating from $CONFIG_EXAMPLE..."
        if ! cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"; then
            echo "ERROR: Failed to copy $CONFIG_EXAMPLE to $CONFIG_FILE" >&2
            exit 1
        fi
        
        echo "Running interactive configuration..."
        configure_base_config
        configure_sniper_config
        
        echo ""
        echo "Configuration saved to $CONFIG_FILE"
    fi
    
    # Durable nonce setup
    if [[ ! -f "$NONCE_FILE" ]]; then
        echo ""
        echo "Durable nonce file not found. Running setup..."
        
        if [[ ! -x "$NONCE_SCRIPT" ]]; then
            if [[ -f "$NONCE_SCRIPT" ]]; then
                chmod +x "$NONCE_SCRIPT"
            else
                echo "ERROR: $NONCE_SCRIPT not found. Cannot setup durable nonce." >&2
                exit 1
            fi
        fi
        
        if ! ./"$NONCE_SCRIPT"; then
            echo "ERROR: Durable nonce setup failed." >&2
            exit 1
        fi
    fi
    
    # Set environment variables
    export BOT_CONFIG="./config.toml"
    export RUST_LOG="${RUST_LOG:-info,h2=warn,hyper=warn,rustls=warn,tungstenite=warn,reqwest=warn}"
    
    # Check for binary
    if [[ ! -x "$BINARY_NAME" ]]; then
        if [[ -f "$BINARY_NAME" ]]; then
            chmod +x "$BINARY_NAME"
        else
            echo ""
            echo "ERROR: Binary ./$BINARY_NAME not found." >&2
            echo "Build it with: cargo build --release" >&2
            echo "Then copy or symlink the binary here." >&2
            exit 1
        fi
    fi
    
    # Launch the bot
    echo ""
    echo "Starting $BINARY_NAME..."
    echo "========================================"
    exec ./"$BINARY_NAME"
}

main "$@"

