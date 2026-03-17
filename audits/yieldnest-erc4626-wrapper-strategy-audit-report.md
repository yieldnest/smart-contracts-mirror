# Security Audit Report: yieldnest-erc4626-wrapper-strategy

## Metadata
- **Repository:** yieldnest-erc4626-wrapper-strategy
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6 (monorepo mirror)
- **Branch:** release-candidate (mirrored into main)
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24
- **EVM Target:** Cancun
- **Additional Pipelines Merged:** Forefy + Archethect (OpenAudit), Auditmos DeFi Checklists

## Audit Scope

| File | Path | LOC |
|------|------|-----|
| ERC4626WrapperStrategy.sol | src/ERC4626WrapperStrategy.sol | 109 |
| ERC4626WrapperHooks.sol | src/hooks/ERC4626WrapperHooks.sol | 193 |
| ERC4626WrapperLib.sol | src/lib/ERC4626WrapperLib.sol | 23 |
| Provider.sol | src/module/Provider.sol | 28 |
| SingleAssetProvider.sol | src/module/SingleAssetProvider.sol | 24 |
| ICurvePool.sol | src/interfaces/ICurvePool.sol | 28 |
| ICurveStableSwapFactoryNG.sol | src/interfaces/ICurveStableSwapFactoryNG.sol | 114 |
| IHooksFactory.sol | src/interfaces/IHooksFactory.sol | 27 |
| IMetaHooks.sol | src/interfaces/IMetaHooks.sol | 16 |
| IProcessAccountingGuardHook.sol | src/interfaces/IProcessAccountingGuardHook.sol | 22 |
| **Total** | | **584** |

Supporting inherited contracts reviewed for context:
- `BaseStrategy.sol` (yieldnest-vault)
- `BaseVault.sol` (yieldnest-vault)
- `VaultLib.sol` (yieldnest-vault)
- `LinearWithdrawalFee.sol` / `LinearWithdrawalFeeLib.sol` (yieldnest-vault)
- `FeeMath.sol` (yieldnest-vault)
- `HooksLib.sol` (yieldnest-vault)
- `Guard.sol` (yieldnest-vault)

## Methodologies Applied

| Pipeline | Methodology | Findings Identified |
|----------|------------|-------------------|
| A | SCV Scan (Vulnerability Pattern Matching) | 3 |
| B | Feynman Business Logic Audit | 4 |
| C | State Inconsistency Analysis | 2 |
| D | Pashov Multi-Vector Scan | 3 |
| E | QuillAI Module Analysis | 2 |
| F | Token Integration Analysis | 2 |
| G | Forefy + Archethect | 7 |
| H | Auditmos DeFi Checklists | 6 |
| **Total unique findings (deduplicated)** | | **16** |

## Executive Summary

The yieldnest-erc4626-wrapper-strategy is a relatively thin wrapper that extends the Yieldnest vault framework to automatically deposit incoming assets into an underlying ERC4626 vault (the "targetVault") via hooks, and withdraw from it before redemptions. The core logic is straightforward and the attack surface is limited by the framework's access control (role-based via OpenZeppelin AccessControl) and reentrancy guards.

**Overall Risk Posture: LOW-MEDIUM**

The primary concerns identified are:

1. **A high-severity issue** where the `handleAfterDeposit` hook approves the `targetVault` without first resetting the allowance to zero, which is incompatible with non-standard tokens like USDT that revert on non-zero-to-non-zero approve calls, potentially bricking the deposit path permanently after the first deposit.

2. **A high-severity issue** involving read-only reentrancy: during hook execution in `handleAfterDeposit` and `handleBeforeRedeem`, transient accounting states expose stale or inflated share prices through view functions like `convertToAssets` and `totalAssets`, which external protocols using the wrapper as a price oracle could be manipulated by.

3. **A medium-severity issue** where the `ERC4626WrapperHooks` contract uses `abi.encodeWithSignature` to make calls through the vault's `processor`, passing memory arrays that do not match the `processor` function's `calldata` parameter types. This works due to Solidity's ABI encoding equivalence but introduces fragility.

4. **A medium-severity issue** where the `handleBeforeRedeem` hook silently caps withdrawal amounts at `maxWithdraw` from the target vault without reverting or notifying the caller, potentially causing users to receive fewer assets than expected while burning the full share amount calculated on the original (uncapped) value.

5. **Several medium-severity issues** including `availableAssets` using `convertToAssets` instead of `maxWithdraw` (creating inconsistent maxWithdraw reporting), withdrawal fees being computed without awareness of the withdrawal source split when amounts are capped, and fee-on-transfer tokens not being accounted for in hook deposit/withdraw flows.

6. **Several low-severity and informational issues** including reliance on the target ERC4626 vault's correctness, absence of slippage protection in hook operations, the `_feeOnRaw`/`_feeOnTotal` functions being marked `public` instead of `internal`, stale pricing in `SingleAssetProvider`, lack of emergency withdrawal paths when the targetVault is unavailable, and missing zero-amount validation in hooks.

No critical vulnerabilities were found. The access control model is properly implemented, reentrancy guards are in place, and the fee math uses OpenZeppelin's `mulDiv` for safe precision handling.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| H-01 | High | Approval to targetVault not reset before setting new allowance, incompatible with USDT-like tokens | G, H | High |
| H-02 | High | Read-only reentrancy via ERC4626 targetVault exposes stale share price during hook execution | H | Medium |
| M-01 | Medium | Silent withdrawal amount capping in `handleBeforeRedeem` can cause user fund loss | B, C, D | High |
| M-02 | Medium | Hooks `processor` call uses memory arrays for calldata parameters -- fragile ABI encoding | A, B, E, G | Medium |
| M-03 | Medium | `availableAssets` uses `convertToAssets` instead of `maxWithdraw`, causing incorrect maxWithdraw/maxRedeem reporting | G, H | High |
| M-04 | Medium | Withdrawal fee bypassed when assets capped to maxWithdrawAmount in `handleBeforeRedeem` | H | Medium |
| M-05 | Medium | `handleAfterDeposit` deposits full asset amount without accounting for fee-on-transfer tokens | H | Medium |
| L-01 | Low | `_feeOnRaw` and `_feeOnTotal` have `public` visibility exposing internal implementation | A, D, G, H | High |
| L-02 | Low | `ERC4626WrapperLib.availableAssets` assumes second asset in list is the targetVault | B, C, G, H | High |
| L-03 | Low | No slippage protection on hook deposit/withdraw to targetVault | B, D, F, G, H | Medium |
| L-04 | Low | Provider `getRate` for vault token relies on target vault's `convertToAssets` which may be manipulable | D, E, F, G, H | Medium |
| L-05 | Low | `SingleAssetProvider` returns a fixed immutable rate, causing stale pricing if the underlying asset value changes | G | Medium |
| L-06 | Low | `handleBeforeRedeem` and `handleAfterDeposit` do not handle targetVault reverts, potentially locking user funds | G | Low |
| L-07 | Low | No zero-amount validation in hook handlers | H | Medium |
| I-01 | Informational | `ERC4626WrapperHooks.onlyVault` modifier error message is misleading | A | High |
| I-02 | Informational | Unused Curve pool interfaces in source tree | A | High |

## Detailed Findings

---

### H-01: Approval to targetVault not reset before setting new allowance, incompatible with USDT-like tokens

**Severity:** High
**Confidence:** High
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleAfterDeposit()` (lines 73-91)

#### Description

In `handleAfterDeposit`, the hook approves the `targetVault` to spend `assets` amount of the underlying token using `abi.encodeWithSignature("approve(address,uint256)", address(targetVault), assets)`. This approval is executed via the vault's `processor` call. The approval is set to the exact deposit amount each time, but it never resets the allowance to zero first.

If the underlying asset is a token like USDT that requires the allowance to be zero before setting a new non-zero value (the well-known USDT approval pattern), subsequent deposits will revert. This is because after the first deposit, if the targetVault's `deposit` call does not consume the entire allowance (which can happen due to rounding in the targetVault's share calculation), a residual non-zero allowance remains. The next approval call with a non-zero amount on a USDT-like token will revert, permanently bricking the deposit path.

Even for standard ERC20 tokens, any residual allowance from a previous operation that was not fully consumed (e.g., targetVault rounding down shares received) means the allowance accumulates rather than being set precisely. While this is not exploitable for standard tokens, it represents a correctness issue.

#### Impact

If the underlying asset is USDT or any token that reverts on non-zero-to-non-zero approve, all deposits after the first successful one will permanently revert. Users cannot deposit into the strategy, effectively bricking the vault's core functionality. Given that the protocol aims to support multiple assets and wrapping strategies, encountering a USDT-like token is a realistic scenario.

#### Recommendation

Before setting the approval, first reset it to zero. Modify `handleAfterDeposit` to include an `approve(address,uint256)` call with amount 0 before the actual approval:

```solidity
address[] memory targets = new address[](3);
uint256[] memory values = new uint256[](3);
bytes[] memory data = new bytes[](3);

// 1. Reset approval to zero
targets[0] = asset;
values[0] = 0;
data[0] = abi.encodeWithSignature("approve(address,uint256)", address(targetVault), 0);

// 2. Approve exact amount
targets[1] = asset;
values[1] = 0;
data[1] = abi.encodeWithSignature("approve(address,uint256)", address(targetVault), assets);

// 3. Deposit into target vault
targets[2] = address(targetVault);
values[2] = 0;
data[2] = abi.encodeWithSignature("deposit(uint256,address)", assets, address(vault));
```

Alternatively, use `forceApprove` from SafeERC20 or set `type(uint256).max` approval once during initialization.

**Sources:** Pipeline G (Forefy), Pipeline H (Auditmos DeFi Checklists - Token Compatibility / State Validation)

---

### H-02: Read-only reentrancy via ERC4626 targetVault exposes stale share price during hook execution

**Severity:** High
**Confidence:** Medium
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleAfterDeposit()` (lines 73-91), `handleBeforeRedeem()` (lines 93-113)

#### Description

The `handleAfterDeposit` function calls `targetVault.deposit()` via the vault's `processor`, which transfers assets into the external `targetVault`. During this external call, the vault's internal accounting (`totalBaseAssets`) has already been updated (via `_addTotalAssets` in `BaseVault._deposit`), but the targetVault shares have not yet been credited to the vault. Between the `_deposit` call and the completion of `processor` (which calls `targetVault.deposit`), any external observer reading `totalAssets()` or `convertToAssets()` on the wrapper strategy sees an inflated total-assets figure (the deposited amount is double-counted: once via `totalBaseAssets` and once the asset sits in the vault's balance before being forwarded). If the `targetVault` has a callback mechanism (e.g., ERC777-compatible token, or the targetVault itself has hooks), an attacker could exploit this window to observe an inflated share price on the wrapper strategy via `convertToAssets` or `totalAssets`, and use this stale/manipulated value in an external protocol that depends on the wrapper strategy's share price (e.g., as collateral in a lending protocol).

Additionally, during `handleBeforeRedeem`, the `targetVault.withdraw()` call via `processor` occurs before the vault burns shares and transfers assets (those happen in `_withdrawAsset`). Between the processor call completing and the share burn, the vault holds both the withdrawn assets and still has the shares outstanding, creating another read-only reentrancy window.

#### Impact

External protocols that use the wrapper strategy's `convertToAssets()`, `totalAssets()`, or `previewRedeem()` as a price oracle could be manipulated during the deposit/withdrawal hook execution window. This could enable inflated collateral valuations or unfair liquidations in integrated lending protocols.

#### Recommendation

Apply `nonReentrant` guard awareness at the hooks level. Since `deposit`, `withdraw`, `redeem`, and `mint` on `BaseStrategy` already use `nonReentrant`, consider ensuring that external view functions used as price feeds are protected with a `nonReentrant` read-only check (e.g., OpenZeppelin's `ReentrancyGuardTransient` pattern or a `_reentrancyGuardEntered()` check in view functions). Document clearly that `convertToAssets` and `totalAssets` should not be used as price oracles during the same transaction as deposit/withdraw operations.

**Sources:** Pipeline H (Auditmos DeFi Checklists - Reentrancy)

---

### M-01: Silent withdrawal amount capping in `handleBeforeRedeem` can cause user fund loss

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleBeforeRedeem()` (lines 93-113)

#### Description

When a user redeems or withdraws, the `handleBeforeRedeem` hook is called to withdraw assets from the underlying `targetVault`. The function checks if the requested `assets` exceeds `targetVault.maxWithdraw(address(vault))` and silently caps the amount:

```solidity
// File: src/hooks/ERC4626WrapperHooks.sol, lines 99-104
uint256 maxWithdrawAmount = targetVault.maxWithdraw(address(vault));
if (assets > maxWithdrawAmount) {
    assets = maxWithdrawAmount;
}
```

This is intended to handle the case where some base asset already exists in the vault outside the targetVault. However, this creates a dangerous scenario: the parent `_redeemAsset` / `_withdrawAsset` function in `BaseStrategy` has already computed `shares` based on the full `assets` amount. The hook withdraws only `maxWithdrawAmount` from the target vault, but the vault then attempts to transfer the full original `assets` amount to the receiver.

If the vault has insufficient loose base asset balance to cover the difference (`assets - maxWithdrawAmount`), the `safeTransfer` in `BaseVault._withdrawAsset` will revert, which is the safe outcome. However, if the vault does have exactly enough loose balance to cover the gap, the user successfully withdraws but the accounting may diverge because `_subTotalAssets` was called with the full amount while the actual vault balance decrease was partially from loose assets and partially from the targetVault.

The core issue is that the hook modifies the effective withdrawal amount without the vault's core accounting logic being aware of the modification.

#### Impact

In the normal case where all assets are in the targetVault and there are no loose assets, this caps correctly and the transfer will succeed because the withdraw populates the balance. However, in edge cases with partial loose balances, the silent capping could lead to accounting inconsistency if `alwaysComputeTotalAssets` is false (cached mode), because `_subTotalAssets` subtracts the full amount while the targetVault only had a partial withdrawal.

In the `alwaysComputeTotalAssets = true` mode (which the test setup uses), this is mitigated since totalAssets is recomputed each time.

#### Recommendation

Instead of silently capping, either:
1. Revert if `assets > maxWithdrawAmount + IERC20(asset).balanceOf(address(vault))` to guarantee the vault can fulfill the request.
2. Or document explicitly that this strategy MUST use `alwaysComputeTotalAssets = true` to avoid accounting drift.

**Sources:** Pipeline B (Feynman Business Logic), Pipeline C (State Inconsistency), Pipeline D (Pashov Logic Flow)

---

### M-02: Hooks `processor` call uses memory arrays for calldata parameters -- fragile ABI encoding

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleAfterDeposit()` (lines 73-91), `handleBeforeRedeem()` (lines 93-113)

#### Description

The `ERC4626WrapperHooks` contract calls `BaseVault(payable(address(vault))).processor(targets, values, data)` where:
- `targets` is declared as `address[] memory`
- `values` is declared as `uint256[] memory`
- `data` is declared as `bytes[] memory`

However, the `processor` function on `BaseVault` is declared as:
```solidity
function processor(address[] calldata targets, uint256[] memory values, bytes[] calldata data)
    external
    virtual
    onlyRole(PROCESSOR_ROLE)
    returns (bytes[] memory returnData)
```

Note that `targets` and `data` are `calldata`, while `values` is `memory`. When calling from Solidity, passing `memory` arrays to `calldata` parameters works because the ABI encoding is identical at the call boundary. This is functionally correct but represents a code quality concern: the mismatch signals the developer may not have been fully aware of the parameter types.

Additionally, the `data` arrays use `abi.encodeWithSignature` rather than `abi.encodeCall`. The `abi.encodeWithSignature` approach does not provide compile-time type checking, meaning signature typos or parameter type mismatches would only be caught at runtime.

```solidity
// File: src/hooks/ERC4626WrapperHooks.sol, lines 82-87
data[0] = abi.encodeWithSignature("approve(address,uint256)", address(targetVault), assets);
data[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, address(vault));
```

The deeper concern is that the `processor` call returns `bytes[] memory returnData`, but this return data is not checked by `handleAfterDeposit` or `handleBeforeRedeem`. If the `approve` call returns `false` (as some ERC20 tokens do on failure instead of reverting), or if the `deposit` call partially fails, the hooks have no way of knowing.

#### Impact

No immediate exploit, but this is a maintenance and correctness risk. If the target vault's function signatures change or if a non-standard ERC4626 vault is used, these calls would silently fail at runtime with cryptic revert messages. If the approval silently fails (returns false without reverting), the subsequent deposit into the targetVault will also fail or deposit 0 assets, creating an accounting inconsistency where the wrapper vault holds idle assets not earning yield.

#### Recommendation

1. Use `abi.encodeCall` for type-safe encoding:
   ```solidity
   data[0] = abi.encodeCall(IERC20.approve, (address(targetVault), assets));
   data[1] = abi.encodeCall(IERC4626.deposit, (assets, address(vault)));
   ```
2. Consider using `abi.encodeCall(IERC4626.withdraw, (...))` in `handleBeforeRedeem` as well.
3. Validate return data from the processor call, or verify after the processor batch that the targetVault balance increased by the expected amount.

**Sources:** Pipeline A (SCV Scan - unchecked return values pattern), Pipeline B (Feynman), Pipeline E (QuillAI external-call-safety), Pipeline G (Archethect semantic_consistency + callback_liveness)

---

### M-03: `availableAssets` uses `convertToAssets` instead of `maxWithdraw`, causing incorrect maxWithdraw/maxRedeem reporting

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `ERC4626WrapperLib.sol`
**Function(s):** `availableAssets()` (lines 9-22)

#### Description

The `ERC4626WrapperLib.availableAssets` function computes the total available assets by summing the direct balance of the underlying asset in the vault PLUS the value of the target vault shares held by the wrapper (via `targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)))`).

This value is used in `_maxWithdrawAsset` and `_maxRedeemAsset` in `BaseStrategy` to cap the maximum withdrawable/redeemable amount. The issue is that `convertToAssets` returns the theoretical value of the shares based on the target vault's current state, but the actual amount receivable via `targetVault.withdraw` may differ due to:

1. **Target vault withdrawal fees**: If the target vault charges a withdrawal fee, `convertToAssets` returns the gross amount but the net amount after fees would be less. The wrapper's `maxWithdraw` would report more assets available than can actually be retrieved.

2. **Target vault liquidity constraints**: The target vault may have its own liquidity limitations (locked in strategies, paused, etc.) that are not reflected in `convertToAssets`. The `handleBeforeRedeem` hook does correctly cap to `targetVault.maxWithdraw(address(vault))`, but `_availableAssets` does NOT use `maxWithdraw` -- it uses `convertToAssets` of the balance. This means `maxWithdraw` on the wrapper can report a higher value than what the hooks will actually be able to withdraw from the target vault.

Furthermore, `computeTotalAssets` in `VaultLib` uses `IERC20(assetList[i]).balanceOf(address(this))` which for the targetVault share token reads the share balance, then converts it via `convertAssetToBase` using the Provider rate. If these two conversion paths (ERC4626WrapperLib's `convertToAssets` vs. VaultLib's Provider-based rate) diverge, the `availableAssets` will be inconsistent with the vault's own `totalAssets`, leading to incorrect `maxWithdraw`/`maxRedeem` calculations.

This creates a scenario where the wrapper's `maxWithdraw` says X assets are available, but when the user actually calls `withdraw(X)`, the `beforeWithdraw` hook can only retrieve `targetVault.maxWithdraw(address(vault))` which may be less than X. The hook silently caps the withdrawal amount (the already-reported M-01 issue), but the root cause is the inconsistency between `_availableAssets` and what the hooks can actually retrieve.

#### Impact

Users relying on `maxWithdraw` or `maxRedeem` view functions to determine safe withdrawal amounts may call `withdraw` or `redeem` with amounts that appear valid but result in receiving fewer assets than expected due to the silent capping in the hooks. Integrating protocols that respect ERC4626's `maxWithdraw` invariant (i.e., "withdraw must succeed for amounts <= maxWithdraw") may experience unexpected behavior. An attacker who can manipulate the external targetVault's `convertToAssets` (e.g., through a donation/inflation attack) could further exacerbate this inconsistency.

#### Recommendation

Modify `ERC4626WrapperLib.availableAssets` to use `targetERC4626Vault.maxWithdraw(address(vault))` instead of `targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)))` when computing available assets. This aligns the reported availability with what the hooks can actually retrieve:

```solidity
if (vault.asset() == asset_) {
    IERC4626 targetERC4626Vault = IERC4626(assets[1]);
    availableAssetsAmount += targetERC4626Vault.maxWithdraw(address(vault));
}
```

Additionally, consider using the Provider rate consistently for both `availableAssets` and `totalAssets` calculations to prevent divergence between the two conversion paths.

**Sources:** Pipeline G (Forefy Economic layer + Integration layer), Pipeline H (Auditmos DeFi Checklists - Math Precision / Staking)

---

### M-04: Withdrawal fee bypassed when assets capped to maxWithdrawAmount in `handleBeforeRedeem`

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleBeforeRedeem()` (lines 93-113)

#### Description

In `handleBeforeRedeem`, when `assets > maxWithdrawAmount`, the hook silently caps `assets` to `maxWithdrawAmount` and only withdraws that capped amount from the targetVault. However, the caller (BaseStrategy's `_redeemAsset` or `_withdrawAsset`) has already computed `shares` based on the full `assets` amount (including the withdrawal fee calculation via `previewRedeemAsset` or `previewWithdrawAsset`). The fee was calculated on the original, uncapped amount.

When the withdrawal actually executes in `_withdrawAsset` of `BaseVault`, it transfers `assets` (the original amount, not the capped amount) from the vault to the receiver. If the vault had some balance of the base asset directly (not in the targetVault), the withdrawal would partially succeed using the vault's direct balance plus whatever was withdrawn from the targetVault. But the fee was computed on the full uncapped amount.

The issue is that the fee structure assumes the full amount is being withdrawn from the targetVault. When a portion of the withdrawal comes from the vault's direct balance (which was not subject to targetVault withdrawal limits), the fee calculation is based on the full withdrawal amount but the targetVault withdrawal is capped. While this specific scenario is related to existing M-01, the fee implication is a distinct issue: the fee is computed without awareness of the withdrawal source split, meaning users who withdraw a mix of direct-balance and targetVault assets pay the same fee as if all assets came from the targetVault.

#### Impact

Users pay withdrawal fees calculated on the full amount even when a portion of their withdrawal comes from the vault's direct asset balance (which may not warrant a fee), or conversely, the fee calculation does not account for the fact that the targetVault withdrawal was silently reduced, potentially leading to an accounting mismatch where the vault collected fees on assets it did not fully withdraw from the yield-bearing targetVault.

#### Recommendation

Consider splitting the fee calculation to account for the portion of assets withdrawn from the targetVault versus the portion from the vault's direct balance. Alternatively, if fees should apply uniformly, document this behavior explicitly and ensure the hook does not silently cap the withdrawal amount (revert instead, as noted in existing M-01).

**Sources:** Pipeline H (Auditmos DeFi Checklists - Math Precision)

---

### M-05: `handleAfterDeposit` deposits full asset amount without accounting for fee-on-transfer tokens

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleAfterDeposit()` (lines 73-91), `handleBeforeRedeem()` (lines 93-113)

#### Description

The `handleAfterDeposit` function uses `params.assets` (the user-specified deposit amount) as the argument for the `targetVault.deposit()` call. However, if the underlying asset is a fee-on-transfer token, the actual amount received by the vault from `safeTransferFrom` in `BaseVault._deposit` is less than `params.assets`. The hook then attempts to approve and deposit the full `params.assets` amount into the targetVault, which will either:
1. Revert because the vault does not hold enough tokens (deposit fails), or
2. If there are residual tokens from prior operations, deposit more than the user actually contributed.

The same issue applies to `handleBeforeRedeem`: the `assets` parameter used for `targetVault.withdraw()` assumes no fee-on-transfer deduction.

#### Impact

If the strategy is configured to accept a fee-on-transfer token as its base asset, deposits will fail (reverting the entire transaction) or, in edge cases where residual tokens exist, incorrect amounts will be deposited into the targetVault. This would break the vault's accounting, as `totalBaseAssets` would track the pre-fee amount while the actual deposited amount is less.

#### Recommendation

If fee-on-transfer tokens are intended to be supported, measure the actual token balance change after the transfer (balance-after minus balance-before) and use that delta as the amount for the targetVault deposit. If fee-on-transfer tokens are explicitly not supported, add a check or document this restriction clearly. Consider adding a pre/post balance check in the hooks.

**Sources:** Pipeline H (Auditmos DeFi Checklists - Token Compatibility)

---

### L-01: `_feeOnRaw` and `_feeOnTotal` have `public` visibility exposing internal implementation

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `ERC4626WrapperStrategy.sol`, inherited from `BaseVault.sol`
**Function(s):** `_feeOnRaw()` (line 52), `_feeOnTotal()` (line 64)

#### Description

The functions `_feeOnRaw` and `_feeOnTotal` in `ERC4626WrapperStrategy` are declared as `public view override`. By Solidity convention, the underscore prefix indicates these should be internal functions. These are declared `public` in `BaseVault` (as part of `IVault` interface requirements) and overridden in `ERC4626WrapperStrategy`.

```solidity
// File: src/ERC4626WrapperStrategy.sol, lines 52-54
function _feeOnRaw(uint256 amount, address user) public view override returns (uint256) {
    return __feeOnRaw(amount, user);
}
```

The `IVault` interface exposes these as external functions:
```solidity
// IVault interface
function _feeOnRaw(uint256 amount, address user) external view returns (uint256);
function _feeOnTotal(uint256 amount, address user) external view returns (uint256);
```

While making fee calculation functions public is not directly exploitable, it exposes internal accounting details that could be useful for an attacker planning fee-evasion strategies. More importantly, the naming convention inconsistency (`_` prefix on a public function) could mislead auditors and developers into believing these functions are internal, potentially causing them to overlook access control concerns in derived contracts.

#### Impact

This is a design issue inherited from the base vault. The leading underscore naming convention violation may confuse integrators. The functions are view-only, so no state risk, but the naming breaks the common Solidity convention that `_` prefixed functions are internal.

#### Recommendation

This is an inherited design pattern from the base vault and cannot be easily changed without breaking the interface. Document that these are intentionally public despite the naming convention. Consider renaming the functions to remove the underscore prefix (reflecting their actual public visibility) or creating separate properly-named public view wrappers upstream.

**Sources:** Pipeline A (SCV Scan - inadherence to standards), Pipeline D (Pashov access control), Pipeline G (Forefy Access control layer), Pipeline H (Auditmos DeFi Checklists - State Validation)

---

### L-02: `ERC4626WrapperLib.availableAssets` assumes second asset in list is the targetVault

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `ERC4626WrapperLib.sol`
**Function(s):** `availableAssets()` (lines 9-22)

#### Description

The library function hardcodes `assets[1]` as the target ERC4626 vault:

```solidity
// File: src/lib/ERC4626WrapperLib.sol, lines 12-20
if (assets.length > 1) {
    IERC4626 targetERC4626Vault = IERC4626(assets[1]);
    if (vault.asset() == asset_) {
        availableAssetsAmount +=
            targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)));
    }
}
```

This creates a tight coupling between the asset list ordering and the library's logic. If assets are ever reordered (e.g., via `deleteAsset` which swaps with the last element), or if a third asset is added at index 1 after deleting index 1, this assumption breaks.

The comment in the code says "assumes it's the asset that the withdrawal hooks reference" which acknowledges this assumption but does not enforce it. The hooks contract stores `targetVault` as an immutable, while the library reads from the vault's dynamic asset list. These two references can become inconsistent if an admin modifies the asset list after deployment.

There is no validation that `assets[1]` actually implements the IERC4626 interface, nor that it is the correct target vault that the hooks are configured to interact with.

#### Impact

If the asset at index 1 is not an ERC4626 vault or is not the intended targetVault, `availableAssets` would return incorrect values, leading to incorrect `maxWithdraw` and `maxRedeem` calculations. This could either over-report available assets (allowing withdrawals that will fail) or under-report them (blocking valid withdrawals).

The `deleteAsset` function in VaultLib prevents deleting index 0 (base asset) and the default asset index. Since `defaultAssetIndex` is 0 in the test setup, index 1 could potentially be deleted, though this would require ASSET_MANAGER_ROLE and a zero balance.

#### Recommendation

Either:
1. Store the targetVault address explicitly in the strategy's storage and reference it directly, or pass the targetVault address as a parameter to `availableAssets`.
2. Add a validation check that `assets[1]` is indeed the expected target ERC4626 vault by reading it from the hooks contract.
3. Add a check that the address at `assets[1]` actually implements IERC4626 before calling `convertToAssets` on it.

**Sources:** Pipeline B (Feynman boundary conditions), Pipeline C (State Inconsistency - coupled state), Pipeline G (Archethect semantic_consistency), Pipeline H (Auditmos DeFi Checklists - State Validation)

---

### L-03: No slippage protection on hook deposit/withdraw to targetVault

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleAfterDeposit()` (lines 73-91), `handleBeforeRedeem()` (lines 93-113)

#### Description

When depositing into the targetVault in `handleAfterDeposit`, the hook calls:
```solidity
data[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, address(vault));
```

The ERC4626 `deposit` function returns shares minted, but this return value is not checked. There is no minimum shares check. Similarly, the `withdraw` call in `handleBeforeRedeem` does not verify the actual assets received.

If the targetVault's share price changes between when the user's deposit was previewed and when the hook executes the deposit into the targetVault (which happens in the same transaction, so this is less of a concern for standard ERC4626 vaults), the vault could receive fewer shares than expected.

Since these calls happen within the hooks (which are part of the deposit/withdraw flow), the user has no way to specify a minimum shares received or maximum shares burned for the targetVault interaction. A sandwich attacker could manipulate the targetVault's exchange rate (e.g., via a large deposit that changes the rate, then backrunning after the victim's transaction) to extract value from wrapper strategy users.

#### Impact

For standard ERC4626 vaults, the deposit and withdraw happen atomically within the same transaction, so sandwich attacks on the targetVault itself are the primary vector. The risk is low for well-behaved underlying vaults but increases for vaults with dynamic pricing or fee-on-transfer mechanisms.

Since the `processor` function in `VaultLib` does check `success` on the low-level call and the vault framework uses `nonReentrant`, the immediate attack surface is limited. The maximum extractable value depends on the targetVault's liquidity depth and the user's transaction size.

#### Recommendation

Consider adding minimum amount checks on the shares received from deposits and assets received from withdrawals, or document the assumption that the targetVault is a trusted, well-behaved ERC4626 vault. Adding a user-specified slippage parameter that flows through to the hooks would provide the strongest protection.

**Sources:** Pipeline B (Feynman), Pipeline D (Pashov external interactions), Pipeline F (Token Integration), Pipeline G (Archethect callback_liveness), Pipeline H (Auditmos DeFi Checklists - Slippage)

---

### L-04: Provider `getRate` for vault token relies on target vault's `convertToAssets` which may be manipulable

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `Provider.sol`
**Function(s):** `getRate()` (lines 19-27)

#### Description

The `Provider` contract returns the rate for the vault token by calling `IERC4626(vault).convertToAssets(unitValue)`:

```solidity
// File: src/module/Provider.sol, lines 19-27
function getRate(address asset) external view returns (uint256) {
    if (asset == underlyingAsset) {
        return unitValue;
    } else if (asset == vault) {
        return IERC4626(vault).convertToAssets(unitValue);
    } else {
        revert UnsupportedAsset(asset);
    }
}
```

The `convertToAssets` function on a standard ERC4626 vault is based on `totalAssets / totalSupply`. If the targetVault is susceptible to donation attacks (direct token transfers that inflate `totalAssets` without minting shares), an attacker could temporarily inflate the rate.

Since the Provider rate is used by `VaultLib.convertAssetToBase` and `VaultLib.convertBaseToAsset` for all share/asset conversions in the wrapper strategy, a manipulated rate directly affects the number of shares minted for deposits, the number of assets received for redemptions, the total assets reported, and the maximum withdraw/redeem amounts.

The `Provider.getRate` function also performs no sanity check on the value returned by `convertToAssets`, allowing zero or extreme values to propagate. A zero rate would cause `processAccounting` to value all target vault shares at zero, while an extremely large rate would inflate the share price.

#### Impact

An inflated rate from the Provider would affect how the wrapper strategy converts between assets and shares. In the `computeTotalAssets` flow, the vault iterates over its asset balances and converts them using the provider rate. An inflated rate on the targetVault shares would inflate the wrapper strategy's reported `totalAssets`, which feeds into share price calculations. For vaults with low TVL, the impact could be significant, effectively enabling a first-depositor-style inflation attack channeled through the Provider rate.

However, the `processAccounting` guard hook (if configured) limits the maximum increase/decrease ratios, providing a secondary defense. Note that this guard does not protect individual deposit/withdrawal operations.

#### Recommendation

1. Ensure the ProcessAccountingGuardHook is always configured with reasonable bounds.
2. Consider using a TWAP or other time-weighted oracle for the rate rather than a spot price.
3. Document the trust assumption on the targetVault's `convertToAssets`.
4. Add minimum and maximum bounds validation in `Provider.getRate`:
   ```solidity
   uint256 rate = IERC4626(vault).convertToAssets(unitValue);
   require(rate > 0, "Provider: zero rate");
   require(rate <= MAX_REASONABLE_RATE, "Provider: rate too high");
   return rate;
   ```

**Sources:** Pipeline D (Pashov arithmetic/precision), Pipeline E (QuillAI oracle-flashloan-analysis), Pipeline F (Token Integration), Pipeline G (Archethect accounting_entitlement + economic_differential + token_oracle_statefulness), Pipeline H (Auditmos DeFi Checklists - Staking / Math Precision)

---

### L-05: `SingleAssetProvider` returns a fixed immutable rate, causing stale pricing if the underlying asset value changes

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `SingleAssetProvider.sol`
**Function(s):** `getRate()` (lines 17-23)

#### Description

The `SingleAssetProvider` contract stores a fixed `unitValue` set at construction time and returns it as the rate for the underlying asset. This rate never changes:

```solidity
function getRate(address asset) external view returns (uint256) {
    if (asset == underlyingAsset) {
        return unitValue;
    } else {
        revert UnsupportedAsset(asset);
    }
}
```

If the wrapper strategy uses `SingleAssetProvider` as its rate provider, and the underlying asset's value changes relative to the base denomination (e.g., due to yield accrual in the target vault, or market price changes), the wrapper vault's `totalAssets` calculation will use a stale rate. This causes the wrapper's share price to not reflect the actual value of the underlying assets.

Note that the `Provider` contract (as opposed to `SingleAssetProvider`) does dynamically read the targetVault's conversion rate for the vault token. However, `SingleAssetProvider` has no such mechanism. If deployed as the rate provider for a strategy where the underlying asset's value fluctuates, accounting will drift.

#### Impact

If `SingleAssetProvider` is used in a context where the underlying asset's value changes, `totalAssets` and share price calculations will be based on stale data. This could benefit depositors (who get underpriced shares if the asset has appreciated) or redeemers (who get overpriced redemptions if the asset has depreciated), at the expense of the other party.

#### Recommendation

1. Clearly document that `SingleAssetProvider` should only be used for assets whose value relative to the base denomination is guaranteed to remain constant (e.g., 1:1 pegged stablecoins with the same denomination).
2. For any asset with variable value, use `Provider` which dynamically reads `convertToAssets` from the target vault.

**Sources:** Pipeline G (Forefy Economic layer + Archethect token_oracle_statefulness)

---

### L-06: `handleBeforeRedeem` and `handleAfterDeposit` do not handle targetVault reverts, potentially locking user funds

**Severity:** Low
**Confidence:** Low
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleBeforeRedeem()` (lines 93-113), `handleAfterDeposit()` (lines 73-91)

#### Description

Both `handleBeforeRedeem` and `handleAfterDeposit` call `BaseVault(payable(address(vault))).processor(...)` which executes calls to the `targetVault`. If the `targetVault` is paused, has insufficient liquidity, or reverts for any other reason, the entire processor call reverts, which causes the hook to revert, which causes the parent deposit/redeem/withdraw operation to revert.

For `handleAfterDeposit`, this means a deposit into the wrapper vault will revert entirely if the target vault's `deposit` function reverts. The user cannot deposit even though the wrapper vault itself is functioning correctly.

For `handleBeforeRedeem`, this means a redemption from the wrapper vault will revert if the target vault's `withdraw` function reverts. Users' shares are locked and cannot be redeemed. Note that the silent capping to `maxWithdraw` in `handleBeforeRedeem` partially mitigates this for liquidity constraints, but does not help if the target vault is fully paused or reverts for other reasons.

There is no emergency withdrawal path that bypasses the hooks, meaning a permanently paused or bricked target vault would permanently lock all wrapper vault depositors' funds. Since the hooks are immutable (constructor-set targets), there is no way to update the target vault reference.

#### Impact

If the target vault becomes unavailable (paused, self-destructed, or permanently reverting), wrapper vault users cannot deposit or withdraw. Funds are locked until the target vault is restored.

#### Recommendation

1. Consider adding an emergency withdrawal mechanism in the strategy that allows withdrawals to bypass the hooks entirely, usable only by admin or when the target vault is detected as unavailable.
2. Alternatively, wrap the processor calls in try/catch logic (though this would require architectural changes to how processor handles errors).
3. Add a fallback path where, if the targetVault is paused, the hooks allow the withdrawal to proceed using only the idle balance in the wrapper vault.

**Sources:** Pipeline G (Archethect callback_liveness)

---

### L-07: No zero-amount validation in hook handlers

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `handleAfterDeposit()` (lines 73-91), `handleBeforeRedeem()` (lines 93-113)

#### Description

Neither `handleAfterDeposit` nor `handleBeforeRedeem` validate that `assets > 0` before executing the processor calls. If `assets` is 0 (which can happen if `previewDeposit` rounds down to 0 for very small deposit amounts, or if the fee calculation consumes the entire amount), the hooks will:
1. Approve 0 tokens to the targetVault (wasted gas)
2. Call `targetVault.deposit(0, vault)` or `targetVault.withdraw(0, vault, vault)` (which may revert depending on the targetVault's implementation, as many ERC4626 vaults revert on zero-amount operations)

This could cause the entire deposit/withdrawal to revert due to the hook failure, even though the zero amount might be a valid edge case that should be handled gracefully.

#### Impact

Potential denial of service for edge-case transactions. If the targetVault reverts on zero-amount deposits/withdrawals, the wrapper strategy would also revert, preventing valid (though economically trivial) operations.

#### Recommendation

Add a guard in both `handleAfterDeposit` and `handleBeforeRedeem`:
```solidity
if (assets == 0) return;
```

**Sources:** Pipeline H (Auditmos DeFi Checklists - State Validation)

---

### I-01: `ERC4626WrapperHooks.onlyVault` modifier error message is misleading

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `ERC4626WrapperHooks.sol`
**Function(s):** `onlyVault` modifier (lines 24-29)

#### Description

The `onlyVault` modifier checks against the `caller` address (set in constructor) and reverts with `CallerNotVault()` error:

```solidity
// File: src/hooks/ERC4626WrapperHooks.sol, lines 24-29
modifier onlyVault() {
    if (msg.sender != caller) {
        revert CallerNotVault();
    }
    _;
}
```

The `caller` is set to `address(stakedLPStrategy)` in the test setup (line 81 of BaseUnitTest.sol). This is correct because the vault itself calls the hooks. However, the naming is slightly confusing: the constructor parameter is named `caller_` while the modifier is named `onlyVault`, and the stored variable is `caller` rather than `vault` (which is a separate variable for the IVault interface). The `vault` immutable stores the same address via `IVault(_vault)` but `caller` is the address used for access control.

#### Impact

No security impact. This is a code clarity issue that could confuse auditors or developers maintaining the code.

#### Recommendation

Consider renaming `caller` to `authorizedCaller` or unifying it with `vault` if they are always the same address.

**Sources:** Pipeline A (SCV Scan - code quality)

---

### I-02: Unused Curve pool interfaces in source tree

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `ICurvePool.sol`, `ICurveStableSwapFactoryNG.sol`

#### Description

The `ICurvePool` and `ICurveStableSwapFactoryNG` interfaces are present in the `src/interfaces/` directory but are not imported or used by any of the core source contracts (`ERC4626WrapperStrategy`, `ERC4626WrapperHooks`, `ERC4626WrapperLib`, `Provider`, `SingleAssetProvider`).

These interfaces total 142 lines of code and appear to be remnants from a planned Curve integration or copied from another project.

#### Impact

No security impact. Dead code increases the cognitive overhead for auditors and developers.

#### Recommendation

Remove unused interfaces or move them to a separate directory if they are planned for future use.

**Sources:** Pipeline A (SCV Scan - unused variables/code)

---

## Informational Notes

### General Observations

1. **Reentrancy Protection:** The vault framework properly uses OpenZeppelin's `ReentrancyGuardUpgradeable`. All external entry points (`deposit`, `withdraw`, `redeem`, `mint`, `processAccounting`) are protected with `nonReentrant`. The hooks execute within the nonReentrant context of the parent call, preventing re-entrance through hook callbacks.

2. **Access Control Model:** The strategy uses a comprehensive role-based access control system inherited from `BaseVault`. Key privileged operations are properly gated:
   - `FEE_MANAGER_ROLE` for fee configuration
   - `ASSET_MANAGER_ROLE` for asset management
   - `PROCESSOR_ROLE` for the `processor` function (which the hooks contract needs)
   - `HOOKS_MANAGER_ROLE` for hooks configuration
   - The `initialize` function uses the `initializer` modifier to prevent re-initialization.

3. **Integer Overflow/Underflow:** Solidity 0.8.24 provides built-in overflow/underflow protection. No `unchecked` blocks are used in the scoped source files. The `FeeMath` library uses OpenZeppelin's `Math.mulDiv` for safe precision arithmetic.

4. **ERC4626 Compliance:** The strategy inherits ERC4626 compliance from `BaseVault`, including proper rounding conventions (round down for deposits/conversions favoring the vault, round up for withdrawals favoring the vault). The virtual price offset of `+1` in `convertToShares`/`convertToAssets` in VaultLib provides basic inflation attack mitigation.

5. **Proxy Pattern:** The strategy is deployed behind a `TransparentUpgradeableProxy`. The base `BaseVault` constructor calls `_disableInitializers()` to prevent initialization of the implementation contract directly.

6. **Fee-on-Transfer Tokens:** The strategy uses `SafeERC20.safeTransferFrom` in the deposit path, but does not check the actual balance change after transfer. If the underlying asset is a fee-on-transfer token, the vault would mint more shares than the actual assets received. This is a known limitation that applies to most ERC4626 vaults and is not specific to this wrapper.

7. **Rebasing Tokens:** If the underlying asset or the targetVault token is a rebasing token, the cached `totalAssets` could become stale. The `alwaysComputeTotalAssets` flag mitigates this when set to `true`.

8. **`SingleAssetProvider` vs `Provider`:** The `SingleAssetProvider` only supports a single asset with a fixed rate, while `Provider` supports both the underlying asset and the vault token. The wrapper strategy test uses `Provider`, which is the correct choice for a strategy that holds both underlying tokens and targetVault shares.

9. **Hooks Processor Flow:** The hooks call the vault's `processor` function to execute operations on behalf of the vault. This is protected by the `PROCESSOR_ROLE` and the `Guard` module validates each call against configured rules. The test setup properly configures deposit, withdraw, and approve rules.

10. **No `delegatecall` usage:** None of the scoped contracts use `delegatecall` directly (only through the proxy pattern, which is managed by OpenZeppelin).

11. **No `tx.origin` usage:** None of the scoped contracts reference `tx.origin`.

12. **No signature/ecrecover usage:** The contracts do not implement any custom signature verification.
