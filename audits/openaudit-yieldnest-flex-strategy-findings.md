# OpenAudit: yieldnest-flex-strategy -- New Findings

**Date:** 2026-03-17
**Pipelines:** Forefy Smart Contract Audit, Archethect SC Auditor (Map-Hunt-Attack)
**Target:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/`
**LOC:** ~1,074
**Solidity Version:** ^0.8.28

**Existing Findings (excluded from this report):**
- FLEX-01: APR cap bypass via snapshot index selection in processRewards

---

## Architecture Summary (MAP Phase)

The yieldnest-flex-strategy system consists of five contracts:

1. **FlexStrategy.sol** -- ERC-4626-style vault strategy that proxies deposited base assets to an associated safe via an AccountingModule, minting IOU accounting tokens to represent transferred value. Inherits from BaseStrategy.
2. **AccountingModule.sol** -- Manages reward/loss processing with APR-based guardrails, cooldown periods, and snapshot-based accounting. Controls minting/burning of AccountingToken.
3. **AccountingToken.sol** -- Non-transferable ERC-20 IOU token. Only the AccountingModule can mint/burn. Transfers are blocked by reverting in `transfer()` and `transferFrom()`.
4. **FixedRateProvider.sol** -- Returns a 1:1 rate for both the base asset and accounting token.
5. **RewardsSweeper.sol** -- Utility that sweeps accumulated reward tokens from its own balance to the safe, then calls `processRewards` on the AccountingModule.

**Trust Boundaries:**
- FlexStrategy <-> AccountingModule (strategy-only modifier)
- AccountingModule <-> AccountingToken (accounting-only modifier)
- RewardsSweeper -> AccountingModule (via REWARDS_PROCESSOR_ROLE)
- AccountingModule -> Safe (multisig, via safeTransferFrom)

---

## Findings

---

### [MEDIUM] OA-FS-01: RewardsSweeper `calculateMaxRewards` uses stale `totalSupply` and `totalAssets` leading to over-rewarding

**Pipeline:** Forefy (Economic Layer) / Archethect (accounting_entitlement)
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/utils/RewardsSweeper.sol`:82-101

**Description:**

In `previewSweepRewardsUpToAPRMax`, the function reads `strategy.totalSupply()` and `strategy.totalAssets()` (lines 89-90) to compute the maximum allowable rewards. These are the *current* values before any reward minting occurs. However, `calculateMaxRewards` computes `totalAssetsWithMaxTargetApy` based on the price-per-share at a historical snapshot multiplied by the *current* `totalSupply`, then subtracts the *current* `totalAssets`:

```solidity
uint256 totalAssetsWithMaxTargetApy = (pricePerShareWithMaxTargetApy * currentSupply / (10 ** sharesDecimals));

if (totalAssetsWithMaxTargetApy > currentAssets) {
    return totalAssetsWithMaxTargetApy - currentAssets;
}
```

The issue is that if any deposits or withdrawals have occurred between the reference snapshot and the current block, the `currentSupply` may have changed significantly while the `pricePerShareAtSnapshot` reflects the old state. This means:

1. If many new deposits occurred after the snapshot, `currentSupply` is higher, and `totalAssetsWithMaxTargetApy` computes a larger target total-assets than what the APR cap intended for the snapshot-era supply level.
2. The function could return a `maxRewards` value that, when actually processed through `AccountingModule.processRewards`, would pass the APR check (since the APR check uses PPS-based comparison against the same snapshot), but the economic intent of the target APY is diluted across a different supply base than existed at snapshot time.

This creates a scenario where the RewardsSweeper can push more rewards than economically appropriate relative to the original depositors who were present at snapshot time, particularly if the REWARDS_SWEEPER_ROLE calls `sweepRewardsUpToAPRMax` with an older snapshot index after significant new deposits.

**Impact:**

Over-rewarding relative to the economic intent of the APR cap. The magnitude depends on the ratio of supply change between the snapshot and the current block. With significant deposit growth (e.g., 2x supply), the sweeper could push roughly 2x the intended reward amount through a single call, as the PPS-based APR check in AccountingModule would still pass (the PPS delta is spread across the larger supply).

**Recommendation:**

Consider using the snapshot's `totalSupply` rather than the current `totalSupply` in the max-rewards calculation, or add a staleness check that bounds how old the referenced snapshot can be relative to the current state.

---

### [MEDIUM] OA-FS-02: `processRewards` mints accounting tokens before APR validation, leaving inflated supply on revert recovery paths

**Pipeline:** Archethect (accounting_entitlement + adversarial_deep)
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:267-292

**Description:**

In `_processRewards`, the accounting tokens are minted and `processAccounting()` is called *before* the APR check:

```solidity
function _processRewards(uint256 amount, uint256 snapshotIndex) internal {
    // ...
    s.accountingToken.mintTo(s.strategy, amount);           // line 277
    strategyVault.processAccounting();                       // line 278

    // check if apr is within acceptable bounds
    StrategySnapshot memory previousSnapshot = s._snapshots[snapshotIndex]; // line 282
    uint256 currentPricePerShare = createStrategySnapshot().pricePerShare;   // line 284

    uint256 aprSinceLastSnapshot = calculateApr(...);        // line 287
    if (aprSinceLastSnapshot > s.targetApy) revert AccountingLimitsExceeded(...); // line 291
}
```

While the function correctly reverts if the APR cap is exceeded (which would undo the mint atomically), this ordering means:

1. The snapshot at line 284 is created with the *post-mint* state. If the function reverts at line 291, the entire transaction reverts, so the snapshot is also reverted -- this is safe for the revert case.

2. However, `createStrategySnapshot()` pushes a new snapshot to the array. If the APR check passes, this post-mint snapshot becomes the latest snapshot. This snapshot reflects the inflated PPS *after* reward minting. Future calls to the default `processRewards(amount)` (no snapshot index) will use `s._snapshots.length - 1` as the reference, which is this post-reward snapshot. This means the *next* reward processing round uses the already-inflated PPS as the baseline, allowing another full APR-cap worth of rewards to be added on top. Over successive rounds, this creates a compounding effect where each round's APR cap is applied to an already-inflated baseline.

This is by design for the default flow (rewards are measured round-over-round), but the interaction with the snapshot-index-based flow creates a subtle accounting issue: the snapshot created during `_processRewards` always reflects the post-reward state, meaning the APR check measures the delta from the *old* snapshot to the *new post-reward* state. If the same snapshot index is reused by a subsequent call (which is blocked by the cooldown), this is fine. But the compounding of snapshots means any gap or delay in processing allows more absolute rewards per round as the base PPS grows.

**Impact:**

The compounding effect means that over N successive reward rounds, the effective total APR is not `targetAPY * N/365.25`, but rather compounds at the target rate. For a 10% target APY processed daily, after one year the compounded growth would be approximately 10.52% rather than 10%. This is a minor accounting discrepancy for low target APYs, but for higher target APYs or more frequent processing, the compounding divergence grows.

**Recommendation:**

Document the compounding behavior explicitly. If simple (non-compounding) APR is intended, consider computing the APR check against the initial snapshot (snapshot 0) or the last snapshot before any rewards were processed, rather than the most recent post-reward snapshot.

---

### [MEDIUM] OA-FS-03: `processLosses` does not validate `amount > 0`, allowing zero-amount loss processing to consume cooldowns and create snapshots

**Pipeline:** Forefy (Technical Layer) / Archethect (semantic_consistency)
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:354-368

**Description:**

The `processLosses` function lacks a check for `amount > 0`:

```solidity
function processLosses(uint256 amount) external onlyRole(LOSS_PROCESSOR_ROLE) checkAndResetCooldown {
    AccountingModuleStorage storage s = _getAccountingModuleStorage();
    uint256 totalSupply = s.accountingToken.totalSupply();
    if (totalSupply < 10 ** s.accountingToken.decimals()) revert TvlTooLow();

    // check bound on losses
    if (amount > totalSupply * s.lowerBound / DIVISOR) {
        revert LossLimitsExceeded(amount, totalSupply * s.lowerBound / DIVISOR);
    }

    s.accountingToken.burnFrom(s.strategy, amount);
    IVault(s.strategy).processAccounting();

    createStrategySnapshot();
}
```

When `amount == 0`:
1. The loss bounds check passes (0 > anything is false).
2. `burnFrom(strategy, 0)` succeeds (ERC-20 `_burn` with zero amount is a no-op).
3. `processAccounting()` is called unnecessarily.
4. A new snapshot is created with the current state (no change from previous).
5. The cooldown is consumed (`checkAndResetCooldown` modifier).

This allows the `LOSS_PROCESSOR_ROLE` to consume cooldown periods without any actual loss processing, effectively blocking legitimate `processRewards` or `processLosses` calls during the cooldown window. While this requires a privileged role, it represents griefing potential in multi-role governance setups where the LOSS_PROCESSOR_ROLE and REWARDS_PROCESSOR_ROLE are held by different entities.

Additionally, the unnecessary snapshot creation bloats the snapshots array (related to existing informational finding FLEX-07, but the zero-amount vector is distinct).

**Impact:**

A `LOSS_PROCESSOR_ROLE` holder can grief the `REWARDS_PROCESSOR_ROLE` holder by consuming cooldowns with zero-amount loss calls. Each zero-amount call also adds an unnecessary snapshot to the unbounded array, contributing to storage bloat over time.

**Recommendation:**

Add `if (amount == 0) revert InvariantViolation();` at the beginning of `processLosses`.

---

### [LOW] OA-FS-04: `calculateApr` underflows for price-per-share decreases without a meaningful revert message

**Pipeline:** Forefy (Technical Layer) / Archethect (semantic_consistency)
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:321-346

**Description:**

The `calculateApr` function computes:

```solidity
return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
    / (currentTimestamp - previousTimestamp);
```

If `currentPricePerShare < previousPricePerShare`, the subtraction `currentPricePerShare - previousPricePerShare` underflows in Solidity 0.8.x, causing an automatic revert with a Panic(0x11) error.

This function is called within `_processRewards` (line 287-289). If between the reference snapshot and the current block the strategy's price-per-share has *decreased* (e.g., due to a loss event, donation manipulation of the vault, or accounting rebalancing), the `processRewards` call will revert with an opaque panic rather than a meaningful error.

This means legitimate reward processing can be blocked if the PPS has decreased for any reason since the reference snapshot, even if the reward amount being processed would bring the PPS back above the reference level.

**Impact:**

Reward processing is blocked whenever the current PPS is below the reference snapshot's PPS. The revert is an opaque arithmetic panic rather than a descriptive custom error, making debugging difficult for integrators. The condition can arise naturally if losses are processed between the reference snapshot and the reward processing attempt.

**Recommendation:**

Add an explicit check and meaningful error message:
```solidity
if (currentPricePerShare <= previousPricePerShare) {
    // PPS has not increased; no positive APR to validate
    // Either allow the reward (it's bringing PPS back up from a loss) or revert with a clear message
    return 0; // or revert with a descriptive error
}
```

---

### [LOW] OA-FS-05: RewardsSweeper `setAccountingModule` has no validation, allows setting to arbitrary address

**Pipeline:** Forefy (Access Control Layer) / Archethect (semantic_consistency)
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/utils/RewardsSweeper.sol`:179-182

**Description:**

The `setAccountingModule` function in RewardsSweeper performs no validation:

```solidity
function setAccountingModule(address accountingModule_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    emit AccountingModuleUpdated(accountingModule_, address(accountingModule));
    accountingModule = IAccountingModule(accountingModule_);
}
```

Unlike the corresponding functions in `FlexStrategy.setAccountingModule` (which checks `address(0)` and validates the accounting token matches) and `AccountingToken.setAccountingModule` (which validates `address(0)`, accounting token back-reference, and base asset match), the RewardsSweeper setter:

1. Does not check for `address(0)`.
2. Does not validate that the new module's `baseAsset()` matches the expected token.
3. Does not validate that the new module's `strategy()` is consistent with the existing configuration.

Setting to `address(0)` would cause all subsequent calls to `sweepRewards`, `canSweepRewards`, and `previewSweepRewardsUpToAPRMax` to revert due to calls on the zero address. Setting to an incompatible module could cause silent accounting errors or fund misdirection.

**Impact:**

Admin misconfiguration risk. Setting to `address(0)` effectively bricks the RewardsSweeper until the admin corrects it. Setting to an incompatible module could cause funds to be swept to the wrong safe or rewards to be processed against the wrong strategy.

**Recommendation:**

Add validation consistent with the other module setters:
```solidity
if (accountingModule_ == address(0)) revert ZeroAddress();
```

Consider also validating that the new module's `baseAsset()` and `strategy()` are consistent with expectations.

---

### [LOW] OA-FS-06: Unlimited `type(uint256).max` approval in `setAccountingModule` persists to potentially upgradeable accounting module

**Pipeline:** Forefy (Integration Layer) / Archethect (token_oracle_statefulness)
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/FlexStrategy.sol`:177-195

**Description:**

When `setAccountingModule` is called, the FlexStrategy grants `type(uint256).max` approval to the new accounting module:

```solidity
IERC20(asset()).approve(accountingModule_, type(uint256).max);
```

The previous module's approval is revoked (set to 0), which is good. However, the unlimited approval to the new module means that if the AccountingModule is deployed behind an upgradeable proxy (which it is -- it uses `Initializable` and `AccessControlUpgradeable`), a malicious upgrade of the accounting module could drain all base assets held by the FlexStrategy.

While this requires a compromised admin to perform the upgrade, the unlimited approval amplifies the blast radius: rather than being limited to a specific amount, a compromised module implementation could drain the *entire* base asset balance in one transaction.

Additionally, if `setAccountingModule` is called multiple times with the same address, the old module's approval is only revoked if `address(oldAccounting) != address(0)`. The first call (when `oldAccounting` is `address(0)`) skips the revocation, which is correct. But subsequent calls do revoke the old and approve the new, which is fine for different addresses. If called with the same address, it revokes and re-approves the same address, which is a no-op but wastes gas.

**Impact:**

If the AccountingModule is upgradeable and an upgrade is compromised, the unlimited approval allows draining all base assets from the FlexStrategy. This is a trust assumption inherent in the design but should be documented.

**Recommendation:**

Consider using exact-amount approvals (approve only the amount being transferred per operation) rather than unlimited approvals, or document the trust assumption that the AccountingModule's upgrade path must be secured with the same rigor as the FlexStrategy's admin keys.

---

### [LOW] OA-FS-07: `RewardsSweeper.sweepRewards` transfers tokens to safe before `processRewards` call, creating a front-run window

**Pipeline:** Archethect (economic_differential)
**Confidence:** Low
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/utils/RewardsSweeper.sol`:152-163

**Description:**

In `sweepRewards`, the base asset is transferred to the safe *before* `processRewards` is called:

```solidity
function sweepRewards(uint256 amount, uint256 snapshotIndex) public onlyRole(REWARDS_SWEEPER_ROLE) {
    if (!canSweepRewards()) revert CannotSweepRewards();
    if (snapshotIndex >= accountingModule.snapshotsLength()) revert SnapshotIndexOutOfBounds(snapshotIndex);

    // Transfer rewards to safe
    IERC20(accountingModule.baseAsset()).safeTransfer(accountingModule.safe(), amount);

    // Process rewards through accounting module with specific snapshot index
    accountingModule.processRewards(amount, snapshotIndex);

    emit RewardsSwept(amount);
}
```

The `safeTransfer` to the safe happens at line 158. Then `processRewards` is called at line 161, which mints accounting tokens and validates the APR. If `processRewards` reverts (e.g., because the APR cap is exceeded), the entire transaction reverts, so the transfer is also undone -- this is safe for the revert case.

However, there is a subtle issue: the tokens are sent to the safe (which is typically a Gnosis Safe multisig) directly, not through the AccountingModule's deposit flow. The AccountingModule's `deposit` function calls `safeTransferFrom(strategy, safe, amount)`, but the RewardsSweeper bypasses this by sending directly to the safe. This means:

1. The safe's token balance increases by `amount` before the accounting tokens are minted.
2. If `_availableAssets` in FlexStrategy is called between the transfer and the mint (e.g., by another transaction in the same block on a non-atomic L2, or by a view function), it would show a temporarily inflated available balance.

For most use cases this ordering is fine since `processRewards` does not call `_availableAssets`. But the temporary state inconsistency between the safe's balance and the accounting token supply could be observed by off-chain systems.

**Impact:**

Temporary state inconsistency between safe balance and accounting token supply within the same transaction. No direct fund loss, but off-chain monitoring systems or view-function-based integrations could observe incorrect intermediate state.

**Recommendation:**

Consider transferring tokens to the safe as part of `processRewards` in the AccountingModule rather than in the RewardsSweeper, to keep the transfer and accounting update atomic from the module's perspective.

---

### [LOW] OA-FS-08: `processLosses` uses a different TVL minimum threshold than `processRewards`

**Pipeline:** Forefy (Economic Layer) / Archethect (semantic_consistency)
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:272-273, 356-357

**Description:**

The two processing functions use different minimum TVL checks:

In `_processRewards` (line 272-273):
```solidity
uint256 totalSupply = s.accountingToken.totalSupply();
if (totalSupply < s.minRewardableAssets) revert TvlTooLow();
```

In `processLosses` (line 356-357):
```solidity
uint256 totalSupply = s.accountingToken.totalSupply();
if (totalSupply < 10 ** s.accountingToken.decimals()) revert TvlTooLow();
```

`processRewards` uses the configurable `minRewardableAssets` parameter, while `processLosses` uses a hardcoded `10 ** decimals()` (1 full token unit). These inconsistent thresholds create a semantic gap:

1. If `minRewardableAssets` is set higher than `10 ** decimals()` (which is typical -- you'd want meaningful TVL before processing rewards), there's a window where losses can be processed but rewards cannot. This makes sense from a safety perspective.

2. However, if `minRewardableAssets` is set *lower* than `10 ** decimals()` (unusual but possible since there's no minimum validation on this parameter during initialization), rewards could be processed at a supply level where losses cannot. This is semantically inconsistent.

3. The `minRewardableAssets` parameter is set only during `initialize` and has no setter function, making it immutable after deployment. This means the threshold cannot be adjusted if the token's value changes significantly.

**Impact:**

Low. The inconsistent thresholds create a potential semantic gap between reward and loss processing eligibility. In practice, `minRewardableAssets` would typically be set higher than `10 ** decimals()`, making the asymmetry intentional (losses can always be processed at lower TVL than rewards).

**Recommendation:**

Document the intentional asymmetry. Consider adding a setter for `minRewardableAssets` with appropriate access control, or validate during initialization that `minRewardableAssets >= 10 ** decimals()`.

---

### [LOW] OA-FS-09: `FlexStrategy._withdrawAsset` does not call `accountingModule.withdraw` with the base-asset-converted amount

**Pipeline:** Archethect (accounting_entitlement)
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/FlexStrategy.sol`:139-170

**Description:**

In `_withdrawAsset`, the function subtracts from total assets using the base-converted amount but passes the raw `assets` amount to the accounting module:

```solidity
function _withdrawAsset(...) internal virtual override hasAccountingModule onlyAllocator {
    if (asset_ != asset()) {
        revert InvalidAsset(asset_);
    }

    // call the base strategy withdraw function for accounting
    _subTotalAssets(_convertAssetToBase(asset_, assets));   // base-converted

    if (caller != owner) {
        _spendAllowance(owner, caller, shares);
    }

    _burn(owner, shares);

    // burn virtual tokens
    _getFlexStrategyStorage().accountingModule.withdraw(assets, receiver);  // raw assets
    emit WithdrawAsset(caller, receiver, owner, asset_, assets, shares);
}
```

The function calls `_subTotalAssets(_convertAssetToBase(asset_, assets))` which converts the asset amount to base units, but then passes raw `assets` to `accountingModule.withdraw(assets, receiver)`.

Since the asset check `if (asset_ != asset()) revert InvalidAsset(asset_)` ensures that `asset_` is the base asset, and `_convertAssetToBase` for the base asset should return the same value (1:1 rate via FixedRateProvider), this is currently safe. However, if the FixedRateProvider's rate for the base asset were ever changed to a non-1:1 rate, or if a different provider were configured, the two amounts could diverge, creating an accounting mismatch between what the vault deducts from total assets and what the accounting module burns/transfers.

**Impact:**

Currently no impact due to the 1:1 rate from FixedRateProvider. However, this creates a latent coupling to the rate provider configuration. If the rate provider is ever changed to return a non-1:1 rate for the base asset, the accounting module would burn/transfer a different amount than what the vault deducted from its internal total assets.

**Recommendation:**

Use the same converted amount for both operations:
```solidity
uint256 baseAssets = _convertAssetToBase(asset_, assets);
_subTotalAssets(baseAssets);
// ...
_getFlexStrategyStorage().accountingModule.withdraw(baseAssets, receiver);
```

---

### [INFORMATIONAL] OA-FS-10: `AccountingModule.initialize` does not validate that `strategy_` implements `IERC4626`

**Pipeline:** Forefy (Integration Layer)
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:135-172

**Description:**

During initialization, the AccountingModule calls `IERC4626(strategy_).asset()` to set the base asset:

```solidity
s.baseAsset = IERC4626(strategy_).asset();
```

If `strategy_` is not a valid IERC4626 implementation (e.g., it's a plain EOA or a contract without an `asset()` function), this call will revert at initialization time, which is safe from a funds perspective. However, the revert message will be a generic low-level revert rather than a descriptive error about the strategy not implementing the expected interface.

More importantly, `createStrategySnapshot()` is called at the end of `initialize`, which calls `strategyVault.convertToAssets(10 ** strategyVault.decimals())`, `strategyVault.totalSupply()`, and `strategyVault.totalAssets()`. If the strategy is deployed but not yet initialized at this point, these functions may return zero values, creating an initial snapshot with `pricePerShare = 0`, `totalSupply = 0`, and `totalAssets = 0`. A zero `pricePerShare` in the initial snapshot would cause `calculateApr` to revert with `InvariantViolation()` when used as a reference, effectively making this snapshot unusable.

**Impact:**

Informational. The initialization would either revert (if strategy is invalid) or create a potentially unusable initial snapshot (if strategy is not yet fully initialized). The deployment script must ensure the strategy is fully initialized before the AccountingModule is initialized.

**Recommendation:**

Add explicit interface validation during initialization and document the deployment ordering requirement.

---

### [INFORMATIONAL] OA-FS-11: `RewardsSweeper` imports `forge-std/console.sol` in production code

**Pipeline:** Forefy (Technical Layer)
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/utils/RewardsSweeper.sol`:10

**Description:**

The RewardsSweeper contract imports `forge-std/console.sol`:

```solidity
import { console } from "forge-std/console.sol";
```

This is a Foundry test utility that should not be present in production deployment code. While it does not affect contract functionality if `console.log` is not called, it increases the deployment bytecode size and signals that the code may not have gone through a production readiness review.

Note: This finding overlaps with existing FLEX-02 but is included here for completeness as it was independently detected.

**Impact:**

No functional impact. Increased bytecode size and deployment cost. Potential indicator of incomplete production preparation.

**Recommendation:**

Remove the `console` import from production code.

---

## Deduplication Notes

The following potential findings were identified but excluded as duplicates of existing findings:

- **APR cap bypass via snapshot index selection**: Duplicate of FLEX-01. Both pipelines independently identified this as the primary medium-severity issue.
- **Zero-amount `processRewards` consuming cooldowns**: Partially overlaps with FLEX-04, but OA-FS-03 specifically covers the `processLosses` variant which was not previously reported.
- **`console.sol` import**: Partially overlaps with FLEX-02 (OA-FS-11 is noted as informational).

## Skeptic Pass (Hard-Negative Validation)

Each finding above was validated against the hard-negative patterns from the Archethect framework:

1. **OA-FS-01 (stale supply in calculateMaxRewards)**: Not a hard-negative match. The issue is not about rounding or fee-on-transfer tokens; it's about using temporally inconsistent data points in a calculation.

2. **OA-FS-02 (compounding snapshots)**: Partial hard-negative match against "epoch-based settlement with clear boundaries." The snapshot system is by design, but the compounding behavior is not documented. Emitted at original priority.

3. **OA-FS-03 (zero-amount processLosses)**: Not a hard-negative match. The "zero-amount operations are no-ops" hard-negative does not apply because this operation has side effects (cooldown consumption, snapshot creation).

4. **OA-FS-04 (calculateApr underflow)**: Not a hard-negative match. The underflow is an unintended consequence of the formula, not an intentional design choice.

5. **OA-FS-05 (RewardsSweeper no validation)**: Not a hard-negative match. The "governance-adjustable parameters with bounds checking" hard-negative explicitly notes that bounds checking should exist.

6. **OA-FS-06 (unlimited approval)**: Partial hard-negative match against "unlimited approval to immutable router." However, the AccountingModule is *upgradeable* (uses Initializable), so the hard-negative does not fully apply. Priority reduced from Medium to Low.

7. **OA-FS-07 (front-run window)**: Partial hard-negative match against "trusted callback target." The AccountingModule is a trusted contract, but the ordering creates observable intermediate state. Priority set at Low.

8. **OA-FS-08 (inconsistent TVL thresholds)**: Partial hard-negative match against "intentional and documented unit differences." The asymmetry may be intentional but is not documented. Priority set at Low.

9. **OA-FS-09 (base conversion mismatch)**: Hard-negative match against "specific token set" -- with the FixedRateProvider always returning 1:1, the amounts are always equal. Priority reduced from Medium to Low as a latent risk.
