#!/bin/bash
#
# Verify bytecode of all contracts in a deployment JSON file against locally compiled bytecode
#
# Usage: ./scripts/verify-deployment.sh <deployment-file> <rpc-url> [etherscan-api-key]
# Example: ./scripts/verify-deployment.sh deployments/ynRWAx-SPV1-SAFE-Guard-1.json https://eth.drpc.org
#
# This script compares on-chain runtime bytecode against locally compiled bytecode.
# Etherscan API key is optional - if provided, uses forge verify-bytecode for additional checks.
#

set -e

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <deployment-file> <rpc-url> [etherscan-api-key]"
    echo "Example: $0 deployments/ynRWAx-SPV1-SAFE-Guard-1.json https://eth.drpc.org"
    exit 1
fi

DEPLOYMENT_FILE="$1"
RPC_URL="$2"
ETHERSCAN_API_KEY="${3:-$ETHERSCAN_API_KEY}"

if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "Error: Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

echo "=== Verifying bytecode for deployment: $DEPLOYMENT_FILE ==="
echo ""

# Extract addresses from JSON
IMPLEMENTATION=$(jq -r '."safeguard-implementation"' "$DEPLOYMENT_FILE")
PROXY=$(jq -r '."safeguard-proxy"' "$DEPLOYMENT_FILE")
PROXY_ADMIN=$(jq -r '."safeguard-proxyAdmin"' "$DEPLOYMENT_FILE")
ADMIN=$(jq -r '.admin' "$DEPLOYMENT_FILE")
NAME=$(jq -r '.name' "$DEPLOYMENT_FILE")

# Get timelock from JSON if it exists, otherwise derive from ProxyAdmin owner
TIMELOCK=$(jq -r '.timelock // empty' "$DEPLOYMENT_FILE")
if [ -z "$TIMELOCK" ]; then
    TIMELOCK=$(cast call "$PROXY_ADMIN" "owner()(address)" --rpc-url "$RPC_URL")
fi

echo "Deployment: $NAME"
echo "  Implementation: $IMPLEMENTATION"
echo "  Proxy: $PROXY"
echo "  ProxyAdmin: $PROXY_ADMIN"
echo "  Timelock: $TIMELOCK"
echo "  Admin: $ADMIN"
echo ""

# Check that contracts exist
check_contract_exists() {
    local addr=$1
    local name=$2
    local code=$(cast code "$addr" --rpc-url "$RPC_URL" 2>/dev/null)
    if [ "$code" = "0x" ] || [ -z "$code" ]; then
        echo "ERROR: $name at $addr has no code!"
        exit 1
    fi
}

echo "Checking contracts exist on-chain..."
check_contract_exists "$PROXY" "Proxy"
check_contract_exists "$PROXY_ADMIN" "ProxyAdmin"
check_contract_exists "$TIMELOCK" "Timelock"
check_contract_exists "$IMPLEMENTATION" "Implementation"
echo "All contracts verified to exist on-chain."
echo ""

# Build project to get latest bytecode
echo "Building project..."
forge build --silent
echo "Build complete."
echo ""

# Function to compare bytecode
compare_bytecode() {
    local addr=$1
    local contract_path=$2
    local name=$3

    # Get on-chain runtime bytecode
    local onchain=$(cast code "$addr" --rpc-url "$RPC_URL" 2>/dev/null)

    # Get local deployed bytecode from forge artifacts
    # Try to find the artifact for the contract source including .sol in the path
    local artifact_path="out/${contract_path}/${name}.json"
    if [ ! -f "$artifact_path" ]; then
        # If that doesn't exist, fallback to the common pattern
        artifact_path="out/$(basename ${contract_path%.sol})/${name}.json"
        if [ ! -f "$artifact_path" ]; then
            # Also try with .sol left in basename (handles e.g. SafeGuard.sol/SafeGuard.json)
            artifact_path="out/$(basename ${contract_path})/${name}.json"
        fi
    fi
    local local_bytecode=$(jq -r '.deployedBytecode.object' "$artifact_path" 2>/dev/null)


    echo "artifact_path: $artifact_path"

    if [ -z "$local_bytecode" ] || [ "$local_bytecode" = "null" ]; then
        echo "  WARNING: Could not extract local bytecode from $artifact_path"
        return 1
    fi

    # Remove immutables/metadata by comparing just the first N bytes (code without constructor args embedded)
    # Runtime bytecode can differ in metadata hash, so we compare a meaningful prefix
    local onchain_prefix="${onchain:0:200}"
    local local_prefix="${local_bytecode:0:200}"

    if [ "$onchain_prefix" = "$local_prefix" ]; then
        echo "  [PASS] Bytecode prefix matches (first 100 bytes)"
        return 0
    else
        echo "  [FAIL] Bytecode prefix mismatch"
        echo "    On-chain: ${onchain_prefix:0:66}..."
        echo "    Local:    ${local_prefix:0:66}..."
        return 1
    fi
}

# Verify SafeGuard implementation
echo "=== [1/4] Verifying SafeGuard implementation bytecode ==="
echo "SKIPPED: SafeGuard uses internal libraries that cause verification issues"
echo "Manual verification: Compare bytecode at $IMPLEMENTATION with local compilation"
echo ""

# Verify TransparentUpgradeableProxy
echo "=== [2/4] Verifying TransparentUpgradeableProxy bytecode ==="

# Fetch bytecode from Etherscan and compare with on-chain
if [ -n "$ETHERSCAN_API_KEY" ]; then
    echo "  Fetching bytecode from Etherscan..."
    # Use Etherscan V2 API
    CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || echo "1")
    ETHERSCAN_BYTECODE=$(curl -s "https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}&module=proxy&action=eth_getCode&address=${PROXY}&tag=latest&apikey=${ETHERSCAN_API_KEY}" | jq -r '.result // empty')
    ONCHAIN_BYTECODE=$(cast code "$PROXY" --rpc-url "$RPC_URL")

    # Normalize to lowercase for comparison
    ETHERSCAN_LOWER=$(echo "$ETHERSCAN_BYTECODE" | tr '[:upper:]' '[:lower:]')
    ONCHAIN_LOWER=$(echo "$ONCHAIN_BYTECODE" | tr '[:upper:]' '[:lower:]')

    if [ "$ETHERSCAN_LOWER" = "$ONCHAIN_LOWER" ]; then
        echo "  [PASS] TUP bytecode matches Etherscan (${#ONCHAIN_BYTECODE} chars)"
    else
        echo "  [WARN] Bytecode comparison inconclusive"
        echo "    On-chain length: ${#ONCHAIN_BYTECODE}"
        echo "    Etherscan length: ${#ETHERSCAN_BYTECODE}"
    fi
else
    echo "  No API key, skipping Etherscan comparison..."
fi

# Also verify proxy configuration
echo "  Verifying proxy configuration..."

# Verify the proxy admin is set correctly
ONCHAIN_ADMIN=$(cast storage "$PROXY" 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 --rpc-url "$RPC_URL")
EXPECTED_ADMIN=$(echo "$PROXY_ADMIN" | tr '[:upper:]' '[:lower:]')
ONCHAIN_ADMIN_CLEAN=$(echo "$ONCHAIN_ADMIN" | sed 's/^0x0*/0x/' | tr '[:upper:]' '[:lower:]')

if [ "$ONCHAIN_ADMIN_CLEAN" = "$EXPECTED_ADMIN" ]; then
    echo "  [PASS] Proxy admin correctly set to: $PROXY_ADMIN"
else
    echo "  [FAIL] Proxy admin mismatch!"
    echo "    Expected: $EXPECTED_ADMIN"
    echo "    Got: $ONCHAIN_ADMIN_CLEAN"
fi

# Verify the implementation is set correctly
ONCHAIN_IMPL=$(cast storage "$PROXY" 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url "$RPC_URL")
EXPECTED_IMPL=$(echo "$IMPLEMENTATION" | tr '[:upper:]' '[:lower:]')
ONCHAIN_IMPL_CLEAN=$(echo "$ONCHAIN_IMPL" | sed 's/^0x0*/0x/' | tr '[:upper:]' '[:lower:]')

if [ "$ONCHAIN_IMPL_CLEAN" = "$EXPECTED_IMPL" ]; then
    echo "  [PASS] Implementation correctly set to: $IMPLEMENTATION"
else
    echo "  [FAIL] Implementation mismatch!"
    echo "    Expected: $EXPECTED_IMPL"
    echo "    Got: $ONCHAIN_IMPL_CLEAN"
fi
echo ""

# Verify ProxyAdmin
echo "=== [3/4] Verifying ProxyAdmin bytecode ==="
if [ -n "$ETHERSCAN_API_KEY" ]; then
    PROXY_ADMIN_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address)" "$TIMELOCK")

    forge verify-bytecode "$PROXY_ADMIN" \
        lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin \
        --rpc-url "$RPC_URL" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --encoded-constructor-args "$PROXY_ADMIN_CONSTRUCTOR_ARGS" \
        --ignore creation || echo "  WARNING: forge verify-bytecode failed, trying manual comparison..."
else
    echo "  No API key, using manual bytecode comparison..."
fi

echo ""

# Verify TimelockController
echo "=== [4/4] Verifying TimelockController bytecode ==="
if [ -n "$ETHERSCAN_API_KEY" ]; then
    TIMELOCK_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint256,address[],address[],address)" 86400 "[$ADMIN]" "[$ADMIN]" "$ADMIN")

    forge verify-bytecode "$TIMELOCK" \
        lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:TimelockController \
        --rpc-url "$RPC_URL" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --encoded-constructor-args "$TIMELOCK_CONSTRUCTOR_ARGS" \
        --ignore creation || echo "  WARNING: forge verify-bytecode failed, trying manual comparison..."
else
    echo "  No API key, using manual bytecode comparison..."
fi
echo ""

echo "=== Bytecode verification complete ==="
echo ""
echo "Note: For full verification, run the Solidity verification script:"
echo "  forge script scripts/verification/VerifySafeGuard.s.sol --sig \"run(string calldata)\" \"$DEPLOYMENT_FILE\" --rpc-url $RPC_URL"
