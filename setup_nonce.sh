#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NONCE_FILE=".durable_nonce.json"
CONFIG_FILE="config.toml"

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Ensure dependencies
command -v solana &>/dev/null || error "Solana CLI not installed"
command -v python3 &>/dev/null || error "Python3 not installed"

# Install base58 if needed
python3 -c "import base58" 2>/dev/null || {
    info "Installing Python base58 (may take a moment)..."
    
    # Try apt package first (fastest)
    if apt-get install -y python3-base58 >/dev/null 2>&1; then
        info "Installed via apt"
    # Try pipx
    elif command -v pipx &>/dev/null && pipx install base58 >/dev/null 2>&1; then
        info "Installed via pipx"
    # Install pip then base58
    else
        apt-get update >/dev/null 2>&1
        apt-get install -y python3-pip >/dev/null 2>&1
        python3 -m pip install --break-system-packages base58 >/dev/null 2>&1 || \
        python3 -m pip install base58 >/dev/null 2>&1 || \
        error "Failed to install base58. Run manually: apt-get install python3-pip && pip3 install base58"
    fi
    
    # Verify
    python3 -c "import base58" 2>/dev/null || error "base58 still not available after install"
    info "base58 installed successfully"
}

# Parse config
[[ -f "$CONFIG_FILE" ]] || error "Config file $CONFIG_FILE not found"

RPC_URL=$(grep -E "^RPC_URL\s*=" "$CONFIG_FILE" | head -1 | sed -E 's/^[^=]*=\s*"([^"]+)".*/\1/')
WALLET_KEY_B58=$(grep -E "^WALLET_PRIVATE_KEY_B58\s*=" "$CONFIG_FILE" | head -1 | sed -E 's/^[^=]*=\s*"([^"]+)".*/\1/')
EXISTING_NONCE=$(grep -E "^DURABLE_NONCE_PUBKEY\s*=" "$CONFIG_FILE" | head -1 | sed -E 's/^[^=]*=\s*"([^"]*)".*/\1/' || echo "")

[[ -n "$RPC_URL" ]] || error "RPC_URL not found in config"
[[ -n "$WALLET_KEY_B58" ]] || error "WALLET_PRIVATE_KEY_B58 not found in config"

info "RPC: $RPC_URL"
info "Wallet key: ${WALLET_KEY_B58:0:10}..."

# Create wallet keypair file from base58
WALLET_KEYPAIR=$(mktemp)
trap "rm -f $WALLET_KEYPAIR" EXIT

python3 -c "
import base58, json
key = base58.b58decode('$WALLET_KEY_B58')
print(json.dumps(list(key)))
" > "$WALLET_KEYPAIR" || error "Failed to decode wallet key"

WALLET_PUBKEY=$(solana-keygen pubkey "$WALLET_KEYPAIR")
info "Wallet pubkey: $WALLET_PUBKEY"

# Check if nonce file exists and verify ownership
if [[ -f "$NONCE_FILE" ]]; then
    FILE_NONCE=$(python3 -c "import json; print(json.load(open('$NONCE_FILE')).get('nonce_account',''))" 2>/dev/null || echo "")
    if [[ -n "$FILE_NONCE" ]]; then
        info "Found existing nonce in file: $FILE_NONCE"
        
        # Check if it exists on-chain
        if solana account "$FILE_NONCE" --url "$RPC_URL" &>/dev/null; then
            # Get authority using nonce-account command
            NONCE_AUTH=$(solana nonce-account "$FILE_NONCE" --url "$RPC_URL" 2>/dev/null | grep -i "Authority:" | awk '{print $2}' || echo "")
            
            if [[ "$NONCE_AUTH" == "$WALLET_PUBKEY" ]]; then
                info "Nonce account exists and belongs to this wallet"
                info "Done! Nonce pubkey: $FILE_NONCE"
                exit 0
            else
                warn "Nonce account belongs to different wallet (authority: $NONCE_AUTH)"
                echo ""
                read -p "Create new nonce account? [y/N]: " choice
                [[ "$choice" =~ ^[Yy]$ ]] || exit 0
            fi
        else
            warn "Nonce account $FILE_NONCE doesn't exist on-chain"
        fi
    fi
fi

# Check existing config nonce
if [[ -n "$EXISTING_NONCE" ]]; then
    info "Found DURABLE_NONCE_PUBKEY in config: $EXISTING_NONCE"
    if solana account "$EXISTING_NONCE" --url "$RPC_URL" &>/dev/null; then
        NONCE_AUTH=$(solana nonce-account "$EXISTING_NONCE" --url "$RPC_URL" 2>/dev/null | grep -i "Authority:" | awk '{print $2}' || echo "")
        if [[ "$NONCE_AUTH" == "$WALLET_PUBKEY" ]]; then
            # Save to file and done
            echo "{\"nonce_account\": \"$EXISTING_NONCE\", \"seed\": \"manual\"}" > "$NONCE_FILE"
            info "Done! Using existing nonce: $EXISTING_NONCE"
            exit 0
        else
            warn "Config nonce belongs to different wallet"
            echo ""
            read -p "Create new nonce account? [y/N]: " choice
            [[ "$choice" =~ ^[Yy]$ ]] || exit 0
        fi
    fi
fi

# Create new nonce account
info "Creating new nonce account..."

# Check balance
BALANCE=$(solana balance "$WALLET_PUBKEY" --url "$RPC_URL" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' || echo "0")
info "Wallet balance: $BALANCE SOL"

# Create nonce keypair
NONCE_KEYPAIR=$(mktemp)
trap "rm -f $WALLET_KEYPAIR $NONCE_KEYPAIR" EXIT

solana-keygen new --no-bip39-passphrase --outfile "$NONCE_KEYPAIR" --force &>/dev/null
NONCE_PUBKEY=$(solana-keygen pubkey "$NONCE_KEYPAIR")
info "New nonce pubkey: $NONCE_PUBKEY"

# Create nonce account on-chain
info "Submitting transaction..."
solana create-nonce-account "$NONCE_KEYPAIR" 0.0015 \
    --nonce-authority "$WALLET_KEYPAIR" \
    --url "$RPC_URL" \
    --keypair "$WALLET_KEYPAIR" \
    || error "Failed to create nonce account"

info "Nonce account created!"

# Save to file
echo "{\"nonce_account\": \"$NONCE_PUBKEY\", \"seed\": \"generated\"}" > "$NONCE_FILE"
info "Saved to $NONCE_FILE"

# Update config
if grep -qE "^DURABLE_NONCE_PUBKEY\s*=" "$CONFIG_FILE"; then
    sed -i "s|^DURABLE_NONCE_PUBKEY\s*=.*|DURABLE_NONCE_PUBKEY = \"$NONCE_PUBKEY\"|" "$CONFIG_FILE"
else
    sed -i "/^\[trading\]/i DURABLE_NONCE_PUBKEY = \"$NONCE_PUBKEY\"" "$CONFIG_FILE"
fi
info "Updated $CONFIG_FILE"

info "Done! Nonce pubkey: $NONCE_PUBKEY"
