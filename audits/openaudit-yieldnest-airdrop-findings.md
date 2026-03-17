# OpenAudit: yieldnest-airdrop Findings

**Target:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/`
**Contracts in Scope:** `Airdrop.sol`, `IAirdrop.sol`
**Solidity Version:** >=0.8.25
**Pipelines Applied:** Forefy Smart Contract Audit (5-layer + multi-expert), Archethect SC Auditor (MAP-HUNT-ATTACK)
**Date:** 2026-03-17

---

## Deduplicated (Already Reported)

- **M-01:** Owner can silently reduce/zero-out user allocations without on-chain accountability

---

## New Findings

### [MEDIUM] OA-AD-01: No event emitted on user allocation updates enables silent state manipulation

**Pipeline:** Forefy
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:111-118

**Description:**
The `_updateUserAmounts()` internal function (called by both `initialize()` and `updateUserAmounts()`) modifies the `amounts` mapping for arbitrary users but emits no event. This means allocation changes -- whether during initialization or subsequent updates -- leave no on-chain trace. Off-chain monitoring systems, indexers, and dashboards cannot detect when allocations are modified. This is distinct from M-01 (which concerns the owner's power to reduce allocations); this finding concerns the complete absence of an audit trail for any allocation change.

Without events, there is no way to:
1. Build an accurate off-chain index of current allocations
2. Detect unauthorized or erroneous allocation changes in monitoring systems
3. Verify that the sum of all allocations matches the expected airdrop total
4. Provide users with notification that their allocation has changed

**Impact:**
Users and governance participants cannot verify allocation integrity. Even an honest owner's changes are invisible to on-chain observers. This fundamentally undermines the trustworthiness of the airdrop mechanism, as there is no verifiable record of who was allocated what and when.

**Recommendation:**
Emit an event for each user's allocation update within the loop in `_updateUserAmounts()`:

```solidity
event AllocationUpdated(address indexed user, uint256 oldAmount, uint256 newAmount);

function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        uint256 oldAmount = amounts[_userAmounts[i].user];
        amounts[_userAmounts[i].user] = _userAmounts[i].amount;
        emit AllocationUpdated(_userAmounts[i].user, oldAmount, _userAmounts[i].amount);
        unchecked {
            i += 1;
        }
    }
}
```

---

### [MEDIUM] OA-AD-02: Pause-unpause frontrunning window allows owner to manipulate allocations and immediately enable claims in a single block

**Pipeline:** Archethect
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:85-105

**Description:**
The `updateUserAmounts()` function requires the contract to be paused (`whenPaused` modifier). However, the owner can execute `pause()`, `updateUserAmounts()`, and `unpause()` atomically in the same block (or even via a multicall/batch transaction). This creates a scenario where allocations are modified and claiming is re-enabled before any user or external observer can react.

The contract itself documents a related risk in a NatSpec comment on line 98: "Note this function can be front-run by a claimant to claim before the amount is updated if amount is non-zero." However, the inverse is equally dangerous and not documented: the owner can front-run user claims by pausing, reducing allocations to zero, and unpausing, all within the same block, effectively stealing pending airdrop entitlements.

The attack sequence:
1. Owner observes a pending `claim()` transaction in the mempool
2. Owner submits a higher-gas-price bundle: `pause()` -> `updateUserAmounts([{user: victim, amount: 0}])` -> `unpause()`
3. The victim's `claim()` transaction executes after the bundle and reverts with `NoAirdrop()`
4. The owner has effectively confiscated the victim's allocation with no on-chain evidence (no events emitted per OA-AD-01)

While this involves the owner acting in bad faith (which overlaps with M-01), the specific mechanism of atomic pause-update-unpause within a single block to frontrun user claims is a distinct operational risk that differs from the static allocation reduction described in M-01. M-01 describes the power to reduce allocations; this finding describes a concrete MEV-style attack that exploits the pause mechanism's lack of a timelock.

**Impact:**
Any user's pending claim transaction can be frontrun and nullified by the owner. The pause mechanism, intended as a safety feature, becomes an attack vector when combined with allocation updates in the same block.

**Recommendation:**
Introduce a minimum pause duration or a timelock on allocation updates:

```solidity
uint256 public constant MIN_PAUSE_DURATION = 1 hours;
uint256 public pausedAt;

function pause() external onlyOwner whenNotPaused {
    pausedAt = block.timestamp;
    _pause();
}

function updateUserAmounts(UserAmount[] calldata _userAmounts) external onlyOwner whenPaused {
    require(block.timestamp >= pausedAt + MIN_PAUSE_DURATION, "Too soon after pause");
    _updateUserAmounts(_userAmounts);
}
```

---

### [MEDIUM] OA-AD-03: Safe's token allowance is a single point of failure with no on-chain validation

**Pipeline:** Forefy
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:133

**Description:**
The `claim()` function transfers tokens from the `safe` address to the claimant using `token.safeTransferFrom(safe, msg.sender, _amountToClaim)`. This requires the `safe` to have approved the Airdrop contract for a sufficient token allowance. However:

1. There is no on-chain validation during `initialize()` or `updateUserAmounts()` that the safe has granted sufficient allowance or even holds sufficient tokens.
2. If the safe revokes its approval or is drained by another approved spender, all claims silently become non-functional. Users will see their `amounts[user]` as non-zero but every `claim()` call will revert at the `safeTransferFrom` step.
3. There is no mechanism to update the `safe` address after initialization. If the safe becomes compromised, blacklisted, or otherwise non-functional, all remaining airdrop allocations are permanently unclaimable.

This creates a liveness risk: the entire airdrop distribution can be bricked by an external action on the safe (approval revocation, token transfer out, address blacklisting) with no recovery path.

**Impact:**
All unclaimed airdrop allocations become permanently unrecoverable if the safe's approval is revoked, the safe is drained, or the safe address is blacklisted by the token contract. Users have no recourse because the `safe` address is immutable post-initialization.

**Recommendation:**
1. Add a setter for the `safe` address (owner-only, with event emission):
```solidity
function setSafe(address _newSafe) external onlyOwner {
    require(_newSafe != address(0), "Invalid safe");
    address oldSafe = safe;
    safe = _newSafe;
    emit SafeUpdated(oldSafe, _newSafe);
}
```
2. Consider adding a view function that checks the safe's current allowance and balance to enable off-chain monitoring:
```solidity
function claimableBalance() external view returns (uint256) {
    uint256 allowance = token.allowance(safe, address(this));
    uint256 balance = token.balanceOf(safe);
    return allowance < balance ? allowance : balance;
}
```

---

### [LOW] OA-AD-04: Duplicate entries in `_userAmounts` array silently overwrite without detection

**Pipeline:** Archethect
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:111-118

**Description:**
The `_updateUserAmounts()` function iterates over a `UserAmount[]` array and directly assigns `amounts[_userAmounts[i].user] = _userAmounts[i].amount` for each entry. If the same user address appears multiple times in the array, only the last entry's amount takes effect, silently overwriting all previous entries for that user. There is no deduplication check, no revert, and no event to indicate that a duplicate was processed.

This matches the fv-sol-5-c10 (Data Structure State Integrity) pattern from the Forefy reference: "no deduplication check allows a user to pass the same ID multiple times in one call."

Example: `[{user: Alice, amount: 1000}, {user: Alice, amount: 0}]` silently sets Alice's allocation to 0, even though the intended allocation may have been 1000. In a large array of hundreds of users, such duplicates could be introduced accidentally by off-chain scripts without detection.

**Impact:**
Operational risk of accidental misconfiguration. A faulty off-chain script generating the `_userAmounts` array could include duplicate addresses with different amounts, leading to incorrect allocations. Since no event is emitted (OA-AD-01), the error would be invisible on-chain.

**Recommendation:**
Add a deduplication check or require the array to be sorted by address with no duplicates:

```solidity
function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        if (i > 0) {
            require(
                uint160(_userAmounts[i].user) > uint160(_userAmounts[i - 1].user),
                "Unsorted or duplicate"
            );
        }
        amounts[_userAmounts[i].user] = _userAmounts[i].amount;
        unchecked {
            i += 1;
        }
    }
}
```

---

### [LOW] OA-AD-05: `updateUserAmounts` can set allocations for `address(0)`, wasting gas and polluting state

**Pipeline:** Forefy
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:111-118

**Description:**
The `_updateUserAmounts()` function does not validate that user addresses in the `_userAmounts` array are non-zero. An entry with `user = address(0)` will be accepted and will set `amounts[address(0)]` to a non-zero value. Since `msg.sender` can never be `address(0)` in a normal transaction, these tokens are effectively allocated to an unclaimable address.

While `initialize()` validates that `_safe` and `_token` are not `address(0)`, no such check is applied to user addresses in the allocation array.

**Impact:**
Allocations assigned to `address(0)` are permanently unclaimable, representing wasted token allocation. In aggregate, if off-chain scripts accidentally include zero-address entries, the total claimable supply would be reduced without any on-chain indication.

**Recommendation:**
Add a zero-address check in the loop:

```solidity
function _updateUserAmounts(UserAmount[] calldata _userAmounts) internal {
    for (uint256 i; i < _userAmounts.length;) {
        require(_userAmounts[i].user != address(0), "Zero address");
        amounts[_userAmounts[i].user] = _userAmounts[i].amount;
        unchecked {
            i += 1;
        }
    }
}
```

---

### [LOW] OA-AD-06: No mechanism to recover tokens if safe approval exceeds total allocations or airdrop is abandoned

**Pipeline:** Archethect
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:19-136

**Description:**
The Airdrop contract has no function to sweep unclaimed tokens back to the safe or any other address. If the airdrop campaign ends and some allocations remain unclaimed, there is no on-chain mechanism to reclaim the corresponding tokens from the safe's approval. The only recovery path is for the safe to revoke its approval to the Airdrop contract, but this also prevents any remaining legitimate claims.

Additionally, if tokens are accidentally sent directly to the Airdrop contract (rather than the safe), they are permanently locked since the contract has no `rescue` or `sweep` function.

**Impact:**
Tokens accidentally sent to the Airdrop contract are permanently lost. Unclaimed allocations require off-chain coordination (safe revoking approval) to recover, which also blocks legitimate late claims. There is no graceful shutdown mechanism.

**Recommendation:**
Add an owner-only function to recover accidentally sent tokens:

```solidity
function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
    IERC20(_token).safeTransfer(_to, _amount);
}
```

And consider adding a deadline after which unclaimed allocations can be zeroed and the airdrop finalized:

```solidity
uint256 public claimDeadline;

function setClaimDeadline(uint256 _deadline) external onlyOwner {
    claimDeadline = _deadline;
}
```

---

### [INFORMATIONAL] OA-AD-07: `Claimed` event does not include remaining claimable balance, reducing off-chain observability

**Pipeline:** Forefy
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:134

**Description:**
The `Claimed` event emits `(address user, uint256 amount)` where `amount` is the claimed quantity. It does not include the user's remaining claimable balance after the claim. Off-chain systems tracking claim progress must make additional RPC calls to read `amounts[user]` after each claim event to determine remaining balances.

This is a minor observability gap. The current event is technically correct (it reports the claim delta, not the cumulative state), but including the remaining balance would improve off-chain integration efficiency.

**Impact:**
Minimal. Off-chain indexers require an additional state read per claim event to track remaining allocations.

**Recommendation:**
Consider extending the event:

```solidity
event Claimed(address indexed user, uint256 amount, uint256 remaining);

// In claim():
amounts[msg.sender] -= _amountToClaim;
emit Claimed(msg.sender, _amountToClaim, amounts[msg.sender]);
```

---

### [INFORMATIONAL] OA-AD-08: Unbounded `_userAmounts` array in `_updateUserAmounts` risks gas limit revert for large airdrops

**Pipeline:** Archethect
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-airdrop/src/Airdrop.sol`:111-118

**Description:**
The `_updateUserAmounts()` function iterates over the entire `_userAmounts` calldata array in a single transaction. For large airdrops with thousands of recipients, this loop may exceed the block gas limit, causing the transaction to revert. Each iteration performs a storage write (`amounts[_userAmounts[i].user] = _userAmounts[i].amount`), which costs approximately 20,000 gas for a new slot or 5,000 gas for an update to a non-zero value.

For a new airdrop with 1,000 recipients: ~20,000,000 gas (close to the 30M block gas limit on Ethereum mainnet).
For 2,000+ recipients: likely exceeds the block gas limit.

The `unchecked` block on the loop counter provides marginal gas savings but does not address the fundamental scaling limitation.

**Impact:**
Operational: large airdrops may need to be split across multiple transactions (multiple pause-update-unpause cycles), which increases the attack surface described in OA-AD-02 and adds operational complexity.

**Recommendation:**
Document the maximum practical batch size. Consider adding a batch-processing pattern or documenting that large airdrops should be split into multiple `updateUserAmounts()` calls while the contract remains paused.

---

## Summary

| ID | Severity | Title | Pipeline |
|---|---|---|---|
| OA-AD-01 | Medium | No event emitted on user allocation updates | Forefy |
| OA-AD-02 | Medium | Pause-unpause frontrunning window | Archethect |
| OA-AD-03 | Medium | Safe's token allowance is a single point of failure | Forefy |
| OA-AD-04 | Low | Duplicate entries silently overwrite | Archethect |
| OA-AD-05 | Low | `address(0)` allocations accepted | Forefy |
| OA-AD-06 | Low | No token recovery mechanism | Archethect |
| OA-AD-07 | Informational | Claimed event lacks remaining balance | Forefy |
| OA-AD-08 | Informational | Unbounded array risks gas limit revert | Archethect |

**Total New Findings:** 8 (3 Medium, 3 Low, 2 Informational)
**Deduplicated:** 1 (M-01)
