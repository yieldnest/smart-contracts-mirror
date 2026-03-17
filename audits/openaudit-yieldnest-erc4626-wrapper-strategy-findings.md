# OpenAudit: Yieldnest ERC4626 Wrapper Strategy -- New Findings

**Target:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-erc4626-wrapper-strategy/src/`
**LOC:** ~600
**Solidity:** 0.8.24
**Date:** 2026-03-17
**Pipelines:** Forefy Smart Contract Audit, Archethect SC Auditor (Map-Hunt-Attack)
**Existing findings (excluded from this report):**
- M-01: Silent withdrawal amount capping in handleBeforeRedeem can cause user fund loss
- M-02: Hooks processor call uses memory arrays for calldata parameters -- fragile ABI encoding

---

## Architecture Summary

The ERC4626WrapperStrategy wraps a target ERC4626 vault. On deposit, the `afterDeposit` hook approves and deposits the received assets into the `targetVault`. On withdrawal/redeem, the `beforeRedeem`/`beforeWithdraw` hook withdraws assets from the `targetVault` back to the wrapper vault before the user receives them. The system includes:

- **ERC4626WrapperStrategy.sol** -- Main strategy inheriting BaseStrategy and LinearWithdrawalFee
- **ERC4626WrapperHooks.sol** -- Hooks contract executing deposit/withdraw forwarding to targetVault
- **ERC4626WrapperLib.sol** -- Library computing available assets across both the wrapper and target vault
- **Provider.sol / SingleAssetProvider.sol** -- Rate providers for asset conversion
- **Interfaces** -- ICurvePool, ICurveStableSwapFactoryNG, IHooksFactory, IMetaHooks, IProcessAccountingGuardHook

---

## Findings

### [HIGH] OA-EW-01: Approval to targetVault is not reset before setting new allowance, incompatible with non-standard tokens like USDT

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/hooks/ERC4626WrapperHooks.sol:82`

**Description:**
In `handleAfterDeposit`, the hook approves the `targetVault` to spend `assets` amount of the underlying token using `abi.encodeWithSignature("approve(address,uint256)", address(targetVault), assets)`. This approval is executed via the vault's `processor` call. The approval is set to the exact deposit amount each time, but it never resets the allowance to zero first.

If the underlying asset is a token like USDT that requires the allowance to be zero before setting a new non-zero value (the well-known USDT approval pattern), subsequent deposits will revert. This is because after the first deposit, if the targetVault's `deposit` call does not consume the entire allowance (which can happen due to rounding in the targetVault's share calculation), a residual non-zero allowance remains. The next approval call with a non-zero amount on a USDT-like token will revert, permanently bricking the deposit path.

Even for standard ERC20 tokens, any residual allowance from a previous operation that was not fully consumed (e.g., targetVault rounding down shares received) means the allowance accumulates rather than being set precisely. While this is not exploitable for standard tokens, it represents a correctness issue.

**Impact:**
If the underlying asset is USDT or any token that reverts on non-zero-to-non-zero approve, all deposits after the first successful one will permanently revert. Users cannot deposit into the strategy, effectively bricking the vault's core functionality. Given that the protocol aims to support multiple assets and wrapping strategies, encountering a USDT-like token is a realistic scenario.

**Recommendation:**
Before setting the approval, first reset it to zero. Modify `handleAfterDeposit` to include a `approve(address,uint256)` call with amount 0 before the actual approval:

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

---

### [MEDIUM] OA-EW-03: Provider.getRate uses targetVault.convertToAssets which is manipulable via donation, leading to incorrect share pricing

**Pipeline:** Archethect (accounting_entitlement + economic_differential)
**Confidence:** Medium
**File:** `src/module/Provider.sol:23`

**Description:**
The `Provider.getRate` function returns the rate for the targetVault token by calling `IERC4626(vault).convertToAssets(unitValue)`. This reads the target vault's current share-to-asset conversion rate. If the target vault's `totalAssets()` is based on `balanceOf(address(targetVault))` (as is common in many ERC4626 implementations), the rate is manipulable through direct token donation to the target vault.

The rate returned by the Provider is used by the wrapper strategy (via `VaultLib.convertToShares` and `VaultLib.convertToAssets`) to determine how many wrapper shares a depositor receives and how many assets a redeemer gets. An attacker who can manipulate the target vault's exchange rate (via donation or flash loan) can cause the wrapper strategy to overprice or underprice shares during `processAccounting`, deposit, or withdrawal operations.

Attack sequence:
1. Attacker donates a large amount of the underlying asset directly to the targetVault, inflating `convertToAssets`.
2. The Provider returns an inflated rate for the targetVault token.
3. The wrapper vault's `computeTotalAssets` / `processAccounting` uses this inflated rate, making the wrapper think it has more total assets than it actually does.
4. The attacker (who already holds wrapper shares) redeems at the inflated rate, extracting more underlying assets than their fair share.
5. Remaining depositors bear the loss when the donated tokens are not actually backing their shares.

**Impact:**
If the target vault is susceptible to donation-based exchange rate manipulation, an attacker can steal funds from the wrapper vault's depositors. The severity depends on the target vault's implementation -- if it uses internal accounting (donation-immune), this is not exploitable. However, the Provider has no validation or sanity check on the returned rate, making it an unconditional trust assumption.

**Recommendation:**
1. Add a maximum rate change threshold in the Provider or in processAccounting to detect and reject abnormal rate jumps (the `IProcessAccountingGuardHook` interface suggests this exists as a separate hook, but it should be enforced at the Provider level as well).
2. Consider using a time-weighted average rate rather than a spot rate for conversion.
3. Document the assumption that the target vault must use internal accounting rather than `balanceOf`-based accounting.

---

### [MEDIUM] OA-EW-04: ERC4626WrapperLib.availableAssets relies on targetVault.convertToAssets which can be stale or manipulated, causing incorrect maxWithdraw/maxRedeem calculations

**Pipeline:** Forefy (Economic layer + Integration layer)
**Confidence:** High
**File:** `src/lib/ERC4626WrapperLib.sol:18-19`

**Description:**
The `ERC4626WrapperLib.availableAssets` function computes the total available assets by summing the direct balance of the underlying asset in the vault PLUS the value of the target vault shares held by the wrapper (via `targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)))`).

This value is used in `_maxWithdrawAsset` and `_maxRedeemAsset` in `BaseStrategy` to cap the maximum withdrawable/redeemable amount. The issue is that `convertToAssets` returns the theoretical value of the shares based on the target vault's current state, but the actual amount receivable via `targetVault.withdraw` may differ due to:

1. **Target vault withdrawal fees**: If the target vault charges a withdrawal fee, `convertToAssets` returns the gross amount but the net amount after fees would be less. The wrapper's `maxWithdraw` would report more assets available than can actually be retrieved.

2. **Target vault liquidity constraints**: The target vault may have its own liquidity limitations (locked in strategies, paused, etc.) that are not reflected in `convertToAssets`. The `handleBeforeRedeem` hook does correctly cap to `targetVault.maxWithdraw(address(vault))`, but `_availableAssets` does NOT use `maxWithdraw` -- it uses `convertToAssets` of the balance. This means `maxWithdraw` on the wrapper can report a higher value than what the hooks will actually be able to withdraw from the target vault.

This creates a scenario where the wrapper's `maxWithdraw` says X assets are available, but when the user actually calls `withdraw(X)`, the `beforeWithdraw` hook can only retrieve `targetVault.maxWithdraw(address(vault))` which may be less than X. The hook silently caps the withdrawal amount (the already-reported M-01 issue), but the root cause is the inconsistency between `_availableAssets` and what the hooks can actually retrieve.

**Impact:**
Users relying on `maxWithdraw` or `maxRedeem` view functions to determine safe withdrawal amounts may call `withdraw` or `redeem` with amounts that appear valid but result in receiving fewer assets than expected due to the silent capping in the hooks. Integrating protocols that respect ERC4626's `maxWithdraw` invariant (i.e., "withdraw must succeed for amounts <= maxWithdraw") may experience unexpected behavior.

**Recommendation:**
Modify `ERC4626WrapperLib.availableAssets` to use `targetERC4626Vault.maxWithdraw(address(vault))` instead of `targetERC4626Vault.convertToAssets(targetERC4626Vault.balanceOf(address(vault)))` when computing available assets. This aligns the reported availability with what the hooks can actually retrieve:

```solidity
if (vault.asset() == asset_) {
    IERC4626 targetERC4626Vault = IERC4626(assets[1]);
    availableAssetsAmount += targetERC4626Vault.maxWithdraw(address(vault));
}
```

---

### [MEDIUM] OA-EW-05: handleAfterDeposit uses abi.encodeWithSignature which does not validate target function existence or return value, risking silent deposit failure

**Pipeline:** Archethect (semantic_consistency + callback_liveness)
**Confidence:** Medium
**File:** `src/hooks/ERC4626WrapperHooks.sol:73-91`

**Description:**
The `handleAfterDeposit` function constructs processor calls using `abi.encodeWithSignature("approve(address,uint256)", ...)` and `abi.encodeWithSignature("deposit(uint256,address)", ...)`. These are low-level encoding mechanisms that:

1. **Do not verify at compile time** that the target contract actually implements the called function.
2. **Rely on string-based function selector computation** which is fragile to typos (though in this case the strings are correct).
3. **Most critically**: the processor function in `VaultLib` does check the return value via the `FunctionRule` mechanism, but the hooks are calling `BaseVault.processor()` which requires `PROCESSOR_ROLE`. The hooks contract (`caller`) must hold this role.

The deeper concern is that the `processor` call returns `bytes[] memory returnData`, but this return data is not checked by `handleAfterDeposit` or `handleBeforeRedeem`. If the `approve` call returns `false` (as some ERC20 tokens do on failure instead of reverting), or if the `deposit` call partially fails, the hooks have no way of knowing.

For the `approve` call specifically: standard ERC20 `approve` returns `bool`. If the processor's FunctionRule is configured to not validate the return value, a failed approval would go undetected, and the subsequent `deposit` call to the targetVault would then fail (or succeed with 0 if the targetVault allows 0 deposits without the approval).

**Impact:**
If the approval silently fails (returns false without reverting), the subsequent deposit into the targetVault will also fail or deposit 0 assets. The user's assets would remain in the wrapper vault un-deposited, creating an accounting inconsistency where the wrapper vault holds idle assets that are not earning yield in the target vault. This represents a yield loss for depositors.

**Recommendation:**
1. Use typed interface calls instead of `abi.encodeWithSignature` where possible, or validate return data from the processor call.
2. Alternatively, verify after the processor batch that the targetVault balance increased by the expected amount by comparing balances before and after.
3. Ensure the FunctionRule for the `approve` selector on the asset contract is configured to validate the boolean return value.

---

### [LOW] OA-EW-06: _feeOnRaw and _feeOnTotal are declared as public view, exposing internal fee calculation to external callers

**Pipeline:** Forefy (Access control layer)
**Confidence:** High
**File:** `src/ERC4626WrapperStrategy.sol:52,64`

**Description:**
The `_feeOnRaw` and `_feeOnTotal` functions are declared as `public view override` in `ERC4626WrapperStrategy`. These functions are prefixed with an underscore (`_`), conventionally indicating internal functions, but they are actually `public`. This is inherited from `BaseVault` where they are declared as `public view virtual`.

While making fee calculation functions public is not directly exploitable, it exposes internal accounting details that could be useful for an attacker planning fee-evasion strategies. More importantly, the naming convention inconsistency (`_` prefix on a public function) could mislead auditors and developers into believing these functions are internal, potentially causing them to overlook access control concerns in derived contracts.

**Impact:**
Low direct impact. The functions are view-only and do not modify state. However, exposing fee calculation details helps attackers optimize fee-evasion strategies (e.g., determining the exact amount threshold below which fees round to zero). The naming inconsistency is a code quality concern.

**Recommendation:**
Either rename the functions to remove the underscore prefix (reflecting their actual public visibility) or make them internal and create separate properly-named public view wrappers. This is inherited from the base contract, so the fix would need to be applied upstream.

---

### [LOW] OA-EW-07: ERC4626WrapperLib.availableAssets assumes assets[1] is the targetVault without validation

**Pipeline:** Archethect (semantic_consistency)
**Confidence:** Medium
**File:** `src/lib/ERC4626WrapperLib.sol:13`

**Description:**
The `availableAssets` function in `ERC4626WrapperLib` retrieves the asset list from the vault via `vault.getAssets()` and then hardcodes the assumption that `assets[1]` is the target ERC4626 vault:

```solidity
if (assets.length > 1) {
    IERC4626 targetERC4626Vault = IERC4626(assets[1]);
    ...
}
```

There is no validation that `assets[1]` actually implements the IERC4626 interface, nor that it is the correct target vault that the hooks are configured to interact with. If the asset list is misconfigured (e.g., assets are reordered, a non-ERC4626 asset is at index 1, or additional assets are added), this function will either revert or return incorrect values.

Furthermore, the code comment says "assumes it's the asset that the withdrawal hooks reference," which confirms this is an unvalidated assumption. The hooks contract stores `targetVault` as an immutable, while the library reads from the vault's dynamic asset list. These two references can become inconsistent if an admin modifies the asset list after deployment.

**Impact:**
If the asset list is misconfigured or modified post-deployment such that `assets[1]` does not correspond to the targetVault used by the hooks, the `availableAssets` calculation will be incorrect. This would cause `maxWithdraw` and `maxRedeem` to return wrong values, potentially allowing users to withdraw more than available (causing reverts) or reporting less available than actually exists (denying legitimate withdrawals).

**Recommendation:**
1. Pass the targetVault address explicitly to `availableAssets` rather than assuming it is at index 1.
2. Alternatively, validate that `assets[1]` matches the hooks' `targetVault` by reading it from the hooks contract.
3. Add a check that the address at `assets[1]` actually implements IERC4626 before calling `convertToAssets` on it.

---

### [LOW] OA-EW-08: SingleAssetProvider returns a fixed immutable rate, causing stale pricing if the underlying asset appreciates or depreciates

**Pipeline:** Forefy (Economic layer) + Archethect (token_oracle_statefulness)
**Confidence:** Medium
**File:** `src/module/SingleAssetProvider.sol:17-23`

**Description:**
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

**Impact:**
If `SingleAssetProvider` is used in a context where the underlying asset's value changes, `totalAssets` and share price calculations will be based on stale data. This could benefit depositors (who get underpriced shares if the asset has appreciated) or redeemers (who get overpriced redemptions if the asset has depreciated), at the expense of the other party.

**Recommendation:**
1. Clearly document that `SingleAssetProvider` should only be used for assets whose value relative to the base denomination is guaranteed to remain constant (e.g., 1:1 pegged stablecoins with the same denomination).
2. For any asset with variable value, use `Provider` which dynamically reads `convertToAssets` from the target vault.

---

### [LOW] OA-EW-09: handleBeforeRedeem and handleAfterDeposit do not handle the case where the targetVault reverts, potentially locking user funds

**Pipeline:** Archethect (callback_liveness)
**Confidence:** Low
**File:** `src/hooks/ERC4626WrapperHooks.sol:93-113, 73-91`

**Description:**
Both `handleBeforeRedeem` and `handleAfterDeposit` call `BaseVault(payable(address(vault))).processor(...)` which executes calls to the `targetVault`. If the `targetVault` is paused, has insufficient liquidity, or reverts for any other reason, the entire processor call reverts, which causes the hook to revert, which causes the parent deposit/redeem/withdraw operation to revert.

For `handleAfterDeposit`, this means a deposit into the wrapper vault will revert entirely if the target vault's `deposit` function reverts. The user cannot deposit even though the wrapper vault itself is functioning correctly.

For `handleBeforeRedeem`, this means a redemption from the wrapper vault will revert if the target vault's `withdraw` function reverts. Users' shares are locked and cannot be redeemed. Note that the silent capping to `maxWithdraw` in `handleBeforeRedeem` partially mitigates this for liquidity constraints, but does not help if the target vault is fully paused or reverts for other reasons.

There is no emergency withdrawal path that bypasses the hooks, meaning a permanently paused or bricked target vault would permanently lock all wrapper vault depositors' funds.

**Impact:**
If the target vault becomes unavailable (paused, self-destructed, or permanently reverting), wrapper vault users cannot deposit or withdraw. Funds are locked until the target vault is restored. Since the hooks are immutable (constructor-set targets), there is no way to update the target vault reference.

**Recommendation:**
1. Consider adding an emergency withdrawal mechanism in the strategy that allows withdrawals to bypass the hooks entirely, usable only by admin or when the target vault is detected as unavailable.
2. Alternatively, wrap the processor calls in try/catch logic (though this would require architectural changes to how processor handles errors).
3. Add a fallback path where, if the targetVault is paused, the hooks allow the withdrawal to proceed using only the idle balance in the wrapper vault.

---

### [INFORMATIONAL] OA-EW-10: Hooks contract uses abi.encodeWithSignature instead of abi.encodeCall, losing compile-time type safety

**Pipeline:** Forefy (Technical layer)
**Confidence:** High
**File:** `src/hooks/ERC4626WrapperHooks.sol:82,87,109-110`

**Description:**
The hooks contract constructs calldata for the processor using `abi.encodeWithSignature` with string-based function signatures:

```solidity
data[0] = abi.encodeWithSignature("approve(address,uint256)", address(targetVault), assets);
data[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, address(vault));
data[0] = abi.encodeWithSignature("withdraw(uint256,address,address)", assets, address(vault), address(vault));
```

Using `abi.encodeWithSignature` with string literals bypasses Solidity's compile-time type checking. If a function signature string is incorrect (typo, wrong parameter types), the error is only caught at runtime. The Solidity compiler introduced `abi.encodeCall` specifically to address this -- it provides compile-time verification of function selectors and parameter types.

**Impact:**
No direct security impact in the current code (the signatures are correct). However, this pattern increases the risk of introducing bugs during future modifications. If a developer changes a parameter type or adds/removes a parameter, the string-based encoding will not produce a compile error.

**Recommendation:**
Replace `abi.encodeWithSignature` calls with `abi.encodeCall` using typed interface references:

```solidity
data[0] = abi.encodeCall(IERC20.approve, (address(targetVault), assets));
data[1] = abi.encodeCall(IERC4626.deposit, (assets, address(vault)));
data[0] = abi.encodeCall(IERC4626.withdraw, (assets, address(vault), address(vault)));
```

Note: This requires the processor to accept `bytes memory` data. If `processor` requires `bytes calldata`, this pattern may need a workaround.

---

### [INFORMATIONAL] OA-EW-11: Provider.getRate performs no sanity check on the value returned by convertToAssets, allowing zero or extreme values

**Pipeline:** Archethect (token_oracle_statefulness)
**Confidence:** Low
**File:** `src/module/Provider.sol:23`

**Description:**
The `Provider.getRate` function returns `IERC4626(vault).convertToAssets(unitValue)` without any bounds checking. If the target vault returns 0 (e.g., when `totalSupply` is 0 and `totalAssets` is 0), or an extremely large value (due to donation attack on the target vault), the Provider propagates this value directly to the wrapper vault's accounting.

A zero rate would cause `processAccounting` to value all target vault shares at zero, potentially triggering accounting guard reverts or dramatically deflating the wrapper vault's share price. An extremely large rate would inflate the share price.

**Impact:**
Low under normal conditions. The `IProcessAccountingGuardHook` provides some protection against extreme rate changes. However, if the guard thresholds are set too loosely, or if the guard hook is not configured, stale or manipulated rates could affect wrapper vault share pricing.

**Recommendation:**
Add minimum and maximum bounds validation in `Provider.getRate`:

```solidity
uint256 rate = IERC4626(vault).convertToAssets(unitValue);
require(rate > 0, "Provider: zero rate");
require(rate <= MAX_REASONABLE_RATE, "Provider: rate too high");
return rate;
```
