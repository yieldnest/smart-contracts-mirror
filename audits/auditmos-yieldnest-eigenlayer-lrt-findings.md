# Auditmos Checklist-Based Audit: yieldnest-eigenlayer-lrt

**Target:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/`
**Description:** EigenLayer Liquid Restaking Token protocol with ynETH and ynEIGEN subsystems
**Methodology:** Auditmos DeFi Checklist Pipeline (6 skill checklists + master checklist)
**Date:** 2026-03-17

---

## Checklist Results

### Master Checklist (always-checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | State changes before external calls (CEI pattern) | PARTIAL | `finalizeRequestsUpToIndex` pushes struct before validation (F-04 known). `ynETH.depositETH` updates `totalDepositedInPool` after `_mint`. `StakingNode.deallocateStakedETH` follows CEI correctly. |
| 2 | NonReentrant modifiers on vulnerable functions | FAIL | `ynETH.sol` has no ReentrancyGuard inheritance or nonReentrant usage at all. `depositETH`, `receiveRewards`, `processWithdrawnETH`, `withdrawETH` all lack protection. |
| 3 | No assumptions about token transfer behavior | PASS | SafeERC20 used for ERC20 transfers. ETH transfers use low-level `.call{value}` with success checks. |
| 4 | Cross-function reentrancy considered | PARTIAL | ynETH lacks reentrancy guard; cross-function reentrancy between `depositETH` and `totalAssets()` is theoretically possible via receiver callbacks (ERC20 standard does not have receive hooks, mitigating risk). |
| 5 | Read-only reentrancy risks evaluated | INFO | `totalDeposited()` in StakingNodesManager includes `redemptionAssetsVault.availableRedemptionAssets()` which could return stale values during reentrancy. |
| 6 | Fee-on-transfer tokens handled correctly | N/A | ynETH subsystem handles only native ETH. ynEIGEN uses specific whitelisted LSDs (wstETH, rETH, etc.) which are not fee-on-transfer. |
| 7 | Rebasing tokens accounted for | PASS | stETH/oETH are wrapped to wstETH/woETH before staking via LSDWrapper. |
| 8 | Tokens with callbacks (ERC777) considered | PASS | Only whitelisted LSD tokens are accepted; none are ERC777. |
| 9 | Zero transfer reverting tokens handled | PASS | Zero amount checks present in deposit functions. |
| 10 | Pausable tokens won't brick protocol | PASS | Pause mechanisms on deposits/withdrawals independently. |
| 11 | Token decimals properly scaled | PARTIAL | `AssetRegistry.convertToUnitOfAccount` handles decimal scaling but uses plain division (see AM-EL-04). |
| 12 | Critical functions have appropriate modifiers | PARTIAL | `updateTotalETHStaked`, `updateTokenStakingNodesBalances`, `synchronizeNodesAndUpdateBalances` are permissionless. |
| 13 | Two-step ownership transfer implemented | PASS | Uses AccessControlUpgradeable with role-based admin. |
| 14 | Role-based permissions properly segregated | PASS | Separate roles for admin, pauser, staking operator, delegator, withdrawer, finalizer. |
| 15 | Emergency pause functionality included | PASS | Pause functions on deposits, withdrawal queue, redemption vaults. |
| 16 | Time delays for critical operations | FAIL | `secondsToFinalization` declared but never initialized or enforced (see AM-EL-01). |

### Staking Checklist (audit-staking/checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Separate tokens: reward token cannot be same as staking token | PASS | ynETH/ynEigen are separate from staked ETH/LSDs. Rewards flow through RewardsDistributor. |
| 2 | No direct transfer dilution: totalSupply tracks staked amounts, not token balance | PASS | `totalDepositedInPool` and `totalETHStaked` are tracked separately from ETH balance. |
| 3 | Precision protection: minimum stake enforced | PARTIAL | Zero checks present but no minimum deposit amount beyond zero. First deposit uses 1:1 rate. |
| 4 | Flash protection: time locks or anti-sandwich | PASS | Withdrawal queue with finalization delay prevents flash deposit/withdraw. |
| 5 | Index updates: updateReward called before/after distribution | PASS | `processRewards` in RewardsDistributor atomically distributes and accounts. |
| 6 | Balance integrity: cached balances updated correctly during claims | PARTIAL | `pendingRequestedRedemptionAmount` can desync (F-03 known). |

### Oracle Checklist (audit-oracle/checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Stale price checks | FAIL | LSDRateProvider has no staleness checks on any rate source (see AM-EL-02). |
| 2 | L2 sequencer check | N/A | Mainnet deployment. |
| 3 | Feed-specific heartbeats | FAIL | No heartbeat validation on any LSD rate provider call. |
| 4 | Oracle precision: decimals() used, no hardcoded decimals | PASS | Returns rates in 1e18 scale consistently. |
| 5 | Price feed addresses: verified correct for chain | PASS | Hardcoded mainnet addresses for known LSD protocols. |
| 6 | Oracle revert handling: try/catch with fallback | FAIL | No try/catch on any external rate call (see AM-EL-02). |
| 7 | Depeg monitoring | PARTIAL | FrxEthWethDualOracle used for sfrxETH depeg detection, but no depeg monitoring for other assets. |
| 8 | Min/max validation | FAIL | No min/max bounds checks on returned rates. |
| 9 | TWAP usage | N/A | Uses protocol-native rates, not AMM spot prices. |
| 10 | Price direction | PASS | All rates are ETH-per-token, consistent. |
| 11 | Circuit breaker checks | FAIL | No circuit breaker on returned rates. |

### Math Precision Checklist (audit-math-precision/checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Multiplication before division | PARTIAL | `AssetRegistry.convertToUnitOfAccount`: `assetRate * amount / (10 ** assetDecimals)` is correct ordering. `calculateRedemptionAmount`: `amount * redemptionRate / (10 ** decimals)` is correct. |
| 2 | Checks for rounding to zero | PASS | `ZeroShares` revert in deposit functions. |
| 3 | Token amounts scaled to common precision | PASS | All amounts converted to unit of account (ETH-denominated, 1e18). |
| 4 | No double-scaling | PASS | Conversion functions are one-directional. |
| 5 | Consistent precision across modules | PARTIAL | `FEE_PRECISION=1000000` in WithdrawalQueueManager vs `_BASIS_POINTS_DENOMINATOR=10000` in RewardsDistributor. Different precision, but each is internally consistent. |
| 6 | SafeCast used for downcasting | PASS | SafeCast.toUint128, SafeCast.toUint64, SafeCast.toUint96 used. |
| 7 | Protocol fees round up, user amounts round down | PARTIAL | `Math.mulDiv` with Floor rounding for user shares. Fee calculation uses plain division (rounds down, favoring user). |
| 8 | Decimal assumptions documented | PASS | YNETH_UNIT=1e18 in Constants.sol. |
| 9 | Interest calculations use correct time units | N/A | No time-based interest. |
| 10 | Token pair directions consistent | PASS | Rate directions consistent across AssetRegistry and LSDRateProvider. |

### Reentrancy Checklist (audit-reentrancy/checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | CEI pattern | PARTIAL | Most contracts follow CEI. `ynETH.depositETH` updates `totalDepositedInPool` after `_mint` (see AM-EL-03). |
| 2 | NonReentrant modifiers on state-changing functions with external calls | FAIL | `ynETH.sol` has zero reentrancy protection (see AM-EL-03). |
| 3 | Token assumptions | PASS | Only whitelisted tokens accepted. |
| 4 | Cross-function analysis | PARTIAL | ynETH's lack of reentrancy guard means all its state-changing functions are unprotected. |
| 5 | Read-only safety | INFO | `previewDeposit`, `previewRedeem` could return inconsistent values mid-transaction. |

### State Validation Checklist (audit-state-validation/checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Multi-step processes verify previous steps | FAIL | `secondsToFinalization` declared but never enforced in `finalizeRequestsUpToIndex` (see AM-EL-01). |
| 2 | Functions validate array lengths > 0 | PASS | Zero-length arrays handled or checked. |
| 3 | Inputs validated for edge cases | PASS | Zero value checks, address(0) checks present. |
| 4 | Return values from function calls checked | PARTIAL | ETH `.call{value}` return values checked. `assertBalanceUnchanged` uses `assert()` instead of `require()` (F-06 known). |
| 5 | State transitions atomic | PARTIAL | `finalizeRequestsUpToIndex` pushes finalization before validation (F-04 known). |
| 6 | ID existence verified before use | PASS | Token ID existence checks in withdrawal claims. |
| 7 | Array parameters have matching length validation | PASS | `claimWithdrawals` checks `tokenIds.length != receivers.length`. `_stakeAssetsToNode` checks `assetsLength != amountsLength`. |
| 8 | Access control on administrative functions | PARTIAL | `updateTotalETHStaked`, `updateTokenStakingNodesBalances`, `synchronizeNodesAndUpdateBalances` lack access control (F-08/F-09 known, but see AM-EL-05 for ynEIGEN side). |
| 9 | State variables updated before external calls (CEI) | PARTIAL | See reentrancy checklist above. |
| 10 | Pause mechanisms synchronized | FAIL | Redemption vault can be paused independently from withdrawal queue. Users could have finalized withdrawals but be unable to claim if vault is paused. No grace period after unpause. |
| 11 | Grace periods after unpause | FAIL | No grace period mechanism after unpause on any contract. |

### Slippage Checklist (audit-slippage/checklist.md)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | User can specify minTokensOut | N/A | No DEX swaps in core contracts. Share calculations use internal exchange rate. |
| 2 | User can specify deadline | N/A | Withdrawal queue uses finalization-based timing, not deadline-based. |
| 3 | Slippage calculated correctly | N/A | No external swaps. |
| 4 | Slippage precision matches output token | N/A | |
| 5 | Hard-coded slippage overridable | N/A | |
| 6 | Slippage checked on final output | N/A | |
| 7 | Slippage calculated off-chain | N/A | |
| 8 | Fee tiers not hardcoded | N/A | |
| 9 | Proper deadline validation | N/A | |

---

## New Findings

**Note:** Findings F-01 through F-04 from the existing audit report are excluded from this analysis. Findings that overlap with F-05 through F-14 are noted.

---

### [MEDIUM] AM-EL-01: `secondsToFinalization` Declared But Never Initialized or Enforced

**Checklist:** audit-state-validation
**Checklist Item:** Multi-step processes verify previous steps were initiated; Grace periods after unpause
**File:** `src/WithdrawalQueueManager.sol`, lines 104, 145-166, 466-495
**Confidence:** High

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

**Impact:**

The REQUEST_FINALIZER_ROLE can finalize withdrawal requests in the same block they are created. This eliminates any time buffer that would allow the protocol to prepare redemption assets or respond to market events. While the finalizer is a trusted role, the absence of a configurable time delay removes a key safety mechanism for users who expected a delay between requesting and finalization.

**Recommendation:**

Add a `setSecondsToFinalization()` admin function and enforce the delay in `finalizeRequestsUpToIndex()`:

```solidity
function setSecondsToFinalization(uint256 _seconds) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
    if (_seconds > MAX_SECONDS_TO_FINALIZATION) {
        revert SecondsToFinalizationExceedsLimit(_seconds);
    }
    emit SecondsToFinalizationUpdated(secondsToFinalization, _seconds);
    secondsToFinalization = _seconds;
}
```

In `finalizeRequestsUpToIndex`, verify that the oldest unfinalized request has passed the required delay:

```solidity
if (secondsToFinalization > 0) {
    WithdrawalRequest memory oldestRequest = withdrawalRequests[lastFinalizedIndex];
    require(
        block.timestamp >= oldestRequest.creationTimestamp + secondsToFinalization,
        "Finalization delay not met"
    );
}
```

---

### [MEDIUM] AM-EL-02: LSDRateProvider Has No Staleness Checks, Revert Handling, or Bounds Validation on External Rate Calls

**Checklist:** audit-oracle
**Checklist Item:** Stale price checks; Oracle revert handling; Min/max validation; Circuit breaker checks
**File:** `src/ynEIGEN/LSDRateProvider.sol`, lines 49-78
**Confidence:** High

**Description:**

The `LSDRateProvider.rate()` function calls six different external protocol contracts to fetch LSD-to-ETH rates but applies no defensive checks:

1. **No staleness detection:** If an external protocol (e.g., Lido, Rocket Pool, Swell) has a bug or paused updates, the rate function will return a stale rate without any indication.
2. **No try/catch:** If any external rate call reverts (protocol upgrade, contract paused, etc.), the entire `rate()` function reverts, which cascades to all operations depending on `AssetRegistry.convertToUnitOfAccount` -- including deposits, withdrawals, and balance calculations.
3. **No bounds validation:** A compromised or buggy external protocol could return an extreme rate (e.g., 0 or `type(uint256).max`), causing incorrect share pricing across the entire ynEIGEN subsystem.

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

**Impact:**

- If any single LSD protocol's rate source reverts, all ynEIGEN deposits and withdrawals for ALL assets would be blocked (since `AssetRegistry.getAssets()` iterates all assets in `availableRedemptionAssets()` and `totalAssets()`).
- A compromised or buggy rate source returning an inflated rate would allow an attacker to deposit the affected LSD token and receive a disproportionate number of ynEigen shares, diluting other depositors.
- A rate returning 0 would cause division by zero in `convertFromUnitOfAccount` or mint shares for free.

**Recommendation:**

1. Wrap each external call in a try/catch pattern, falling back to a cached last-known-good rate or reverting with a specific error.
2. Add min/max bounds validation on returned rates (e.g., rates should be between 0.9e18 and 1.5e18 for LSDs that track ETH).
3. Consider adding a staleness timestamp tracking mechanism or a circuit breaker that pauses affected assets.

```solidity
function rate(address _asset) external view returns (uint256) {
    uint256 _rate;
    if (_asset == LIDO_ASSET) {
        try IstETH(LIDO_UDERLYING).getPooledEthByShares(UNIT) returns (uint256 r) {
            _rate = r;
        } catch {
            revert RateProviderFailed(_asset);
        }
    }
    // ... similar for other assets
    if (_rate < MIN_RATE || _rate > MAX_RATE) revert RateOutOfBounds(_asset, _rate);
    return _rate;
}
```

---

### [LOW] AM-EL-03: ynETH Contract Has No ReentrancyGuard Protection

**Checklist:** audit-reentrancy, always-checklist
**Checklist Item:** NonReentrant modifiers on state-changing functions with external calls
**File:** `src/ynETH.sol`, lines 119-141, 258-265, 272-291, 298-308
**Confidence:** Medium

**Description:**

The `ynETH` contract does not inherit from `ReentrancyGuardUpgradeable` and none of its state-changing functions use the `nonReentrant` modifier. This contrasts with `ynEigen.sol` which does use `nonReentrant` on its `deposit` function (line 122).

Key unprotected functions:
- `depositETH(address receiver)` (line 119) -- payable, mints shares, updates `totalDepositedInPool`
- `receiveRewards()` (line 258) -- payable, updates `totalDepositedInPool`
- `processWithdrawnETH()` (line 298) -- payable, updates `totalDepositedInPool`
- `withdrawETH(uint256 ethAmount)` (line 272) -- sends ETH via `.call{value}`, updates `totalDepositedInPool`

```solidity
// Line 119: No nonReentrant modifier
function depositETH(address receiver) public payable returns (uint256 shares) {
    // ...
    shares = previewDeposit(assets); // reads totalSupply() and totalAssets()
    _mint(receiver, shares);         // mints before updating totalDepositedInPool
    totalDepositedInPool += assets;  // state update AFTER _mint
    // ...
}
```

In `depositETH`, the ordering of `_mint` before `totalDepositedInPool += assets` means that during `_mint`, if any callback were triggered, the `totalSupply()` would reflect the new shares but `totalAssets()` would not yet include the new deposit. This would cause `_convertToShares` to return fewer shares for any concurrent deposit (since totalSupply increased but totalAssets did not). While ERC20 `_mint` does not trigger receive hooks in standard implementations, this violates the CEI pattern.

**Impact:**

The practical risk is low because:
1. Standard ERC20 `_mint` does not trigger receiver callbacks.
2. A reentrant depositor would get a worse rate (more totalSupply, same totalAssets), harming themselves.
3. ETH-receiving functions (`receiveRewards`, `processWithdrawnETH`) have caller restrictions.

However, the complete absence of reentrancy protection is an architectural gap that could become exploitable if the contract is modified or integrated with contracts that do trigger callbacks. The inconsistency with `ynEigen.sol` (which does use `nonReentrant`) suggests this was an oversight.

**Recommendation:**

Add `ReentrancyGuardUpgradeable` to `ynETH` or `ynBase`, and apply `nonReentrant` to `depositETH`, `withdrawETH`, `receiveRewards`, and `processWithdrawnETH`. Also reorder `depositETH` to update `totalDepositedInPool` before `_mint`:

```solidity
function depositETH(address receiver) public payable nonReentrant returns (uint256 shares) {
    // ...
    shares = previewDeposit(assets);
    totalDepositedInPool += assets;  // state update BEFORE external interaction
    _mint(receiver, shares);
    // ...
}
```

---

### [LOW] AM-EL-04: AssetRegistry Conversion Functions Use Plain Division, Risking Rounding Loss

**Checklist:** audit-math-precision
**Checklist Item:** Multiplication always performed before division; Checks for rounding to zero
**File:** `src/ynEIGEN/AssetRegistry.sol`, lines 306-320
**Confidence:** High

**Description:**

The `convertToUnitOfAccount` and `convertFromUnitOfAccount` functions use plain Solidity division rather than `Math.mulDiv` for precision:

```solidity
// Line 306-312
function convertToUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
    uint256 assetRate = rateProvider.rate(address(asset));
    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    return assetDecimals != 18
        ? assetRate * amount / (10 ** assetDecimals)
        : assetRate * amount / 1e18;
}

// Line 314-320
function convertFromUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
    uint256 assetRate = rateProvider.rate(address(asset));
    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    return assetDecimals != 18
        ? amount * (10 ** assetDecimals) / assetRate
        : amount * 1e18 / assetRate;
}
```

For `convertToUnitOfAccount`, `assetRate * amount` can overflow for very large amounts when both values are close to 1e18 scale (product approaches 1e36, well within uint256 range). The overflow risk is minimal, but the lack of `Math.mulDiv` means phantom overflow protection from OpenZeppelin is not utilized.

More importantly, in `convertFromUnitOfAccount`, `amount * 1e18 / assetRate` performs integer division that always rounds down. When this function is used in `RedemptionAssetsVault.transferRedemptionAssets` to calculate how many tokens to send to users during redemption, the rounding consistently favors the protocol (users receive slightly fewer tokens). While individually small, this compounds across many redemptions.

**Impact:**

Each redemption through the multi-asset vault loses up to 1 wei per asset due to integer division truncation. The cumulative effect is small but non-zero dust accumulation in the vault. This is related to existing finding F-05 but focuses on the root cause in `AssetRegistry` rather than the symptom in `RedemptionAssetsVault`.

**Recommendation:**

Use `Math.mulDiv` with explicit rounding direction:

```solidity
function convertToUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
    uint256 assetRate = rateProvider.rate(address(asset));
    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    return Math.mulDiv(assetRate, amount, 10 ** assetDecimals, Math.Rounding.Floor);
}

function convertFromUnitOfAccount(IERC20 asset, uint256 amount) public view returns (uint256) {
    uint256 assetRate = rateProvider.rate(address(asset));
    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    return Math.mulDiv(amount, 10 ** assetDecimals, assetRate, Math.Rounding.Floor);
}
```

---

### [LOW] AM-EL-05: `synchronizeNodesAndUpdateBalances` Is Permissionless and Can Trigger Costly State Updates

**Checklist:** audit-state-validation
**Checklist Item:** Access control modifiers on all administrative functions
**File:** `src/ynEIGEN/EigenStrategyManager.sol`, lines 207-218, 228-229
**Confidence:** Medium

**Description:**

Two functions in `EigenStrategyManager` that update critical accounting state are permissionless:

```solidity
// Line 207: No access control
function synchronizeNodesAndUpdateBalances(ITokenStakingNode[] calldata nodes) external {
    uint256 nodesLength = nodes.length;
    for(uint256 i = 0; i < nodesLength; i++) {
        nodes[i].synchronize();
    }
    // updates strategiesBalance for all assets
    IERC20[] memory assets = IynEigenVars(address(ynEigen)).assetRegistry().getAssets();
    uint256 assetsLength = assets.length;
    for (uint256 i = 0; i < assetsLength; i++) {
        _updateTokenStakingNodesBalances(assets[i], IStrategy(address(0)));
    }
}

// Line 228: No access control
function updateTokenStakingNodesBalances(IERC20 asset) public {
    _updateTokenStakingNodesBalances(asset, strategies[asset]);
}
```

The `synchronizeNodesAndUpdateBalances` function is particularly notable because it:
1. Accepts an arbitrary array of `ITokenStakingNode` addresses
2. Calls `synchronize()` on each, which resets and recalculates queued shares
3. Then iterates ALL assets and ALL nodes to recalculate `strategiesBalance`

This mirrors the known issue F-08 (permissionless `updateTotalETHStaked`) and F-09 (permissionless `synchronize`) from the ynETH side, but affects the ynEIGEN subsystem. The design comment in the code states this is intentional ("users will have an incentive to call this function, to decrease the exchange rate" during slashing events), but the function could be used for griefing by repeatedly calling it to waste gas or to strategically time balance updates around deposits.

**Impact:**

An attacker could call `synchronizeNodesAndUpdateBalances` immediately before a large deposit to ensure the exchange rate reflects the most current (possibly slashed) balances, or call `updateTokenStakingNodesBalances` to force a balance recalculation at an inopportune time. The gas cost to the caller is the primary deterrent, but on-chain MEV searchers could bundle these calls profitably.

**Recommendation:**

Consider adding a cooldown period between successive calls, or restrict to a keeper role while maintaining a public emergency override:

```solidity
uint256 public lastBalanceUpdate;
uint256 public constant MIN_UPDATE_INTERVAL = 1 hours;

function updateTokenStakingNodesBalances(IERC20 asset) public {
    require(block.timestamp >= lastBalanceUpdate + MIN_UPDATE_INTERVAL, "Too frequent");
    lastBalanceUpdate = block.timestamp;
    _updateTokenStakingNodesBalances(asset, strategies[asset]);
}
```

---

### [LOW] AM-EL-06: StakingNode Gwei Truncation Comparison Allows Up to 1 Gwei Discrepancy Per Withdrawal

**Checklist:** audit-math-precision
**Checklist Item:** Consistent precision scaling across all modules
**File:** `src/StakingNode.sol`, lines 465-472
**Confidence:** High

**Description:**

In `completeQueuedWithdrawals`, the validation of the actual ETH received against the expected amount uses gwei-level truncation:

```solidity
// Line 468-472
// comparing gwei values because eigenlayer truncates the precision to gwei
if (actualWithdrawalAmount / GWEI_TO_WEI != totalWithdrawableShares / GWEI_TO_WEI) {
    revert IncorrectWithdrawalAmount();
}
```

Where `GWEI_TO_WEI = 1e9`. This means the comparison allows a discrepancy of up to `1e9 - 1` wei (approximately 0.999999999 gwei) between the actual and expected amounts. While this is documented as necessary due to EigenLayer's gwei precision, it means each completed withdrawal could silently gain or lose up to ~1 gwei.

**Impact:**

The impact per withdrawal is negligible (~1 gwei = ~$0.000003 at current ETH prices). However, across thousands of withdrawals over the protocol's lifetime, this could accumulate to a small accounting discrepancy between the tracked `withdrawnETH` and the actual contract balance. The discrepancy is bounded and well-documented, making this informational.

**Recommendation:**

This is an accepted design trade-off due to EigenLayer's gwei precision. Document the maximum cumulative discrepancy in the contract's NatSpec and consider periodic reconciliation of `withdrawnETH` against actual balance.

---

### [INFORMATIONAL] AM-EL-07: Withdrawal Queue Pause Not Synchronized with Redemption Vault Pause

**Checklist:** audit-state-validation
**Checklist Item:** Pause mechanisms synchronized; Grace periods after unpause
**File:** `src/WithdrawalQueueManager.sol`, `src/ynETHRedemptionAssetsVault.sol`, `src/ynEIGEN/RedemptionAssetsVault.sol`
**Confidence:** Medium

**Description:**

The `WithdrawalQueueManager`, `ynETHRedemptionAssetsVault`, and `RedemptionAssetsVault` each have independent pause mechanisms controlled by separate roles. There is no synchronization between them:

- `ynETHRedemptionAssetsVault.pause()` is controlled by `PAUSER_ROLE`
- `WithdrawalQueueManager` has no pause on `claimWithdrawal` itself
- `RedemptionAssetsVault.pause()` is controlled by its own `PAUSER_ROLE`

If the redemption vault is paused while the withdrawal queue is not, users with finalized withdrawal requests will have their `claimWithdrawal` calls revert at the `transferRedemptionAssets` step (due to `whenNotPaused` modifier), even though their requests are legitimately finalized.

Additionally, no grace period exists after unpausing any contract. Users who were blocked during a pause have no additional time to claim before new finalizations can occur.

**Impact:**

Users with finalized withdrawals may be temporarily unable to claim during redemption vault pauses. Since pause is an emergency mechanism, this is expected behavior, but the lack of grace period could be frustrating for users. No funds are at risk since the withdrawal requests remain finalized and claimable once unpaused.

**Recommendation:**

Document the dependency between pause states. Consider adding a `claimsPaused` flag to `WithdrawalQueueManager` that is automatically set when the redemption vault is paused, providing clearer error messages to users. Optionally add a grace period after unpause events.

---

## Summary

| ID | Severity | Title | Checklist |
|----|----------|-------|-----------|
| AM-EL-01 | Medium | `secondsToFinalization` declared but never initialized or enforced | audit-state-validation |
| AM-EL-02 | Medium | LSDRateProvider has no staleness checks, revert handling, or bounds validation | audit-oracle |
| AM-EL-03 | Low | ynETH contract has no ReentrancyGuard protection | audit-reentrancy |
| AM-EL-04 | Low | AssetRegistry conversion functions use plain division, risking rounding loss | audit-math-precision |
| AM-EL-05 | Low | `synchronizeNodesAndUpdateBalances` is permissionless and can trigger costly state updates | audit-state-validation |
| AM-EL-06 | Low | StakingNode gwei truncation comparison allows up to 1 gwei discrepancy | audit-math-precision |
| AM-EL-07 | Informational | Withdrawal queue pause not synchronized with redemption vault pause | audit-state-validation |

**Total new findings: 7** (2 Medium, 4 Low, 1 Informational)

**Deduplicated against:** F-01 (permissionless processRewards donation), F-02 (trusted rewardsAmount), F-03 (pendingRequestedRedemptionAmount desync), F-04 (finalizeRequestsUpToIndex CEI). Also noted overlaps with existing report findings F-05 through F-14 where applicable.
