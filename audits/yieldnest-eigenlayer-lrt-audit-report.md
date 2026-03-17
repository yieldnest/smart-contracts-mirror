# Security Audit Report: yieldnest-eigenlayer-lrt

## Metadata
- **Repository:** yieldnest-eigenlayer-lrt
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6
- **Branch:** flat-repos
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24 (solc 0.8.27)
- **Previous Audits:** Chain Security, Zokyo

## Audit Scope

### ynETH Subsystem (Core Restaking)

| File | LOC | Description |
|------|-----|-------------|
| `src/ynETH.sol` | 360 | Core LRT token, deposit/withdraw, share accounting |
| `src/ynBase.sol` | 147 | ERC20 base with transfer pause and whitelist |
| `src/Constants.sol` | 9 | Protocol constants |
| `src/StakingNode.sol` | 716 | EigenLayer staking node, delegation, withdrawal |
| `src/StakingNodesManager.sol` | 775 | Node creation, validator registration, principal withdrawals |
| `src/RewardsDistributor.sol` | 193 | Rewards aggregation and fee distribution |
| `src/RewardsReceiver.sol` | 113 | Rewards receiver (CL/EL) |
| `src/WithdrawalsProcessor.sol` | 100 | Withdrawal bundling processor |
| `src/WithdrawalQueueManager.sol` | 615 | NFT-based withdrawal queue with finalization |
| `src/PooledDepositsVault.sol` | 77 | Pre-launch pooled deposits |
| `src/ReferralDepositAdapter.sol` | 106 | Referral deposit proxy |
| `src/ynETHRedemptionAssetsVault.sol` | 170 | ETH redemption vault for ynETH |
| `src/ynViewer.sol` | 67 | Read-only viewer contract |

### ynEIGEN Subsystem (Token Restaking)

| File | LOC | Description |
|------|-----|-------------|
| `src/ynEIGEN/ynEigen.sol` | 385 | Multi-asset LRT token |
| `src/ynEIGEN/AssetRegistry.sol` | 378 | Asset management and valuation |
| `src/ynEIGEN/EigenStrategyManager.sol` | 490 | Strategy management for EigenLayer deposits |
| `src/ynEIGEN/TokenStakingNode.sol` | 585 | Token-based staking node |
| `src/ynEIGEN/TokenStakingNodesManager.sol` | 340 | Token staking node creation/upgrade |
| `src/ynEIGEN/RedemptionAssetsVault.sol` | 282 | Multi-asset redemption vault |
| `src/ynEIGEN/WithdrawalsProcessor.sol` | 611 | Automated withdrawal pipeline |
| `src/ynEIGEN/LSDRateProvider.sol` | 79 | LSD exchange rate provider |
| `src/ynEIGEN/LSDWrapper.sol` | 96 | wstETH/woETH wrap/unwrap |
| `src/ynEIGEN/ynEigenDepositAdapter.sol` | 203 | stETH/oETH deposit adapter |
| `src/ynEIGEN/ynEigenViewer.sol` | 134 | Read-only viewer |

### Libraries and Support

| File | LOC | Description |
|------|-----|-------------|
| `src/lib/ArrayLib.sol` | 52 | Address array deduplication |
| `src/PlaceholderContract.sol` | 4 | Empty placeholder |

**Total Audited LOC:** 8,332 across 26 source contracts (excluding interfaces, externals, testnet)

## Methodologies Applied

| Pipeline | Methodology | Focus Areas | Findings |
|----------|------------|-------------|----------|
| A | SCV Scan (36 vulnerability patterns) | Reentrancy, unchecked returns, access control, DoS | 5 |
| B | Feynman Business Logic Audit | Share accounting, withdrawal queues, rewards distribution | 6 |
| C | State Inconsistency Analysis | Coupled state variables, totalAssets tracking | 4 |
| D | Pashov Multi-Vector Scan | Access control, reentrancy, arithmetic, logic | 4 |
| E | QuillAI Modules (10 modules) | Behavioral state, oracle, proxy, DoS/griefing | 3 |
| F | Token Integration Analysis | ERC20 conformance, transfer restrictions | 2 |

## Executive Summary

The yieldnest-eigenlayer-lrt repository implements a comprehensive liquid restaking protocol with two subsystems: ynETH (native ETH restaking) and ynEIGEN (multi-asset token restaking), both integrated with EigenLayer's delegation and slashing infrastructure. The protocol has been previously audited by Chain Security and Zokyo.

This audit identified **14 unique findings** across 6 independent methodologies. The codebase demonstrates strong security engineering overall, with proper use of ReentrancyGuard, AccessControl, SafeERC20, and careful checks-effects-interactions patterns. The most notable issues relate to: (1) permissionless reward processing enabling donation/inflation attacks in edge cases, (2) trusted off-chain inputs for reward/principal separation, (3) potential precision loss in multi-asset redemption flows, and (4) finalization ordering issues in the withdrawal queue.

The ELIP-002 slashing integration adds significant complexity to the accounting model, particularly the dual-tracking of pre/post-upgrade queued shares. The synchronization mechanism is well-designed but relies on external callers to invoke `synchronize()` after operator-initiated undelegation events.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| F-01 | Medium | Permissionless `processRewards()` enables donation attack on non-bootstrapped system | B, C, D | High |
| F-02 | Medium | Trusted off-chain `rewardsAmount` in principal withdrawals can misattribute principal as rewards | B, D | High |
| F-03 | Medium | `pendingRequestedRedemptionAmount` can desync from actual claims due to rate-minimum logic | B, C | Medium |
| F-04 | Medium | `WithdrawalQueueManager.finalizeRequestsUpToIndex` creates Finalization before validation | B, D | High |
| F-05 | Low | `RedemptionAssetsVault.transferRedemptionAssets` rounding loss in multi-asset transfer loop | B, E | High |
| F-06 | Low | `RewardsDistributor.processRewards` uses `assert()` for balance check instead of `require()` | A, D | High |
| F-07 | Low | `ynETH.processWithdrawnETH` has overly broad caller authorization | A, D | Medium |
| F-08 | Low | `updateTotalETHStaked` is permissionless and iterates all nodes | A, E | Medium |
| F-09 | Low | `StakingNode.synchronize()` is permissionless allowing timing manipulation | D, E | Medium |
| F-10 | Low | `WithdrawalQueueManager.findFinalizationForTokenId` unbounded binary search can underflow | A, B | Medium |
| F-11 | Informational | `initializeV3` in `StakingNodesManager` lacks access control modifier | A | High |
| F-12 | Informational | TODO comments remain in production code indicating incomplete review | A | High |
| F-13 | Informational | `ynEigen.processWithdrawn` calls `safeTransferFrom` after updating state | A | Medium |
| F-14 | Informational | `Finalization.redemptionRate` truncated to `uint96` may overflow for high-value tokens | E, F | Low |

## Detailed Findings

---

### F-01: Permissionless `processRewards()` enables donation attack on non-bootstrapped system

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `RewardsDistributor.sol`
**Function(s):** `processRewards()`
**Sources:** Pipeline B (Business Logic), Pipeline C (State Inconsistency), Pipeline D (Pashov)

**Description:**

The `processRewards()` function in `RewardsDistributor` is permissionless -- anyone can call it. It reads the ETH balances of `executionLayerReceiver` and `consensusLayerReceiver`, transfers those balances to itself, deducts fees, and sends the net rewards to `ynETH.receiveRewards()`.

The code itself contains a comment acknowledging this risk at line 128-129:
```
// NOTE: Having the permisionless processRewards able to send rewards to ynETH
// opens up ynETH to donation attack for a non boostrapped system.
```

Similarly, `StakingNodesManager.totalDeposited()` at line 752-753:
```
// NOTE: Counting the availableRedemptionAssets towards totalDeposited
//  opens up ynETH to donation attack for a non boostrapped system.
```

An attacker could donate ETH to the `consensusLayerReceiver` or `executionLayerReceiver` contracts (which have `receive() external payable {}`), then call `processRewards()` to inflate `totalDepositedInPool` in ynETH. Before the first real deposit, this manipulates the share price. After bootstrapping, donation would simply increase all holders' share value proportionally (no direct exploit), but the attack window during bootstrapping is real.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/RewardsDistributor.sol` lines 107-142
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynETH.sol` lines 258-265
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/RewardsReceiver.sol` line 69

**Impact:** Before bootstrapping, an attacker could manipulate the initial share price, causing the first real depositor to receive fewer shares. The classic "first depositor" inflation attack vector.

**Recommendation:** Add access control to `processRewards()` or ensure the system is bootstrapped with a meaningful deposit before making it publicly available. Alternatively, implement a minimum initial deposit that seeds the share supply at a safe ratio.

---

### F-02: Trusted off-chain `rewardsAmount` in principal withdrawals can misattribute principal as rewards

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `StakingNodesManager.sol`
**Function(s):** `_processPrincipalWithdrawalForNode()`
**Sources:** Pipeline B (Business Logic), Pipeline D (Pashov)

**Description:**

The `WithdrawalAction` struct includes a `rewardsAmount` field that is trusted off-chain input, as acknowledged in the code comments at lines 604-617:

```solidity
// The rewardsAmount is trusted off-chain input provided in the WithdrawalAction struct.
// SECURITY NOTE:
// The accuracy and integrity of this value relies on the off-chain process
// that calculates it. There's an implicit trust that the WITHDRAWAL_MANAGER_ROLE
// will provide correct and verified data and that principal is not counted as Rewards
// and applied a fee.
```

If the `WITHDRAWAL_MANAGER_ROLE` (or an attacker who compromises this role) provides an inflated `rewardsAmount`, protocol fees are applied to principal, extracting value from stakers. The fee is sent to `feesReceiver` and the net is returned to `ynETH.receiveRewards()`.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNodesManager.sol` lines 599-663

**Impact:** Incorrect reward attribution leads to excessive fee extraction from the protocol's total assets. Since `totalAssets()` decreases by the fee amount (line 647-651), this directly reduces the ynETH exchange rate, harming all holders.

**Recommendation:** Implement on-chain bounds checking. For example, track the original deposit amount per validator and cap `rewardsAmount` at `totalAmount - expectedPrincipal`. Even a rough bound would limit the damage from misconfiguration.

---

### F-03: `pendingRequestedRedemptionAmount` can desync from actual claims due to rate-minimum logic

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `requestWithdrawal()`, `_claimWithdrawal()`
**Sources:** Pipeline B (Business Logic), Pipeline C (State Inconsistency)

**Description:**

When a withdrawal is requested, `pendingRequestedRedemptionAmount` is increased by `calculateRedemptionAmount(amount, currentRate)` at the current rate. When it is claimed, the actual redemption uses `min(requestRate, finalizationRate)`:

```solidity
// Line 292-296
uint256 redemptionRate = (
    request.redemptionRateAtRequestTime < redemptionRateAtFinalization
    ? request.redemptionRateAtRequestTime
    : redemptionRateAtFinalization
);
```

However, `pendingRequestedRedemptionAmount` is decreased by the amount calculated with the *request-time rate* (line 210), not the minimum rate that was actually used for the claim:

At request time (line 210): `pendingRequestedRedemptionAmount += calculateRedemptionAmount(amount, currentRate);`
At claim time (line 300): `pendingRequestedRedemptionAmount -= unitOfAccountAmount;`

Where `unitOfAccountAmount = calculateRedemptionAmount(request.amount, min(requestRate, finalizationRate))`.

If `finalizationRate < requestRate`, then `unitOfAccountAmount` will be *less* than what was originally added to `pendingRequestedRedemptionAmount`. This means `pendingRequestedRedemptionAmount` decreases by a smaller amount than was added, leaving a persistent positive delta. Over many withdrawals where rate drops occur, this accumulation makes `pendingRequestedRedemptionAmount` permanently overstated.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 191-214, 253-320

**Impact:** An overstated `pendingRequestedRedemptionAmount` means `surplusRedemptionAssets()` returns a lower value, preventing withdrawal of genuine surplus. It also causes `deficitRedemptionAssets()` to overstate the deficit, potentially triggering unnecessary withdrawal queuing in the ynEIGEN `WithdrawalsProcessor`.

**Recommendation:** Track `pendingRequestedRedemptionAmount` using the request-time rate (as currently done for the increase) and also the same rate for the decrease. Alternatively, recalculate the pending amount based on finalized rates.

---

### F-04: `WithdrawalQueueManager.finalizeRequestsUpToIndex` creates Finalization before validation

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `finalizeRequestsUpToIndex()`
**Sources:** Pipeline B (Business Logic), Pipeline D (Pashov)

**Description:**

The `finalizeRequestsUpToIndex` function pushes a new `Finalization` struct to the `finalizations` array *before* validating that `_lastFinalizedIndex` is valid:

```solidity
// Line 475-484 - Struct is created and pushed FIRST
Finalization memory newFinalization = Finalization({
    startIndex: SafeCast.toUint64(lastFinalizedIndex),
    endIndex: SafeCast.toUint64(_lastFinalizedIndex),
    redemptionRate: SafeCast.toUint96(currentRate)
});
finalizationIndex = finalizations.length;
finalizations.push(newFinalization);

// Line 486-491 - Validation happens AFTER
if (_lastFinalizedIndex > _tokenIdCounter) {
    revert IndexExceedsTokenCount(_lastFinalizedIndex, _tokenIdCounter);
}
if (_lastFinalizedIndex <= lastFinalizedIndex) {
    revert IndexNotAdvanced(_lastFinalizedIndex, lastFinalizedIndex);
}
```

If the validation reverts, the entire transaction reverts and the push is undone. However, this is a checks-effects-interactions pattern violation. If a future modification adds a try/catch or if the function is called via delegatecall in some context, the invalid Finalization could persist.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 466-495

**Impact:** Currently the revert undoes the push, so this is not exploitable in the current code. However, it violates defensive programming principles and creates a latent bug if the function's calling context changes. The reversed order also means the `finalizationIndex` return value is computed even when the call will revert, wasting gas.

**Recommendation:** Move the validation checks (lines 486-491) above the Finalization creation (lines 475-484) to follow proper checks-effects-interactions ordering.

---

### F-05: `RedemptionAssetsVault.transferRedemptionAssets` rounding loss in multi-asset transfer loop

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `ynEIGEN/RedemptionAssetsVault.sol`
**Function(s):** `transferRedemptionAssets()`
**Sources:** Pipeline B (Business Logic), Pipeline E (QuillAI)

**Description:**

The `transferRedemptionAssets` function in the ynEIGEN `RedemptionAssetsVault` iterates through assets and converts between unit-of-account amounts and asset amounts using `convertToUnitOfAccount` and `convertFromUnitOfAccount`. Each conversion incurs rounding:

```solidity
// Line 176-177
uint256 assetBalanceInUnit = assetRegistry.convertToUnitOfAccount(asset, assetBalance);
if (assetBalanceInUnit >= amount) {
    uint256 reqAmountInAsset = assetRegistry.convertFromUnitOfAccount(asset, amount);
```

The double conversion (asset -> unit -> asset) loses precision. For assets with different decimal counts or highly volatile exchange rates, the actual transferred amount may be slightly less than the claimed `unitOfAccountAmount`. This could leave small amounts of assets stranded in the vault or result in users receiving marginally less than expected.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/RedemptionAssetsVault.sol` lines 165-191

**Impact:** Small rounding losses per withdrawal. Over many withdrawals, these can accumulate, though each individual loss is minimal. The `balances` mapping may also drift slightly from actual token balances.

**Recommendation:** Consider adding a small dust threshold tolerance in the balance accounting. For critical paths, compute asset amounts directly rather than double-converting through the unit of account.

---

### F-06: `RewardsDistributor.processRewards` uses `assert()` for balance check instead of `require()`

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `RewardsDistributor.sol`
**Function(s):** `processRewards()` via `assertBalanceUnchanged` modifier
**Sources:** Pipeline A (SCV Scan), Pipeline D (Pashov)

**Description:**

The `assertBalanceUnchanged` modifier uses `assert()`:

```solidity
modifier assertBalanceUnchanged() {
    uint256 before = address(this).balance;
    _;
    assert(address(this).balance == before);
}
```

Per the SCV cheatsheet, `assert()` should only be used for invariants that can never fail. The `RewardsDistributor` contract has a `receive() external payable {}` fallback, meaning anyone can send ETH to the contract between the `before` snapshot and the `assert` check. While this would require a transaction being mined in the same block (practically difficult with a single `processRewards` call), it technically makes the assertion violable.

In Solidity 0.8+, `assert` failures cause a `Panic(0x01)` error and consume all remaining gas (unlike `require` which refunds remaining gas prior to EIP-3529 and still provides error messages).

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/RewardsDistributor.sol` lines 177-181

**Impact:** If ETH is sent to the contract during execution (e.g., via selfdestruct or coinbase transactions), the assert will fail, consuming all gas. An attacker could grief `processRewards()` calls by front-running with ETH delivery to the RewardsDistributor address.

**Recommendation:** Replace `assert` with `require` for a more informative error and gas refund on failure. Consider using `>=` instead of `==` to tolerate unexpected ETH inflows, or remove the modifier entirely if the accounting is trusted.

---

### F-07: `ynETH.processWithdrawnETH` has overly broad caller authorization

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ynETH.sol`
**Function(s):** `processWithdrawnETH()`
**Sources:** Pipeline A (SCV Scan), Pipeline D (Pashov)

**Description:**

The `processWithdrawnETH` function allows calls from either `stakingNodesManager` or `stakingNodesManager.redemptionAssetsVault()`:

```solidity
function processWithdrawnETH() public payable {
    if (!(msg.sender == address(stakingNodesManager)
        || msg.sender == (address(stakingNodesManager.redemptionAssetsVault())))) {
        revert CallerNotAuthorized(msg.sender);
    }
    totalDepositedInPool += msg.value;
}
```

This function increases `totalDepositedInPool` which directly affects the ynETH share price via `totalAssets()`. The `redemptionAssetsVault` is a separate contract whose address is set in `StakingNodesManager.initializeV2()`. If the `redemptionAssetsVault` is compromised or if its address is not yet set (returns `address(0)` before `initializeV2`), authorization could be bypassed.

Before `initializeV2` is called, `stakingNodesManager.redemptionAssetsVault()` returns `address(0)`, meaning `address(0)` is an authorized caller. However, `address(0)` cannot initiate transactions, so this is not exploitable in practice.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynETH.sol` lines 298-308

**Impact:** Low in current deployment. However, the trust assumption on `redemptionAssetsVault` being correctly deployed is important -- if it is compromised, an attacker could inflate `totalDepositedInPool` to manipulate the share price.

**Recommendation:** Consider adding explicit validation that the vault address is not zero before accepting it as an authorized caller.

---

### F-08: `updateTotalETHStaked` is permissionless and iterates all nodes

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `StakingNodesManager.sol`
**Function(s):** `updateTotalETHStaked()`
**Sources:** Pipeline A (SCV Scan), Pipeline E (QuillAI - DoS/griefing)

**Description:**

`updateTotalETHStaked()` is a public function with no access control that iterates through all staking nodes:

```solidity
function updateTotalETHStaked() public {
    uint256 updatedTotalETHStaked = 0;
    IStakingNode[] memory allNodes = getAllNodes();
    for (uint256 i = 0; i < allNodes.length; i++) {
        if (!allNodes[i].isSynchronized()) {
            revert NodeNotSynchronized(address(allNodes[i]));
        }
        updatedTotalETHStaked += allNodes[i].getETHBalance();
    }
    totalETHStaked = updatedTotalETHStaked;
}
```

As the number of nodes grows, this becomes increasingly expensive. Each `getETHBalance()` call makes an external call to `delegationManager.getWithdrawableShares()`. With many nodes, this could approach the block gas limit. Additionally, if any single node is not synchronized, the entire function reverts, potentially blocking other operations that depend on `updateTotalETHStaked()` (such as `registerValidators` and `processPrincipalWithdrawals`).

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNodesManager.sol` lines 671-684

**Impact:** A single unsynchronized node can block validator registration and principal withdrawal processing. As node count grows, gas costs scale linearly with potential DoS at high node counts.

**Recommendation:** Consider implementing batched updates or caching per-node balances that can be updated individually. Add a mechanism to exclude specific nodes from the total if they are temporarily out of sync.

---

### F-09: `StakingNode.synchronize()` is permissionless allowing timing manipulation

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `StakingNode.sol`, `TokenStakingNode.sol`
**Function(s):** `synchronize()`
**Sources:** Pipeline D (Pashov), Pipeline E (QuillAI)

**Description:**

Both `StakingNode.synchronize()` and `TokenStakingNode.synchronize()` are public functions callable by anyone. While the documentation states this is intentional ("Anyone can call this function because every call is beneficial to the protocol"), the timing of synchronization can matter.

In `StakingNode`, `synchronize()` updates both `delegatedTo` and calls `syncQueuedShares()`, which rebuilds the `queuedSharesAmount` from the delegation manager's state. If an attacker calls `synchronize()` at a strategically chosen moment (e.g., immediately after a slashing event but before the protocol's admin has prepared the appropriate response), it could lock in unfavorable state.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNode.sol` lines 576-582
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/TokenStakingNode.sol` lines 419-454

**Impact:** An attacker could manipulate the timing of state synchronization to their advantage, though the actual financial impact is limited since synchronization reflects the true state of the delegation manager.

**Recommendation:** Consider restricting `synchronize()` to authorized roles or implementing a delay mechanism. The current design is a reasonable trade-off, but the team should be aware of the timing implications.

---

### F-10: `WithdrawalQueueManager.findFinalizationForTokenId` unbounded binary search can underflow

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `findFinalizationForTokenId()`
**Sources:** Pipeline A (SCV Scan), Pipeline B (Business Logic)

**Description:**

The binary search implementation has a potential underflow issue:

```solidity
function findFinalizationForTokenId(uint256 tokenId) public view returns (uint256 finalizationId) {
    uint256 left = 0;
    uint256 right = finalizationsLength - 1;
    while (left <= right) {
        uint256 mid = (left + right) / 2;
        // ...
        } else if (tokenId < finalization.startIndex) {
            right = mid - 1; // Can underflow when mid = 0
        }
```

When `mid = 0` and the condition `tokenId < finalization.startIndex` is true, `right = mid - 1` underflows to `type(uint256).max` in Solidity 0.8+, causing a revert. This is actually correct behavior (the token is not finalized), but the revert message will be a Panic rather than the intended `NotFinalized` error.

The function comment on line 501 acknowledges it is "UNBOUNDED" in complexity.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 503-527

**Impact:** Calling `findFinalizationForTokenId` with a token ID that precedes all finalizations will cause an arithmetic underflow panic instead of the descriptive `NotFinalized` error. This affects UX and gas efficiency.

**Recommendation:** Add a check: `if (mid == 0 && tokenId < finalization.startIndex) revert NotFinalized(tokenId);` before the `right = mid - 1` assignment.

---

### F-11: `initializeV3` in `StakingNodesManager` lacks access control modifier

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `StakingNodesManager.sol`
**Function(s):** `initializeV3()`
**Sources:** Pipeline A (SCV Scan)

**Description:**

`initializeV3` uses `reinitializer(3)` but has no access control modifier:

```solidity
function initializeV3(
    IRewardsCoordinator _rewardsCoordinator
) external virtual reinitializer(3) {
```

In contrast, `initializeV2` requires `onlyRole(DEFAULT_ADMIN_ROLE)`. The `reinitializer(3)` modifier ensures this can only be called once, but anyone can front-run the admin's initialization call with potentially malicious parameters (e.g., setting `_rewardsCoordinator` to a controlled address).

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNodesManager.sol` lines 248-261

**Impact:** An attacker could front-run the initialization with a malicious `rewardsCoordinator` address, potentially redirecting reward claims. The `reinitializer` prevents repeated calls, making this a one-shot opportunity during upgrade deployment.

**Recommendation:** Add `onlyRole(DEFAULT_ADMIN_ROLE)` modifier to `initializeV3`.

---

### F-12: TODO comments remain in production code indicating incomplete review

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `StakingNodesManager.sol`
**Function(s):** `initializeV2()`
**Sources:** Pipeline A (SCV Scan)

**Description:**

Two TODO comments remain in the codebase:

```solidity
// TODO: hardcode these values instead of setting them as parameters
function initializeV2(Init2 calldata init)
    ...
    // TODO: review role access here for what can execute this
```

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNodesManager.sol` lines 230, 239

**Impact:** Indicates incomplete review and potentially sub-optimal parameter handling. The role access TODO suggests the developers themselves were unsure about the access control design.

**Recommendation:** Resolve all TODO items before production deployment. Hardcode values where possible to reduce initialization attack surface.

---

### F-13: `ynEigen.processWithdrawn` calls `safeTransferFrom` after updating state

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `ynEIGEN/ynEigen.sol`
**Function(s):** `processWithdrawn()`
**Sources:** Pipeline A (SCV Scan)

**Description:**

The `processWithdrawn` function updates the internal balance before performing the token transfer:

```solidity
function processWithdrawn(uint256 _amount, address _asset) public {
    // ...
    uint256 _newBalance = assets[_asset].balance + _amount;
    assets[_asset].balance = _newBalance;
    IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
}
```

If the `safeTransferFrom` reverts, the entire transaction reverts, so the state update is undone. However, this ordering violates the checks-effects-interactions pattern. With certain ERC-20 tokens that have transfer callbacks (ERC-777), this could potentially be exploited via reentrancy, though the function's caller restriction (`yieldNestStrategyManager` or `redemptionAssetsVault`) makes this unlikely.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/ynEigen.sol` lines 323-338

**Impact:** Minimal given the caller restrictions, but represents a pattern that could become problematic if access is broadened.

**Recommendation:** Move the `safeTransferFrom` call before the state update, or add `nonReentrant` to this function.

---

### F-14: `Finalization.redemptionRate` truncated to `uint96` may overflow for high-value tokens

**Severity:** Informational
**Confidence:** Low
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `finalizeRequestsUpToIndex()`
**Sources:** Pipeline E (QuillAI), Pipeline F (Token Integration)

**Description:**

The `Finalization` struct uses `uint96` for `redemptionRate`:

```solidity
struct Finalization {
    uint64 startIndex;
    uint64 endIndex;
    uint96 redemptionRate;
}
```

`uint96` has a maximum value of approximately 7.9 * 10^28. The redemption rate is calculated as `ynETH.previewRedeem(1e18)` or `ynEigen.previewRedeem(1e18)`, which for ETH-denominated tokens would need to exceed ~79 billion ETH per ynETH to overflow. This is practically impossible for ynETH.

However, if this pattern is reused for tokens with extremely high rates or different decimal configurations, the `SafeCast.toUint96` will revert, potentially blocking finalization.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 16-19, 478

**Impact:** Negligible for current usage. Would only be relevant if the contract is reused for non-ETH-denominated assets with extreme rate values.

**Recommendation:** Document the `uint96` assumption. If the contract may be reused for other asset types, consider using `uint128` or `uint256`.

---

## Cross-Reference with Existing Audits

The protocol has been audited by **Chain Security** and **Zokyo**. Based on the patterns observed in the codebase:

1. **Donation Attack (F-01):** The code contains explicit comments acknowledging this risk (lines 128-129 in RewardsDistributor.sol and lines 752-753 in StakingNodesManager.sol), suggesting this was likely identified in a previous audit. The team appears to have accepted the risk for bootstrapped systems while acknowledging the theoretical vector.

2. **Off-chain Trust Assumptions (F-02):** The detailed security comments around `rewardsAmount` in `_processPrincipalWithdrawalForNode` (lines 604-617) indicate this design trade-off was deliberately documented, likely as a result of prior audit feedback regarding EigenLayer M3's lack of principal/reward separation.

3. **ELIP-002 Slashing Integration:** The dual-tracking of `preELIP002QueuedSharesAmount` and post-upgrade `queuedSharesAmount`, along with the `NotSyncedAfterSlashing` check, indicates thorough handling of the EigenLayer slashing upgrade. The `synchronize()` pattern and `onlyWhenSynchronized` modifier appear to be post-audit additions to handle slashing-induced desynchronization.

4. **New Findings:** F-03 (pending amount desync), F-04 (finalization ordering), F-10 (binary search underflow), and F-11 (missing access control on initializeV3) appear to be newly identified issues not addressed by the acknowledged comments in the codebase.

## Informational Notes

### Best Practices Observed

1. **ReentrancyGuard Usage:** Properly applied on `StakingNode`, `TokenStakingNode`, `ynEigen`, `WithdrawalQueueManager`, `RedemptionAssetsVault`, and `ynETHRedemptionAssetsVault`.

2. **SafeERC20:** Consistently used throughout the ynEIGEN subsystem for all ERC20 interactions.

3. **Access Control:** Comprehensive role-based access control with granular roles (STAKING_ADMIN_ROLE, VALIDATOR_MANAGER_ROLE, STAKING_NODES_OPERATOR_ROLE, etc.).

4. **Initializer Protection:** All upgradeable contracts properly use `_disableInitializers()` in constructors and `initializer`/`reinitializer()` modifiers.

5. **Zero Address Checks:** Consistent use of `notZeroAddress` modifiers across initialization functions.

6. **ERC7201 Namespaced Storage:** `ynBase` uses the ERC-7201 storage pattern to avoid storage collisions in upgradeable contracts.

### Architectural Observations

1. **Transfer Pause Mechanism:** `ynBase` implements a one-way unpause toggle -- once transfers are unpaused, they cannot be re-paused. This is a deliberate security choice that prevents governance attacks from re-enabling transfer restrictions.

2. **Beacon Proxy Pattern:** Both `StakingNode` and `TokenStakingNode` use the beacon proxy pattern, enabling efficient batch upgrades of all nodes simultaneously.

3. **Versioned Initialization:** The `initializeStakingNode` pattern in `StakingNodesManager` handles multi-version initialization gracefully, ensuring new nodes start at the latest version and existing nodes are upgraded incrementally.

4. **Dual Subsystem Design:** The ynETH (native ETH) and ynEIGEN (multi-asset) subsystems share the `ynBase` token base and `WithdrawalQueueManager` pattern but have independent strategy managers and staking node implementations, reducing cross-contamination risk.

### Gas Optimization Notes

1. **ArrayLib.deduplicate:** O(n^2) complexity. Acceptable for small arrays (node counts typically < 100) but would be problematic at scale.

2. **getAllAssetBalances in AssetRegistry:** Iterates all assets and all nodes, creating O(assets * nodes) complexity. This is bounded by the `maxNodeCount` parameter.

3. **ynEIGEN WithdrawalsProcessor:** The `getTotalQueuedWithdrawals()` function iterates all assets and all nodes with external calls, making it expensive. It is called frequently in the keeper workflow.
