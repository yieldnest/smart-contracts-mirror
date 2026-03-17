# Security Audit Report: wrapped-token

## Metadata
- **Repository:** wrapped-token
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6
- **Branch:** main
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.0
- **Framework:** Foundry (Forge)
- **Dependencies:** OpenZeppelin Contracts, OpenZeppelin Contracts Upgradeable

## Audit Scope

| File | Path | LOC (with blanks/comments) |
|------|------|---------------------------|
| WrappedToken.sol | `src/WrappedToken.sol` | 201 |
| IWrappedToken.sol | `src/interface/IWrappedToken.sol` | 10 |
| **Total** | | **211** |

The audit covers the two source files in `src/`. Test utilities (e.g., `GovernedWrappedToken.sol` in `test/utils/`) were read for context but are not in scope.

## Methodologies Applied

| Pipeline | Methodology | Focus |
|----------|-------------|-------|
| A | SCV Scan (Vulnerability Pattern Matching) | Reentrancy, unchecked returns, access control, overflow, delegatecall, tx.origin, signatures, frontrunning, precision loss, DoS |
| B | Feynman Business Logic Audit | Line-by-line reasoning, symmetric function comparison, boundary conditions |
| C | State Inconsistency Analysis | Storage variable coupling, mutation path completeness, masking patterns |
| D | Pashov Multi-Vector Scan | 4 perspectives: access control, reentrancy, arithmetic, logic flow |
| E | QuillAI Modules | Input-arithmetic-safety, external-call-safety, behavioral-state-analysis |

## Executive Summary

WrappedToken is a compact, upgradeable ERC20 wrapper that normalizes decimals between an underlying token and its wrapped representation. The contract uses a fixed conversion rate based on a `decimalsOffset` exponent, with no exchange rate manipulation possible. The codebase is small, well-structured, and uses OpenZeppelin's battle-tested libraries (SafeERC20, Math, ERC20Upgradeable).

**No critical or high-severity vulnerabilities were found.** Two medium-severity findings and three low-severity findings were identified, along with two informational notes. The most significant issues are (1) a storage slot that occupies the ERC-1967 implementation namespace, creating a collision risk in proxy deployments, and (2) incompatibility with fee-on-transfer tokens that could lead to under-collateralization.

## Findings Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 3 |
| Informational | 2 |
| **Total** | **7** |

## Detailed Findings

---

### M-01: Storage Slot Occupies ERC-1967 Implementation Namespace

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline A, Pipeline C, Pipeline D

**Description:**

The `TokenStorageLocation` constant is set to `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382b00`. The inline comment states this is derived from `keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))`, but independent computation shows this is **incorrect**.

The actual value `0x360894...382b00` is the ERC-7201 namespace base slot derived from the **ERC-1967 implementation slot** (`keccak256("eip1967.proxy.implementation") - 1 = 0x360894...382bcc`), masked with `& ~bytes32(uint256(0xff))`.

The correctly computed slot for `"WrappedToken.storage"` would be `0x197626c3a3afe5578bb01cb78b89fb6ab8ac10cf2f95c38552c1a1c17533b100`.

**Code Reference:**

```solidity
// src/WrappedToken.sol, lines 192-193
// keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant TokenStorageLocation = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382b00;
```

**Impact:**

The `TokenStorage` struct (containing `underlyingToken`, `decimals`, and `decimalsOffset`) is stored at offset 0x00 within the ERC-1967 namespace (0x00-0xFF). The ERC-1967 implementation address itself is stored at offset 0xCC within this same namespace. While these two specific slots do not directly overlap (they are 204 slots apart and `TokenStorage` packs into a single slot), they share the same ERC-7201 namespace. This means:

1. Any tooling or contract that enumerates or reserves the ERC-1967 namespace could assume slot `...b00` is part of proxy infrastructure.
2. Future extensions to proxy patterns that use additional slots in this namespace could collide with `TokenStorage`.
3. The misleading comment obscures the actual provenance of the slot, making auditability harder.

In practice, with the current storage layout, no direct data corruption occurs between `TokenStorage` at slot `...b00` and the ERC-1967 implementation slot at `...bcc`.

**Recommendation:**

Recompute the storage slot using the correct namespace string `"WrappedToken.storage"` and update the constant:

```solidity
// keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant TokenStorageLocation = 0x197626c3a3afe5578bb01cb78b89fb6ab8ac10cf2f95c38552c1a1c17533b100;
```

Note: This is a breaking change for any already-deployed proxies, as it moves where storage is read/written. For new deployments, this should be corrected. For existing deployments, the current slot works without collision, so migration may not be necessary.

---

### M-02: Incompatibility with Fee-on-Transfer Tokens

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline B, Pipeline D, Pipeline E

**Description:**

The `deposit()` function calculates shares based on the `amount` parameter rather than the actual amount of tokens received by the contract. If the underlying token charges a transfer fee (e.g., USDT with fees enabled, deflationary tokens), the contract receives fewer tokens than `amount`, but mints shares as if the full amount was deposited.

**Code Reference:**

```solidity
// src/WrappedToken.sol, lines 92-101
function deposit(uint256 amount, address receiver) public returns (uint256) {
    uint256 shares = convertToShares(amount); // shares based on requested amount

    SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount); // may receive less
    _mint(receiver, shares); // mints shares for full amount

    emit Deposit(msg.sender, receiver, amount, shares);

    return shares;
}
```

**Impact:**

Over time, the contract becomes under-collateralized: `convertToAssets(totalSupply())` exceeds the actual token balance. Later redeemers will face reverts when the contract's underlying balance is exhausted, effectively creating a first-come-first-served withdrawal situation. This is a form of implicit loss socialization.

**Recommendation:**

If fee-on-transfer tokens are in scope, measure the actual received amount:

```solidity
function deposit(uint256 amount, address receiver) public returns (uint256) {
    uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
    SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
    uint256 actualReceived = IERC20(asset()).balanceOf(address(this)) - balanceBefore;

    uint256 shares = convertToShares(actualReceived);
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, actualReceived, shares);
    return shares;
}
```

If fee-on-transfer tokens are explicitly out of scope, document this assumption clearly in the contract's NatSpec.

---

### L-01: Shares Burned for Zero Assets in `redeem()`

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline B, Pipeline D, Pipeline E

**Description:**

When `decimalsOffset > 0`, redeeming a number of shares less than `10^decimalsOffset` results in `convertToAssets()` returning 0 due to floor division. The shares are still burned, but the user receives zero underlying tokens.

**Code Reference:**

```solidity
// src/WrappedToken.sol, lines 110-123
function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
    uint256 assets = convertToAssets(shares); // returns 0 if shares < 10^offset

    if (msg.sender != owner) {
        _spendAllowance(owner, msg.sender, shares);
    }

    _burn(owner, shares);                    // shares burned
    SafeERC20.safeTransfer(IERC20(asset()), receiver, assets); // sends 0 tokens

    emit Withdraw(msg.sender, receiver, owner, assets, shares);

    return assets; // returns 0
}
```

**Impact:**

Users who call `redeem()` with fewer shares than `10^decimalsOffset` permanently lose those shares with no underlying tokens returned. While this is unlikely for informed users, it could affect integrating contracts or UIs that do not enforce minimum redemption amounts.

**Recommendation:**

Add a check that the computed asset amount is non-zero when shares are non-zero:

```solidity
function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
    uint256 assets = convertToAssets(shares);
    require(shares == 0 || assets > 0, "WrappedToken: redeem amount too small");
    // ...
}
```

---

### L-02: Missing Initialization Parameter Validation

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline B, Pipeline E

**Description:**

The `_initialize()` function only validates that `underlyingToken != address(this)`. It does not validate:

1. `underlyingToken != address(0)` -- setting the underlying to the zero address would brick all deposit/redeem operations.
2. `tokenDecimalsOffset` is within a safe range -- values greater than 77 cause `10 ** decimalsOffset` to overflow `uint256`, making `convertToShares()` revert for any non-zero input.
3. `decimalsValue` is reasonable -- while any `uint8` value is technically valid, extremely high values would be misleading.

**Code Reference:**

```solidity
// src/WrappedToken.sol, lines 67-84
function _initialize(
    IERC20 underlyingToken,
    string memory name,
    string memory symbol,
    uint8 decimalsValue,
    uint8 tokenDecimalsOffset
) internal {
    if (address(underlyingToken) == address(this)) {
        revert ERC20InvalidUnderlying(address(this));
    }
    // No further validation
    __ERC20_init(name, symbol);
    TokenStorage storage ts = _getTokenStorage();
    ts.underlyingToken = address(underlyingToken);
    ts.decimals = decimalsValue;
    ts.decimalsOffset = tokenDecimalsOffset;
}
```

**Impact:**

Since `initialize()` can only be called once (due to the `initializer` modifier), an incorrect initialization is permanent and irreversible. A misconfigured `decimalsOffset > 77` would make the contract unusable, and a zero-address underlying would cause all transfers to revert.

**Recommendation:**

Add validation:

```solidity
require(address(underlyingToken) != address(0), "WrappedToken: zero address");
require(tokenDecimalsOffset <= 77, "WrappedToken: offset too large");
```

---

### L-03: Non-CEI Pattern in `deposit()` with ERC-777 Compatible Tokens

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline A, Pipeline D

**Description:**

In `deposit()`, the external call `safeTransferFrom()` executes **before** the state-changing `_mint()` call. This violates the Checks-Effects-Interactions (CEI) pattern. If the underlying token implements ERC-777 transfer hooks (e.g., `tokensToSend` on the sender), the sender receives a callback before shares are minted.

**Code Reference:**

```solidity
// src/WrappedToken.sol, lines 92-101
function deposit(uint256 amount, address receiver) public returns (uint256) {
    uint256 shares = convertToShares(amount);

    SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount); // external call FIRST
    _mint(receiver, shares);  // state update SECOND

    emit Deposit(msg.sender, receiver, amount, shares);
    return shares;
}
```

**Impact:**

In practice, re-entering `deposit()` from the callback simply performs another independent deposit (each call computes shares independently from its own `amount`), so no profit extraction is possible. However, the non-CEI ordering is a code smell and could become exploitable if the function logic is modified in a future upgrade. Additionally, re-entering `redeem()` from within a `deposit()` callback would also not yield an advantage because no shares have been minted yet.

**Recommendation:**

Reorder to follow CEI -- mint shares before transferring tokens in:

```solidity
function deposit(uint256 amount, address receiver) public returns (uint256) {
    uint256 shares = convertToShares(amount);

    _mint(receiver, shares);  // effect first
    SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount); // interaction second

    emit Deposit(msg.sender, receiver, amount, shares);
    return shares;
}
```

Alternatively, add OpenZeppelin's `ReentrancyGuardUpgradeable` as a defense-in-depth measure.

---

## Informational Notes

### I-01: Unused `ALLOCATOR_ROLE` Constant and `AllocatorStatusChanged` Event

**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline A, Pipeline D

The `ALLOCATOR_ROLE` constant (line 42) and `AllocatorStatusChanged` event (line 39) are declared in `WrappedToken.sol` but never referenced within the contract itself. They are used only in the derived `GovernedWrappedToken` contract (located in `test/utils/`, outside audit scope).

Declaring these in the base contract when they are only needed in a specific extension increases the base contract's surface area and could confuse auditors and integrators. Consider moving these declarations to the derived contract that uses them, or to a shared interface.

---

### I-02: Incorrect Inline Comment for Storage Slot Derivation

**Affected Contract(s):** `WrappedToken.sol`
**Sources:** Pipeline A, Pipeline C

The comment on line 192 claims the storage slot is derived from `keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))`. Independent computation shows this formula yields `0x197626c3a3afe5578bb01cb78b89fb6ab8ac10cf2f95c38552c1a1c17533b100`, not the declared value `0x360894...382b00`. The declared value actually corresponds to the ERC-1967 implementation slot namespace. This discrepancy is already addressed as a finding in M-01 but is also noted here for completeness as a documentation accuracy issue.

```solidity
// src/WrappedToken.sol, line 192
// keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant TokenStorageLocation = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382b00;
```

---

## Appendix: Pipeline Cross-Reference Matrix

| Finding | Pipeline A (SCV) | Pipeline B (Feynman) | Pipeline C (State) | Pipeline D (Pashov) | Pipeline E (QuillAI) |
|---------|:-:|:-:|:-:|:-:|:-:|
| M-01: Storage Slot Namespace | X | | X | X | |
| M-02: Fee-on-Transfer | | X | | X | X |
| L-01: Zero-Asset Burn | | X | | X | X |
| L-02: Init Validation | | X | | | X |
| L-03: Non-CEI deposit() | X | | | X | |
| I-01: Unused ALLOCATOR_ROLE | X | | | X | |
| I-02: Incorrect Comment | X | | X | | |
