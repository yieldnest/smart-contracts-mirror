# Security Audit Report: yieldnest-eigenlayer-lrt

## Metadata
- **Repository:** yieldnest-eigenlayer-lrt
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6
- **Branch:** flat-repos
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24 (solc 0.8.27)
- **Previous Audits:** Chain Security, Zokyo
- **Additional Pipelines:** Forefy + Archethect (OpenAudit), Auditmos DeFi Checklists

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
| G | Forefy + Archethect | Protocol-specific 5-layer audit + SETUP-MAP-HUNT-ATTACK methodology | 17 |
| H | Auditmos DeFi Checklists | 14 DeFi-specific vulnerability checklists (staking, slippage, math precision, etc.) | 7 |

## Executive Summary

The yieldnest-eigenlayer-lrt repository implements a comprehensive liquid restaking protocol with two subsystems: ynETH (native ETH restaking) and ynEIGEN (multi-asset token restaking), both integrated with EigenLayer's delegation and slashing infrastructure. The protocol has been previously audited by Chain Security and Zokyo.

This audit identified **32 unique findings** across 8 independent methodologies. The codebase demonstrates strong security engineering overall, with proper use of ReentrancyGuard, AccessControl, SafeERC20, and careful checks-effects-interactions patterns. The most notable issues relate to: (1) permissionless reward processing enabling donation/inflation attacks in edge cases, (2) trusted off-chain inputs for reward/principal separation, (3) potential precision loss in multi-asset redemption flows, (4) finalization ordering issues in the withdrawal queue, (5) absence of staleness and bounds checking on LSD rate oracle sources, (6) unenforced finalization delay despite declared infrastructure, (7) share price manipulation via privileged burn, and (8) missing reentrancy protection on the ynETH core contract.

The ELIP-002 slashing integration adds significant complexity to the accounting model, particularly the dual-tracking of pre/post-upgrade queued shares. The synchronization mechanism is well-designed but relies on external callers to invoke `synchronize()` after operator-initiated undelegation events.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| F-01 | Medium | Permissionless `processRewards()` enables donation attack on non-bootstrapped system | B, C, D | High |
| F-02 | Medium | Trusted off-chain `rewardsAmount` in principal withdrawals can misattribute principal as rewards | B, D | High |
| F-03 | Medium | `pendingRequestedRedemptionAmount` can desync from actual claims due to rate-minimum logic | B, C | Medium |
| F-04 | Medium | `WithdrawalQueueManager.finalizeRequestsUpToIndex` creates Finalization before validation | B, D | High |
| F-05 | Low | `RedemptionAssetsVault.transferRedemptionAssets` rounding loss in multi-asset transfer loop | B, E | High |
| F-06 | Low | `RewardsDistributor.processRewards` uses `assert()` for balance check instead of `require()` | A, D, G | High |
| F-07 | Low | `ynETH.processWithdrawnETH` has overly broad caller authorization | A, D | Medium |
| F-08 | Low | `updateTotalETHStaked` is permissionless and iterates all nodes | A, E, G | Medium |
| F-09 | Low | `StakingNode.synchronize()` is permissionless allowing timing manipulation | D, E | Medium |
| F-10 | Low | `WithdrawalQueueManager.findFinalizationForTokenId` unbounded binary search can underflow | A, B | Medium |
| F-11 | Medium | `initializeV3` in `StakingNodesManager` lacks access control modifier | A, G | High |
| F-12 | Informational | TODO comments remain in production code indicating incomplete review | A | High |
| F-13 | Informational | `ynEigen.processWithdrawn` calls `safeTransferFrom` after updating state | A, G | Medium |
| F-14 | Informational | `Finalization.redemptionRate` truncated to `uint96` may overflow for high-value tokens | E, F | Low |
| F-15 | Medium | LSDRateProvider returns on-chain rates with no staleness, bounds, or revert handling | G, H | High |
| F-16 | Medium | `secondsToFinalization` declared but never initialized or enforced | H | High |
| F-17 | Medium | ynETH and ynEigen share pricing vulnerable to `totalSupply` manipulation via privileged burn | G | Medium |
| F-18 | Medium | `WithdrawalsProcessor.processPrincipalWithdrawals` finalizes with potentially stale `tokenIdToFinalize` | G | Medium |
| F-19 | Low | ynETH contract has no ReentrancyGuard protection | H | Medium |
| F-20 | Low | `RedemptionAssetsVault.deposit` credits balance before receiving tokens (CEI violation) | G | Medium |
| F-21 | Low | `SafeCast.toUint128` truncation risk for strategy balances in `EigenStrategyManager` | G | Medium |
| F-22 | Low | `TokenStakingNode.synchronize` deletes `queuedShares` before rebuilding, allowing transient zero state | G | Medium |
| F-23 | Low | `WithdrawalQueueManager.claimWithdrawal` allows approved address but not `isApprovedForAll` operator | G | High |
| F-24 | Low | `StakingNode.completeQueuedWithdrawals` GWEI truncation allows up to 1 Gwei discrepancy per withdrawal | G, H | High |
| F-25 | Low | `RedemptionAssetsVault.transferRedemptionAssets` iterates assets in fixed order, creating unfair distribution | G | High |
| F-26 | Low | `WithdrawalQueueManager.setWithdrawalFee` allows fee up to 100% | G | High |
| F-27 | Low | `PooledDepositsVault.finalizeDeposits` has no deadline or minimum shares protection | G | Medium |
| F-28 | Low | `AssetRegistry` conversion functions use plain division, risking rounding loss | H | High |
| F-29 | Low | `synchronizeNodesAndUpdateBalances` is permissionless in ynEIGEN and can trigger costly state updates | H | Medium |
| F-30 | Informational | `ynViewer.getRate` and `ynEigenViewer.getRate` return `1 ether` when totalAssets is zero, masking catastrophic state | G | High |
| F-31 | Informational | `WithdrawalQueueManager.withdrawalFee` NatSpec says "basis points" but `FEE_PRECISION` is parts-per-million | G | High |
| F-32 | Informational | Withdrawal queue pause not synchronized with redemption vault pause, no grace period | H | Medium |

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
**Sources:** Pipeline A (SCV Scan), Pipeline D (Pashov), Pipeline G (Forefy)

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

**Recommendation:** Replace `assert` with a custom error revert for better gas efficiency and debugging. Consider using `>=` instead of `==` to tolerate unexpected ETH inflows, or remove the modifier entirely if the accounting is trusted.

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
**Sources:** Pipeline A (SCV Scan), Pipeline E (QuillAI - DoS/griefing), Pipeline G (Archethect)

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

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `StakingNodesManager.sol`
**Function(s):** `initializeV3()`
**Sources:** Pipeline A (SCV Scan), Pipeline G (Forefy + Archethect)

**Description:**

`initializeV3` uses `reinitializer(3)` but has no access control modifier:

```solidity
function initializeV3(
    IRewardsCoordinator _rewardsCoordinator
) external virtual reinitializer(3) {
```

In contrast, `initializeV2` requires `onlyRole(DEFAULT_ADMIN_ROLE)`. The `reinitializer(3)` modifier ensures this can only be called once, but anyone can front-run the admin's initialization call with potentially malicious parameters (e.g., setting `_rewardsCoordinator` to a controlled address).

The Forefy + Archethect pipeline (G) independently confirmed this finding and elevated it to Medium severity. If front-run during deployment, the attacker sets a malicious `rewardsCoordinator` address. The `StakingNode.setClaimer()` function calls `rewardsCoordinator.setClaimerFor(claimer)`, which would interact with the attacker's contract. This could allow the attacker to intercept or redirect EigenLayer reward claims.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNodesManager.sol` lines 248-261

**Impact:** An attacker could front-run the initialization with a malicious `rewardsCoordinator` address, potentially redirecting reward claims. The `reinitializer` prevents repeated calls, making this a one-shot opportunity during upgrade deployment. Severity elevated to Medium due to the direct impact on reward claim redirection confirmed by Pipeline G.

**Recommendation:** Add `onlyRole(DEFAULT_ADMIN_ROLE)` modifier to `initializeV3`, consistent with `initializeV2`.

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
**Sources:** Pipeline A (SCV Scan), Pipeline G (Archethect)

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

Pipeline G (Archethect) additionally notes that while the contract inherits `ReentrancyGuardUpgradeable`, `processWithdrawn` does not use the `nonReentrant` modifier, meaning the CEI violation is not mitigated by a reentrancy guard on this specific function.

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

### F-15: LSDRateProvider returns on-chain rates with no staleness, bounds, or revert handling

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `ynEIGEN/LSDRateProvider.sol`, `ynEIGEN/AssetRegistry.sol`
**Function(s):** `rate()`
**Sources:** Pipeline G (Archethect + Forefy), Pipeline H (Auditmos oracle checklist)

**Description:**

`LSDRateProvider.rate()` reads exchange rates from various LSD protocols (Lido `getPooledEthByShares`, RocketPool `getExchangeRate`, Swell `swETHToETHRate`, Frax dual oracle, etc.) without any staleness validation, sanity bounds, or manipulation resistance. These rates feed directly into `AssetRegistry.convertToUnitOfAccount()`, which determines share pricing for deposits and withdrawals via `ynEigen.totalAssets()`.

```solidity
// Line 49-78: All calls are bare external calls with no validation
function rate(address _asset) external view returns (uint256) {
    if (_asset == LIDO_ASSET) {
        return IstETH(LIDO_UDERLYING).getPooledEthByShares(UNIT);
        // No staleness check, no bounds check, no try/catch
    }
    if (_asset == FRAX_ASSET) {
        uint256 frxETHPriceInETH = IFrxEthWethDualOracle(FRX_ETH_WETH_DUAL_ORACLE).getCurveEmaEthPerFrxEth();
        return IsfrxETH(FRAX_ASSET).pricePerShare() * frxETHPriceInETH / UNIT;
        // Two external calls, either could revert or return stale/extreme values
    }
    // ... similar patterns for woETH, rETH, mETH, swETH
}
```

The Auditmos oracle checklist (Pipeline H) flagged five distinct failures: no staleness detection, no try/catch revert handling, no min/max bounds validation, no circuit breaker, and only partial depeg monitoring (FrxEthWethDualOracle covers sfrxETH but other assets have none).

**Impact:**
- If any single LSD protocol's rate source reverts, all ynEIGEN deposits and withdrawals for ALL assets would be blocked (since `AssetRegistry.getAssets()` iterates all assets in `availableRedemptionAssets()` and `totalAssets()`).
- A compromised or buggy rate source returning an inflated rate would allow an attacker to deposit the affected LSD token and receive a disproportionate number of ynEigen shares, diluting other depositors.
- A rate returning 0 would cause division by zero in `convertFromUnitOfAccount` or allow free share minting.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/LSDRateProvider.sol` lines 49-78
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/AssetRegistry.sol` lines 306-320

**Recommendation:**
1. Wrap each external call in a try/catch pattern, falling back to a cached last-known-good rate or reverting with a specific error.
2. Add min/max bounds validation on returned rates (e.g., rates should be between 0.9e18 and 1.5e18 for LSDs that track ETH).
3. Consider adding a staleness timestamp tracking mechanism or a circuit breaker that pauses affected assets.

---

### F-16: `secondsToFinalization` declared but never initialized or enforced

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `initialize()`, `finalizeRequestsUpToIndex()`
**Sources:** Pipeline H (Auditmos state-validation checklist)

**Description:**

The `WithdrawalQueueManager` declares `secondsToFinalization` (line 104) and defines `MAX_SECONDS_TO_FINALIZATION = 3600 * 24 * 28` (line 85), and emits a `SecondsToFinalizationUpdated` event (line 32). However:

1. The `initialize()` function (lines 145-166) never sets `secondsToFinalization`, leaving it at the default value of 0.
2. There is no `setSecondsToFinalization()` function anywhere in the contract.
3. The `finalizeRequestsUpToIndex()` function (lines 466-495) never checks whether sufficient time has elapsed since withdrawal requests were created.

This means withdrawal requests can be finalized immediately after creation, bypassing any intended time delay. The infrastructure for a finalization delay exists (variable declaration, max constant, event) but the enforcement logic is completely missing.

```solidity
// Line 104: Declared but never set
uint256 public secondsToFinalization;

// Lines 466-495: finalizeRequestsUpToIndex never checks secondsToFinalization
function finalizeRequestsUpToIndex(uint256 _lastFinalizedIndex)
    external
    onlyRole(REQUEST_FINALIZER_ROLE)
    returns (uint256 finalizationIndex)
{
    uint256 currentRate = redemptionAssetsVault.redemptionRate();
    // ... creates Finalization struct and pushes it
    // NO CHECK: block.timestamp >= request.creationTimestamp + secondsToFinalization
    // ...
    lastFinalizedIndex = _lastFinalizedIndex;
}
```

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 85, 104, 145-166, 466-495

**Impact:** The `REQUEST_FINALIZER_ROLE` can finalize withdrawal requests in the same block they are created. This eliminates any time buffer that would allow the protocol to prepare redemption assets or respond to market events. While the finalizer is a trusted role, the absence of a configurable time delay removes a key safety mechanism for users who expected a delay between requesting and finalization.

**Recommendation:** Add a `setSecondsToFinalization()` admin function and enforce the delay in `finalizeRequestsUpToIndex()`:

```solidity
function setSecondsToFinalization(uint256 _seconds) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
    if (_seconds > MAX_SECONDS_TO_FINALIZATION) {
        revert SecondsToFinalizationExceedsLimit(_seconds);
    }
    emit SecondsToFinalizationUpdated(secondsToFinalization, _seconds);
    secondsToFinalization = _seconds;
}
```

In `finalizeRequestsUpToIndex`, verify that the oldest unfinalized request has passed the required delay.

---

### F-17: ynETH and ynEigen share pricing vulnerable to `totalSupply` manipulation via privileged burn

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `ynETH.sol`, `ynEIGEN/ynEigen.sol`
**Function(s):** `_convertToShares()`
**Sources:** Pipeline G (Archethect + Forefy)

**Description:**

Both `ynETH._convertToShares` and `ynEigen._convertToShares` use `totalSupply() == 0` to determine whether to use the 1:1 bootstrap exchange rate. The `BURNER_ROLE` holder can burn tokens via `burn()`. If all shares except a dust amount are burned while `totalAssets()` remains large (due to staked ETH in validators or strategies), the share price becomes enormously inflated.

```solidity
function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view returns (uint256) {
    if (totalSupply() == 0) {
        return ethAmount;
    }
    return Math.mulDiv(ethAmount, totalSupply(), totalAssets(), rounding);
}
```

If `totalSupply()` is reduced to a very small number (e.g., 1 wei) while `totalAssets()` is large (e.g., 1000 ETH), a new deposit of 1 ETH would receive `1e18 * 1 / 1000e18 = 0` shares (rounded down), effectively donating the deposit. The `ZeroShares` revert protects against zero-share deposits, but a sufficiently small (but non-zero) share count still results in extreme value extraction.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynETH.sol` lines 165-179
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/ynEigen.sol` lines 171-189

**Impact:** Requires the `BURNER_ROLE` to be compromised or to collude. If the `BURNER_ROLE` is assigned to a contract (like `WithdrawalQueueManager`), the attack surface expands to anyone who can trigger burns through the withdrawal claim flow. A sufficiently small (but non-zero) share count still results in extreme value extraction.

**Recommendation:** Consider implementing virtual shares/assets offset (as in ERC-4626 with virtual offset) to prevent share price manipulation, or enforce a minimum `totalSupply` invariant that cannot be burned below a threshold.

---

### F-18: `WithdrawalsProcessor.processPrincipalWithdrawals` finalizes with potentially stale `tokenIdToFinalize`

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `ynEIGEN/WithdrawalsProcessor.sol`
**Function(s):** `processPrincipalWithdrawals()`
**Sources:** Pipeline G (Archethect + Forefy)

**Description:**

In `processPrincipalWithdrawals()`, the `tokenIdToFinalize` is captured from the `QueuedWithdrawal` struct at queue time (line 372: `tokenIdToFinalize: withdrawalQueueManager._tokenIdCounter()`). By the time `processPrincipalWithdrawals()` runs (potentially days or weeks later after the EigenLayer withdrawal delay), new withdrawal requests may have been created. The function then calls `withdrawalQueueManager.finalizeRequestsUpToIndex(_tokenIdToFinalize)` with this stale value.

This means all withdrawal requests created AFTER the `queueWithdrawals` call but BEFORE `processPrincipalWithdrawals` will NOT be finalized in this batch, even though the redemption assets vault may have sufficient assets to cover them. This creates a delay in finalization for newer requests.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/WithdrawalsProcessor.sol` lines 372, 440-508

**Impact:** Withdrawal requests created between the queue and process steps experience delayed finalization. Users must wait for the next processing cycle to have their requests finalized. This is a liveness issue rather than a safety issue.

**Recommendation:** Consider using the current `_tokenIdCounter()` at processing time rather than the stale value from queue time, or implement a separate finalization step that is decoupled from the processing flow.

---

### F-19: ynETH contract has no ReentrancyGuard protection

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ynETH.sol`
**Function(s):** `depositETH()`, `receiveRewards()`, `processWithdrawnETH()`, `withdrawETH()`
**Sources:** Pipeline H (Auditmos reentrancy checklist)

**Description:**

The `ynETH` contract does not inherit from `ReentrancyGuardUpgradeable` and none of its state-changing functions use the `nonReentrant` modifier. This contrasts with `ynEigen.sol` which does use `nonReentrant` on its `deposit` function.

Key unprotected functions:
- `depositETH(address receiver)` -- payable, mints shares, updates `totalDepositedInPool`
- `receiveRewards()` -- payable, updates `totalDepositedInPool`
- `processWithdrawnETH()` -- payable, updates `totalDepositedInPool`
- `withdrawETH(uint256 ethAmount)` -- sends ETH via `.call{value}`, updates `totalDepositedInPool`

```solidity
// No nonReentrant modifier
function depositETH(address receiver) public payable returns (uint256 shares) {
    // ...
    shares = previewDeposit(assets); // reads totalSupply() and totalAssets()
    _mint(receiver, shares);         // mints before updating totalDepositedInPool
    totalDepositedInPool += assets;  // state update AFTER _mint
    // ...
}
```

In `depositETH`, the ordering of `_mint` before `totalDepositedInPool += assets` means that during `_mint`, if any callback were triggered, the `totalSupply()` would reflect the new shares but `totalAssets()` would not yet include the new deposit. This would cause `_convertToShares` to return fewer shares for any concurrent deposit.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynETH.sol` lines 119-141, 258-265, 272-291, 298-308

**Impact:** The practical risk is low because standard ERC20 `_mint` does not trigger receiver callbacks, and a reentrant depositor would get a worse rate. However, the complete absence of reentrancy protection is an architectural gap inconsistent with `ynEigen.sol`, suggesting it was an oversight.

**Recommendation:** Add `ReentrancyGuardUpgradeable` to `ynETH` or `ynBase`, and apply `nonReentrant` to `depositETH`, `withdrawETH`, `receiveRewards`, and `processWithdrawnETH`. Also reorder `depositETH` to update `totalDepositedInPool` before `_mint`.

---

### F-20: `RedemptionAssetsVault.deposit` credits balance before receiving tokens (CEI violation)

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ynEIGEN/RedemptionAssetsVault.sol`
**Function(s):** `deposit()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The `deposit` function updates the internal `balances[asset]` mapping before calling `safeTransferFrom`:

```solidity
function deposit(uint256 amount, address asset) external {
    if (!assetRegistry.assetIsSupported(IERC20(asset))) revert AssetNotSupported();
    balances[asset] += amount;
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    emit AssetDeposited(asset, msg.sender, amount);
}
```

This violates the checks-effects-interactions (CEI) pattern. If the token has a callback mechanism (e.g., ERC-777 `tokensToSend` hook), the balance is credited before the transfer completes, temporarily inflating `availableRedemptionAssets()`. Although the supported tokens (wstETH, woETH, etc.) are not ERC-777, this is a code quality issue that could become exploitable if the asset registry adds a token with transfer hooks.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/RedemptionAssetsVault.sol` lines 125-132

**Impact:** Currently low impact because the supported LSD tokens do not have transfer hooks. If a future asset with ERC-777 compatibility is added, the inflated `availableRedemptionAssets()` during the callback could be used to manipulate withdrawal queue calculations.

**Recommendation:** Move the `balances[asset] += amount` line after the `safeTransferFrom` call, or use the balance-before/balance-after pattern. Additionally, consider adding `nonReentrant` to the `deposit` function.

---

### F-21: `SafeCast.toUint128` truncation risk for strategy balances in `EigenStrategyManager`

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ynEIGEN/EigenStrategyManager.sol`
**Function(s):** `_updateTokenStakingNodesBalances()`
**Sources:** Pipeline G (Archethect + Forefy)

**Description:**

The `_updateTokenStakingNodesBalances` function casts the accumulated strategy balances to `uint128` using `SafeCast.toUint128`:

```solidity
StrategyBalance memory _strategyBalance = StrategyBalance({
    stakedBalance: SafeCast.toUint128(_strategiesBalance + _strategiesWithdrawalQueueBalance),
    withdrawnBalance: SafeCast.toUint128(_strategiesWithdrawnBalance)
});
```

`SafeCast.toUint128` reverts on overflow (values exceeding ~3.4e38). For 18-decimal tokens, this corresponds to approximately 3.4e20 tokens. While this is an extremely large amount, it creates a hard ceiling on the protocol's capacity for any single strategy. The revert would brick `updateTokenStakingNodesBalances`, which is required for deposit and withdrawal operations.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/EigenStrategyManager.sol` line 266

**Impact:** If any strategy accumulates more than `type(uint128).max` in underlying token units (extremely unlikely for current LSD tokens but theoretically possible for tokens with many decimals or very large TVL), all deposit and withdrawal operations for that strategy would permanently revert.

**Recommendation:** Consider using `uint256` for the `StrategyBalance` struct fields, or document the maximum supported TVL per strategy as a known limitation.

---

### F-22: `TokenStakingNode.synchronize` deletes `queuedShares` before rebuilding, allowing transient zero state

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ynEIGEN/TokenStakingNode.sol`
**Function(s):** `synchronize()`
**Sources:** Pipeline G (Archethect + Forefy)

**Description:**

The `synchronize()` function first iterates through all withdrawals to delete `queuedShares[strategy]` for each strategy, then iterates again to rebuild them:

```solidity
// Reset queued shares to 0 for each strategy
for (uint256 i = 0; i < withdrawals.length; i++) {
    IStrategy strategy = withdrawals[i].strategies[0];
    delete queuedShares[strategy];
}

for (uint256 i = 0; i < withdrawals.length; i++) {
    // ... rebuild queuedShares[strategy] += withdrawableShares;
}
```

Between the two loops, if any external call were to read `queuedShares`, the values would be zero. While `synchronize()` itself does not make external calls between the loops, the function is `public` and callable by anyone. The two-loop pattern is also redundant because strategies may appear multiple times across withdrawals, so the first loop may `delete` a strategy's shares only for the second loop to partially rebuild them.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/TokenStakingNode.sol` lines 419-454

**Impact:** Low direct impact because no external calls occur between the loops within the same transaction context. However, the two-loop pattern is fragile and could become a source of bugs in future modifications.

**Recommendation:** Combine both loops into a single pass, or collect unique strategies and reset only once before accumulating.

---

### F-23: `WithdrawalQueueManager.claimWithdrawal` allows approved address but not `isApprovedForAll` operator

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `_claimWithdrawal()`
**Sources:** Pipeline G (Forefy)

**Description:**

The `_claimWithdrawal` function checks `_ownerOf(claim.tokenId) != msg.sender && _getApproved(claim.tokenId) != msg.sender` but does not check `isApprovedForAll(owner, msg.sender)`. The ERC-721 standard's `_getApproved` only returns the single-token approved address, not the operator-for-all address. This means a user who has been granted `setApprovalForAll` by the token owner cannot claim withdrawals on their behalf.

```solidity
if (_ownerOf(claim.tokenId) != msg.sender && _getApproved(claim.tokenId) != msg.sender) {
    revert CallerNotOwnerNorApproved(claim.tokenId, msg.sender);
}
```

This is inconsistent with standard ERC-721 behavior where `isApprovedForAll` operators can perform any action the owner can.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` line 259

**Impact:** Users who set up operators via `setApprovalForAll` (common for portfolio management contracts and smart wallets) cannot claim withdrawals. This is a usability issue that may block integrations with existing infrastructure.

**Recommendation:** Add `isApprovedForAll` check:
```solidity
if (_ownerOf(claim.tokenId) != msg.sender
    && _getApproved(claim.tokenId) != msg.sender
    && !isApprovedForAll(_ownerOf(claim.tokenId), msg.sender)) {
    revert CallerNotOwnerNorApproved(claim.tokenId, msg.sender);
}
```

---

### F-24: `StakingNode.completeQueuedWithdrawals` GWEI truncation allows up to 1 Gwei discrepancy per withdrawal

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `StakingNode.sol`
**Function(s):** `completeQueuedWithdrawals()`
**Sources:** Pipeline G (Archethect + Forefy), Pipeline H (Auditmos math-precision checklist)

**Description:**

The withdrawal amount comparison truncates both sides to GWEI precision:

```solidity
if (actualWithdrawalAmount / GWEI_TO_WEI != totalWithdrawableShares / GWEI_TO_WEI) {
    revert IncorrectWithdrawalAmount();
}
```

This means a discrepancy of up to `GWEI_TO_WEI - 1 = 999999999 wei` (approximately 1 Gwei, or ~$0.000000003 at current ETH prices) between the actual withdrawal and expected amount will pass silently. While this is by design to handle EigenLayer's GWEI precision truncation, the discrepancy accumulates in `withdrawnETH` and propagates to `getETHBalance()` and ultimately `totalAssets()`.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/StakingNode.sol` lines 465-472

**Impact:** Each withdrawal can introduce up to ~1 Gwei of accounting error. Over thousands of withdrawals, this could accumulate to a meaningful amount (e.g., 1000 withdrawals = up to 1000 Gwei = 0.000001 ETH). The impact is negligible for any realistic scenario.

**Recommendation:** This is an acknowledged design decision. Consider documenting the maximum per-withdrawal rounding error explicitly in the contract comments for auditor clarity, and consider periodic reconciliation of `withdrawnETH` against actual balance.

---

### F-25: `RedemptionAssetsVault.transferRedemptionAssets` iterates assets in fixed order, creating unfair distribution

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `ynEIGEN/RedemptionAssetsVault.sol`
**Function(s):** `transferRedemptionAssets()`
**Sources:** Pipeline G (Archethect + Forefy)

**Description:**

The `transferRedemptionAssets` function iterates over assets in the order returned by `assetRegistry.getAssets()` and transfers each asset's full balance before moving to the next:

```solidity
for (uint256 i = 0; i < assets.length; ++i) {
    IERC20 asset = assets[i];
    uint256 assetBalance = balances[address(asset)];
    if (assetBalance > 0) {
        uint256 assetBalanceInUnit = assetRegistry.convertToUnitOfAccount(asset, assetBalance);
        if (assetBalanceInUnit >= amount) {
            // Transfer only needed amount of this asset
            break;
        } else {
            // Transfer ALL of this asset, continue to next
            amount -= assetBalanceInUnit;
        }
    }
}
```

The first claimant always receives the first asset in the array (e.g., wstETH), draining it before subsequent claimants who receive later assets (e.g., woETH, rETH). This creates an asymmetric outcome where the asset received depends on claim ordering and the asset registry ordering, not on the user's preference.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/RedemptionAssetsVault.sol` lines 165-191

**Impact:** Early claimants may receive a more liquid or desirable asset (e.g., wstETH), while later claimants receive less liquid assets. This creates a race condition incentive for front-running claims. The financial impact is bounded by the spread between asset values, which should be small for ETH-pegged LSDs.

**Recommendation:** Consider implementing pro-rata distribution across all available assets, or allowing claimants to specify a preferred asset. At minimum, document this behavior so users understand the asset-ordering dependency.

---

### F-26: `WithdrawalQueueManager.setWithdrawalFee` allows fee up to 100%

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `setWithdrawalFee()`
**Sources:** Pipeline G (Forefy)

**Description:**

The `setWithdrawalFee` function validates that `feePercentage <= FEE_PRECISION` (1000000), which allows a 100% fee:

```solidity
function setWithdrawalFee(uint256 feePercentage) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
    if (feePercentage > FEE_PRECISION) {
        revert FeePercentageExceedsLimit();
    }
    withdrawalFee = feePercentage;
}
```

A `WITHDRAWAL_QUEUE_ADMIN_ROLE` holder can set the fee to `FEE_PRECISION`, causing `calculateFee(amount, FEE_PRECISION)` to return the entire withdrawal amount as fees, meaning the user receives nothing.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 357-363

**Impact:** Requires compromised or malicious `WITHDRAWAL_QUEUE_ADMIN_ROLE`. Users who have already submitted withdrawal requests with a lower fee are protected because the fee is captured at request time (`feeAtRequestTime`). Only new requests created after the fee increase would be affected.

**Recommendation:** Implement a reasonable maximum fee cap (e.g., 5% = 50000) and add a timelock for fee changes to give users time to react.

---

### F-27: `PooledDepositsVault.finalizeDeposits` has no deadline or minimum shares protection

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `PooledDepositsVault.sol`
**Function(s):** `finalizeDeposits()`
**Sources:** Pipeline G (Archethect + Forefy)

**Description:**

The `finalizeDeposits` function converts pre-deposited ETH into ynETH shares at the current exchange rate without any deadline or minimum shares check:

```solidity
function finalizeDeposits(address[] calldata _depositors) external {
    if (address(ynETH) == address(0)) revert YnETHNotSet();
    for (uint256 i = 0; i < _depositors.length; i++) {
        // ...
        uint256 shares = ynETH.depositETH{value: depositAmountPerDepositor}(depositor);
    }
}
```

The caller of `finalizeDeposits` can time the call to when the ynETH exchange rate is unfavorable (e.g., after a large reward distribution that dilutes share value, or after a slashing event). There is no slippage protection or deadline parameter.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/PooledDepositsVault.sol` lines 58-71

**Impact:** Pre-depositors cannot control when their ETH is converted to shares. A malicious or negligent caller could finalize at an unfavorable rate. However, `depositETH` does revert on `ZeroShares`, providing minimal protection against extreme devaluation.

**Recommendation:** Add a `deadline` parameter to `finalizeDeposits` and consider adding a minimum shares parameter per depositor, or allow depositors to finalize their own deposits individually.

---

### F-28: `AssetRegistry` conversion functions use plain division, risking rounding loss

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `ynEIGEN/AssetRegistry.sol`
**Function(s):** `convertToUnitOfAccount()`, `convertFromUnitOfAccount()`
**Sources:** Pipeline H (Auditmos math-precision checklist)

**Description:**

The `convertToUnitOfAccount` and `convertFromUnitOfAccount` functions use plain Solidity division rather than `Math.mulDiv` for precision:

```solidity
function convertToUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
    uint256 assetRate = rateProvider.rate(address(asset));
    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    return assetDecimals != 18
        ? assetRate * amount / (10 ** assetDecimals)
        : assetRate * amount / 1e18;
}

function convertFromUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
    uint256 assetRate = rateProvider.rate(address(asset));
    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    return assetDecimals != 18
        ? amount * (10 ** assetDecimals) / assetRate
        : amount * 1e18 / assetRate;
}
```

In `convertFromUnitOfAccount`, `amount * 1e18 / assetRate` performs integer division that always rounds down. When this function is used in `RedemptionAssetsVault.transferRedemptionAssets` to calculate how many tokens to send to users during redemption, the rounding consistently favors the protocol. This is related to F-05 but identifies the root cause in `AssetRegistry` rather than the symptom in `RedemptionAssetsVault`.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/AssetRegistry.sol` lines 306-320

**Impact:** Each redemption through the multi-asset vault loses up to 1 wei per asset due to integer division truncation. The cumulative effect is small but non-zero dust accumulation in the vault.

**Recommendation:** Use `Math.mulDiv` with explicit rounding direction for both conversion functions to enable callers to specify whether rounding should favor the user or the protocol.

---

### F-29: `synchronizeNodesAndUpdateBalances` is permissionless in ynEIGEN and can trigger costly state updates

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ynEIGEN/EigenStrategyManager.sol`
**Function(s):** `synchronizeNodesAndUpdateBalances()`, `updateTokenStakingNodesBalances()`
**Sources:** Pipeline H (Auditmos state-validation checklist)

**Description:**

Two functions in `EigenStrategyManager` that update critical accounting state are permissionless:

```solidity
// No access control
function synchronizeNodesAndUpdateBalances(ITokenStakingNode[] calldata nodes) external {
    uint256 nodesLength = nodes.length;
    for(uint256 i = 0; i < nodesLength; i++) {
        nodes[i].synchronize();
    }
    IERC20[] memory assets = IynEigenVars(address(ynEigen)).assetRegistry().getAssets();
    uint256 assetsLength = assets.length;
    for (uint256 i = 0; i < assetsLength; i++) {
        _updateTokenStakingNodesBalances(assets[i], IStrategy(address(0)));
    }
}

// No access control
function updateTokenStakingNodesBalances(IERC20 asset) public {
    _updateTokenStakingNodesBalances(asset, strategies[asset]);
}
```

This mirrors F-08 (permissionless `updateTotalETHStaked`) and F-09 (permissionless `synchronize`) from the ynETH side, but affects the ynEIGEN subsystem. The `synchronizeNodesAndUpdateBalances` function accepts an arbitrary array of `ITokenStakingNode` addresses, calls `synchronize()` on each, then iterates ALL assets and ALL nodes to recalculate `strategiesBalance`.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/EigenStrategyManager.sol` lines 207-218, 228-229

**Impact:** An attacker could call `synchronizeNodesAndUpdateBalances` immediately before a large deposit to ensure the exchange rate reflects the most current (possibly slashed) balances, or call `updateTokenStakingNodesBalances` to force a balance recalculation at an inopportune time. The gas cost to the caller is the primary deterrent, but on-chain MEV searchers could bundle these calls profitably.

**Recommendation:** Consider adding a cooldown period between successive calls, or restrict to a keeper role while maintaining a public emergency override.

---

### F-30: `ynViewer.getRate` and `ynEigenViewer.getRate` return `1 ether` when totalAssets is zero, masking catastrophic state

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `ynViewer.sol`, `ynEIGEN/ynEigenViewer.sol`
**Function(s):** `getRate()`
**Sources:** Pipeline G (Archethect)

**Description:**

Both viewer contracts return `1 ether` when either `totalSupply` or `totalAssets` is zero:

```solidity
function getRate() external view returns (uint256) {
    uint256 _totalSupply = ynETH.totalSupply();
    uint256 _totalAssets = ynETH.totalAssets();
    if (_totalSupply == 0 || _totalAssets == 0) return 1 ether;
    return 1 ether * _totalAssets / _totalSupply;
}
```

The condition `_totalAssets == 0` with `_totalSupply > 0` represents a catastrophic scenario (all assets lost while shares exist). Returning `1 ether` (implying a 1:1 rate) in this case is misleading. The actual exchange rate would be 0 (zero assets backing the shares).

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynViewer.sol` lines 33-37
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/ynEigenViewer.sol` lines 129-134

**Impact:** Off-chain integrations or UIs relying on `getRate()` would display an incorrect rate during edge conditions. No on-chain impact since these are view-only contracts.

**Recommendation:** Return 0 when `totalAssets == 0 && totalSupply > 0` to accurately reflect the catastrophic scenario, or revert to signal an invalid state.

---

### F-31: `WithdrawalQueueManager.withdrawalFee` NatSpec says "basis points" but `FEE_PRECISION` is parts-per-million

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `WithdrawalQueueManager.sol`
**Function(s):** `setWithdrawalFee()`
**Sources:** Pipeline G (Archethect)

**Description:**

The constant `FEE_PRECISION = 1000000` and the NatSpec on `setWithdrawalFee` states "fee percentage in basis points." Basis points use a denominator of 10000, not 1000000. The actual fee unit is parts-per-million (ppm), not basis points. This semantic mismatch between documentation and code could lead to incorrect fee configuration by governance.

For example, a governance proposal to set a "50 basis point (0.5%) fee" might pass `50` as the parameter, resulting in a fee of `50/1000000 = 0.005%` instead of the intended `50/10000 = 0.5%`. The correct ppm value would be `5000`.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol` lines 84, 356-357

**Impact:** Governance misconfiguration risk. If operators rely on the NatSpec rather than inspecting `FEE_PRECISION`, fees would be set 100x lower than intended.

**Recommendation:** Update the NatSpec to accurately reflect that the fee is denominated in parts-per-million (ppm) with `FEE_PRECISION = 1000000`, or rename the constant and update documentation for clarity.

---

### F-32: Withdrawal queue pause not synchronized with redemption vault pause, no grace period

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `WithdrawalQueueManager.sol`, `ynETHRedemptionAssetsVault.sol`, `ynEIGEN/RedemptionAssetsVault.sol`
**Function(s):** `claimWithdrawal()`, `transferRedemptionAssets()`
**Sources:** Pipeline H (Auditmos state-validation checklist)

**Description:**

The `WithdrawalQueueManager`, `ynETHRedemptionAssetsVault`, and `RedemptionAssetsVault` each have independent pause mechanisms controlled by separate roles. There is no synchronization between them:

- `ynETHRedemptionAssetsVault.pause()` is controlled by `PAUSER_ROLE`
- `WithdrawalQueueManager` has no pause on `claimWithdrawal` itself
- `RedemptionAssetsVault.pause()` is controlled by its own `PAUSER_ROLE`

If the redemption vault is paused while the withdrawal queue is not, users with finalized withdrawal requests will have their `claimWithdrawal` calls revert at the `transferRedemptionAssets` step (due to `whenNotPaused` modifier), even though their requests are legitimately finalized.

Additionally, no grace period exists after unpausing any contract. Users who were blocked during a pause have no additional time to claim before new finalizations can occur.

**Code Reference:**
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/WithdrawalQueueManager.sol`
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynETHRedemptionAssetsVault.sol`
- `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/ynEIGEN/RedemptionAssetsVault.sol`

**Impact:** Users with finalized withdrawals may be temporarily unable to claim during redemption vault pauses. Since pause is an emergency mechanism, this is expected behavior, but the lack of grace period could be frustrating for users. No funds are at risk since the withdrawal requests remain finalized and claimable once unpaused.

**Recommendation:** Document the dependency between pause states. Consider adding a `claimsPaused` flag to `WithdrawalQueueManager` that is automatically set when the redemption vault is paused, providing clearer error messages to users. Optionally add a grace period after unpause events.

---

## Cross-Reference with Existing Audits

The protocol has been audited by **Chain Security** and **Zokyo**. Based on the patterns observed in the codebase:

1. **Donation Attack (F-01):** The code contains explicit comments acknowledging this risk (lines 128-129 in RewardsDistributor.sol and lines 752-753 in StakingNodesManager.sol), suggesting this was likely identified in a previous audit. The team appears to have accepted the risk for bootstrapped systems while acknowledging the theoretical vector.

2. **Off-chain Trust Assumptions (F-02):** The detailed security comments around `rewardsAmount` in `_processPrincipalWithdrawalForNode` (lines 604-617) indicate this design trade-off was deliberately documented, likely as a result of prior audit feedback regarding EigenLayer M3's lack of principal/reward separation.

3. **ELIP-002 Slashing Integration:** The dual-tracking of `preELIP002QueuedSharesAmount` and post-upgrade `queuedSharesAmount`, along with the `NotSyncedAfterSlashing` check, indicates thorough handling of the EigenLayer slashing upgrade. The `synchronize()` pattern and `onlyWhenSynchronized` modifier appear to be post-audit additions to handle slashing-induced desynchronization.

4. **New Findings:** F-03 (pending amount desync), F-04 (finalization ordering), F-10 (binary search underflow), and F-11 (missing access control on initializeV3) appear to be newly identified issues not addressed by the acknowledged comments in the codebase.

5. **Pipeline G/H New Findings:** F-15 (LSD rate oracle risks), F-16 (unenforced finalization delay), F-17 (share pricing via burn manipulation), and F-18 (stale tokenIdToFinalize) represent significant new findings from the Forefy + Archethect and Auditmos pipelines that were not identified by earlier methodologies.

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
