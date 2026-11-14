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
| `BSV_NETWORK` | `mainnet` | Network: `mainnet` or `testnet`. The aliases `main` and `test` are also accepted. Any other value stops the server with an error. |
| `BSV_ARC_URL` | *(none)* | Base URL of a classic ARC endpoint, for example `https://arc.taal.com`. The SDK appends `/v1/tx`, so give the base URL without `/v1`. Must be `https` (plain `http` is accepted only for a localhost or loopback host). |
| `BSV_ARC_API_KEY` | *(none)* | API key sent as a bearer token to `BSV_ARC_URL` only. |

Blank values count as unset.

`BSV_NETWORK` applies to every network-aware tool, unless the call passes its own `network` parameter.

`BSV_ARC_URL` is used only for broadcasts on the server's `BSV_NETWORK`. A call that passes the other network uses that network's default broadcaster. Without `BSV_ARC_URL`, `broadcast_p2pkh` uses the GorillaPool provider's broadcaster.

`BSV_ARC_API_KEY` is ignored, with a warning, when `BSV_ARC_URL` is not set, and is never sent to the default broadcaster.

### Testnet

Set `BSV_NETWORK=testnet` to target testnet for all network operations:

```json
{
  "mcpServers": {
    "bsv-sdk": {
      "command": "bundle",
      "args": ["exec", "bsv-mcp"],
      "cwd": "/path/to/your/project",
      "env": {
        "BSV_NETWORK": "testnet"
      }
    }
  }
}
```

Individual tools also accept a `network` parameter to override the server default on a per-call basis.

To broadcast through your own ARC endpoint, add `BSV_ARC_URL` (and, if the endpoint needs one, `BSV_ARC_API_KEY`) to the same `env` block.

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

The assistant calls `broadcast_p2pkh`, which fetches UTXOs, builds and signs the transaction, and broadcasts it. On success it returns the txid it computed, the service's `txStatus` and the raw transaction hex.

A status such as `RECEIVED` or `STORED` means the service has accepted the submission, not that the network has accepted the transaction. A 2xx response carrying a rejected status, or a txid that differs from the computed one, is reported as an error. The tool also rejects a recipient that is not a P2PKH address for the call's network (P2SH addresses included), and a WIF for the other network.

**Important:** `broadcast_p2pkh` spends real satoshis. Always confirm the network and amounts before authorising the call.

## Security Considerations

- WIF private keys are passed in tool arguments. They are used only within the call and are never persisted by the server, but they do appear in MCP request logs. Use testnet keys for experimentation.
- The server runs locally over stdio and accepts no inbound connections, but the tools make outbound HTTPS calls: to WhatsOnChain for UTXOs, transactions and balances, and to the broadcaster for `broadcast_p2pkh`.
- `BSV_ARC_API_KEY` is sent only to `BSV_ARC_URL`, which must be `https` (except for localhost), and never to the default broadcaster.
- `broadcast_p2pkh` performs real network operations. On mainnet this spends real funds; on testnet it uses testnet coins only.
