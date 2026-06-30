---
title: MCP Server
nav_order: 6
parent: Reference
---

# MCP Server

The SDK ships with a built-in MCP (Model Context Protocol) server that exposes core BSV operations as tools for AI assistants such as Claude Code.

## Setup

### Claude Code

Add the server to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "bsv-sdk": {
      "command": "bundle",
      "args": ["exec", "bsv-mcp"],
      "cwd": "/path/to/your/project"
    }
  }
}
```

The `bsv-mcp` executable is installed automatically when the gem is bundled.

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or the equivalent on your platform:

```json
{
  "mcpServers": {
    "bsv-sdk": {
      "command": "bundle",
      "args": ["exec", "bsv-mcp"],
      "cwd": "/path/to/your/project"
    }
  }
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `generate_key` | Generate a new random BSV keypair (WIF + public key hex + address) |
| `decode_tx` | Parse and inspect a raw transaction hex string |
| `fetch_utxos` | Fetch UTXOs for an address from WhatsOnChain |
| `fetch_tx` | Fetch a full transaction by txid from WhatsOnChain |
| `check_balance` | Check the balance of an address or WIF private key |
| `broadcast_p2pkh` | Build, sign, and broadcast a P2PKH payment |

## Configuration

The server reads configuration from environment variables at startup:

| Variable | Default | Description |
|----------|---------|-------------|
| `BSV_NETWORK` | `main` | Network: `main` or `test` |
| `BSV_ARC_URL` | GorillaPool Arcade | Custom ARC endpoint URL |
| `BSV_ARC_API_KEY` | *(none)* | ARC API key for authenticated access |

### Testnet

Set `BSV_NETWORK=test` to target testnet for all network operations:

```json
{
  "mcpServers": {
    "bsv-sdk": {
      "command": "bundle",
      "args": ["exec", "bsv-mcp"],
      "cwd": "/path/to/your/project",
      "env": {
        "BSV_NETWORK": "test"
      }
    }
  }
}
```

Individual tools also accept a `network` parameter to override the server default on a per-call basis.

## Example Workflows

### Inspect a transaction

Ask your AI assistant:

> Decode this transaction hex and explain what it does:
> `0100000001...`

The assistant will call `decode_tx` and receive a structured breakdown of inputs, outputs, script types, and amounts.

### Check a balance

> What is the balance of address `1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa`?

The assistant calls `check_balance`, which queries WhatsOnChain and returns the total balance and individual UTXOs.

### Generate a key

> Generate a new BSV key for testnet.

The assistant calls `generate_key` with `network: testnet`. The WIF is returned in the response — it is never stored by the server. Store it securely immediately.

### Send a payment (testnet)

> Send 1000 satoshis from WIF `cNbVuq...` to address `mtest...` on testnet.

The assistant calls `broadcast_p2pkh`, which fetches UTXOs, builds and signs the transaction, and broadcasts it via ARC. The txid is returned on success.

**Important:** `broadcast_p2pkh` spends real satoshis. Always confirm the network and amounts before authorising the call.

## Security Considerations

- WIF private keys are passed in tool arguments. They are used only within the call and are never persisted by the server, but they do appear in MCP request logs. Use testnet keys for experimentation.
- The server runs locally over stdio. There is no network exposure — MCP communication happens entirely within the process boundary.
- `broadcast_p2pkh` performs real network operations. On mainnet this spends real funds; on testnet it uses testnet coins only.
