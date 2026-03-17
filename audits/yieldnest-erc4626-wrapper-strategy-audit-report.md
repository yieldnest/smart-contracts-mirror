# Security Audit Report: yieldnest-erc4626-wrapper-strategy

## Metadata
- **Repository:** yieldnest-erc4626-wrapper-strategy
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6 (monorepo mirror)
- **Branch:** release-candidate (mirrored into main)
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24
- **EVM Target:** Cancun

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
| **Total unique findings (deduplicated)** | | **8** |

## Executive Summary

The yieldnest-erc4626-wrapper-strategy is a relatively thin wrapper that extends the Yieldnest vault framework to automatically deposit incoming assets into an underlying ERC4626 vault (the "targetVault") via hooks, and withdraw from it before redemptions. The core logic is straightforward and the attack surface is limited by the framework's access control (role-based via OpenZeppelin AccessControl) and reentrancy guards.

**Overall Risk Posture: LOW-MEDIUM**

The primary concerns identified are:

1. **A medium-severity issue** where the `ERC4626WrapperHooks` contract uses `abi.encodeWithSignature` to make calls through the vault's `processor`, passing memory arrays that do not match the `processor` function's `calldata` parameter types. This works due to Solidity's ABI encoding equivalence but introduces fragility.

2. **A medium-severity issue** where the `handleBeforeRedeem` hook silently caps withdrawal amounts at `maxWithdraw` from the target vault without reverting or notifying the caller, potentially causing users to receive fewer assets than expected while burning the full share amount calculated on the original (uncapped) value.

3. **Several low-severity and informational issues** including reliance on the target ERC4626 vault's correctness, absence of slippage protection in hook operations, and the `_feeOnRaw`/`_feeOnTotal` functions being marked `public` instead of `internal`.

No critical vulnerabilities were found. The access control model is properly implemented, reentrancy guards are in place, and the fee math uses OpenZeppelin's `mulDiv` for safe precision handling.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| H-01 | -- | No high-severity findings | -- | -- |
| M-01 | Medium | Silent withdrawal amount capping in `handleBeforeRedeem` can cause user fund loss | B, C, D | High |
| M-02 | Medium | Hooks `processor` call uses memory arrays for calldata parameters -- fragile ABI encoding | A, B, E | Medium |
| L-01 | Low | `_feeOnRaw` and `_feeOnTotal` have `public` visibility exposing internal implementation | A, D | High |
| L-02 | Low | `ERC4626WrapperLib.availableAssets` assumes second asset in list is the targetVault | B, C | High |
| L-03 | Low | No slippage protection on hook deposit/withdraw to targetVault | B, D, F | Medium |
| L-04 | Low | Provider `getRate` for vault token relies on target vault's `convertToAssets` which may be manipulable | D, E, F | Medium |
| I-01 | Informational | `ERC4626WrapperHooks.onlyVault` modifier error message is misleading | A | High |
| I-02 | Informational | Unused Curve pool interfaces in source tree | A | High |

## Detailed Findings

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

#### Impact

No immediate exploit, but this is a maintenance and correctness risk. If the target vault's function signatures change or if a non-standard ERC4626 vault is used, these calls would silently fail at runtime with cryptic revert messages.

#### Recommendation

1. Use `abi.encodeCall` for type-safe encoding:
   ```solidity
   data[0] = abi.encodeCall(IERC20.approve, (address(targetVault), assets));
   data[1] = abi.encodeCall(IERC4626.deposit, (assets, address(vault)));
   ```
2. Consider using `abi.encodeCall(IERC4626.withdraw, (...))` in `handleBeforeRedeem` as well.

**Sources:** Pipeline A (SCV Scan - unchecked return values pattern), Pipeline B (Feynman), Pipeline E (QuillAI external-call-safety)

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

#### Impact

This is a design issue inherited from the base vault. The leading underscore naming convention violation may confuse integrators. The functions are view-only, so no state risk, but the naming breaks the common Solidity convention that `_` prefixed functions are internal.

#### Recommendation

This is an inherited design pattern from the base vault and cannot be easily changed without breaking the interface. Document that these are intentionally public despite the naming convention.

**Sources:** Pipeline A (SCV Scan - inadherence to standards), Pipeline D (Pashov access control)

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

The comment in the code says "assumes it's the asset that the withdrawal hooks reference" which acknowledges this assumption but does not enforce it.

#### Impact

If the asset at index 1 is not an ERC4626 vault or is not the intended targetVault, `availableAssets` would return incorrect values, leading to incorrect `maxWithdraw` and `maxRedeem` calculations. This could either over-report available assets (allowing withdrawals that will fail) or under-report them (blocking valid withdrawals).

The `deleteAsset` function in VaultLib prevents deleting index 0 (base asset) and the default asset index. Since `defaultAssetIndex` is 0 in the test setup, index 1 could potentially be deleted, though this would require ASSET_MANAGER_ROLE and a zero balance.

#### Recommendation

Either:
1. Store the targetVault address explicitly in the strategy's storage and reference it directly.
2. Add a validation check that `assets[1]` is indeed the expected target ERC4626 vault.

**Sources:** Pipeline B (Feynman boundary conditions), Pipeline C (State Inconsistency - coupled state)

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

#### Impact

For standard ERC4626 vaults, the deposit and withdraw happen atomically within the same transaction, so sandwich attacks on the targetVault itself are the primary vector. The risk is low for well-behaved underlying vaults but increases for vaults with dynamic pricing or fee-on-transfer mechanisms.

Since the `processor` function in `VaultLib` does check `success` on the low-level call and the vault framework uses `nonReentrant`, the immediate attack surface is limited.

#### Recommendation

Consider adding minimum amount checks on the shares received from deposits and assets received from withdrawals, or document the assumption that the targetVault is a trusted, well-behaved ERC4626 vault.

**Sources:** Pipeline B (Feynman), Pipeline D (Pashov external interactions), Pipeline F (Token Integration)

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

#### Impact

An inflated rate from the Provider would affect how the wrapper strategy converts between assets and shares. In the `computeTotalAssets` flow, the vault iterates over its asset balances and converts them using the provider rate. An inflated rate on the targetVault shares would inflate the wrapper strategy's reported `totalAssets`, which feeds into share price calculations.

However, the `processAccounting` guard hook (if configured) limits the maximum increase/decrease ratios, providing a secondary defense.

#### Recommendation

1. Ensure the ProcessAccountingGuardHook is always configured with reasonable bounds.
2. Consider using a TWAP or other time-weighted oracle for the rate rather than a spot price.
3. Document the trust assumption on the targetVault's `convertToAssets`.

**Sources:** Pipeline D (Pashov arithmetic/precision), Pipeline E (QuillAI oracle-flashloan-analysis), Pipeline F (Token Integration)

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
