# Security Audit Report: yieldnest-vault

## Metadata
- **Repository:** yieldnest-vault
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6
- **Branch:** eth-max-vault-release-candidate
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24
- **Auditor:** Multi-Pipeline Automated Security Analysis

## Audit Scope

| File | LOC | Description |
|------|-----|-------------|
| `src/BaseVault.sol` | 1030 | Core ERC4626 multi-asset vault |
| `src/Vault.sol` | 109 | Concrete vault with linear withdrawal fees |
| `src/Common.sol` | 30 | Import aggregator |
| `src/library/VaultLib.sol` | 459 | Core vault library (storage, conversions, processor) |
| `src/library/HooksLib.sol` | 178 | Hook dispatch library |
| `src/library/LinearWithdrawalFeeLib.sol` | 96 | Fee calculation library |
| `src/module/FeeMath.sol` | 41 | Base fee math (feeOnRaw, feeOnTotal) |
| `src/module/Guard.sol` | 46 | Processor call validation |
| `src/module/Provider.sol` | 128 | Rate oracle provider |
| `src/module/LinearWithdrawalFee.sol` | 83 | Withdrawal fee module |
| `src/strategy/BaseStrategy.sol` | 472 | Base strategy with allocator pattern |
| `src/hooks/FeeHooks.sol` | 232 | Performance fee hook implementation |
| `src/withdraws/BaseWithdrawer.sol` | 78 | Base async withdrawer |
| `src/withdraws/Withdrawer.sol` | 57 | Concrete withdrawer (Origin/Lido/YN) |
| `src/withdraws/library/AsyncWithdrawalLib.sol` | 88 | Async withdrawal accounting |
| `src/withdraws/library/OriginWithdrawalLib.sol` | 152 | Origin Protocol withdrawal handling |
| `src/utils/BaseVaultViewer.sol` | 113 | Vault info viewer |
| `src/utils/MaxVaultViewer.sol` | 122 | Extended vault viewer |
| `src/utils/XReferralAdapter.sol` | 88 | Referral deposit adapter |
| `src/interface/IVault.sol` | 182 | Vault interface |
| `src/interface/IHooks.sol` | 182 | Hooks interface |
| `src/interface/IProvider.sol` | 79 | Provider + external interfaces |
| `src/interface/IBaseStrategy.sol` | 35 | Strategy interface |
| `src/interface/IStrategy.sol` | 21 | Minimal ERC4626 strategy |
| `src/interface/IValidator.sol` | 12 | Processor validator interface |
| `src/interface/IFeeHooks.sol` | 30 | Fee hooks interface |
| `src/interface/IVaultViewer.sol` | 62 | Viewer interface |
| `src/interface/IWithdrawalQueueManager.sol` | 56 | Withdrawal queue manager interface |
| `src/interface/ICurveLpConnector.sol` | 14 | Curve LP connector interface |
| `src/interface/external/lido/IWithdrawalQueue.sol` | 41 | Lido withdrawal queue interface |
| `src/interface/external/origin/IOETHVault.sol` | 32 | Origin OETH vault interface |
| **Total** | **4,348** | **31 files** |

## Methodologies Applied

| Pipeline | Methodology | Findings |
|----------|-------------|----------|
| A | SCV Scan (36 vulnerability pattern matching) | 5 |
| B | Feynman Business Logic Audit | 6 |
| C | State Inconsistency Analysis | 3 |
| D | Pashov Multi-Vector Scan | 4 |
| E | QuillAI Module Analysis | 4 |
| F | Token Integration / ERC4626 Conformance | 4 |
| **Total unique (deduplicated)** | | **14** |

## Executive Summary

The yieldnest-vault codebase implements a multi-asset ERC4626 vault with sophisticated features: multi-asset deposit support with base denomination accounting, a hook system for extensibility, linear withdrawal fees, a processor for arbitrary external calls, and async withdrawal support for protocols like Lido and Origin.

**Overall Risk Posture: MODERATE**

The architecture is generally well-designed with proper use of OpenZeppelin's upgradeable contracts, role-based access control, reentrancy guards, and SafeERC20. The virtual inflation attack is mitigated via the +1 offset pattern. However, several medium and low severity issues were identified, primarily around:

1. State consistency risks between cached and computed total assets
2. Fee function visibility exposing internal functions as public
3. Potential denial-of-service vectors in unbounded loops
4. Storage slot collision risk in MaxVaultViewer
5. Deposit-before-accounting race conditions

No critical vulnerabilities that enable immediate fund theft were found, but several issues could lead to value leakage, DOS conditions, or incorrect accounting under specific conditions.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| YNV-01 | Medium | Deposit front-running via stale cached totalAssets | B, C, D | High |
| YNV-02 | Medium | Public `_feeOnRaw` and `_feeOnTotal` violate interface naming convention and expose internal fee logic | A, F | High |
| YNV-03 | Medium | `processAccounting()` is permissionless and can be sandwiched | B, D | High |
| YNV-04 | Medium | Storage slot collision between MaxVaultViewer and VaultLib AssetStorage | A, C | High |
| YNV-05 | Low | Unbounded loop in async withdrawal balance computation can cause DOS | A, E | High |
| YNV-06 | Low | Guard parameter validation only checks ADDRESS type, skips UINT256 | A, B | High |
| YNV-07 | Low | `previewWithdraw` and `previewRedeem` use `_msgSender()` making them caller-dependent | F | High |
| YNV-08 | Low | No slippage protection on deposit/mint operations | D | Medium |
| YNV-09 | Low | `_withdraw` subtracts base assets using Floor rounding, creating marginal value leakage | B, C | Medium |
| YNV-10 | Low | Provider hardcodes stETH rate as 1e18, ignoring actual stETH/ETH rate | B | High |
| YNV-11 | Low | `OriginWithdrawalLib.oeth.approve` does not use `forceApprove` | A | Medium |
| YNV-12 | Informational | Performance fee uses integer division creating dust loss | B | High |
| YNV-13 | Informational | `convertToShares` rounds `baseAssets` down regardless of rounding parameter | B, F | Medium |
| YNV-14 | Informational | `receive()` accepts arbitrary ETH without accounting update | C | High |

## Detailed Findings

---

### YNV-01: Deposit front-running via stale cached totalAssets

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`, `VaultLib.sol`
**Function(s):** `_deposit()`, `_depositAsset()`, `convertToShares()`, `addTotalAssets()`
**Sources:** Pipeline B, C, D

**Description:**

When `alwaysComputeTotalAssets` is `false` (the default), the vault uses a cached `totalAssets` value for share calculations. The `_deposit` function at BaseVault.sol:547 calls `_addTotalAssets(baseAssets)` which updates the cached total *before* `convertToShares` is called in the deposit flow. However, the critical issue is that the cached `totalAssets` can become stale between `processAccounting()` calls.

If the vault's actual underlying assets appreciate (e.g., stETH or strategy returns), but `processAccounting()` has not been called, the cached total is lower than reality. A savvy user can:
1. Observe that the vault's assets have appreciated.
2. Deposit at the stale (lower) rate, receiving more shares than deserved.
3. Call `processAccounting()` (which is permissionless) to update the cached total.
4. Redeem at the now-correct (higher) rate.

This creates value extraction from existing shareholders.

**Code Reference:**

```solidity
// VaultLib.sol:304-312
function convertToShares(address asset_, uint256 assets, Math.Rounding rounding)
    public view returns (uint256 shares, uint256 baseAssets)
{
    uint256 totalAssets = IVault(address(this)).totalBaseAssets(); // uses cached value
    uint256 totalSupply = getERC20Storage().totalSupply;
    baseAssets = convertAssetToBase(asset_, assets, rounding);
    shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
}
```

```solidity
// VaultLib.sol:253-259
function addTotalAssets(uint256 baseAssets) public {
    IVault.VaultStorage storage vaultStorage = getVaultStorage();
    if (!vaultStorage.alwaysComputeTotalAssets) {
        uint256 previousTotal = vaultStorage.totalAssets;
        vaultStorage.totalAssets = previousTotal + baseAssets;
    }
}
```

**Impact:** Value leakage from existing shareholders to depositors who exploit stale accounting. The magnitude depends on the frequency of `processAccounting()` calls and rate of yield accrual.

**Recommendation:**
1. Restrict `processAccounting()` to a trusted role, or
2. Automatically call `processAccounting()` before deposits when the cached total is sufficiently stale (e.g., timestamp-based staleness check), or
3. Use `alwaysComputeTotalAssets = true` for production deployments (accepting the gas cost), or
4. Add a minimum time delay or access control to `processAccounting()` to prevent sandwich attacks.

---

### YNV-02: Public `_feeOnRaw` and `_feeOnTotal` violate naming convention and expose internal fee logic

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`, `Vault.sol`, `BaseWithdrawer.sol`, `IVault.sol`
**Function(s):** `_feeOnRaw()`, `_feeOnTotal()`
**Sources:** Pipeline A, F

**Description:**

The functions `_feeOnRaw` and `_feeOnTotal` are declared as `public` in `BaseVault.sol` (lines 1021-1029) and exposed in the `IVault.sol` interface (lines 180-181). By Solidity convention, underscore-prefixed functions should be `internal` or `private`. Making them `public` means:

1. They are part of the external ABI and callable by anyone.
2. They are declared in the interface, creating a permanent API commitment.
3. In `BaseWithdrawer.sol` (lines 39-48), they return `0` as `pure` functions, which could confuse integrators relying on the interface to determine withdrawal fees.

More importantly, `previewWithdraw` and `previewRedeem` in `BaseVault.sol` call these functions with `_msgSender()` as the user parameter, meaning the public interface functions return fee amounts for the *caller* rather than for an arbitrary user. External contracts calling `_feeOnRaw` directly get the correct per-user fee, but the preview functions do not allow specifying the user.

**Code Reference:**

```solidity
// BaseVault.sol:1021-1029
function _feeOnRaw(uint256 amount, address user) public view virtual override returns (uint256);
function _feeOnTotal(uint256 amount, address user) public view virtual override returns (uint256);
```

```solidity
// IVault.sol:180-181
function _feeOnRaw(uint256 amount, address user) external view returns (uint256);
function _feeOnTotal(uint256 amount, address user) external view returns (uint256);
```

**Impact:** Naming convention violation that creates confusion. The public fee functions could be misused by integrators. Not a direct fund loss, but affects integration correctness and code maintainability.

**Recommendation:** Rename to `feeOnRaw` and `feeOnTotal` (without underscore prefix) in both the interface and implementations to follow Solidity naming conventions for public functions.

---

### YNV-03: `processAccounting()` is permissionless and can be sandwiched

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`, `VaultLib.sol`, `FeeHooks.sol`
**Function(s):** `processAccounting()`, `afterProcessAccounting()`
**Sources:** Pipeline B, D

**Description:**

`processAccounting()` in `BaseVault.sol:933` is callable by anyone (`public virtual nonReentrant`). This has two implications:

1. **Sandwich Attack on Performance Fees:** When `FeeHooks` is active, `processAccounting()` triggers performance fee calculation and share minting. An attacker can:
   - Observe that yield has accrued.
   - Deposit a large amount (diluting their fee exposure).
   - Call `processAccounting()` to trigger fee collection.
   - Redeem immediately.

   The attacker dilutes the performance fee impact on their shares while extracting full yield.

2. **Griefing by frequent calls:** Anyone can call `processAccounting()` repeatedly. If the hook contract performs gas-intensive operations, this could be used to waste gas or trigger unexpected state changes.

**Code Reference:**

```solidity
// BaseVault.sol:933-935
function processAccounting() public virtual nonReentrant {
    _processAccounting();
}
```

```solidity
// VaultLib.sol:394-432 - processAccounting updates cached totalAssets and calls hooks
```

**Impact:** Performance fee dilution for the fee recipient. Potential sandwich attacks around accounting updates. Griefing vector.

**Recommendation:** Add an access control modifier (e.g., `onlyRole(PROCESSOR_ROLE)`) to `processAccounting()`, or implement a minimum time interval between calls, or add a dead-time around deposits/withdrawals where accounting cannot be processed.

---

### YNV-04: Storage slot collision between MaxVaultViewer and VaultLib AssetStorage

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `MaxVaultViewer.sol`, `VaultLib.sol`
**Function(s):** `_getAssetStorage()`
**Sources:** Pipeline A, C

**Description:**

`MaxVaultViewer.sol` (line 63) defines a `_getAssetStorage()` function that uses the exact same storage slot as `VaultLib.getAssetStorage()`:

```solidity
// MaxVaultViewer.sol:61-66
function _getAssetStorage() internal pure returns (AssetStorage storage $) {
    assembly {
        // keccak256("yieldnest.storage.asset")
        $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
    }
}
```

```solidity
// VaultLib.sol:49-53
function getAssetStorage() public pure returns (IVault.AssetStorage storage $) {
    assembly {
        // keccak256("yieldnest.storage.asset")
        $.slot := 0x2dd192a2474c87efcf5ffda906a4b4f8a678b0e41f9245666251cfed8041e680
    }
}
```

However, the storage structs are **different types**:
- `VaultLib.AssetStorage`: `{ mapping(address => AssetParams) assets; address[] list; }`
- `MaxVaultViewer.AssetStorage`: `{ mapping(address => bool) underlyingAssets; uint256 underlyingAssetsLength; }`

If `MaxVaultViewer` is deployed behind a proxy that was previously a Vault, or if the viewer is ever co-located with vault storage (e.g., via delegatecall or proxy migration), the different struct layouts at the same slot would cause data corruption.

Currently `MaxVaultViewer` is a separate upgradeable contract (with its own proxy), so this is a latent risk rather than an active exploit. But the identical slot comment string `"yieldnest.storage.asset"` with different struct shapes is a maintenance hazard.

**Code Reference:** `MaxVaultViewer.sol:61-66` and `VaultLib.sol:49-53`

**Impact:** Latent storage collision risk. If MaxVaultViewer is ever deployed behind a proxy that shares storage with a vault, data corruption could occur. Currently mitigated by separate deployment, but a dangerous maintenance trap.

**Recommendation:** Use a unique storage slot for `MaxVaultViewer`, e.g., `keccak256("yieldnest.storage.maxvaultviewer.asset")`.

---

### YNV-05: Unbounded loop in async withdrawal balance computation can cause DOS

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `AsyncWithdrawalLib.sol`, `OriginWithdrawalLib.sol`
**Function(s):** `_asyncWithdrawalBalanceYNAsset()`, `_asyncWithdrawalBalanceWSTETH()`, `_asyncWithdrawalBalanceWOETH()`
**Sources:** Pipeline A, E

**Description:**

Several functions iterate over unbounded arrays to compute async withdrawal balances:

1. `_asyncWithdrawalBalanceYNAsset()` (AsyncWithdrawalLib.sol:39): iterates `requests.length` from `withdrawalRequestsForOwner`.
2. `_asyncWithdrawalBalanceWSTETH()` (AsyncWithdrawalLib.sol:58): iterates `requestIds` from `getWithdrawalRequests`.
3. `_asyncWithdrawalBalanceWOETH()` (OriginWithdrawalLib.sol:146): iterates `requestIds.length`.

These are called from `computeTotalAssets()` which is called from `processAccounting()` and, if `alwaysComputeTotalAssets` is true, from every share conversion. If the number of pending withdrawal requests grows large, these functions could exceed the block gas limit, effectively bricking `processAccounting()` and potentially all deposit/withdrawal operations.

**Code Reference:**

```solidity
// AsyncWithdrawalLib.sol:39-47
for (uint256 i = 0; i < requests.length; i++) {
    if (!requests[i].processed) {
        uint256 baseAmount = requests[i].amount * requests[i].redemptionRateAtRequestTime / decimals;
        uint256 fee = baseAmount * requests[i].feeAtRequestTime / 1000000;
        baseAssets += baseAmount - fee;
    }
}
```

**Impact:** Denial of service on `processAccounting()` and potentially on all vault operations if `alwaysComputeTotalAssets` is enabled.

**Recommendation:** Implement batched processing or maintain a running total of pending async withdrawals that gets updated incrementally instead of recomputed from scratch each time.

---

### YNV-06: Guard parameter validation only checks ADDRESS type, skips UINT256

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `Guard.sol`
**Function(s):** `validateCall()`
**Sources:** Pipeline A, B

**Description:**

The `Guard.validateCall()` function (Guard.sol:22-29) iterates over parameter rules but only validates `ParamType.ADDRESS` types. Parameters of type `ParamType.UINT256` are silently skipped with no validation:

```solidity
for (uint256 i = 0; i < rule.paramRules.length; i++) {
    if (rule.paramRules[i].paramType == IVault.ParamType.ADDRESS) {
        address addressValue = abi.decode(data[4 + i * 32:], (address));
        _validateAddress(addressValue, rule.paramRules[i]);
        continue;
    }
    // UINT256 parameters fall through with no validation
}
```

If an administrator configures a processor rule with `ParamType.UINT256` expecting it to be validated, it will be silently ignored, potentially allowing unauthorized parameter values.

**Code Reference:** `Guard.sol:22-29`

**Impact:** Processor calls with UINT256 parameters cannot be validated by the Guard. This reduces the security of the processor system, though the PROCESSOR_ROLE itself is permissioned.

**Recommendation:** Either implement UINT256 validation (e.g., min/max range checks) or explicitly revert if a UINT256 param rule is configured, making it clear that only ADDRESS validation is supported.

---

### YNV-07: `previewWithdraw` and `previewRedeem` use `_msgSender()` making them caller-dependent

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`, `BaseStrategy.sol`
**Function(s):** `previewWithdraw()`, `previewRedeem()`, `previewRedeemAsset()`, `previewWithdrawAsset()`
**Sources:** Pipeline F

**Description:**

Per EIP-4626, `previewWithdraw` and `previewRedeem` should return values independent of the caller. However, these functions call `_feeOnRaw` and `_feeOnTotal` with `_msgSender()` as the user parameter:

```solidity
// BaseVault.sol:197-199
function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
    uint256 fee = _feeOnRaw(assets, _msgSender());
    (shares,) = _convertToShares(asset(), assets + fee, Math.Rounding.Ceil);
}
```

Since withdrawal fees can be overridden per-user via `overrideBaseWithdrawalFee()`, different callers get different preview results for the same input. This violates the ERC4626 spec which states these preview functions MUST be inclusive of any fees and MUST NOT revert, but does not mandate caller-independence. However, the practical effect is:

- Off-chain integrators calling these functions from different addresses get different results.
- Smart contract routers that call preview functions will get results based on the router's fee tier, not the actual user's.

**Code Reference:** `BaseVault.sol:196-209`, `BaseStrategy.sol:191-205`

**Impact:** ERC4626 preview functions return caller-specific results due to per-user fee overrides, potentially causing integration issues for smart contract routers and aggregators.

**Recommendation:** Document this behavior clearly. Consider adding alternative preview functions that accept a user address parameter for integrators.

---

### YNV-08: No slippage protection on deposit/mint operations

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `deposit()`, `mint()`, `depositAsset()`
**Sources:** Pipeline D

**Description:**

The `deposit`, `mint`, and `depositAsset` functions do not have minimum shares/maximum assets parameters for slippage protection. While the standard ERC4626 functions (`deposit(assets, receiver)` and `mint(shares, receiver)`) follow the spec which does not include slippage parameters, the extended `depositAsset` function could have included them.

In a multi-asset vault where rates are fetched from external providers, a change in the provider rate between transaction submission and execution could result in a user receiving significantly fewer shares than expected.

**Code Reference:** `BaseVault.sol:280-316`, `BaseVault.sol:481-492`

**Impact:** Users may receive fewer shares than expected if rates change between transaction submission and execution. Particularly relevant for multi-asset deposits where rate providers can return different values.

**Recommendation:** Consider adding `minSharesOut` parameters to deposit functions, especially `depositAsset`. Alternatively, document that users should use the preview functions to set appropriate gas price / deadline for transactions.

---

### YNV-09: `_withdraw` subtracts base assets using Floor rounding, creating marginal value leakage

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `_withdraw()`, `_withdrawAsset()`
**Sources:** Pipeline B, C

**Description:**

In `_withdraw()` (BaseVault.sol:591) and `_withdrawAsset()` (BaseVault.sol:652), the base assets to subtract from `totalAssets` are calculated with `Math.Rounding.Floor`:

```solidity
_subTotalAssets(_convertAssetToBase(asset(), assets, Math.Rounding.Floor));
```

The comment at line 589-590 acknowledges this: "baseAssets is rounded down to error on the side of undercounting the removed assets. Rate may increase as a result of the rounding."

While this rounds in favor of the vault (fewer base assets subtracted = higher apparent vault value), the discrepancy accumulates over many withdrawals, causing `totalAssets` to gradually drift upward from the actual value. This means the cached `totalAssets` becomes increasingly inaccurate until `processAccounting()` corrects it.

**Code Reference:** `BaseVault.sol:589-591`, `BaseVault.sol:650-652`

**Impact:** Gradual upward drift in cached `totalAssets` between accounting updates. Over many withdrawals, this could cause share prices to be slightly inflated, benefiting withdrawing users at the expense of remaining holders. Mitigated by regular `processAccounting()` calls.

**Recommendation:** This is an intentional design choice favoring the vault. Ensure `processAccounting()` is called regularly to reset the drift. Consider documenting the expected drift rate.

---

### YNV-10: Provider hardcodes stETH and OETH rate as 1e18

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `Provider.sol`
**Function(s):** `getRate()`
**Sources:** Pipeline B

**Description:**

The Provider contract hardcodes the rate for stETH and OETH as `1e18` (lines 50-56):

```solidity
if (asset == MC.STETH) {
    return 1e18;
}

if (asset == MC.OETH) {
    return 1e18;
}
```

stETH is a rebasing token that maintains a slightly different exchange rate than ETH in practice (often trading at a 0.1-0.5% discount on secondary markets). OETH similarly may not always be exactly 1:1 with ETH. Hardcoding 1e18 means:

- stETH depositors get treated as if 1 stETH = 1 ETH, which is approximately correct but not exact.
- If stETH depegs (as happened in June 2022), the vault would overvalue stETH deposits.

**Code Reference:** `Provider.sol:50-56`

**Impact:** Minor mispricing of stETH and OETH assets. During a depeg event, this could allow arbitrage against the vault.

**Recommendation:** Consider using a Chainlink stETH/ETH oracle or the Lido protocol's rate for more accurate pricing. At minimum, document the assumption and the risk of depeg events.

---

### YNV-11: `OriginWithdrawalLib` uses `approve` instead of `forceApprove` for OETH

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `OriginWithdrawalLib.sol`
**Function(s):** `_requestWithdrawalOETH()`
**Sources:** Pipeline A

**Description:**

In `_requestWithdrawalOETH()` (OriginWithdrawalLib.sol:114), the function uses `oeth.approve(address(oethVault), amount)` directly on the IERC20 interface rather than using `SafeERC20.forceApprove()`:

```solidity
oeth.approve(address(oethVault), amount);
```

While OETH is a known token that likely implements standard `approve` correctly, this pattern is inconsistent with the rest of the codebase which uses SafeERC20 throughout. If there is any residual allowance from a previous call, some tokens (like USDT) would revert on `approve` to a non-zero value when the current allowance is also non-zero. While OETH is not USDT, using `forceApprove` is a defensive best practice.

**Code Reference:** `OriginWithdrawalLib.sol:114`

**Impact:** Low. If OETH ever changes its approve behavior or if the pattern is copied for other tokens, it could cause reverts.

**Recommendation:** Use `SafeERC20.forceApprove(oeth, address(oethVault), amount)` for consistency and defensive coding.

---

### YNV-12: Performance fee uses integer division creating dust loss

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `FeeHooks.sol`
**Function(s):** `afterProcessAccounting()`
**Sources:** Pipeline B

**Description:**

The performance fee calculation at FeeHooks.sol:98 uses standard integer division:

```solidity
uint256 feesAccruedInBaseAsset = (yieldEarnedInBaseAsset * performanceFee) / FEE_DENOMINATOR;
```

This floors the fee amount, meaning small amounts of yield are not captured as fees. This is correct behavior (favoring vault holders over the fee recipient), but worth noting that dust amounts of yield will never generate fees.

The share minting calculation at line 109-112 uses `Math.Rounding.Floor`, which is also correct (fewer fee shares minted = better for vault holders).

**Code Reference:** `FeeHooks.sol:96-113`

**Impact:** Negligible. Dust amounts of yield escape fee collection. This is the correct economic direction (favoring vault holders).

**Recommendation:** No action needed. This is correct behavior.

---

### YNV-13: `convertToShares` always rounds `baseAssets` down regardless of rounding parameter

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `VaultLib.sol`
**Function(s):** `convertToShares()`
**Sources:** Pipeline B, F

**Description:**

In `VaultLib.convertToShares()` (line 311), the `baseAssets` conversion passes the `rounding` parameter to `convertAssetToBase`, but the `@dev` comment in `BaseVault.sol:684` states "baseAssets is always rounded down, ignoring the rounding parameter."

Looking at the actual code:
```solidity
function convertToShares(address asset_, uint256 assets, Math.Rounding rounding)
    public view returns (uint256 shares, uint256 baseAssets)
{
    uint256 totalAssets = IVault(address(this)).totalBaseAssets();
    uint256 totalSupply = getERC20Storage().totalSupply;
    baseAssets = convertAssetToBase(asset_, assets, rounding);  // uses rounding param
    shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
}
```

The code actually does pass `rounding` to `convertAssetToBase`, contradicting the `@dev` comment. For `mint()` which uses `Rounding.Ceil` on `convertToAssets`, this is fine. But for `_depositAsset` which uses `Rounding.Floor`, the comment and code are consistent. The discrepancy is in the documentation, not the code.

**Code Reference:** `VaultLib.sol:304-313`, `BaseVault.sol:684`

**Impact:** Documentation inconsistency. The code behavior appears correct for all call sites.

**Recommendation:** Update the `@dev` comment in `BaseVault.sol:684` to reflect the actual behavior.

---

### YNV-14: `receive()` accepts arbitrary ETH without accounting update

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `receive()`
**Sources:** Pipeline C

**Description:**

The `receive()` function at BaseVault.sol:1010-1012 accepts ETH and emits an event, but does not update the cached `totalAssets`:

```solidity
receive() external payable {
    emit NativeDeposit(msg.value);
}
```

When `countNativeAsset` is true, the vault's `computeTotalAssets()` includes `address(this).balance`. However, the cached `totalAssets` is not updated when ETH is received. This means:

- If `alwaysComputeTotalAssets = false`: The cached total is lower than reality until `processAccounting()` is called.
- If `alwaysComputeTotalAssets = true`: No issue, as `computeTotalAssets()` is called for every operation.

No shares are minted for the ETH received, so this ETH effectively accrues as yield to existing shareholders (after `processAccounting()`). While this may be the intended behavior for handling native ETH rewards, it creates a window of stale accounting.

**Code Reference:** `BaseVault.sol:1010-1012`

**Impact:** Temporary accounting staleness when ETH is received and `countNativeAsset` is true with cached mode. Not a loss of funds since the ETH accrues to shareholders.

**Recommendation:** Document that `processAccounting()` should be called after significant ETH deposits. Alternatively, update cached total in the `receive()` function.

---

## Informational Notes

### Architecture Observations

1. **Reentrancy Protection:** The vault properly uses OpenZeppelin's `ReentrancyGuardUpgradeable` on all external state-modifying functions (`deposit`, `mint`, `withdraw`, `redeem`, `depositAsset`, `processAccounting`). The hook system calls external contracts but is protected by the reentrancy guard on the parent function.

2. **ERC4626 Virtual Inflation Attack Mitigation:** The vault uses the `+1` offset pattern in share/asset conversions (`totalSupply + 1`, `totalAssets + 1`), which mitigates the classic first-depositor inflation attack. This is a well-known mitigation.

3. **Role-Based Access Control:** The vault implements a comprehensive role system (PROCESSOR_ROLE, PAUSER_ROLE, UNPAUSER_ROLE, PROVIDER_MANAGER_ROLE, BUFFER_MANAGER_ROLE, ASSET_MANAGER_ROLE, PROCESSOR_MANAGER_ROLE, HOOKS_MANAGER_ROLE, ASSET_WITHDRAWER_ROLE). This is well-designed but requires proper role assignment during deployment.

4. **Upgradeable Pattern:** The contracts use OpenZeppelin's transparent proxy upgrade pattern with `_disableInitializers()` in constructors, which is correct.

5. **Hook System Design:** The hook system is well-designed with per-operation enable/disable flags and a VAULT immutable to prevent cross-vault hook attacks. The `setHooks` function correctly validates that `IHooks(hooks_).VAULT() == address(this)`.

6. **Processor System:** The `processor()` function allows the PROCESSOR_ROLE to make arbitrary external calls from the vault, gated by the Guard system. This is a powerful feature that requires careful rule configuration. The Guard validation includes allow-list checking for address parameters.

7. **Fee System:** The fee system correctly rounds up (ceiling) when calculating fees, which favors the vault over the user. The `BASIS_POINT_SCALE` of 1e8 provides 6 decimal places of fee precision.

### Best Practices Noted

- Consistent use of `SafeERC20` for token transfers (except the one `approve` noted in YNV-11).
- Proper event emission for all state changes.
- Storage layout uses ERC-7201 namespaced storage pattern for upgrade safety.
- Initialization functions properly use the `initializer` modifier.
- The vault starts paused by default, requiring explicit unpause after configuration.
- `unpause()` requires the provider to be set, preventing operation without a rate source.

### Gas Optimization Observations

- `computeTotalAssets()` iterates all assets and calls the provider for each one. With many assets, this becomes expensive. The cached mode (`alwaysComputeTotalAssets = false`) appropriately mitigates this.
- The `Guard._isInArray` function uses a linear search. For large allow-lists, this could be gas-intensive. Consider using a mapping for O(1) lookups if allow-lists grow large.
- `HooksLib` functions make external calls to check `getConfig()` before each hook call. This adds ~2600 gas per hook check even when hooks are disabled. Consider caching the config or using a bitmap pattern.
