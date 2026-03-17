# Auditmos DeFi Checklist-Based Audit: YieldNest Vault

**Repository:** `yieldnest-vault/src/`
**Lines of Code:** ~4,348
**Date:** 2026-03-17
**Methodology:** Auditmos DeFi Checklists (staking, slippage, math-precision, reentrancy, state-validation)

---

## Existing Findings (Excluded from this Report)

- **YNV-01:** Deposit front-running via stale cached totalAssets
- **YNV-02:** Public `_feeOnRaw`/`_feeOnTotal` naming convention violation
- **YNV-03:** `processAccounting()` is permissionless and can be sandwiched
- **YNV-04:** Storage slot collision between MaxVaultViewer and VaultLib AssetStorage

---

## 1. Checklist Results

### 1.1 Always Checklist (Master)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | State changes before external calls (CEI pattern) | FAIL | See AM-YNV-01: `_deposit()` updates totalAssets before `safeTransferFrom` but mints shares before hook callbacks; `_withdraw()` follows CEI. However, `processAccounting()` makes external hook calls after state update -- potential read-only reentrancy. |
| 2 | NonReentrant modifiers on vulnerable functions | PASS | `deposit`, `mint`, `withdraw`, `redeem`, `processAccounting` all have `nonReentrant`. |
| 3 | No assumptions about token transfer behavior | FAIL | See AM-YNV-02: `_deposit()` does not verify actual tokens received via `safeTransferFrom` matches `assets` parameter. Fee-on-transfer tokens would break accounting. |
| 4 | Cross-function reentrancy considered | PASS | Global `nonReentrant` from `ReentrancyGuardUpgradeable` covers cross-function reentrancy within the vault. |
| 5 | Read-only reentrancy risks evaluated | FAIL | See AM-YNV-03: Hook callbacks via `HooksLib.callHook` use low-level `.call()` which could re-enter view functions during state transitions. |
| 6 | Fee-on-transfer tokens handled correctly | FAIL | See AM-YNV-02 |
| 7 | Rebasing tokens accounted for | INFO | OETH and stETH are rebasing; vault tracks balances via `processAccounting()` which recomputes. Acceptable design, but relies on timely calls. |
| 8 | Tokens with callbacks (ERC777) considered | PASS | `nonReentrant` on all entry points mitigates. |
| 9 | Zero transfer reverting tokens handled | INFO | No explicit zero-amount checks on deposit, but `_convertToShares` returning 0 shares would still proceed. Low practical risk. |
| 10 | Pausable tokens won't brick protocol | PASS | External token pausing would block deposits/withdrawals but not brick vault state. |
| 11 | Token decimals properly scaled | PASS | Multi-decimal support via `convertAssetToBase`/`convertBaseToAsset` with per-asset decimal tracking. |
| 12 | Critical functions have appropriate modifiers | PASS | Role-based access control via OpenZeppelin `AccessControlUpgradeable`. |
| 13 | Two-step ownership transfer | PASS | Uses role-based admin, not single-owner pattern. `DEFAULT_ADMIN_ROLE` can be managed with standard OZ patterns. |
| 14 | Role-based permissions properly segregated | PASS | Separate roles for PROCESSOR, PAUSER, UNPAUSER, ASSET_MANAGER, FEE_MANAGER, etc. |
| 15 | Emergency pause functionality included | PASS | `pause()`/`unpause()` with separate `PAUSER_ROLE`/`UNPAUSER_ROLE`. |
| 16 | Time delays for critical operations | INFO | No timelock on role-gated operations. Relies on external governance/timelock. |

### 1.2 Staking Checklist

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Separate tokens: Reward token cannot be same as staking token | N/A | Vault is ERC4626, not a staking reward distributor. Performance fees minted as shares via FeeHooks. No separate reward token. |
| 2 | No direct transfer dilution: totalSupply tracks staked amounts, not token balance | FAIL | See AM-YNV-04: When `alwaysComputeTotalAssets = false`, `totalAssets` is a cached value updated via `_addTotalAssets`/`_subTotalAssets` on deposit/withdraw. But `computeTotalAssets()` reads actual `balanceOf()` for all assets. Direct token transfers inflate `computeTotalAssets()` vs cached value. The `processAccounting()` syncs them, but between calls, discrepancies exist. |
| 3 | Precision protection: Minimum stake enforced | FAIL | See AM-YNV-05: No minimum deposit amount enforced. A deposit of 1 wei could yield 0 shares due to rounding (shares rounded Floor), yet still increment `totalAssets`. |
| 4 | Flash protection: Time locks or anti-sandwich | INFO | No time locks on deposit/withdraw. Withdrawal fee provides some friction but can be overridden to 0 for specific users. |
| 5 | Index updates: updateReward called before AND after distribution | N/A | Not a traditional staking contract. Performance fees calculated in `afterProcessAccounting` hook. |
| 6 | Balance integrity: Cached balances updated correctly during claims | PASS | Share burning happens before external calls in `_withdraw`. |

### 1.3 Slippage Checklist

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | User can specify minTokensOut for all swaps | FAIL | See AM-YNV-06: `deposit()`, `depositAsset()`, `mint()` have no minimum shares/assets output parameter. Users cannot specify slippage protection on deposits. |
| 2 | User can specify deadline for time-sensitive operations | FAIL | See AM-YNV-07: No deadline parameter on any deposit/withdraw/redeem/mint function. Transactions can be held by validators and executed at different share prices. |
| 3 | Slippage calculated correctly | N/A | No swap integrations in the vault itself. Provider rates are used for conversion. |
| 4 | Slippage precision matches output token | N/A | |
| 5 | Hard-coded slippage can be overridden | N/A | |
| 6 | Slippage checked on final output amount | N/A | |
| 7 | Slippage calculated off-chain, not on-chain | FAIL | See AM-YNV-08: `Provider.getRate()` calls external contracts (`convertToAssets(1e18)`, `getExchangeRate()`, etc.) on-chain. These rates can be manipulated in the same transaction. |
| 8 | Fee tiers not hardcoded | N/A | |
| 9 | Proper deadline validation | FAIL | See AM-YNV-07. |

### 1.4 Math Precision Checklist

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Multiplication always performed before division | PASS | Uses OpenZeppelin `Math.mulDiv` throughout. |
| 2 | Checks for rounding to zero with appropriate reverts | FAIL | See AM-YNV-05: No check that `shares > 0` after `_convertToShares` in `_depositAsset`. Zero-share deposits possible. |
| 3 | Token amounts scaled to common precision before calculations | PASS | `convertAssetToBase` handles decimal scaling via `mulDiv`. |
| 4 | No double-scaling of already scaled values | PASS | Clear separation between base and asset denominations. |
| 5 | Consistent precision scaling across all modules | PASS | All use `VaultLib` conversion functions. |
| 6 | SafeCast used for all downcasting operations | PASS | Limited downcasting in the codebase. Fee storage uses `uint64` but inputs are validated `<= BASIS_POINT_SCALE`. |
| 7 | Protocol fees round up, user amounts round down | PASS | `FeeMath.feeOnRaw` and `feeOnTotal` use `Math.Rounding.Ceil`. Deposit shares round down (Floor). Withdrawal shares round up (Ceil). Correct ERC4626 convention. |
| 8 | Decimal assumptions documented and validated | PASS | First asset must match vault decimals, subsequent assets must have `<= base` decimals. |
| 9 | Interest calculations use correct time units | N/A | No time-based interest calculations. |
| 10 | Token pair directions consistent | PASS | Rate direction consistent: `getRate(asset)` returns units of base per unit of asset. |

### 1.5 Reentrancy Checklist

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | CEI pattern: State changes before external calls | PARTIAL | `_deposit` updates `totalAssets` before `safeTransferFrom` (good), but the `afterDeposit` hook is called after minting. `_withdraw` burns shares before external call (good). |
| 2 | NonReentrant modifiers on all state-changing functions with external calls | PASS | All public entry points have `nonReentrant`. |
| 3 | Token assumptions: No assumptions about callback behavior | FAIL | See AM-YNV-02 on fee-on-transfer. |
| 4 | Cross-function analysis: Shared state protected | PASS | Global reentrancy guard. |
| 5 | Read-only safety: View functions return consistent values during reentrancy | FAIL | See AM-YNV-03: During hook callbacks in `processAccounting`, `totalAssets` has been updated but share supply may change (via `mintShares` in FeeHooks). External protocols reading `totalAssets()`/`totalSupply()` during this window see inconsistent state. |

### 1.6 State Validation Checklist

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Multi-step processes verify previous steps | PASS | `unpause` checks `provider != address(0)`. |
| 2 | Functions validate array lengths > 0 before processing | FAIL | See AM-YNV-09: `processor()` does not validate `targets.length > 0` or match `targets.length == data.length`. |
| 3 | All function inputs validated for edge cases | FAIL | See AM-YNV-10: `setBuffer(address(0))` is explicitly allowed, but `_withdraw` will revert with opaque error when trying to call `IStrategy(address(0)).withdraw()`. |
| 4 | Return values from all function calls checked | PARTIAL | `processor()` checks `success` from low-level calls. `SafeERC20` used for token transfers. `oeth.approve()` in `OriginWithdrawalLib` uses raw `approve` without SafeERC20. |
| 5 | State transitions are atomic | PASS | Deposit/withdraw are atomic within single transactions. |
| 6 | ID existence verified before use | PASS | Asset index bounds checked in `updateAsset`/`deleteAsset`. |
| 7 | Array parameters have matching length validation | FAIL | See AM-YNV-09. |
| 8 | Access control modifiers on all administrative functions | PASS | All admin functions have appropriate role checks. |
| 9 | State variables updated before external calls | PARTIAL | See reentrancy section. |
| 10 | Pause mechanisms synchronized | PASS | Single `paused` flag blocks all deposit/withdraw operations uniformly. |
| 11 | Grace periods after unpause | INFO | No grace period after unpause. Users could be disadvantaged if vault is unpaused during unfavorable market conditions. Low severity given role separation. |

---

## 2. New Findings

### [MEDIUM] AM-YNV-01: Hooks System Allows Arbitrary External Calls During State Transitions
**Checklist:** reentrancy
**Checklist Item:** CEI pattern / Read-only safety
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/library/HooksLib.sol:53-57`
**Description:**
The `HooksLib.callHook()` function executes a low-level `.call()` to the hooks contract during deposit, withdraw, redeem, mint, and processAccounting flows. The hooks contract is set by `HOOKS_MANAGER_ROLE` and could be any contract implementing the `IHooks` interface. During `processAccounting()`, `afterProcessAccounting` is called after `vaultStorage.totalAssets` has been updated (line VaultLib.sol:415), but before the function returns. The `FeeHooks.afterProcessAccounting()` calls `VAULT.mintShares()` which mints new shares, modifying `totalSupply` while `totalAssets` has already been set. Any external protocol reading the vault's `convertToAssets()` or `convertToShares()` during the `mintShares` callback will see the post-accounting `totalAssets` but the pre-mint `totalSupply`, resulting in an inflated share price.

While `nonReentrant` prevents re-entering the vault's own functions, the hooks contract can make arbitrary external calls that read stale view function values.

**Impact:**
External DeFi protocols that use the vault's share price (e.g., as collateral valuation) could be manipulated during `processAccounting()` if they are called within the hook execution window. This is a classic read-only reentrancy vector. The actual exploitability depends on which protocols integrate with the vault and whether they read the share price in a composable manner.

**Recommendation:**
Consider adding a reentrancy lock check to critical view functions like `totalBaseAssets()`, `convertToAssets()`, and `convertToShares()` that returns a cached or reverts when the lock is active. Alternatively, restructure `processAccounting` to complete all state changes (including fee share minting) before any external callbacks.

---

### [MEDIUM] AM-YNV-02: Fee-on-Transfer Tokens Break Vault Accounting
**Checklist:** staking / always-checklist
**Checklist Item:** No assumptions about token transfer behavior / No direct transfer dilution
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/BaseVault.sol:535-557`
**Description:**
The `_deposit()` function at line 547-550 calls `_addTotalAssets(baseAssets)` and then `SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets)`. The `baseAssets` value is computed from the nominal `assets` parameter, not from the actual amount received. If a fee-on-transfer token is added as a vault asset, the vault will credit `totalAssets` with more than what was actually received. Over time, this leads to `totalAssets` exceeding actual holdings, inflating the share price and creating a shortfall when users withdraw.

```solidity
function _deposit(...) internal virtual {
    if (!_getAssetStorage().assets[asset_].active) revert AssetNotActive();
    _addTotalAssets(baseAssets);  // Credits full amount
    SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);  // May receive less
    _mint(receiver, shares);
}
```

**Impact:**
If a fee-on-transfer token is ever added as a vault asset, the vault's accounting becomes permanently inflated. The last withdrawers would be unable to withdraw their full balance, effectively losing funds. This is a latent vulnerability that manifests upon asset configuration.

**Recommendation:**
Measure the actual balance change before and after the transfer:
```solidity
uint256 balanceBefore = IERC20(asset_).balanceOf(address(this));
SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
uint256 actualReceived = IERC20(asset_).balanceOf(address(this)) - balanceBefore;
```
Then use `actualReceived` for accounting. Alternatively, document that fee-on-transfer tokens are explicitly unsupported and add a validation check in `addAsset()`.

---

### [MEDIUM] AM-YNV-03: Zero-Share Deposits Inflate totalAssets Without Minting Shares
**Checklist:** math-precision / staking
**Checklist Item:** Checks for rounding to zero with appropriate reverts / Precision protection
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/BaseVault.sol:503-524`
**Description:**
The `_depositAsset()` function computes shares via `_convertToShares(asset_, assets, Math.Rounding.Floor)` which rounds down. For very small deposit amounts (especially with multi-asset decimal differences), the computed `shares` could round to 0 while `baseAssets` remains non-zero. The function proceeds to call `_deposit()` which adds `baseAssets` to `totalAssets` and mints 0 shares. This permanently increases the vault's `totalAssets` without issuing corresponding shares, causing all existing share holders' shares to be worth slightly more (value donated to the vault).

In `VaultLib.convertToShares()` (line 304-313):
```solidity
baseAssets = convertAssetToBase(asset_, assets, rounding);
shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
```
When `totalAssets` is very large relative to `baseAssets * (totalSupply + 1)`, `shares` rounds to 0.

There is no `require(shares > 0)` check anywhere in the deposit path.

**Impact:**
An attacker could repeatedly deposit dust amounts of a low-decimal asset to slowly inflate `totalAssets` without minting shares. While each individual deposit is negligible, automated griefing over many transactions would slowly donate value to existing holders and waste gas. More importantly, this violates the ERC4626 invariant that deposits should always mint shares > 0 (or revert).

**Recommendation:**
Add a check in `_depositAsset()` or `_deposit()`:
```solidity
if (shares == 0) revert ZeroAmount();
```

---

### [LOW] AM-YNV-04: No Deposit Deadline Parameter Allows Stale Transaction Execution
**Checklist:** slippage
**Checklist Item:** User can specify deadline for time-sensitive operations / Proper deadline validation
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/BaseVault.sol:280-286`
**Description:**
None of the deposit/mint/withdraw/redeem functions accept a `deadline` parameter. Pending transactions in the mempool can be executed at any future block when the share price may have changed significantly from what the user expected. Unlike DEX swaps where deadline protection is critical, vault deposits are somewhat less exposed since the vault uses a cached `totalAssets` (unless `alwaysComputeTotalAssets` is true). However, if `processAccounting()` is called between a user's transaction submission and execution, the share price can change materially.

**Impact:**
Users could receive significantly fewer shares than expected if their deposit transaction is delayed and `processAccounting()` runs in the interim. The cached `totalAssets` design mitigates immediate sandwich attacks, but delayed execution remains a concern.

**Recommendation:**
Add an optional `deadline` parameter or a minimum shares output parameter to deposit functions. Example:
```solidity
function deposit(uint256 assets, address receiver, uint256 minShares) public returns (uint256 shares) {
    shares = _depositAsset(asset(), assets, receiver);
    require(shares >= minShares, "Slippage");
}
```

---

### [LOW] AM-YNV-05: Provider getRate() Relies on Spot Values Susceptible to Manipulation
**Checklist:** slippage
**Checklist Item:** Slippage calculated off-chain, not on-chain
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/module/Provider.sol:45-127`
**Description:**
The `Provider.getRate()` function fetches exchange rates by calling external contracts directly (`IERC4626(asset).convertToAssets(1e18)`, `IStETH.getPooledEthByShares(1e18)`, etc.). These are spot rates that reflect current on-chain state. For assets where the rate comes from `IERC4626.convertToAssets()` (e.g., BUFFER, MORPHO_MEV_CAPITAL_WETH, YNETH, EULER_WETH_22_VAULT, etc.), a large deposit or withdrawal to that underlying vault in the same block could manipulate the reported rate.

This is partially mitigated by:
1. The cached `totalAssets` mechanism (deposits use stale rates when `alwaysComputeTotalAssets = false`)
2. The `processAccounting()` being a separate transaction
3. The `nonReentrant` guard

However, when `alwaysComputeTotalAssets = true`, every deposit/withdraw reads live rates, making manipulation within the same block more feasible.

**Impact:**
With `alwaysComputeTotalAssets = true`, an attacker could manipulate an underlying vault's rate (e.g., via large deposit to a Morpho vault) to inflate the rate seen by `Provider.getRate()`, then deposit into the YieldNest vault at an artificially favorable rate, then reverse the manipulation. The profitability depends on the specific external vault's liquidity and rate sensitivity.

**Recommendation:**
Consider using TWAP-based rates or adding rate deviation bounds in the Provider. At minimum, document that `alwaysComputeTotalAssets = true` increases manipulation risk and should only be used with trusted/manipulation-resistant rate sources.

---

### [LOW] AM-YNV-06: processor() Missing Array Length Validation
**Checklist:** state-validation
**Checklist Item:** Functions validate array lengths > 0 / Array parameters have matching length validation
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/library/VaultLib.sol:441-458`
**Description:**
The `processor()` function accepts three arrays (`targets`, `values`, `data`) but does not validate that all three arrays have matching lengths or that they are non-empty. While `setProcessorRules()` does validate matching lengths (line 338), `processor()` does not. If `targets.length != values.length` or `targets.length != data.length`, the function will revert with an out-of-bounds error rather than a descriptive error message.

```solidity
function processor(address[] calldata targets, uint256[] memory values, bytes[] calldata data)
    public returns (bytes[] memory returnData)
{
    uint256 targetsLength = targets.length;
    returnData = new bytes[](targetsLength);
    for (uint256 i = 0; i < targetsLength; i++) {
        // No check: values.length >= targetsLength, data.length >= targetsLength
        Guard.validateCall(targets[i], values[i], data[i]);
        ...
    }
}
```

**Impact:**
This is a usability issue affecting the `PROCESSOR_ROLE` holder. Mismatched array lengths cause opaque reverts. Since only a privileged role can call this function, exploitation risk is minimal.

**Recommendation:**
Add explicit length validation:
```solidity
if (targets.length != values.length || targets.length != data.length) revert IVault.InvalidArray();
if (targets.length == 0) revert IVault.InvalidArray();
```

---

### [LOW] AM-YNV-07: OriginWithdrawalLib Uses Raw approve() Instead of SafeERC20
**Checklist:** state-validation
**Checklist Item:** Return values from all function calls are checked
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/withdraws/library/OriginWithdrawalLib.sol:114`
**Description:**
In `_requestWithdrawalOETH()`, the OETH token approval is done via `oeth.approve(address(oethVault), amount)` using the raw `IERC20.approve()` call without using `SafeERC20.safeApprove()` or `SafeERC20.forceApprove()`. While OETH's `approve()` is known to return `true`, this is inconsistent with the rest of the codebase which uses `SafeERC20` patterns.

```solidity
oeth.approve(address(oethVault), amount);  // Raw approve, no return value check
```

**Impact:**
If the OETH token ever changes its `approve()` behavior (e.g., returning false on failure instead of reverting), the withdrawal request would proceed with an insufficient approval, causing the subsequent `requestWithdrawal` to fail. Minimal practical risk with current OETH implementation.

**Recommendation:**
Use `SafeERC20.forceApprove(IERC20(MC.OETH), address(oethVault), amount)` for consistency and safety.

---

### [LOW] AM-YNV-08: FeeHooks Performance Fee Calculation Uses totalSupplyBeforeAccounting But Shares Are Minted After
**Checklist:** math-precision
**Checklist Item:** Protocol fees round up, user amounts round down
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/hooks/FeeHooks.sol:109-113`
**Description:**
In `afterProcessAccounting()`, the performance fee shares are calculated using `totalSupplyBeforeAccounting` (the share supply before `processAccounting` was called). The formula is:

```solidity
sharesToMint = feesAccruedInBaseAsset.mulDiv(
    params.totalSupplyBeforeAccounting,
    params.totalBaseAssetsAfterAccounting - feesAccruedInBaseAsset,
    Math.Rounding.Floor
);
```

This correctly uses `Floor` rounding (favoring the vault over the fee recipient), and the formula itself is mathematically sound for computing shares that represent the fee portion of yield. However, if `processAccounting()` is called multiple times in rapid succession with small yield increments, the `Floor` rounding can cause `sharesToMint` to round to 0 on each call, effectively forfeiting small fee amounts. Over many small accounting updates, accumulated fees could be lost.

**Impact:**
Performance fee recipient may lose small fee increments when `processAccounting()` is called frequently with small yield changes. This benefits depositors at the expense of the fee recipient.

**Recommendation:**
Consider accumulating fee amounts across accounting periods and minting shares only when the accumulated fee exceeds a minimum threshold, or using `Ceil` rounding for fee share minting to favor the protocol.

---

### [INFORMATIONAL] AM-YNV-09: Guard.validateCall Only Validates ADDRESS ParamType, Skips UINT256
**Checklist:** state-validation
**Checklist Item:** All function inputs are validated for edge cases
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/module/Guard.sol:22-28`
**Description:**
The `Guard.validateCall()` function iterates through parameter rules but only validates parameters of type `ADDRESS`. Parameters of type `UINT256` are silently skipped (the loop `continue`s for ADDRESS and has no handling for UINT256):

```solidity
for (uint256 i = 0; i < rule.paramRules.length; i++) {
    if (rule.paramRules[i].paramType == IVault.ParamType.ADDRESS) {
        address addressValue = abi.decode(data[4 + i * 32:], (address));
        _validateAddress(addressValue, rule.paramRules[i]);
        continue;
    }
    // UINT256 type falls through with no validation
}
```

**Impact:**
The `processor()` function's Guard module cannot enforce bounds on uint256 parameters. Only address allowlisting is functional. If a protocol admin expects uint256 parameter validation to be enforced by the Guard, those rules would be silently ignored. However, custom `IValidator` implementations can still validate any parameter type when set on a rule.

**Recommendation:**
Either implement uint256 parameter validation (e.g., min/max bounds) or remove `UINT256` from the `ParamType` enum to avoid false expectations. Document that custom `IValidator` contracts should be used for non-address parameter validation.

---

### [INFORMATIONAL] AM-YNV-10: Withdrawal Fee Can Be Set to 100% Via overrideBaseWithdrawalFee
**Checklist:** state-validation
**Checklist Item:** All function inputs validated for edge cases
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/library/LinearWithdrawalFeeLib.sol:56-62`
**Description:**
The `overrideBaseWithdrawalFee()` function validates that `baseWithdrawalFee_ <= FeeMath.BASIS_POINT_SCALE` (i.e., `<= 1e8`). Since `BASIS_POINT_SCALE = 1e8` represents 100%, this allows setting a 100% withdrawal fee for a specific user via the `FEE_MANAGER_ROLE`. With a 100% fee, the user's `previewRedeem` would return 0 assets for any amount of shares, effectively bricking their withdrawal.

The same validation exists in `setBaseWithdrawalFee()` which could set the global fee to 100%.

**Impact:**
A malicious or compromised `FEE_MANAGER_ROLE` holder could brick withdrawals for specific users or all users by setting the fee to 100%. This is a privileged operation and severity is informational given the trust assumption in role holders.

**Recommendation:**
Consider adding a maximum fee cap well below 100% (e.g., 10% or 20%) to limit potential governance attacks:
```solidity
uint64 public constant MAX_WITHDRAWAL_FEE = 0.2e8; // 20%
if (baseWithdrawalFee_ > MAX_WITHDRAWAL_FEE) revert ExceedsMaxBasisPoints(baseWithdrawalFee_);
```

---

## 3. Summary

| Severity | Count | Finding IDs |
|----------|-------|-------------|
| Medium | 3 | AM-YNV-01, AM-YNV-02, AM-YNV-03 |
| Low | 5 | AM-YNV-04, AM-YNV-05, AM-YNV-06, AM-YNV-07, AM-YNV-08 |
| Informational | 2 | AM-YNV-09, AM-YNV-10 |

### Key Observations

1. **Reentrancy Protection:** The vault properly uses `ReentrancyGuardUpgradeable` on all state-changing entry points. However, the hooks system introduces a read-only reentrancy vector during `processAccounting()` that could affect external integrators (AM-YNV-01).

2. **Fee-on-Transfer Token Risk:** The vault does not account for fee-on-transfer tokens in its deposit logic (AM-YNV-02). While these tokens are uncommon among major LSTs, adding such a token as a vault asset would silently corrupt accounting.

3. **ERC4626 Compliance:** Zero-share deposits are possible due to missing minimum output validation (AM-YNV-03), which is a deviation from the ERC4626 spirit where deposits should always be meaningful.

4. **Slippage Protection Gap:** The vault provides no user-facing slippage or deadline parameters on deposit/withdraw operations (AM-YNV-04, AM-YNV-07). The cached `totalAssets` design mitigates some sandwich risks but does not fully protect users.

5. **Rate Oracle Risk:** The Provider contract uses spot rates from external protocols (AM-YNV-05), which could be manipulated when `alwaysComputeTotalAssets = true`.

6. **Access Control:** The vault demonstrates strong role separation with dedicated roles for each administrative function. The trust assumptions in privileged roles are reasonable for a governed protocol.
