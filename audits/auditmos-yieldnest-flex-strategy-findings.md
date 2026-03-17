# Auditmos DeFi Checklist Audit: yieldnest-flex-strategy -- New Findings

**Date:** 2026-03-17
**Methodology:** Auditmos DeFi Checklists (Staking, Math Precision, State Validation, Reentrancy, Slippage)
**Target:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/`
**LOC:** ~1,074
**Solidity Version:** ^0.8.28

**Existing Findings (excluded from this report):**
- FLEX-01: APR cap bypass via snapshot index selection in processRewards

---

## Checklist Verification Summary

### Always-Checklist
- [x] State changes before external calls (CEI pattern) -- FINDING (AM-FS-01)
- [ ] NonReentrant modifiers on vulnerable functions -- FINDING (AM-FS-01)
- [x] No assumptions about token transfer behavior -- PASS (AccountingToken blocks transfers)
- [ ] Cross-function reentrancy considered -- FINDING (AM-FS-01)
- [x] Read-only reentrancy risks evaluated -- PASS (view functions do not depend on intermediate state)
- [x] Fee-on-transfer tokens handled correctly -- N/A (base asset is fixed at initialization)
- [x] Rebasing tokens accounted for -- N/A (accounting token is non-rebasing IOU)
- [x] Tokens with callbacks (ERC777) considered -- PASS (AccountingToken blocks transfer/transferFrom)
- [x] Zero transfer reverting tokens handled -- FINDING (AM-FS-04)
- [x] Pausable tokens won't brick protocol -- PASS (pause inherited from BaseVault)
- [x] Token decimals properly scaled -- PASS (FixedRateProvider uses tracked asset decimals)
- [x] Critical functions have appropriate modifiers -- PASS (role-based access on all state-changing functions)
- [x] Two-step ownership transfer implemented -- N/A (uses AccessControl roles, not Ownable)
- [x] Role-based permissions properly segregated -- PASS
- [x] Emergency pause functionality included -- PASS (inherited from BaseVault)
- [ ] Time delays for critical operations -- FINDING (AM-FS-02)

### Staking Checklist
- [x] Separate tokens -- PASS (base asset and accounting token are distinct)
- [x] No direct transfer dilution -- PASS (totalSupply tracked via mint/burn, not balanceOf)
- [ ] Precision protection -- FINDING (AM-FS-05)
- [x] Flash protection -- PASS (cooldown mechanism between reward/loss processing)
- [x] Index updates -- PASS (processAccounting called after mint/burn, snapshot created)
- [x] Balance integrity -- PASS (accounting token mint/burn atomic with base asset transfer)

### Math Precision Checklist
- [x] Multiplication always performed before division -- PARTIAL (AM-FS-03)
- [x] Checks for rounding to zero with appropriate reverts -- FINDING (AM-FS-05)
- [x] Token amounts scaled to common precision before calculations -- PASS
- [x] No double-scaling of already scaled values -- PASS
- [x] Consistent precision scaling across all modules -- PASS (DIVISOR = 1e18 used consistently)
- [x] SafeCast used for all downcasting operations -- N/A (only uint64 cast from block.timestamp, safe until year 584 billion)
- [ ] Protocol fees round up, user amounts round down -- N/A (fees are zero)
- [x] Decimal assumptions documented and validated -- PASS (decimals queried from tracked asset)
- [x] Interest calculations use correct time units -- PASS (YEAR = 365.25 days used consistently)
- [x] Token pair directions consistent across calculations -- PASS

### State Validation Checklist
- [x] All multi-step processes verify previous steps were initiated -- PASS
- [x] Functions validate array lengths > 0 before processing -- N/A (no array-based batch operations)
- [ ] All function inputs are validated for edge cases -- FINDING (AM-FS-02, AM-FS-04)
- [x] Return values from all function calls are checked -- PASS (SafeERC20 used throughout)
- [x] State transitions are atomic and cannot be partially completed -- PASS (reverts undo all changes)
- [x] ID existence is verified before use -- PASS (snapshot index bounds checked)
- [x] Array parameters have matching length validation -- N/A
- [x] Access control modifiers on all administrative functions -- PASS
- [x] State variables updated before external calls (CEI pattern) -- FINDING (AM-FS-01)
- [x] Pause mechanisms synchronized -- PASS (single pause inherited from BaseVault)
- [x] Grace periods implemented after unpause events -- N/A (cooldown serves similar purpose)

### Reentrancy Checklist
- [ ] CEI pattern -- FINDING (AM-FS-01)
- [ ] NonReentrant modifiers -- FINDING (AM-FS-01)
- [x] Token assumptions -- PASS (AccountingToken is non-transferable)
- [ ] Cross-function analysis -- FINDING (AM-FS-01)
- [x] Read-only safety -- PASS

### Slippage Checklist
- [x] User can specify minTokensOut for all swaps -- N/A (no DEX integrations)
- [x] User can specify deadline for time-sensitive operations -- N/A
- [x] Slippage calculated correctly -- N/A
- [ ] Slippage precision matches output token -- N/A
- [x] Hard-coded slippage can be overridden by users -- N/A
- [x] Slippage checked on final output amount -- N/A
- [x] Slippage calculated off-chain, not on-chain -- N/A
- [x] Fee tiers not hardcoded -- N/A
- [x] Proper deadline validation (not block.timestamp) -- N/A

---

## Findings

---

### [MEDIUM] AM-FS-01: AccountingModule lacks reentrancy protection on reward and loss processing functions

**Checklist:** Reentrancy
**Checklist Item:** NonReentrant modifiers applied to all state-changing functions with external calls; Cross-function reentrancy considered
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:218, 228, 354

**Description:**

The `processRewards` and `processLosses` functions in `AccountingModule` perform multiple external calls without a `nonReentrant` modifier:

```solidity
function _processRewards(uint256 amount, uint256 snapshotIndex) internal {
    // ...
    s.accountingToken.mintTo(s.strategy, amount);    // External call #1
    strategyVault.processAccounting();                // External call #2
    // ...
    uint256 currentPricePerShare = createStrategySnapshot().pricePerShare;
    // createStrategySnapshot calls:
    //   strategyVault.convertToAssets(...)            // External call #3
    //   strategyVault.totalSupply()                   // External call #4
    //   strategyVault.totalAssets()                   // External call #5
    // ...
}
```

Similarly, `processLosses` makes external calls to `accountingToken.burnFrom`, `strategyVault.processAccounting`, and multiple view calls within `createStrategySnapshot`.

While `processAccounting()` on `BaseVault` has a `nonReentrant` modifier, this guard only protects the strategy vault contract from reentrancy into itself. It does not prevent reentrancy back into `AccountingModule`. The `AccountingModule` has no reentrancy guard of its own.

The `accountingToken.mintTo` and `accountingToken.burnFrom` are calls to the `AccountingToken` contract. If the `AccountingToken` implementation were ever upgraded (it uses `Initializable` and `AccessControlUpgradeable`), or if the mint/burn implementation triggered any hooks or callbacks (e.g., via an ERC-20 extension), a reentrant call back into `AccountingModule` could observe intermediate state where tokens are minted but `processAccounting` has not yet been called and the APR check has not yet been validated.

Cross-function reentrancy is also a concern. Between `_processRewards` external calls, the `deposit` or `withdraw` functions (callable by the strategy) could theoretically be invoked if any callback reaches the strategy. The `deposit` and `withdraw` functions share state (the accounting token supply and the strategy's total assets) with `_processRewards`.

In practice, the current `AccountingToken` implementation uses standard OpenZeppelin `_mint`/`_burn` without hooks, and `transfer`/`transferFrom` revert, so the current attack surface is limited. However, the absence of a reentrancy guard means the protection relies on implementation details of external contracts rather than explicit defense.

**Impact:**

Currently low exploitability due to the standard OpenZeppelin `AccountingToken` implementation. However, if the `AccountingToken` is upgraded to include any callback mechanism (e.g., ERC-20 extensions, hooks, or cross-contract notifications), the lack of reentrancy protection on `AccountingModule` could allow an attacker to reenter `processRewards` or `processLosses` to manipulate state. The cooldown mechanism provides some protection (only one reward/loss operation per cooldown period), but the cooldown is set in the modifier before the function body executes, and within a single transaction the modifier's state change would be visible.

**Recommendation:**

Add `ReentrancyGuardUpgradeable` from OpenZeppelin to `AccountingModule` and apply the `nonReentrant` modifier to `processRewards` (both overloads), `processLosses`, `deposit`, and `withdraw`:

```solidity
contract AccountingModule is IAccountingModule, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // ...
    function processRewards(uint256 amount) external onlyRole(REWARDS_PROCESSOR_ROLE) checkAndResetCooldown nonReentrant {
        // ...
    }
}
```

---

### [MEDIUM] AM-FS-02: `cooldownSeconds` can be set to zero, disabling rate-limiting on reward and loss processing

**Checklist:** State Validation
**Checklist Item:** All function inputs are validated for edge cases (zero values)
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:424-428

**Description:**

The `_setCooldownSeconds` function accepts any `uint16` value including zero, with no minimum validation:

```solidity
function _setCooldownSeconds(uint16 cooldownSeconds_) internal {
    AccountingModuleStorage storage s = _getAccountingModuleStorage();
    emit CooldownSecondsUpdated(cooldownSeconds_, s.cooldownSeconds);
    s.cooldownSeconds = cooldownSeconds_;
}
```

When `cooldownSeconds` is zero, the `checkAndResetCooldown` modifier becomes effectively a no-op:

```solidity
modifier checkAndResetCooldown() {
    AccountingModuleStorage storage s = _getAccountingModuleStorage();
    if (block.timestamp < s.nextUpdateWindow) revert TooEarly();
    s.nextUpdateWindow = (uint64(block.timestamp) + s.cooldownSeconds); // +0 = current timestamp
    _;
}
```

With `cooldownSeconds = 0`, the `nextUpdateWindow` is set to `block.timestamp`, which means the check `block.timestamp < s.nextUpdateWindow` will fail (they are equal, not less than) on the next call in the same block. However, in the very next block (or even a later transaction in the same block if `block.timestamp` hasn't changed), the condition passes again since `block.timestamp >= nextUpdateWindow`.

This effectively allows the `REWARDS_PROCESSOR_ROLE` or `LOSS_PROCESSOR_ROLE` to call `processRewards` or `processLosses` once per block (or multiple times across blocks within the same second), removing the rate-limiting protection that the cooldown is designed to provide. The cooldown is a key safety mechanism that limits how quickly rewards or losses can be processed, giving governance time to react to anomalies. Without it, a compromised or malicious rewards processor could rapidly push many reward operations, potentially compounding the APR cap issue described in FLEX-01.

The `setCooldownSeconds` function is gated by `SAFE_MANAGER_ROLE`, and the same role sets `targetApy` and `lowerBound`. However, the cooldown serves as a defense-in-depth mechanism that should have a non-trivial minimum even if the manager role is trusted.

**Impact:**

Setting `cooldownSeconds = 0` removes the rate-limiting protection on reward and loss processing. A `REWARDS_PROCESSOR_ROLE` holder could then call `processRewards` every block, compounding rewards at the maximum APR cap rate. Combined with the snapshot index selection (FLEX-01), this amplifies the potential for over-rewarding: many small reward calls in rapid succession, each within the APR cap but cumulatively exceeding the intended rate due to compounding.

For example, with a 10% target APY and zero cooldown, a rewards processor could call `processRewards` 7,200 times per day (at 12-second blocks), each time pushing rewards up to the per-second APR limit. The compounding effect across these rapid calls results in a higher effective annual rate than the intended 10%.

**Recommendation:**

Add a minimum cooldown validation in `_setCooldownSeconds`:

```solidity
uint16 public constant MIN_COOLDOWN_SECONDS = 3600; // 1 hour minimum

function _setCooldownSeconds(uint16 cooldownSeconds_) internal {
    AccountingModuleStorage storage s = _getAccountingModuleStorage();
    if (cooldownSeconds_ < MIN_COOLDOWN_SECONDS) revert InvariantViolation();
    emit CooldownSecondsUpdated(cooldownSeconds_, s.cooldownSeconds);
    s.cooldownSeconds = cooldownSeconds_;
}
```

---

### [MEDIUM] AM-FS-03: Rounding discrepancy between RewardsSweeper and AccountingModule causes sweep-to-max to revert at boundary

**Checklist:** Math Precision
**Checklist Item:** Multiplication always performed before division; Checks for rounding to zero with appropriate reverts
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/utils/RewardsSweeper.sol`:126-129, `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:344-345

**Description:**

The `RewardsSweeper.calculateMaxRewards` and `AccountingModule.calculateApr` use inverse formulas to compute the maximum allowable reward amount and the resulting APR respectively. Due to integer division truncation, these formulas are not perfectly inverse, causing the sweeper to compute a maximum reward amount that, when processed, results in an APR slightly above the target -- causing the `processRewards` call to revert.

In `RewardsSweeper.calculateMaxRewards` (line 126-129):

```solidity
uint256 pricePerShareWithMaxTargetApy = previousPricePerShare
    + (targetApy * previousPricePerShare * (currentTimestamp - previousTimestamp)) / (YEAR * DIVISOR);

uint256 totalAssetsWithMaxTargetApy = (pricePerShareWithMaxTargetApy * currentSupply / (10 ** sharesDecimals));
```

In `AccountingModule.calculateApr` (line 344-345):

```solidity
return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
    / (currentTimestamp - previousTimestamp);
```

The truncation in `calculateMaxRewards` at two division points (dividing by `YEAR * DIVISOR` on line 127, and by `10 ** sharesDecimals` on line 129) produces a `totalAssetsWithMaxTargetApy` that is slightly lower than the exact value. This means the computed `maxRewards` is slightly conservative. So far this is safe.

However, the issue arises in how `processAccounting` recalculates `totalAssets` and `convertToAssets`. The vault's `convertToAssets(10 ** decimals)` performs its own rounding, and the relationship between `totalAssets / totalSupply * 10**decimals` and the sweeper's calculation may not align perfectly. Specifically, the vault's `processAccounting` recomputes total assets by iterating over all asset balances and converting via rates, which can introduce additional rounding steps not accounted for in the sweeper's linear formula.

The reverse calculation in `calculateApr` also truncates with two sequential divisions (`/ previousPricePerShare / timeDelta`), which loses up to `timeDelta - 1` units of precision compared to a single division by `previousPricePerShare * timeDelta`. While this precision loss is typically negligible (< 0.001% for realistic values), at the exact boundary where the computed APR equals `targetApy`, the rounding direction mismatch between the forward (sweeper) and reverse (accounting module) calculations can cause the APR to be calculated as `targetApy + 1`, triggering the revert.

**Impact:**

When `sweepRewardsUpToAPRMax` is called, it computes the maximum reward amount and then calls `sweepRewards`, which calls `accountingModule.processRewards`. If the rounding discrepancy causes the resulting APR to be `targetApy + 1` (one unit above target), the transaction reverts with `AccountingLimitsExceeded`. The REWARDS_SWEEPER_ROLE holder must then manually reduce the amount by a small epsilon to succeed, defeating the purpose of the automated maximum-sweep function.

This is most likely to manifest with:
- Small time deltas (e.g., cooldown just barely passed) where the absolute rounding error is proportionally larger
- Large total supply values where `totalAssetsWithMaxTargetApy` calculation has more significant truncation
- When the vault's `processAccounting` rounds total assets in a different direction than the sweeper expects

**Recommendation:**

Apply a small safety margin in `calculateMaxRewards` to ensure the computed maximum stays safely below the APR cap:

```solidity
// Subtract a small buffer (e.g., 1 basis point worth of precision) to avoid boundary revert
uint256 safetyMargin = previousPricePerShare / 10000; // 0.01% of PPS
uint256 pricePerShareWithMaxTargetApy = previousPricePerShare
    + (targetApy * previousPricePerShare * (currentTimestamp - previousTimestamp)) / (YEAR * DIVISOR);

if (pricePerShareWithMaxTargetApy > safetyMargin) {
    pricePerShareWithMaxTargetApy -= safetyMargin;
}
```

Alternatively, use a single combined division in `calculateApr` to minimize truncation:

```solidity
return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR
    / (previousPricePerShare * (currentTimestamp - previousTimestamp));
```

---

### [LOW] AM-FS-04: `processRewards` does not validate `amount > 0`, allowing zero-amount reward processing to consume cooldowns and create snapshots

**Checklist:** State Validation
**Checklist Item:** All function inputs are validated for edge cases (zero values)
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:218-221, 228-237

**Description:**

Neither overload of `processRewards` validates that `amount > 0`:

```solidity
function processRewards(uint256 amount) external onlyRole(REWARDS_PROCESSOR_ROLE) checkAndResetCooldown {
    AccountingModuleStorage storage s = _getAccountingModuleStorage();
    _processRewards(amount, s._snapshots.length - 1);
}
```

When `amount == 0`:
1. `mintTo(strategy, 0)` succeeds (OpenZeppelin ERC-20 `_mint` with zero amount is a no-op).
2. `processAccounting()` is called, performing unnecessary computation.
3. A new snapshot is created, appending to the unbounded `_snapshots` array.
4. `calculateApr` returns 0 (since PPS hasn't changed), which passes the `> targetApy` check.
5. The cooldown is consumed by the `checkAndResetCooldown` modifier.

This allows a `REWARDS_PROCESSOR_ROLE` holder to:
- Consume cooldown periods without distributing any rewards, blocking legitimate processing during the cooldown window
- Inflate the snapshots array with redundant entries, increasing gas costs for functions that reference snapshot length or iterate over snapshots
- In multi-role governance setups, grief the system by repeatedly calling `processRewards(0)` to lock out the cooldown

This is analogous to the existing finding OA-FS-03 for `processLosses`, but the `processRewards` path was not previously reported.

**Impact:**

A `REWARDS_PROCESSOR_ROLE` holder can deny legitimate reward and loss processing by consuming cooldowns with zero-amount calls. Each call adds an unnecessary snapshot to storage, contributing to unbounded array growth over time. In multi-party governance where different entities hold REWARDS_PROCESSOR_ROLE and LOSS_PROCESSOR_ROLE, this enables cross-role griefing.

**Recommendation:**

Add zero-amount validation at the beginning of `_processRewards`:

```solidity
function _processRewards(uint256 amount, uint256 snapshotIndex) internal {
    if (amount == 0) revert InvariantViolation();
    // ...
}
```

---

### [LOW] AM-FS-05: No minimum deposit enforcement allows dust deposits that produce zero shares

**Checklist:** Staking
**Checklist Item:** Precision protection: Minimum stake enforced or sufficient scaling to prevent rounding to zero
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/FlexStrategy.sol`:110-128

**Description:**

The `FlexStrategy._deposit` function does not enforce a minimum deposit amount:

```solidity
function _deposit(
    address asset_,
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares,
    uint256 baseAssets
)
    internal
    virtual
    override
    hasAccountingModule
{
    super._deposit(asset_, caller, receiver, assets, shares, baseAssets);
    _getFlexStrategyStorage().accountingModule.deposit(assets);
}
```

The base vault's `_deposit` calls `_addTotalAssets(baseAssets)` and `_mint(receiver, shares)`, where `shares` is pre-computed by the calling function. If the deposit amount is very small (e.g., 1 wei) and `totalAssets` is large relative to `totalSupply`, the share calculation `shares = assets * totalSupply / totalAssets` can round down to zero.

While the base vault may have protections against zero-share minting (ERC-4626 typically reverts on zero shares), the accounting module's `deposit` function will still transfer 1 wei to the safe and mint 1 wei of accounting tokens. This creates an asymmetry: 1 wei of base asset is transferred and 1 accounting token is minted, but zero vault shares are minted to the receiver. The depositor loses their 1 wei with no share representation.

Over many such dust deposits, the accounting token supply and base asset in the safe could diverge from the vault's totalAssets tracking, as each dust deposit adds to the accounting module's state without corresponding vault shares.

Additionally, the `AccountingModule` enforces `minRewardableAssets` for reward processing but not for deposits. Extremely small deposits could be used to manipulate the accounting token supply or create insignificant share dilution.

**Impact:**

Low. Dust deposits result in the depositor losing their deposit with no shares. The economic loss per transaction is negligible (1 wei + gas), making sustained exploitation uneconomical. However, the accounting divergence between accounting token supply and vault totalAssets could accumulate over many dust deposits, creating minor long-term inconsistency.

**Recommendation:**

Add a minimum deposit check in `_deposit`:

```solidity
function _deposit(...) internal virtual override hasAccountingModule {
    if (assets < MIN_DEPOSIT) revert DepositTooSmall();
    super._deposit(asset_, caller, receiver, assets, shares, baseAssets);
    _getFlexStrategyStorage().accountingModule.deposit(assets);
}
```

Alternatively, validate that `shares > 0` before proceeding:

```solidity
if (shares == 0) revert ZeroShares();
```

---

### [LOW] AM-FS-06: RewardsSweeper `initialize` missing zero-address validation for `admin` and `accountingModule_`

**Checklist:** State Validation
**Checklist Item:** All function inputs are validated for edge cases (zero values)
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/utils/RewardsSweeper.sol`:40-45

**Description:**

The `initialize` function in `RewardsSweeper` does not validate either parameter for the zero address:

```solidity
function initialize(address admin, address accountingModule_) external initializer {
    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    accountingModule = IAccountingModule(accountingModule_);
}
```

If `admin` is `address(0)`, `DEFAULT_ADMIN_ROLE` is granted to the zero address. Since no one can send transactions from `address(0)`, the contract becomes permanently ungovernable: no one can grant roles, change the accounting module, or perform any admin action. The contract is effectively bricked.

If `accountingModule_` is `address(0)`, all subsequent calls to `sweepRewards`, `canSweepRewards`, and `previewSweepRewardsUpToAPRMax` will revert when attempting to call functions on `address(0)`.

Unlike `AccountingModule.initialize` (which validates `admin != address(0)` and `accountingToken_ != address(0)`) and `AccountingToken.initialize` (which validates `admin != address(0)`), the `RewardsSweeper.initialize` performs no such validation.

Since `initialize` can only be called once (due to the `initializer` modifier), a deployment error with `address(0)` parameters would require redeploying the contract entirely.

**Impact:**

Deployment misconfiguration risk. Passing `address(0)` for either parameter results in a permanently bricked contract that must be redeployed. While this is an operational error rather than an exploit, it creates unnecessary redeployment cost and potential temporary unavailability of the sweep functionality.

**Recommendation:**

Add zero-address validation consistent with the other contracts:

```solidity
function initialize(address admin, address accountingModule_) external initializer {
    if (admin == address(0)) revert ZeroAddress();
    if (accountingModule_ == address(0)) revert ZeroAddress();

    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    accountingModule = IAccountingModule(accountingModule_);
}
```

---

### [LOW] AM-FS-07: `calculateApr` reverts with opaque Panic on negative PPS delta instead of descriptive error

**Checklist:** Math Precision
**Checklist Item:** Checks for rounding to zero with appropriate reverts
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-flex-strategy/src/AccountingModule.sol`:344

**Description:**

The `calculateApr` function computes:

```solidity
return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
    / (currentTimestamp - previousTimestamp);
```

If `currentPricePerShare < previousPricePerShare`, the subtraction `currentPricePerShare - previousPricePerShare` causes an arithmetic underflow, reverting with a Solidity `Panic(0x11)` error rather than a descriptive custom error.

This scenario arises naturally when:
1. `processLosses` decreases the PPS, then `processRewards` is called referencing a snapshot from before the loss (using the `snapshotIndex` parameter). The post-loss PPS is lower than the pre-loss snapshot's PPS.
2. External factors cause the vault's `convertToAssets` to return a lower value than at the referenced snapshot (e.g., if the base asset balance in the safe decreased due to a Gnosis Safe transaction outside the protocol's control).

The function is `public pure`, meaning it can also be called directly by integrators or off-chain systems for APR estimation. An opaque panic provides no diagnostic information about why the call failed.

**Impact:**

Integrators and monitoring systems calling `calculateApr` with a PPS that has decreased receive an opaque `Panic(0x11)` rather than a descriptive error. Within the protocol, `_processRewards` referencing a pre-loss snapshot would revert without indication that the issue is a negative PPS delta, making debugging and operational monitoring more difficult. No direct fund loss, but reduced operational clarity.

**Recommendation:**

Add an explicit check with a descriptive error:

```solidity
error NegativePricePerShareDelta(uint256 currentPricePerShare, uint256 previousPricePerShare);

function calculateApr(...) public pure returns (uint256 apr) {
    if (currentTimestamp <= previousTimestamp) revert CurrentTimestampBeforePreviousTimestamp();
    if (previousPricePerShare == 0) revert InvariantViolation();
    if (currentPricePerShare < previousPricePerShare) {
        revert NegativePricePerShareDelta(currentPricePerShare, previousPricePerShare);
    }

    return (currentPricePerShare - previousPricePerShare) * YEAR * DIVISOR / previousPricePerShare
        / (currentTimestamp - previousTimestamp);
}
```

Alternatively, if the protocol should allow processing rewards even when PPS has decreased (e.g., recovery after a loss), return 0 for negative deltas and let the caller decide.

---

## Deduplication Notes

The following potential findings were identified but excluded as duplicates of existing or prior-pipeline findings:

- **APR cap bypass via snapshot index selection**: Duplicate of FLEX-01.
- **Zero-amount `processLosses`**: Reported in OA-FS-03 from the prior OpenAudit pipeline.
- **RewardsSweeper `setAccountingModule` missing zero-address check**: Reported in OA-FS-05. AM-FS-06 covers the `initialize` function instead.
- **Unlimited `type(uint256).max` approval to upgradeable module**: Reported in OA-FS-06 from the prior pipeline.
- **`processLosses` inconsistent TVL threshold**: Reported in OA-FS-08 from the prior pipeline.
- **`forge-std/console.sol` import in production**: Reported in OA-FS-11.
- **RewardsSweeper uses stale totalSupply in calculateMaxRewards**: Reported in OA-FS-01. AM-FS-03 covers a distinct but related rounding discrepancy.
- **Compounding effect of sequential reward snapshots**: Reported in OA-FS-02.

---

## Findings Summary

| ID | Severity | Title | Checklist |
|----|----------|-------|-----------|
| AM-FS-01 | Medium | AccountingModule lacks reentrancy protection on processing functions | Reentrancy |
| AM-FS-02 | Medium | `cooldownSeconds` can be set to zero, disabling rate-limiting | State Validation |
| AM-FS-03 | Medium | Rounding discrepancy between RewardsSweeper and AccountingModule at boundary | Math Precision |
| AM-FS-04 | Low | `processRewards` accepts zero amount, consuming cooldowns | State Validation |
| AM-FS-05 | Low | No minimum deposit enforcement allows dust deposits | Staking |
| AM-FS-06 | Low | RewardsSweeper `initialize` missing zero-address validation | State Validation |
| AM-FS-07 | Low | `calculateApr` reverts with opaque Panic on negative PPS delta | Math Precision |
