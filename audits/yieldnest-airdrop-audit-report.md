# Security Audit Report: yieldnest-airdrop

## Metadata
- **Repository:** yieldnest-airdrop
- **Commit:** 221599c53801d8422630256d43707759147fdd9a
- **Branch:** dev
- **Date:** 2026-03-17
- **Solidity Version:** >=0.8.25 (compiled with 0.8.25, EVM target: cancun)
- **Framework:** Foundry

## Audit Scope

| File | Path | LOC (total lines) |
|------|------|--------------------|
| Airdrop.sol | src/Airdrop.sol | 136 |
| IAirdrop.sol | src/IAirdrop.sol | 97 |
| **Total** | | **233** |

### Contract Architecture Summary

The `Airdrop` contract is an upgradeable (TransparentUpgradeableProxy pattern) token distribution contract. An owner pre-loads a mapping of user addresses to claimable amounts. Tokens are not held in the contract itself but in an external "safe" address; when users claim, tokens are transferred from the safe via `safeTransferFrom`. The contract inherits `OwnableUpgradeable`, `PausableUpgradeable`, and `ReentrancyGuardUpgradeable` from OpenZeppelin.

Key functions:
- `initialize()`: Sets owner, safe, token, and initial user amounts.
- `claim(uint256)`: Users claim tokens (pulled from the safe).
- `updateUserAmounts(UserAmount[])`: Owner updates allocations (only while paused).
- `pause()` / `unpause()`: Owner toggles claim availability.

## Methodologies Applied

| Pipeline | Methodology | Description | Status |
|----------|------------|-------------|--------|
| A | SCV Scan | Vulnerability pattern matching against 30+ known vulnerability classes | Completed |
| B | Feynman Business Logic Audit | Line-by-line reasoning about function behavior and boundary conditions | Completed |
| C | State Inconsistency Analysis | Storage variable coupling and mutation path verification | Completed |
| D | Pashov Multi-Vector Scan | Four-perspective analysis (access control, reentrancy, arithmetic, logic) | Completed |
| E | QuillAI Modules | Input-arithmetic-safety, external-call-safety, dos-griefing-analysis | Completed |

## Executive Summary

The yieldnest-airdrop codebase is a minimal, well-structured airdrop distribution contract with a small attack surface. The contract uses battle-tested OpenZeppelin libraries for access control, pausability, reentrancy protection, and safe ERC20 operations. The overall security posture is **good** for a contract of this scope.

The audit identified **0 Critical**, **0 High**, **1 Medium**, and **3 Low** severity issues, along with several informational notes. The most significant finding relates to the owner's ability to overwrite user allocations (including reducing them to zero) without an on-chain record of previous values, which constitutes a centralization risk. Other findings relate to missing input validation, gas considerations for large batch updates, and a missing event emission for state changes.

## Findings Summary

| ID | Severity | Confidence | Title |
|----|----------|------------|-------|
| M-01 | Medium | High | Owner can silently reduce or zero-out user allocations without on-chain accountability |
| L-01 | Low | High | `_updateUserAmounts` does not validate against `address(0)` user entries |
| L-02 | Low | High | No event emitted when user amounts are updated |
| L-03 | Low | Medium | `updateUserAmounts` with large arrays may exceed block gas limit |

## Detailed Findings

---

### M-01: Owner can silently reduce or zero-out user allocations without on-chain accountability

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `Airdrop.sol`
**Sources:** Pipeline B (Feynman Business Logic), Pipeline C (State Inconsistency), Pipeline D (Pashov Access Control)

**Description:**

The `updateUserAmounts()` function allows the owner to set any user's claimable amount to any value, including zero, with no on-chain record of the previous value and no event emission. While this is paused-only and owner-gated, it creates a significant centralization risk: the owner can revoke a user's airdrop allocation after it has been publicly committed, with no transparent on-chain trail.

Additionally, the `_updateUserAmounts` function performs a direct overwrite (`amounts[user] = amount`) rather than an additive or differential update. This means calling `updateUserAmounts` on a subset of users does not affect other users, but calling it with a user's amount set to 0 effectively revokes their allocation.

**Code Reference:**

```solidity
// src/Airdrop.sol, lines 111-118
function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        amounts[_userAmounts[i].user] = _userAmounts[i].amount;
        unchecked {
            i += 1;
        }
    }
}
```

**Impact:**

- Users have no trustless guarantee that their allocation will not be changed post-initialization.
- If the owner key is compromised, the attacker can zero out all allocations before users claim.
- No on-chain audit trail of changes to user allocations.

**Recommendation:**

1. Emit an event for each user amount update, including the old and new value:
   ```solidity
   event UserAmountUpdated(address indexed user, uint256 oldAmount, uint256 newAmount);
   ```
2. Consider whether a time-lock or multi-sig requirement for `updateUserAmounts` is appropriate for the protocol's trust model.
3. Consider restricting updates to only increase allocations (if business logic permits), or adding a separate function for revocations with additional safeguards.

---

### L-01: `_updateUserAmounts` does not validate against `address(0)` user entries

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `Airdrop.sol`
**Sources:** Pipeline A (SCV Scan), Pipeline B (Feynman Business Logic), Pipeline E (QuillAI Input Safety)

**Description:**

The `_updateUserAmounts` internal function, called from both `initialize()` and `updateUserAmounts()`, does not check if `_userAmounts[i].user` is `address(0)`. While `initialize()` does validate `_safe` and `_token` against `address(0)`, the user address in the `UserAmount` struct is not validated.

Setting an amount for `address(0)` wastes gas and pollutes state. More importantly, if a caller accidentally includes `address(0)` in the list, those tokens become unclaimable because no one controls `address(0)`.

**Code Reference:**

```solidity
// src/Airdrop.sol, lines 111-118
function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        amounts[_userAmounts[i].user] = _userAmounts[i].amount; // no address(0) check
        unchecked {
            i += 1;
        }
    }
}
```

**Impact:**

Low -- primarily an input validation gap. No funds are at risk since `address(0)` cannot call `claim()`, but the amounts mapping would record a phantom allocation that could confuse off-chain tracking.

**Recommendation:**

Add a check:
```solidity
if (_userAmounts[i].user == address(0)) revert InvalidAirdrop();
```

---

### L-02: No event emitted when user amounts are updated

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `Airdrop.sol`
**Sources:** Pipeline B (Feynman Business Logic), Pipeline C (State Inconsistency)

**Description:**

The `_updateUserAmounts` function modifies the `amounts` mapping but does not emit any event. The only event defined in `IAirdrop` related to user state is `Claimed`. There is no event for allocation changes.

This makes it impossible for off-chain systems (indexers, UIs, monitoring tools) to track allocation changes without scanning raw storage diffs. The `updateUserAmounts` function's own NatSpec acknowledges the front-running risk, but the lack of events makes the problem harder to detect.

**Code Reference:**

```solidity
// src/Airdrop.sol, lines 111-118
function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        amounts[_userAmounts[i].user] = _userAmounts[i].amount;
        // No event emitted
        unchecked {
            i += 1;
        }
    }
}
```

**Impact:**

Reduced transparency and auditability. Off-chain systems cannot easily monitor allocation changes.

**Recommendation:**

Emit an event per update or a batch event:
```solidity
event UserAmountUpdated(address indexed user, uint256 amount);
```

---

### L-03: `updateUserAmounts` with large arrays may exceed block gas limit

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `Airdrop.sol`
**Sources:** Pipeline A (SCV Scan - DoS Gas Limit), Pipeline E (QuillAI DoS/Griefing)

**Description:**

The `_updateUserAmounts` function iterates over the entire `_userAmounts` array in a single transaction. While the deployment scripts use a `BatchUpdate` helper with a batch size of 800, the on-chain function itself has no batching mechanism. If the owner calls `updateUserAmounts` directly (not through the batching script) with a very large array, the transaction could exceed the block gas limit.

Each iteration performs one `SSTORE` operation (minimum ~5,000 gas for warm slot, ~20,000 for cold slot), plus calldata decoding overhead. For extremely large airdrop lists (tens of thousands of users), this could exceed the block gas limit.

**Code Reference:**

```solidity
// src/Airdrop.sol, lines 111-118
function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        amounts[_userAmounts[i].user] = _userAmounts[i].amount;
        unchecked {
            i += 1;
        }
    }
}
```

**Impact:**

Low -- The deployment scripts already handle batching off-chain (BATCH_SIZE = 800). This is only a risk if the function is called directly with an excessively large array. The contract is paused during updates, so no user funds are at risk.

**Recommendation:**

This is adequately mitigated by the off-chain batching scripts. Optionally, document the expected maximum batch size or add an on-chain batch size limit.

---

## Informational Notes

### I-01: Checks-Effects-Interactions pattern correctly followed in `claim()`

The `claim()` function correctly updates state (`amounts[msg.sender] -= _amountToClaim`) before making the external call (`token.safeTransferFrom`). Combined with the `nonReentrant` modifier, reentrancy is not a concern. The `ReentrancyGuardUpgradeable` usage is appropriate and correct.

### I-02: `unchecked` block in loop increment is safe

The `unchecked { i += 1; }` in `_updateUserAmounts` is safe because the loop condition `i < _userAmounts.length` ensures `i` cannot overflow a `uint256` (the array length is bounded by calldata size and block gas limit, which is astronomically less than `type(uint256).max`). This is a standard gas optimization.

### I-03: Subtraction in `claim()` is safe against underflow

```solidity
amounts[msg.sender] -= _amountToClaim;
```

This cannot underflow because the `whenAvailable` modifier ensures `_amountToClaim <= amounts[msg.sender]` before execution reaches this line. Solidity 0.8.25 has built-in overflow/underflow checks, and the modifier provides the necessary pre-condition.

### I-04: SafeERC20 usage is correct

The contract uses `SafeERC20.safeTransferFrom()` for token transfers, which correctly handles non-standard ERC20 tokens (e.g., tokens that do not return a boolean). This is the recommended approach.

### I-05: Upgradeable contract initialization is properly secured

The implementation contract's constructor calls `_disableInitializers()`, which prevents the implementation from being initialized directly. The proxy-based initialization uses the `initializer` modifier correctly, ensuring `initialize()` can only be called once.

### I-06: `safe` and `token` are immutable after initialization

The `safe` address and `token` address are set in `initialize()` and cannot be changed afterward. There is no setter function. While this prevents accidental misconfiguration, it also means that if the safe address needs to change (e.g., safe migration), a new proxy deployment would be required. Depending on the protocol's needs, this could be considered either a safety feature or a limitation. Since the contract is upgradeable, a new implementation could add setters if needed.

### I-07: No `owner` validation in `_updateUserAmounts` for `address(0)` as owner

The `initialize` function passes `_owner` to `__Ownable_init(_owner)`, which has its own `address(0)` check in OpenZeppelin's `OwnableUpgradeable`. This is correctly handled by the library.

### I-08: Front-running risk on `updateUserAmounts` is acknowledged but mitigated

The NatSpec on `updateUserAmounts` (line 98-99) acknowledges the front-running risk: a user could claim their current allocation before the owner's update transaction is mined. However, this is mitigated by requiring the contract to be paused before updating. Since `claim()` has the `whenNotPaused` modifier, no claims can occur while updates are being applied. The risk only exists in a theoretical scenario where the owner unpauses before the update or if the pause and update are in separate transactions with insufficient atomicity guarantees. The deployment scripts handle this correctly by keeping the contract paused throughout the update process.

### I-09: No mechanism to recover tokens sent directly to the contract

If tokens are accidentally sent directly to the Airdrop contract address (rather than the safe), there is no recovery mechanism. However, the contract design intentionally avoids holding tokens -- all tokens reside in the safe. This is an informational note, not a vulnerability.

### I-10: `claim` function is `virtual` allowing extension by derived contracts

The `claim` function is marked `virtual override`, meaning it can be overridden in derived contracts. This is intentional for extensibility but should be noted: any derived contract overriding `claim` must ensure it maintains the security invariants (reentrancy guard, pause check, amount validation, state update before external call).

### I-11: Duplicate user entries in `_userAmounts` will silently overwrite

If the same user address appears multiple times in the `_userAmounts` array, only the last entry's amount will be stored. This is the expected behavior of mapping writes but could be surprising if the input data has unintentional duplicates. This is a data quality concern, not a contract vulnerability.

## SCV Scan Results (Pipeline A) -- Pattern Match Summary

| Vulnerability Pattern | Result | Notes |
|-----------------------|--------|-------|
| Reentrancy | Not Vulnerable | `nonReentrant` + CEI pattern in `claim()` |
| Unchecked Return Values | Not Vulnerable | Uses `SafeERC20.safeTransferFrom` |
| Access Control | Properly Implemented | `onlyOwner` on admin functions, `whenPaused`/`whenNotPaused` guards |
| Integer Overflow/Underflow | Not Vulnerable | Solidity 0.8.25 built-in checks; `unchecked` only on loop counter |
| Delegatecall | Not Present | No delegatecall in source (only in proxy layer, managed by OZ) |
| tx.origin | Not Present | Not used |
| Signature Issues | Not Applicable | No signature verification in contract |
| Frontrunning | Mitigated | Updates require paused state; claims blocked when paused |
| Precision Loss | Not Applicable | No division or multiplication operations |
| DoS Vectors | Low Risk | Large array iteration mitigated by off-chain batching (see L-03) |
| Hash Collision (encodePacked) | Not Present | No `abi.encodePacked` usage |
| Arbitrary Storage | Not Present | No user-controlled storage writes |
| Timestamp Dependence | Not Present | No `block.timestamp` usage |
| Uninitialized Storage | Not Applicable | Solidity >=0.8.25 |
| Deprecated Functions | Not Present | No deprecated functions used |

## State Inconsistency Analysis (Pipeline C) Summary

### Storage Variables and Their Coupling

| Variable | Coupled With | Mutation Functions | Consistency Check |
|----------|--------------|--------------------|-------------------|
| `amounts[user]` | Token balance in `safe` | `_updateUserAmounts`, `claim` | PASS -- `claim` reduces `amounts` and transfers tokens atomically |
| `safe` | Token allowance from safe to contract | `initialize` (set once) | PASS -- immutable after init |
| `token` | All claim operations | `initialize` (set once) | PASS -- immutable after init |
| `_paused` (inherited) | `claim`, `updateUserAmounts` | `pause`, `unpause` | PASS -- correctly gated |
| `_owner` (inherited) | All admin functions | `initialize`, `transferOwnership` | PASS -- OZ implementation |

### Critical Invariant Verification

1. **Invariant: `amounts[user]` can only decrease via `claim()`**: PASS -- `claim` subtracts, `_updateUserAmounts` can set to any value but is owner-only and paused-only.
2. **Invariant: Sum of all `amounts[user]` should not exceed safe's token balance**: NOT ENFORCED ON-CHAIN -- The contract does not track or verify total allocated amounts. The deployment script (`BaseScript.s.sol` line 73) checks `totalAmount > initialSafeBalance` off-chain, but this is not enforced on-chain. If the owner sets user amounts that exceed the safe's balance (or its allowance to the contract), late claimers will face reverts from `safeTransferFrom`. This is by design (pull-based model with external safe), not a vulnerability, but is noted for awareness.
3. **Invariant: No claims while paused**: PASS -- `whenNotPaused` modifier on `claim()`.

## Conclusion

The yieldnest-airdrop contract is a well-implemented, minimal airdrop distribution mechanism with appropriate use of OpenZeppelin's battle-tested libraries. The primary risk surface is centralization (owner control over allocations), which is inherent to the design. The code follows Solidity best practices including CEI pattern, reentrancy guards, safe ERC20 operations, and proper upgrade safety.

The recommended actions in priority order:
1. **M-01**: Add event emissions for allocation changes and consider governance safeguards on `updateUserAmounts`.
2. **L-01**: Add `address(0)` validation for user entries in `_updateUserAmounts`.
3. **L-02**: Add allocation update events for off-chain monitoring.
4. **L-03**: Document expected batch sizes (already mitigated by scripts).
