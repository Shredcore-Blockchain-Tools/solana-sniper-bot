# shredcore-sniper

A high-performance Solana token sniper bot written in Rust for maximum efficiency. This bot automatically detects and trades new token launches and migrations on PumpFun and PumpSwap platforms.

## Why Rust?

This bot is written in Rust, a systems programming language known for its exceptional performance, memory safety, and low latency. Rust's zero-cost abstractions and efficient execution make it ideal for high-frequency trading where every millisecond counts. The bot can process market events and execute trades faster than bots written in interpreted languages, giving you a competitive edge in the fast-paced world of token sniping.

## Performance

This is one of the **speediest bot on the market**. With optimal server, RPC, and gRPC provider configuration, the bot can achieve **0 to 3 blocks landing speed** after signal detection. This exceptional speed gives you a significant advantage in competitive token sniping scenarios where being first to market can make all the difference.

## Durable Nonce Technology

This bot uses **Durable Nonce** technology, which is essential for its operation. Here's why:

When trading at high speeds, the bot sends the same transaction to multiple SWQoS (Solana Quality of Service) providers simultaneously - including Jito, Nozomi (Temporal), and Astralane. This "spam sending" strategy dramatically improves transaction inclusion speed and success rates by ensuring your transaction reaches validators through multiple paths.

However, without durable nonces, sending the same transaction to multiple providers could result in duplicate executions if multiple providers include it in the same block. Durable nonces solve this by ensuring each transaction can only be executed once, even if it's submitted through multiple channels. This allows the bot to safely spam transactions to all available SWQoS providers for maximum speed and inclusion probability, while preventing accidental double-spends.

## Supported Platforms

- **PumpFun** - The original bonding curve platform
- **PumpSwap** - After migration from bonding curves
... Many more to come

## Features

### Core Sniper Capabilities

- **Launch Sniping**: Automatically detects and trades new token launches from specific deployer wallets you configure
- **Migration Sniping**: Monitors for tokens migrating from bonding curves to Raydium and can automatically enter or exit
- **Deployer Wallet Monitoring**: Track specific wallet addresses that deploy tokens you want to snipe
- **Platform Filtering**: Skip tokens from Mayhem Token or PumpFun Classic platforms if desired

### Risk Management

- **Stop Loss**: Automatically sell if your position drops below a configured loss percentage
- **Take Profit Levels**: Set multiple profit targets with partial sell percentages (e.g., sell 50% at 50% profit, then 100% at 100% profit)
- **Dynamic Trailing Stop Loss (DTSL)**: As your profit increases, the stop loss floor automatically raises to lock in gains
- **Time-Based Exits**: Force exits after maximum hold time, negative PnL duration, or minimum profit target duration
- **Bonding Curve Dump**: Automatically exit when bonding curve reaches a certain completion percentage
- **Migration Dump**: Automatically exit when token migrates to Raydium

### Advanced Trading Features

- **Dollar Cost Averaging (DCA)**: Automatically add to losing positions to average down your entry price
- **Position Limits**: Control maximum concurrent positions to manage risk
- **Portfolio Exposure Limits**: Limit total capital deployed across all positions
- **Simulation Mode**: Test strategies without risking real SOL

### Execution Features

- **SWQoS Integration**: Simultaneously sends transactions to multiple providers (Jito, Nozomi, Astralane) for maximum inclusion speed
- **Priority Fees**: Configurable fees to encourage faster validator inclusion
- **High Slippage Tolerance**: Configured for aggressive entry/exit to ensure trades execute
- **Transaction Retries**: Automatic retry logic for failed transactions
- **Real-Time Market Data**: Uses gRPC (Yellowstone) or WebSocket streams for instant market updates

## Setup and Installation

### Prerequisites

- Solana CLI tools (for nonce setup)
- A Solana wallet with SOL for trading
- A license key
- RPC endpoint (high-performance private RPC recommended)
- gRPC endpoint (Yellowstone gRPC) or WebSocket endpoint

### Quick Start

1. **Configure the bot**:
   ```bash
   ./start.sh
   ```
   
   The interactive setup script will guide you through:
   - License key entry
   - RPC and gRPC/WebSocket URL configuration
   - Wallet private key (Base58 encoded)
   - Sniper mode selection (launch or migration)
   - Deployer wallet addresses to monitor

2. **Setup Durable Nonce**:
   The setup script automatically runs `setup_nonce.sh` if no nonce account exists. This creates a durable nonce account that's required for safe multi-provider transaction sending.

3. **Launch the bot**:
   ```bash
   ./start.sh
   ```
   
   Or if you've already configured:
   ```bash
   ./rust-sniper
   ```

### Manual Configuration

If you prefer to configure manually:

1. Copy the example config:
   ```bash
   cp config.example.toml config.toml
   ```

2. Edit `config.toml` with your settings:
   - `LICENSE_KEY`: Your license key
   - `RPC_URL`: Your Solana RPC endpoint
   - `GRPC_URL`: Your Yellowstone gRPC endpoint (if using gRPC)
   - `WALLET_PRIVATE_KEY_B58`: Your wallet private key in Base58 format
   - `SNIPE_MODE`: "launch" or "migration"
   - `SNIPE_DEPLOYER_WALLETS`: Array of deployer wallet addresses to monitor
   - Adjust trading parameters (buy amounts, stop loss, take profit, etc.)

3. Setup durable nonce:
   ```bash
   ./setup_nonce.sh
   ```

4. Run the bot:
   ```bash
   ./rust-sniper
   ```

### Configuration File

The `config.toml` file contains all bot settings organized into sections:

- `[config]`: Connection settings, wallet, license, and nonce configuration
- `[trading]`: Trading parameters, risk management, and sniper-specific settings

See `config.example.toml` for detailed comments on each setting.

## Usage

### Normal Operation

Simply run `./start.sh` or `./rust-sniper` and the bot will:
1. Connect to market data streams
2. Monitor for new token launches from your configured deployer wallets
3. Automatically execute buy orders when opportunities are detected
4. Manage positions with your configured risk management rules
5. Execute sells based on stop loss, take profit, or time-based rules

### Command Line Interface

You can also manually trigger trades:

**Buy a specific token**:
```bash
./rust-sniper --buy <MINT_ADDRESS> [--platform PUMP_FUN|PUMP_SWAP]
```

**Sell a position**:
```bash
./rust-sniper --sell <MINT_ADDRESS>
```

### Logs

Logs are saved to `.logs/rust-sniper.log` by default (can be disabled in config). Monitor this file to track bot activity, trades, and any issues.

## Important Notes

- **Durable Nonce is Required**: The bot requires a durable nonce account for safe operation with multiple SWQoS providers. The setup script handles this automatically.

- **High-Performance RPC Recommended**: For best results, use a private, high-performance RPC endpoint. Public RPCs may have rate limits and higher latency.

- **Wallet Security**: Never share your `WALLET_PRIVATE_KEY_B58`. Keep your `config.toml` file secure and never commit it to version control.

- **Start with Small Amounts**: When first using the bot, start with small `BUY_AMOUNT_SOL` values to test your configuration.

- **Simulation Mode**: Use `SIMULATE = true` in your config to test without risking real SOL.

## Troubleshooting

- **"Durable nonce file not found"**: Run `./setup_nonce.sh` manually
- **"License validation failed"**: Check your `LICENSE_KEY` in config.toml
- **"Failed to create trade-stream client"**: Verify your `GRPC_URL` or `WS_URL` is correct
- **Transactions failing**: Check your wallet has sufficient SOL for trades and fees
- **No trades executing**: Verify deployer wallets are correct and tokens are being launched

## Support

For issues, questions, or feature requests, please contact support through your license provider.

