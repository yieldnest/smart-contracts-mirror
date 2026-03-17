# Security Audit Report: yieldnest-flex-strategy

## Metadata
- **Repository:** yieldnest-flex-strategy
- **Commit:** 8c53830c0162dc7f5bd5bfeb80c14480053bcddc
- **Branch:** release-candidate
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.28
- **Auditor:** Multi-Pipeline Automated Audit (6 methodologies)

## Audit Scope

| File | Path | LOC |
|------|------|-----|
| FlexStrategy.sol | `src/FlexStrategy.sol` | 234 |
| AccountingModule.sol | `src/AccountingModule.sol` | 483 |
| AccountingToken.sol | `src/AccountingToken.sol` | 139 |
| FixedRateProvider.sol | `src/FixedRateProvider.sol` | 35 |
| RewardsSweeper.sol | `src/utils/RewardsSweeper.sol` | 183 |
| **Total** | | **1074** |

Dependencies reviewed for context (not in primary audit scope):
- `BaseStrategy.sol` (yieldnest-vault)
- `BaseVault.sol` (yieldnest-vault)
- `VaultLib.sol` (yieldnest-vault)

## Methodologies Applied

| Pipeline | Methodology | Findings |
|----------|-------------|----------|
| A | SCV Scan (36 Vulnerability Patterns) | 3 |
| B | Feynman Business Logic Audit | 3 |
| C | State Inconsistency Analysis | 2 |
| D | Pashov Multi-Vector Scan | 2 |
| E | QuillAI Module Analysis | 1 |
| F | Token Integration Analysis | 1 |
| **Total unique findings** | | **9** |

## Executive Summary

The yieldnest-flex-strategy codebase implements a vault strategy that proxies deposited base assets to an associated safe (multisig), minting IOU accounting tokens to represent transferred value. It includes an accounting module for reward/loss processing with APR-based guardrails and cooldown periods, and a RewardsSweeper utility for automated reward distribution.

The architecture is generally sound with proper use of access control roles, cooldown mechanisms, and APR caps. However, the audit identified **1 medium-severity**, **4 low-severity**, and **4 informational** findings. The medium finding relates to the APR validation in `processRewards` which can be bypassed through snapshot index manipulation by the privileged `REWARDS_PROCESSOR_ROLE`. The low findings cover production debug imports, unsafe ERC20 approve patterns, missing zero-amount validation, and cooldown period limitations. No critical or high-severity vulnerabilities were identified.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| FLEX-01 | Medium | APR cap bypass via snapshot index selection in `processRewards` | B, C, D | High |
| FLEX-02 | Low | Forge `console.sol` import in production RewardsSweeper contract | A | High |
| FLEX-03 | Low | Unsafe `approve` pattern in `setAccountingModule` (non-zero to non-zero) | A, F | Medium |
| FLEX-04 | Low | No validation that `processRewards` `amount > 0`; zero-amount calls create snapshots and waste cooldowns | B, E | High |
| FLEX-05 | Low | `cooldownSeconds` as `uint16` limits max cooldown to ~18.2 hours | D, B | Medium |
| FLEX-06 | Informational | `calculateApr` reverts on underflow when PPS decreases after reward minting | B, C | Medium |
| FLEX-07 | Informational | Unbounded snapshot array growth in AccountingModule | A, E | Medium |
| FLEX-08 | Informational | No reentrancy guard on AccountingModule or RewardsSweeper external functions | D, E | Low |
| FLEX-09 | Informational | RewardsSweeper `setAccountingModule` lacks validation checks | D, F | Medium |

---

## Detailed Findings

---

### FLEX-01: APR cap bypass via snapshot index selection in `processRewards`

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `AccountingModule.sol`, `RewardsSweeper.sol`
**Function(s):** `processRewards(uint256 amount, uint256 snapshotIndex)`, `_processRewards()`
**Sources:** Pipeline B (Business Logic), Pipeline C (State Inconsistency), Pipeline D (Logic & Business Flow)

**Description:**

The `processRewards` function with the snapshot index parameter (line 228-237 of `AccountingModule.sol`) allows the caller with `REWARDS_PROCESSOR_ROLE` to specify any historical snapshot index for APR validation. The intent is to allow smoothing of irregular reward distributions. However, this creates a bypass vector:

By selecting a very old snapshot (e.g., snapshot index 0 from deployment time), the effective time window for APR calculation grows extremely large, making the per-period denominator in the APR formula very large and thus allowing arbitrarily large single reward amounts to pass the APR check.

**Code Reference:**

```solidity
// AccountingModule.sol, lines 228-237
function processRewards(
    uint256 amount,
    uint256 snapshotIndex
)
    external
    onlyRole(REWARDS_PROCESSOR_ROLE)
    checkAndResetCooldown
{
    _processRewards(amount, snapshotIndex);
}
```

```solidity
// AccountingModule.sol, lines 287-291
uint256 aprSinceLastSnapshot = calculateApr(
    previousSnapshot.pricePerShare, previousSnapshot.timestamp, currentPricePerShare, block.timestamp
);
if (aprSinceLastSnapshot > s.targetApy) revert AccountingLimitsExceeded(aprSinceLastSnapshot, s.targetApy);
```

The APR formula is: `(currentPPS - previousPPS) * YEAR * DIVISOR / previousPPS / (currentTimestamp - previousTimestamp)`

With a large time delta (e.g., 365 days from snapshot 0), the denominator `(currentTimestamp - previousTimestamp)` becomes very large, causing `aprSinceLastSnapshot` to be small even if the actual reward amount is disproportionately large relative to recent activity.

Additionally, the `RewardsSweeper.sweepRewards(uint256 amount, uint256 snapshotIndex)` at line 152 of `RewardsSweeper.sol` also allows snapshot index selection and forwards it directly to `accountingModule.processRewards(amount, snapshotIndex)`.

**Impact:**

A compromised or malicious `REWARDS_PROCESSOR_ROLE` holder could inflate the PPS significantly in a single transaction by choosing snapshot index 0 (or any sufficiently old snapshot), effectively bypassing the APR cap that is meant to protect depositors from sudden PPS manipulation.

Note: This requires a privileged role. The `cooldownSeconds` rate-limiting still applies, but a single large reward can be pushed through.

**Recommendation:**

Consider enforcing a maximum age for the referenced snapshot. For example, only allow snapshots within the last N periods:

```solidity
if (block.timestamp - previousSnapshot.timestamp > MAX_SNAPSHOT_AGE) revert SnapshotTooOld();
```

Alternatively, enforce that `snapshotIndex >= s._snapshots.length - MAX_LOOKBACK` to limit how far back the comparison can go.

---

### FLEX-02: Forge `console.sol` import in production RewardsSweeper contract

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `RewardsSweeper.sol`
**Function(s):** N/A (file-level import)
**Sources:** Pipeline A (SCV Scan - Unused Variables / Inadherence to Standards)

**Description:**

The `RewardsSweeper.sol` contract imports the Forge standard library `console.sol` on line 10:

```solidity
// RewardsSweeper.sol, line 10
import { console } from "forge-std/console.sol";
```

This is a development/testing dependency that should not be present in production contracts. While `console` is not actively called in the current code (no `console.log` statements), the import itself:
1. Increases deployment bytecode size unnecessarily.
2. Signals incomplete code cleanup before release.
3. Could mask the fact that debug logging was removed but the import was forgotten.

**Impact:**

Minimal direct security impact, but indicates incomplete release preparation. The import increases contract bytecode size and gas costs for deployment.

**Recommendation:**

Remove the import:
```diff
- import { console } from "forge-std/console.sol";
```

---

### FLEX-03: Unsafe `approve` pattern in `setAccountingModule`

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `FlexStrategy.sol`
**Function(s):** `setAccountingModule()`
**Sources:** Pipeline A (SCV Scan - Inadherence to Standards), Pipeline F (Token Integration)

**Description:**

In `FlexStrategy.setAccountingModule()` (lines 177-195), the function uses `IERC20.approve()` directly:

```solidity
// FlexStrategy.sol, lines 186 and 194
IERC20(asset()).approve(address(oldAccounting), 0);
// ...
IERC20(asset()).approve(accountingModule_, type(uint256).max);
```

This uses the raw `IERC20.approve()` rather than `SafeERC20.forceApprove()` or `SafeERC20.safeApprove()`. Some ERC20 tokens (notably USDT) do not return a boolean from `approve()`, causing the call to revert when using the standard IERC20 interface. Since the contract imports and uses `SafeERC20` elsewhere, this inconsistency may cause the `setAccountingModule` function to revert for non-standard tokens.

Furthermore, the pattern of approving `type(uint256).max` to the new accounting module creates an unlimited allowance. While functional, the old accounting module's approval is correctly reset to 0 first, which is good practice.

**Impact:**

If the base asset is a non-standard ERC20 (e.g., USDT), the `setAccountingModule` function would revert, preventing the admin from updating the accounting module. This could be problematic in an emergency scenario where the accounting module needs to be replaced.

**Recommendation:**

Use `SafeERC20.forceApprove()` (available in OpenZeppelin v5+) or the safe approve pattern:

```solidity
IERC20(asset()).forceApprove(address(oldAccounting), 0);
IERC20(asset()).forceApprove(accountingModule_, type(uint256).max);
```

---

### FLEX-04: Zero-amount `processRewards` / `processLosses` wastes cooldown and creates empty snapshots

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `AccountingModule.sol`
**Function(s):** `processRewards()`, `processLosses()`
**Sources:** Pipeline B (Business Logic), Pipeline E (Input Arithmetic Safety)

**Description:**

Neither `processRewards` nor `processLosses` validates that `amount > 0`. Calling `processRewards(0)` will:

1. Pass the `checkAndResetCooldown` modifier, resetting `nextUpdateWindow` (line 177).
2. Mint 0 accounting tokens (a no-op mint).
3. Call `strategyVault.processAccounting()`.
4. Create a new snapshot in the `_snapshots` array (line 308).
5. Pass the APR check (APR will be 0 or negligible).

This effectively wastes the cooldown period. A `REWARDS_PROCESSOR_ROLE` holder could accidentally or intentionally call `processRewards(0)` to consume the cooldown window, preventing legitimate reward processing until the next window opens.

Similarly, `processLosses(0)` passes the loss bound check (0 > anything is false), burns 0 tokens, and creates a snapshot.

```solidity
// AccountingModule.sol, line 218
function processRewards(uint256 amount) external onlyRole(REWARDS_PROCESSOR_ROLE) checkAndResetCooldown {
    // no check: amount > 0
    AccountingModuleStorage storage s = _getAccountingModuleStorage();
    _processRewards(amount, s._snapshots.length - 1);
}
```

**Impact:**

A privileged role holder could grief the system by wasting cooldown periods. Additionally, each zero-amount call appends an unnecessary snapshot to storage, contributing to unbounded array growth (see FLEX-07).

**Recommendation:**

Add a zero-amount check:

```solidity
if (amount == 0) revert ZeroAmount();
```

---

### FLEX-05: `cooldownSeconds` as `uint16` limits max cooldown to ~18.2 hours

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `AccountingModule.sol`
**Function(s):** `_setCooldownSeconds()`
**Sources:** Pipeline D (Arithmetic & Precision), Pipeline B (Business Logic)

**Description:**

The `cooldownSeconds` field is typed as `uint16` (max value 65535), which limits the maximum cooldown period to approximately 18.2 hours:

```solidity
// AccountingModuleStorage, line 80
uint16 cooldownSeconds;
```

```
65535 seconds = 18.2 hours
```

For a strategy that processes rewards periodically, administrators may want to set cooldown periods of 24 hours, 48 hours, or even 7 days to ensure conservative reward processing cadences. The `uint16` type prevents this.

The `nextUpdateWindow` is stored as `uint64`, so the addition `uint64(block.timestamp) + s.cooldownSeconds` on line 177 won't overflow, but the max cooldown is artificially limited by the `uint16` type.

**Impact:**

Administrators cannot configure cooldown periods longer than ~18.2 hours, which may be insufficient for some operational scenarios. This is a design limitation rather than a vulnerability.

**Recommendation:**

Consider using `uint32` for `cooldownSeconds`, which would allow cooldowns up to ~136 years, or `uint64` to match the `nextUpdateWindow` type. A `uint32` would be sufficient and maintain storage packing efficiency.

---

### FLEX-06: `calculateApr` reverts on underflow when PPS decreases after reward minting

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `AccountingModule.sol`
**Function(s):** `calculateApr()`, `_processRewards()`
**Sources:** Pipeline B (Business Logic), Pipeline C (State Inconsistency)

**Description:**

In `calculateApr()` (line 344), the expression `(currentPricePerShare - previousPricePerShare)` will revert due to arithmetic underflow if `currentPricePerShare < previousPricePerShare`:

```solidity
// AccountingModule.sol, line 344
return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
    / (currentTimestamp - previousTimestamp);
```

In the context of `_processRewards`, `currentPricePerShare` is computed *after* minting new accounting tokens and calling `processAccounting()`. If the strategy vault's `computeTotalAssets()` computes a value lower than expected (e.g., due to an external factor decreasing the accounting token's effective value, or rounding), the current PPS could theoretically be lower than a historical snapshot's PPS, causing the entire `processRewards` transaction to revert.

This is actually a safe behavior -- it prevents reward processing when the system is in an inconsistent state. However, it could block legitimate reward processing if there are rounding discrepancies in the vault's total assets computation.

**Impact:**

This is a defensive behavior rather than a vulnerability. However, it could cause operational issues if the PPS calculation has rounding-induced decreases between snapshots.

**Recommendation:**

If the PPS decrease case should be handled gracefully (returning 0 APR instead of reverting), consider:

```solidity
if (currentPricePerShare <= previousPricePerShare) return 0;
```

However, the current revert behavior may be intentionally conservative. Document this behavior explicitly.

---

### FLEX-07: Unbounded snapshot array growth in AccountingModule

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `AccountingModule.sol`
**Function(s):** `createStrategySnapshot()`, `_processRewards()`, `processLosses()`
**Sources:** Pipeline A (SCV Scan - DoS with Block Gas Limit), Pipeline E (State Invariant Detection)

**Description:**

Every call to `processRewards` or `processLosses` appends a new `StrategySnapshot` to the `_snapshots` array (line 308):

```solidity
// AccountingModule.sol, line 308
s._snapshots.push(snapshot);
```

This array grows indefinitely. Each `StrategySnapshot` struct contains 4 `uint256` values (128 bytes of storage). With daily reward processing over several years, the array grows but individual reads remain O(1) since snapshots are accessed by index.

The `snapshotsLength()` view function and `lastSnapshot()` function both access the array length, which is a single SLOAD operation and remains efficient. The `snapshots(uint256 index)` function also remains O(1).

However, if any future logic iterates over the snapshots array, it could become a gas issue. The array is also referenced by index in `_processRewards` (line 282), which is O(1).

**Impact:**

No current gas issue due to O(1) access patterns. The concern is limited to storage costs over time and potential future iteration needs. At 1 snapshot per day, this amounts to ~2.3 KB of new storage per year.

**Recommendation:**

This is an informational note. Consider adding a snapshot pruning mechanism if storage costs become a concern, or document the expected growth rate.

---

### FLEX-08: No reentrancy guard on AccountingModule or RewardsSweeper external functions

**Severity:** Informational
**Confidence:** Low
**Affected Contract(s):** `AccountingModule.sol`, `RewardsSweeper.sol`
**Function(s):** `processRewards()`, `processLosses()`, `deposit()`, `withdraw()`, `sweepRewards()`
**Sources:** Pipeline D (Reentrancy & External Interactions), Pipeline E (Reentrancy Pattern Analysis)

**Description:**

Neither `AccountingModule` nor `RewardsSweeper` use `ReentrancyGuard` or a `nonReentrant` modifier. Both contracts make external calls:

- `AccountingModule._processRewards()` calls `strategyVault.processAccounting()` (line 278) and `s.accountingToken.mintTo()` (line 277).
- `AccountingModule.processLosses()` calls `s.accountingToken.burnFrom()` (line 364) and `IVault(s.strategy).processAccounting()` (line 365).
- `AccountingModule.deposit()` calls `safeTransferFrom` (line 196) and `mintTo` (line 197).
- `AccountingModule.withdraw()` calls `burnFrom` (line 208) and `safeTransferFrom` (line 209).
- `RewardsSweeper.sweepRewards()` calls `safeTransfer` (line 158) and `accountingModule.processRewards()` (line 161).

In `_processRewards`, the state mutation pattern is:
1. Mint tokens (external call to AccountingToken)
2. Process accounting (external call to strategy vault)
3. Read snapshot from storage
4. Create new snapshot (external calls for PPS)
5. Validate APR

This follows a pattern where external calls are made before final state reads. However, the `AccountingToken.mintTo()` is access-controlled to only the accounting module, and `processAccounting()` is protected by `nonReentrant` in the BaseVault. The strategy vault's `processAccounting` is called by the accounting module via `IVault`, and BaseVault.processAccounting has `nonReentrant`.

The access control on all entry points (`onlyRole`, `onlyStrategy`) and the `checkAndResetCooldown` modifier (which sets `nextUpdateWindow` before the function body) provide implicit reentrancy protection for reward/loss processing.

**Impact:**

No exploitable reentrancy path was identified due to the combination of access controls and the cooldown mechanism. The `checkAndResetCooldown` modifier effectively acts as a reentrancy guard for reward/loss operations by advancing the `nextUpdateWindow` before the function body executes.

**Recommendation:**

This is informational. The current access control and cooldown patterns provide adequate protection. However, adding `ReentrancyGuard` as defense-in-depth would be consistent with the BaseVault pattern.

---

### FLEX-09: RewardsSweeper `setAccountingModule` lacks validation checks

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `RewardsSweeper.sol`
**Function(s):** `setAccountingModule()`
**Sources:** Pipeline D (Access Control), Pipeline F (Token Integration)

**Description:**

The `RewardsSweeper.setAccountingModule()` function (lines 179-182) allows the admin to set an arbitrary address as the accounting module without any validation:

```solidity
// RewardsSweeper.sol, lines 179-182
function setAccountingModule(address accountingModule_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit AccountingModuleUpdated(accountingModule_, address(accountingModule));
    accountingModule = IAccountingModule(accountingModule_);
}
```

In contrast, `AccountingToken.setAccountingModule()` (lines 118-132) validates that:
1. The address is not zero.
2. The new module's `accountingToken()` matches the current token.
3. The new module's `baseAsset()` matches the tracked asset.

And `FlexStrategy.setAccountingModule()` (lines 177-195) validates that:
1. The address is not zero.
2. The new module's `accountingToken()` matches the old module's.

The RewardsSweeper performs no such validations, allowing it to be pointed at an arbitrary contract or even `address(0)`.

**Impact:**

The admin (`DEFAULT_ADMIN_ROLE`) could accidentally set the accounting module to `address(0)` or an incompatible contract, causing all subsequent `sweepRewards` calls to revert. This is mitigated by the fact that only a privileged admin can make this change.

**Recommendation:**

Add basic validation:

```solidity
function setAccountingModule(address accountingModule_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (accountingModule_ == address(0)) revert ZeroAddress();
    emit AccountingModuleUpdated(accountingModule_, address(accountingModule));
    accountingModule = IAccountingModule(accountingModule_);
}
```

---

## Informational Notes

### Note 1: FixedRateProvider assumes 1:1 rate permanently

The `FixedRateProvider` returns `10 ** DECIMALS` for both the base asset and the accounting token, establishing a permanent 1:1 rate. This is by design for the flex strategy architecture (accounting tokens represent deposited base assets at par). However, this means:

- The strategy vault's PPS is driven entirely by the ratio of accounting token balance to strategy shares.
- Any deviation from 1:1 value (e.g., the accounting token representing more or less than the base asset) is not captured by the rate provider.

This is appropriate for the current design where accounting tokens are purely internal IOUs.

### Note 2: AccountingToken transfer restrictions

`AccountingToken` correctly blocks `transfer()` and `transferFrom()` with `revert NotAllowed()` (lines 103-112). This prevents accounting tokens from being transferred outside the strategy, maintaining the invariant that accounting tokens are only held by the strategy contract. The `_mint` and `_burn` internal functions from ERC20Upgradeable bypass these restrictions as intended.

### Note 3: FlexStrategy._withdrawAsset argument mismatch with BaseVault

In `FlexStrategy._withdrawAsset()` at line 158, the call `_subTotalAssets(_convertAssetToBase(asset_, assets))` passes only 2 arguments to `_convertAssetToBase`, while the parent `BaseVault._convertAssetToBase` requires 3 arguments (including a `Math.Rounding` parameter). This suggests the actual vault dependency version used in the build may differ from the version present in this monorepo mirror. If this represents the production code, a rounding direction parameter should be specified (typically `Math.Rounding.Floor` for withdrawals to err on the side of under-counting removed assets, consistent with the BaseVault pattern).

### Note 4: AccountingModule.initialize creates initial snapshot at deployment

The `initialize()` function calls `createStrategySnapshot()` at line 171, which reads `strategyVault.convertToAssets()`, `totalSupply()`, and `totalAssets()`. At initialization time, the strategy vault may not yet have any deposits, which means the initial snapshot could have `pricePerShare = 0` if `totalSupply = 0`. However, `convertToAssets(10^decimals)` with zero supply uses the vault's `+1` virtual offset formula, so it returns a non-zero value. This is safe.

### Note 5: Safe must approve base asset transfers

For `AccountingModule.withdraw()` to work (line 209), the safe address must have granted sufficient ERC20 approval to the `AccountingModule` contract for the base asset. This is an external operational requirement not enforced by the contract itself. If the safe's approval is insufficient, withdrawals will revert with a transfer failure.

### Note 6: processRewards mints before validation (commit-then-validate pattern)

In `_processRewards()`, accounting tokens are minted and `processAccounting()` is called before the APR validation check (lines 277-291). If the APR check fails, the entire transaction reverts, undoing the mint. This is a safe pattern in Solidity (atomic transactions), but it means every failed reward attempt consumes gas for the mint and processAccounting calls before reverting.
