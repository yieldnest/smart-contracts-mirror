# How to download verified smart contract source code

Try these methods in order. Prefer Sourcify (no API key needed) and Etherscan (most complete coverage).

## 1. Sourcify (preferred — no API key needed)

```bash
# Full match (exact metadata match)
curl "https://sourcify.dev/server/files/1/0xCONTRACT_ADDRESS"

# Partial match (bytecode matches but metadata may differ)
curl "https://sourcify.dev/server/files/any/1/0xCONTRACT_ADDRESS"
```

Returns all source files if the contract is verified on Sourcify. Replace `1` with the chain ID (1=Ethereum, 10=Optimism, 137=Polygon, 42161=Arbitrum, 8453=Base, etc.).

No API key required. Try this first.

## 2. Etherscan API v2 (best coverage)

**Note:** Etherscan API v1 is deprecated and will not work. Use v2 instead.

```bash
# Get verified source code via API v2
curl "https://api.etherscan.io/v2/api?chainid=1&module=contract&action=getsourcecode&address=0xCONTRACT_ADDRESS&apikey=YOUR_API_KEY"
```

The response JSON contains `SourceCode`, `ContractName`, `CompilerVersion`, and `ABI`. For multi-file contracts, `SourceCode` is a JSON object with all source files.

In v2, use a single base URL (`api.etherscan.io/v2/api`) and specify the chain via `chainid`:
- Ethereum: `chainid=1`
- Arbitrum: `chainid=42161`
- Base: `chainid=8453`
- Polygon: `chainid=137`
- Optimism: `chainid=10`

## 3. Foundry's `forge` (best for full project structure)

```bash
# Download source + metadata into a directory
forge clone 0xCONTRACT_ADDRESS --etherscan-api-key YOUR_API_KEY

# For non-Ethereum chains
forge clone 0xCONTRACT_ADDRESS --chain base --etherscan-api-key YOUR_API_KEY
```

This reconstructs the full Foundry project structure with sources, remappings, and compiler settings. Best option when you need a compilable project.

## 4. Blockscout API (fallback)

```bash
curl "https://eth.blockscout.com/api?module=contract&action=getsourcecode&address=0xCONTRACT_ADDRESS"
```

Same API format as Etherscan, no API key required for most Blockscout instances. Use as a fallback if Sourcify and Etherscan don't have the contract.

## Recommendation

1. **Start with Sourcify** — no API key, fast, and supports many chains
2. **Fall back to Etherscan** — broadest coverage of verified contracts
3. **Use `forge clone`** when you need a full compilable project for running `slither`, `mythril`, or other analysis tools
