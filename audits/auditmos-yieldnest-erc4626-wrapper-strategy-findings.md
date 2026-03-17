# Auditmos DeFi Checklist-Based Audit: yieldnest-erc4626-wrapper-strategy

**Audit Date:** 2026-03-17
**Methodology:** Auditmos DeFi Checklists (Staking, Slippage, Math Precision, State Validation, Reentrancy)
**Target:** `yieldnest-erc4626-wrapper-strategy/src/` (~600 LOC)
**Auditor:** Claude Opus 4.6 (Auditmos Pipeline)

**Existing Findings (excluded):**
- M-01: Silent withdrawal amount capping in handleBeforeRedeem can cause user fund loss
- M-02: Hooks processor call uses memory arrays for calldata parameters

---

## New Findings

---

### [HIGH] AM-EW-01: Read-Only Reentrancy via ERC4626 targetVault Exposes Stale Share Price

**Checklist:** Reentrancy
**Checklist Item:** Read-only reentrancy risks evaluated
**File:** `yieldnest-erc4626-wrapper-strategy/src/hooks/ERC4626WrapperHooks.sol:73-113`
**Description:**
The `handleAfterDeposit` function calls `targetVault.deposit()` via the vault's `processor`, which transfers assets into the external `targetVault`. During this external call, the vault's internal accounting (`totalBaseAssets`) has already been updated (via `_addTotalAssets` in `BaseVault._deposit`), but the targetVault shares have not yet been credited to the vault. Between the `_deposit` call and the completion of `processor` (which calls `targetVault.deposit`), any external observer reading `totalAssets()` or `convertToAssets()` on the wrapper strategy sees an inflated total-assets figure (the deposited amount is double-counted: once via `totalBaseAssets` and once the asset sits in the vault's balance before being forwarded). If the `targetVault` has a callback mechanism (e.g., ERC777-compatible token, or the targetVault itself has hooks), an attacker could exploit this window to observe an inflated share price on the wrapper strategy via `convertToAssets` or `totalAssets`, and use this stale/manipulated value in an external protocol that depends on the wrapper strategy's share price (e.g., as collateral in a lending protocol).

Additionally, during `handleBeforeRedeem`, the `targetVault.withdraw()` call via `processor` occurs before the vault burns shares and transfers assets (those happen in `_withdrawAsset`). Between the processor call completing and the share burn, the vault holds both the withdrawn assets and still has the shares outstanding, creating another read-only reentrancy window.

**Impact:**
External protocols that use the wrapper strategy's `convertToAssets()`, `totalAssets()`, or `previewRedeem()` as a price oracle could be manipulated during the deposit/withdrawal hook execution window. This could enable inflated collateral valuations or unfair liquidations in integrated lending protocols.

**Recommendation:**
Apply `nonReentrant` guard awareness at the hooks level. Since `deposit`, `withdraw`, `redeem`, and `mint` on `BaseStrategy` already use `nonReentrant`, consider ensuring that external view functions used as price feeds are protected with a `nonReentrant` read-only check (e.g., OpenZeppelin's `ReentrancyGuardTransient` pattern or a `_reentrancyGuardEntered()` check in view functions). Document clearly that `convertToAssets` and `totalAssets` should not be used as price oracles during the same transaction as deposit/withdraw operations.

---

### [MEDIUM] AM-EW-02: availableAssets Uses Manipulable convertToAssets from External targetVault

**Checklist:** Math Precision / Staking
**Checklist Item:** No direct transfer dilution: totalSupply tracks staked amounts, not token balance / Token amounts scaled to common precision before calculations
**File:** `yieldnest-erc4626-wrapper-strategy/src/lib/ERC4626WrapperLib.sol:9-23`
**Description:**
The `availableAssets` function in `ERC4626WrapperLib` computes the total available assets by summing two values:
1. `IERC20(asset_).balanceOf(address(vault))` -- the raw token balance
2. `targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)))` -- the value of shares in the external targetVault

The second component relies on `targetERC4626Vault.convertToAssets()`, which reads from the external vault's state. This value is subject to manipulation if the external vault's `totalAssets()` can be influenced (e.g., via donation attacks or read-only reentrancy). Since `availableAssets` directly controls `maxWithdraw` and `maxRedeem` in `BaseStrategy`, a manipulated value could artificially inflate or deflate the maximum withdrawal/redemption amounts.

Furthermore, `computeTotalAssets` in `VaultLib` uses `IERC20(assetList[i]).balanceOf(address(this))` which for the targetVault share token reads the share balance, then converts it via `convertAssetToBase` using the Provider rate. If these two conversion paths (ERC4626WrapperLib's `convertToAssets` vs. VaultLib's Provider-based rate) diverge, the `availableAssets` will be inconsistent with the vault's own `totalAssets`, leading to incorrect `maxWithdraw`/`maxRedeem` calculations.

**Impact:**
An attacker who can manipulate the external targetVault's `convertToAssets` (e.g., through a donation/inflation attack on the targetVault) could cause `availableAssets` to return an inflated value, allowing larger-than-safe withdrawals. Alternatively, a deflated value would prevent legitimate withdrawals (denial of service). The dual conversion path inconsistency between `availableAssets` and `totalAssets` could also lead to scenarios where `maxWithdraw` exceeds actual redeemable value or vice versa.

**Recommendation:**
Consider using the Provider rate consistently for both `availableAssets` and `totalAssets` calculations rather than relying on the external vault's `convertToAssets`. If the external vault's conversion must be used, add a sanity check that the external vault's reported value does not deviate beyond an acceptable threshold from the Provider-based valuation.

---

### [MEDIUM] AM-EW-03: Withdrawal Fee Bypassed When assets Capped to maxWithdrawAmount in handleBeforeRedeem

**Checklist:** Math Precision
**Checklist Item:** Protocol fees round up, user amounts round down
**File:** `yieldnest-erc4626-wrapper-strategy/src/hooks/ERC4626WrapperHooks.sol:93-113`
**Description:**
In `handleBeforeRedeem`, when `assets > maxWithdrawAmount`, the hook silently caps `assets` to `maxWithdrawAmount` and only withdraws that capped amount from the targetVault. However, the caller (BaseStrategy's `_redeemAsset` or `_withdrawAsset`) has already computed `shares` based on the full `assets` amount (including the withdrawal fee calculation via `previewRedeemAsset` or `previewWithdrawAsset`). The fee was calculated on the original, uncapped amount.

When the withdrawal actually executes in `_withdrawAsset` of `BaseVault`, it transfers `assets` (the original amount, not the capped amount) from the vault to the receiver. If the vault had some balance of the base asset directly (not in the targetVault), the withdrawal would partially succeed using the vault's direct balance plus whatever was withdrawn from the targetVault. But the fee was computed on the full uncapped amount.

The issue is that the fee structure assumes the full amount is being withdrawn from the targetVault. When a portion of the withdrawal comes from the vault's direct balance (which was not subject to targetVault withdrawal limits), the fee calculation is based on the full withdrawal amount but the targetVault withdrawal is capped. While this specific scenario is related to existing M-01, the fee implication is a distinct issue: the fee is computed without awareness of the withdrawal source split, meaning users who withdraw a mix of direct-balance and targetVault assets pay the same fee as if all assets came from the targetVault.

**Impact:**
Users pay withdrawal fees calculated on the full amount even when a portion of their withdrawal comes from the vault's direct asset balance (which may not warrant a fee), or conversely, the fee calculation does not account for the fact that the targetVault withdrawal was silently reduced, potentially leading to an accounting mismatch where the vault collected fees on assets it did not fully withdraw from the yield-bearing targetVault.

**Recommendation:**
Consider splitting the fee calculation to account for the portion of assets withdrawn from the targetVault versus the portion from the vault's direct balance. Alternatively, if fees should apply uniformly, document this behavior explicitly and ensure the hook does not silently cap the withdrawal amount (revert instead, as noted in existing M-01).

---

### [MEDIUM] AM-EW-04: handleAfterDeposit Deposits Full Asset Amount Without Accounting for Fee-On-Transfer Tokens

**Checklist:** Always Checklist (Token Compatibility)
**Checklist Item:** Fee-on-transfer tokens handled correctly
**File:** `yieldnest-erc4626-wrapper-strategy/src/hooks/ERC4626WrapperHooks.sol:73-91`
**Description:**
The `handleAfterDeposit` function uses `params.assets` (the user-specified deposit amount) as the argument for the `targetVault.deposit()` call. However, if the underlying asset is a fee-on-transfer token, the actual amount received by the vault from `safeTransferFrom` in `BaseVault._deposit` is less than `params.assets`. The hook then attempts to approve and deposit the full `params.assets` amount into the targetVault, which will either:
1. Revert because the vault does not hold enough tokens (deposit fails), or
2. If there are residual tokens from prior operations, deposit more than the user actually contributed.

The same issue applies to `handleBeforeRedeem`: the `assets` parameter used for `targetVault.withdraw()` assumes no fee-on-transfer deduction.

**Impact:**
If the strategy is configured to accept a fee-on-transfer token as its base asset, deposits will fail (reverting the entire transaction) or, in edge cases where residual tokens exist, incorrect amounts will be deposited into the targetVault. This would break the vault's accounting, as `totalBaseAssets` would track the pre-fee amount while the actual deposited amount is less.

**Recommendation:**
If fee-on-transfer tokens are intended to be supported, measure the actual token balance change after the transfer (balance-after minus balance-before) and use that delta as the amount for the targetVault deposit. If fee-on-transfer tokens are explicitly not supported, add a check or document this restriction clearly. Consider adding a pre/post balance check in the hooks.

---

### [MEDIUM] AM-EW-05: No Slippage Protection on targetVault Deposit/Withdraw in Hooks

**Checklist:** Slippage
**Checklist Item:** User can specify minTokensOut for all swaps / Slippage checked on final output amount
**File:** `yieldnest-erc4626-wrapper-strategy/src/hooks/ERC4626WrapperHooks.sol:73-113`
**Description:**
The `handleAfterDeposit` function calls `targetVault.deposit(assets, address(vault))` which deposits assets into the external ERC4626 vault. The ERC4626 `deposit` function returns shares, but this return value is not checked against any minimum. Similarly, `handleBeforeRedeem` calls `targetVault.withdraw(assets, address(vault), address(vault))` without any slippage protection on the number of shares burned.

While the wrapper strategy's own `previewDeposit`/`previewRedeem` functions provide a conversion rate based on the Provider, the actual interaction with the targetVault uses the targetVault's own exchange rate, which could differ from what the Provider reports. If the targetVault's exchange rate changes between when the user's transaction is submitted and when it is executed (e.g., due to a large deposit/withdrawal by another user, or a processAccounting update), the user receives fewer shares than expected on deposit, or more shares are burned than expected on withdrawal.

Since these calls happen within the hooks (which are part of the deposit/withdraw flow), the user has no way to specify a minimum shares received or maximum shares burned for the targetVault interaction.

**Impact:**
Users depositing into or withdrawing from the wrapper strategy have no protection against unfavorable exchange rate changes in the targetVault. A sandwich attacker could manipulate the targetVault's exchange rate (e.g., via a large deposit that changes the rate, then backrunning after the victim's transaction) to extract value from wrapper strategy users. The maximum extractable value depends on the targetVault's liquidity depth and the user's transaction size.

**Recommendation:**
Consider adding a minimum shares received check for deposits to the targetVault, and a maximum shares burned check for withdrawals. This could be implemented by comparing the shares returned by `targetVault.deposit()` against the expected amount, or by adding a user-specified slippage parameter that flows through to the hooks. At minimum, verify that the shares received/burned are within an acceptable range of the Provider's reported rate.

---

### [MEDIUM] AM-EW-06: Provider.getRate Uses Spot convertToAssets Which Is Manipulable via Donation

**Checklist:** Staking / Math Precision
**Checklist Item:** No direct transfer dilution: totalSupply tracks staked amounts, not token balance / No assumptions about token transfer behavior
**File:** `yieldnest-erc4626-wrapper-strategy/src/module/Provider.sol:19-27`
**Description:**
The `Provider.getRate()` function returns `IERC4626(vault).convertToAssets(unitValue)` for the vault asset. This calls the external vault's `convertToAssets`, which typically computes `shares * totalAssets / totalSupply`. The `totalAssets` of the external vault can be manipulated via donation (sending tokens directly to the vault), which inflates the rate.

Since the Provider rate is used by `VaultLib.convertAssetToBase` and `VaultLib.convertBaseToAsset` for all share/asset conversions in the wrapper strategy, a manipulated rate directly affects:
- The number of shares minted for deposits (`convertToShares`)
- The number of assets received for redemptions (`convertToAssets`)
- The total assets reported (`totalAssets`)
- The maximum withdraw/redeem amounts

An attacker could donate tokens to the external vault (targetVault) to inflate its `convertToAssets` rate, then deposit into the wrapper strategy at the inflated rate to receive more shares than warranted. After the donation is absorbed (or the attacker withdraws from the targetVault), the rate normalizes and the attacker's shares are worth more than what they deposited.

**Impact:**
Direct manipulation of the wrapper strategy's share pricing. The magnitude depends on the external vault's susceptibility to donation attacks and the wrapper strategy's total assets. For vaults with low TVL, the impact could be significant. This effectively enables a first-depositor-style inflation attack channeled through the Provider rate.

**Recommendation:**
Consider using a time-weighted average rate (TWAP) or a rate from a separate oracle rather than a spot `convertToAssets` call. Alternatively, implement bounds checking on the rate to ensure it does not deviate beyond a configurable threshold from a stored reference rate. The `IProcessAccountingGuardHook` interface suggests such guards exist for processAccounting, but they do not protect individual deposit/withdrawal operations.

---

### [LOW] AM-EW-07: _feeOnRaw and _feeOnTotal Are Public Functions Exposing Internal Fee Logic

**Checklist:** State Validation
**Checklist Item:** Access control modifiers on all administrative functions
**File:** `yieldnest-erc4626-wrapper-strategy/src/ERC4626WrapperStrategy.sol:52-66` and `yieldnest-vault/src/BaseVault.sol:1021-1029`
**Description:**
The functions `_feeOnRaw` and `_feeOnTotal` are declared as `public view` in `BaseVault` (as interface-required virtuals from `IVault`) and overridden in `ERC4626WrapperStrategy`. The underscore-prefixed naming convention typically indicates internal functions, but these are exposed publicly. While the `IVault` interface mandates these as public, the naming is misleading and could lead to developer confusion about the intended visibility.

More importantly, these functions are defined as `public view override` rather than `external view override`, meaning they are callable both externally and internally. This is functionally correct but exposes internal fee calculation details to any external caller, which could assist an attacker in crafting optimal MEV strategies by precisely predicting the fee amount for any withdrawal.

**Impact:**
Low direct security impact. The fee information is publicly queryable, which is standard for transparent DeFi protocols. However, the misleading underscore naming convention could cause integration issues or auditor confusion.

**Recommendation:**
This is a design choice inherited from the BaseVault interface. Consider documenting that despite the underscore prefix, these functions are intentionally public per the IVault interface requirement.

---

### [LOW] AM-EW-08: ERC4626WrapperLib.availableAssets Assumes Second Asset Is Always the targetVault

**Checklist:** State Validation
**Checklist Item:** ID existence is verified before use
**File:** `yieldnest-erc4626-wrapper-strategy/src/lib/ERC4626WrapperLib.sol:13`
**Description:**
The `availableAssets` function hardcodes the assumption that `assets[1]` is the target ERC4626 vault:
```solidity
IERC4626 targetERC4626Vault = IERC4626(assets[1]);
```
There is no validation that `assets[1]` is actually an ERC4626-compliant contract or that it corresponds to the targetVault configured in the hooks. If the asset list is reordered (e.g., via `deleteAsset` which swaps the last element into the deleted position), or if more than 2 assets are added, `assets[1]` may not be the targetVault.

While `deleteAsset` prevents deleting index 0 (base asset) or the default asset index, other indices can be deleted and reordered. If a third asset were added at index 2 and then deleted, it would not affect index 1. However, if `assets[1]` is deleted (and it is not the default asset), the last asset would move to position 1, breaking the assumption.

**Impact:**
If the asset list is modified such that `assets[1]` is no longer the targetVault, `availableAssets` would call `convertToAssets` and `balanceOf` on the wrong contract. This could return incorrect values (if the contract at `assets[1]` happens to implement these functions) or revert (if it does not), breaking `maxWithdraw` and `maxRedeem`.

**Recommendation:**
Instead of hardcoding `assets[1]`, store the targetVault address explicitly in the library or pass it as a parameter. Alternatively, add a validation check that `assets[1]` matches the expected targetVault address before using it.

---

### [LOW] AM-EW-09: Approval to targetVault Not Reset After Deposit in handleAfterDeposit

**Checklist:** Always Checklist (Token Compatibility) / State Validation
**Checklist Item:** No assumptions about token transfer behavior / State transitions are atomic and cannot be partially completed
**File:** `yieldnest-erc4626-wrapper-strategy/src/hooks/ERC4626WrapperHooks.sol:80-82`
**Description:**
In `handleAfterDeposit`, the hook approves `assets` amount to the targetVault and then deposits. The approval is set exactly to the amount being deposited, so after a successful deposit the allowance is consumed. However, if the targetVault's `deposit` implementation does not consume the full approval (e.g., it deposits slightly less due to internal rounding), a residual approval remains. Over multiple deposits, these residual approvals could accumulate.

Furthermore, the approval pattern `approve(targetVault, assets)` does not first reset the approval to 0. Some tokens (notably USDT) require resetting to 0 before setting a new value. If the base asset is such a token and there is a residual approval, the `approve` call will revert, permanently bricking the deposit functionality.

**Impact:**
For USDT-like tokens that require approval reset, the deposit hook would fail after the first deposit if any residual approval exists. For other tokens, residual approvals represent a minor but unnecessary security surface.

**Recommendation:**
Add an approval reset to 0 before setting the new approval, or use `safeIncreaseAllowance`/`forceApprove` patterns. After the deposit, consider resetting the approval to 0 to minimize the approval surface. Example:
```solidity
data[0] = abi.encodeWithSignature("approve(address,uint256)", address(targetVault), 0);
// then a second approve with the actual amount, or use forceApprove
```

---

### [LOW] AM-EW-10: No Zero-Amount Validation in Hook Handlers

**Checklist:** State Validation
**Checklist Item:** All function inputs are validated for edge cases (matching inputs, zero values)
**File:** `yieldnest-erc4626-wrapper-strategy/src/hooks/ERC4626WrapperHooks.sol:73-113`
**Description:**
Neither `handleAfterDeposit` nor `handleBeforeRedeem` validate that `assets > 0` before executing the processor calls. If `assets` is 0 (which can happen if `previewDeposit` rounds down to 0 for very small deposit amounts, or if the fee calculation consumes the entire amount), the hooks will:
1. Approve 0 tokens to the targetVault (wasted gas)
2. Call `targetVault.deposit(0, vault)` or `targetVault.withdraw(0, vault, vault)` (which may revert depending on the targetVault's implementation, as many ERC4626 vaults revert on zero-amount operations)

This could cause the entire deposit/withdrawal to revert due to the hook failure, even though the zero amount might be a valid edge case that should be handled gracefully.

**Impact:**
Potential denial of service for edge-case transactions. If the targetVault reverts on zero-amount deposits/withdrawals, the wrapper strategy would also revert, preventing valid (though economically trivial) operations.

**Recommendation:**
Add a guard in both `handleAfterDeposit` and `handleBeforeRedeem`:
```solidity
if (assets == 0) return;
```

---

## Checklist Verification Summary

### Always Checklist
| Item | Status | Notes |
|------|--------|-------|
| State changes before external calls (CEI pattern) | PARTIAL | Deposit: state updated before hook calls processor; Redeem: hook calls processor before state update (by design for beforeRedeem) |
| NonReentrant modifiers on vulnerable functions | PASS | All external entry points (deposit, withdraw, redeem, mint) have nonReentrant |
| No assumptions about token transfer behavior | FAIL | AM-EW-04: Fee-on-transfer tokens not handled |
| Cross-function reentrancy considered | PASS | nonReentrant is global across all state-changing functions |
| Read-only reentrancy risks evaluated | FAIL | AM-EW-01: Stale price during hook execution |
| Fee-on-transfer tokens handled correctly | FAIL | AM-EW-04 |
| Rebasing tokens accounted for | N/A | Not applicable to this vault design |
| Tokens with callbacks (ERC777) considered | WARN | The vault uses SafeERC20 but hooks make external calls within the nonReentrant guard |
| Zero transfer reverting tokens handled | FAIL | AM-EW-10 |
| Pausable tokens won't brick protocol | PASS | Vault has its own pause mechanism |
| Token decimals properly scaled | PASS | VaultLib handles decimal scaling via Provider |
| Critical functions have appropriate modifiers | PASS | Role-based access control throughout |
| Two-step ownership transfer implemented | PASS | Uses AccessControl with role-based management |
| Emergency pause functionality included | PASS | PAUSER_ROLE and UNPAUSER_ROLE exist |

### Staking Checklist
| Item | Status | Notes |
|------|--------|-------|
| Separate tokens | N/A | Not a staking/reward protocol |
| No direct transfer dilution | WARN | AM-EW-06: Provider rate uses spot convertToAssets |
| Precision protection | PASS | FeeMath uses mulDiv with rounding |
| Flash protection | PASS | No time-lock but fees serve as anti-flash mechanism |
| Index updates | PASS | totalAssets updated atomically in deposit/withdraw |
| Balance integrity | PASS | Share balances managed by ERC20 standard |

### Slippage Checklist
| Item | Status | Notes |
|------|--------|-------|
| User can specify minTokensOut | FAIL | AM-EW-05: No slippage on targetVault operations |
| User can specify deadline | N/A | No time-sensitive swap operations |
| Hard-coded slippage can be overridden | FAIL | No slippage parameter exists for hooks |
| Slippage checked on final output | FAIL | AM-EW-05 |

### Math Precision Checklist
| Item | Status | Notes |
|------|--------|-------|
| Multiplication before division | PASS | Uses OpenZeppelin Math.mulDiv |
| Checks for rounding to zero | WARN | AM-EW-10: Zero amounts not validated in hooks |
| Token amounts scaled to common precision | PASS | VaultLib handles scaling |
| No double-scaling | PASS | |
| Consistent precision across modules | WARN | AM-EW-02: availableAssets vs totalAssets use different conversion paths |
| SafeCast for downcasting | PASS | Fee values use uint64 with bounds check |
| Protocol fees round up | PASS | FeeMath uses Rounding.Ceil for fees |

### State Validation Checklist
| Item | Status | Notes |
|------|--------|-------|
| Multi-step processes verify previous steps | WARN | Hooks assume asset list ordering (AM-EW-08) |
| Arrays validated length > 0 | WARN | AM-EW-10: Zero amount not validated |
| Function inputs validated for edge cases | FAIL | AM-EW-10 |
| Return values checked | WARN | Processor checks call success but not return values of ERC4626 operations |
| Access control on admin functions | PASS | All admin functions role-gated |
| State updated before external calls | PARTIAL | afterDeposit: yes; beforeRedeem: state updated after (by design) |

### Reentrancy Checklist
| Item | Status | Notes |
|------|--------|-------|
| CEI pattern | PARTIAL | beforeRedeem hook makes external call before state update |
| NonReentrant modifiers | PASS | Applied to all user-facing functions |
| Token assumptions | WARN | AM-EW-04: Fee-on-transfer not handled |
| Cross-function reentrancy | PASS | Global nonReentrant lock |
| Read-only safety | FAIL | AM-EW-01 |
