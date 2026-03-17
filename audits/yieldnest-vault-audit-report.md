# Security Audit Report: yieldnest-vault

## Metadata
- **Repository:** yieldnest-vault
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6
- **Branch:** eth-max-vault-release-candidate
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24
- **Auditor:** Multi-Pipeline Automated Security Analysis
- **Additional Pipelines:** Forefy + Archethect (OpenAudit), Auditmos DeFi Checklists

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

## Tools & Methodologies Applied

| Pipeline | Methodology | Findings |
|----------|-------------|----------|
| A | SCV Scan (36 vulnerability pattern matching) | 5 |
| B | Feynman Business Logic Audit | 6 |
| C | State Inconsistency Analysis | 3 |
| D | Pashov Multi-Vector Scan | 4 |
| E | QuillAI Module Analysis | 4 |
| F | Token Integration / ERC4626 Conformance | 4 |
| G | Forefy + Archethect | Protocol-specific 5-layer audit + SETUP-MAP-HUNT-ATTACK methodology |
| H | Auditmos DeFi Checklists | 14 DeFi-specific vulnerability checklists (staking, slippage, math precision, etc.) |
| **Total unique (deduplicated)** | | **31** |

## Executive Summary

The yieldnest-vault codebase implements a multi-asset ERC4626 vault with sophisticated features: multi-asset deposit support with base denomination accounting, a hook system for extensibility, linear withdrawal fees, a processor for arbitrary external calls, and async withdrawal support for protocols like Lido and Origin.

**Overall Risk Posture: MODERATE**

The architecture is generally well-designed with proper use of OpenZeppelin's upgradeable contracts, role-based access control, reentrancy guards, and SafeERC20. The virtual inflation attack is mitigated via the +1 offset pattern. However, several medium and low severity issues were identified, primarily around:

1. State consistency risks between cached and computed total assets
2. Fee function visibility exposing internal functions as public
3. Potential denial-of-service vectors in unbounded loops
4. Storage slot collision risk in MaxVaultViewer
5. Deposit-before-accounting race conditions
6. Privileged withdrawal path bypassing fee mechanism
7. Provider rate oracle susceptibility to spot price manipulation
8. Read-only reentrancy vectors through the hooks system
9. Fee-on-transfer token and zero-share deposit accounting risks
10. Deep external call chains during accounting creating manipulation surfaces

No critical vulnerabilities that enable immediate fund theft were found, but several issues could lead to value leakage, DOS conditions, or incorrect accounting under specific conditions.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| YNV-01 | Medium | Deposit front-running via stale cached totalAssets | B, C, D | High |
| YNV-02 | Medium | Public `_feeOnRaw` and `_feeOnTotal` violate interface naming convention and expose internal fee logic | A, F | High |
| YNV-03 | Medium | `processAccounting()` is permissionless and can be sandwiched | B, D | High |
| YNV-04 | Medium | Storage slot collision between MaxVaultViewer and VaultLib AssetStorage | A, C | High |
| YNV-05 | Low | Unbounded loop in async withdrawal balance computation can cause DOS | A, E, G | High |
| YNV-06 | Low | Guard parameter validation only checks ADDRESS type, skips UINT256 | A, B, G, H | High |
| YNV-07 | Low | `previewWithdraw` and `previewRedeem` use `_msgSender()` making them caller-dependent | F | High |
| YNV-08 | Low | No slippage protection on deposit/mint operations | D, H | Medium |
| YNV-09 | Low | `_withdraw` subtracts base assets using Floor rounding, creating marginal value leakage | B, C | Medium |
| YNV-10 | Low | Provider hardcodes stETH rate as 1e18, ignoring actual stETH/ETH rate | B | High |
| YNV-11 | Low | `OriginWithdrawalLib.oeth.approve` does not use `forceApprove` | A, G, H | Medium |
| YNV-12 | Informational | Performance fee uses integer division creating dust loss | B | High |
| YNV-13 | Informational | `convertToShares` rounds `baseAssets` down regardless of rounding parameter | B, F | Medium |
| YNV-14 | Informational | `receive()` accepts arbitrary ETH without accounting update | C, G | High |
| YNV-15 | High | Withdrawal fee not applied in `withdrawAsset` (ASSET_WITHDRAWER_ROLE path) | G | High |
| YNV-16 | High | Provider.getRate uses spot prices without staleness or manipulation checks | G, H | High |
| YNV-17 | Medium | FeeHooks performance fee minting uses stale totalSupply snapshot, allowing fee dilution | G, H | Medium |
| YNV-18 | Medium | `_deposit` adds to totalAssets before token transfer, creating brief accounting inflation window | G | Medium |
| YNV-19 | Medium | `processAccounting` deep external call chain creates manipulation surface | G | Medium |
| YNV-20 | Low | `BaseVault.hasAsset` reverts when asset list is empty instead of returning false | G | High |
| YNV-21 | Low | `VaultLib.addAsset` duplicate check has subtle gap after asset deletion | G | Medium |
| YNV-22 | Low | `MaxVaultViewer.getStrategies` reverts instead of returning empty array | G | High |
| YNV-23 | Low | `AsyncWithdrawalLib` uses hardcoded fee denominator inconsistent with FeeStorage | G | Medium |
| YNV-24 | Low | `OriginWithdrawalLib._removeRequestId` linear search creates O(n) gas cost per claim | G | Medium |
| YNV-25 | Low | `XReferralAdapter` does not validate that asset is supported by target vault | G | Medium |
| YNV-26 | Informational | `VaultLib` storage slot comment mismatch for ProcessorStorage | G | High |
| YNV-27 | Medium | Hooks system allows arbitrary external calls during state transitions (read-only reentrancy) | H | Medium |
| YNV-28 | Medium | Fee-on-transfer tokens break vault accounting | H | Medium |
| YNV-29 | Medium | Zero-share deposits inflate totalAssets without minting shares | H | Medium |
| YNV-30 | Low | `processor()` missing array length validation | H | Medium |
| YNV-31 | Informational | Withdrawal fee can be set to 100% via `overrideBaseWithdrawalFee` | H | Medium |

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
**Affected Contract(s):** `AsyncWithdrawalLib.sol`, `OriginWithdrawalLib.sol`, `Guard.sol`, `VaultLib.sol`
**Function(s):** `_asyncWithdrawalBalanceYNAsset()`, `_asyncWithdrawalBalanceWSTETH()`, `_asyncWithdrawalBalanceWOETH()`, `_isInArray()`, `computeTotalAssets()`
**Sources:** Pipeline A, E, G

**Description:**

Several functions iterate over unbounded arrays to compute async withdrawal balances:

1. `_asyncWithdrawalBalanceYNAsset()` (AsyncWithdrawalLib.sol:39): iterates `requests.length` from `withdrawalRequestsForOwner`.
2. `_asyncWithdrawalBalanceWSTETH()` (AsyncWithdrawalLib.sol:58): iterates `requestIds` from `getWithdrawalRequests`.
3. `_asyncWithdrawalBalanceWOETH()` (OriginWithdrawalLib.sol:146): iterates `requestIds.length`.

Additionally, `Guard._isInArray` uses a linear search over an unbounded storage array for each processor call parameter, and `VaultLib.computeTotalAssets` iterates over all registered assets with external calls to `balanceOf` and `getRate` per iteration.

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

```solidity
// Guard.sol:35-42
function _isInArray(address value, address[] storage array) private view returns (bool) {
    for (uint256 i = 0; i < array.length; i++) {
        if (array[i] == value) return true;
    }
    return false;
}
```

```solidity
// VaultLib.sol:374-389
for (uint256 i = 0; i < assetListLength; i++) {
    uint256 balance = IERC20(assetList[i]).balanceOf(address(this));
    if (balance == 0) continue;
    totalBaseBalance += convertAssetToBase(assetList[i], balance, Math.Rounding.Floor);
}
```

**Impact:** Denial of service on `processAccounting()` and potentially on all vault operations if `alwaysComputeTotalAssets` is enabled. A growing asset list or allowlist can also cause gas costs to exceed block limits for `processor()` calls.

**Recommendation:**
1. Implement batched processing or maintain a running total of pending async withdrawals that gets updated incrementally instead of recomputed from scratch each time.
2. Enforce a maximum length for the asset list (e.g., `MAX_ASSETS = 20`) to bound the gas cost of `computeTotalAssets`.
3. Consider using a mapping-based lookup for Guard address validation instead of linear array search.

---

### YNV-06: Guard parameter validation only checks ADDRESS type, skips UINT256

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `Guard.sol`
**Function(s):** `validateCall()`
**Sources:** Pipeline A, B, G, H

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

If an administrator configures a processor rule with `ParamType.UINT256` expecting it to be validated, it will be silently ignored, potentially allowing unauthorized parameter values. A compromised or malicious PROCESSOR_ROLE account could bypass intended parameter constraints on uint256 values (e.g., transfer amounts, exchange rates, slippage bounds). Custom `IValidator` implementations can still validate any parameter type when set on a rule.

**Code Reference:** `Guard.sol:22-29`

**Impact:** Processor calls with UINT256 parameters cannot be validated by the Guard. This reduces the security of the processor system, though the PROCESSOR_ROLE itself is permissioned.

**Recommendation:** Either implement UINT256 validation (e.g., min/max range checks) or explicitly revert if a UINT256 param rule is configured, making it clear that only ADDRESS validation is supported. Remove `UINT256` from the `ParamType` enum if validation is not planned.

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
**Sources:** Pipeline D, H

**Description:**

The `deposit`, `mint`, and `depositAsset` functions do not have minimum shares/maximum assets parameters for slippage protection. While the standard ERC4626 functions (`deposit(assets, receiver)` and `mint(shares, receiver)`) follow the spec which does not include slippage parameters, the extended `depositAsset` function could have included them.

In a multi-asset vault where rates are fetched from external providers, a change in the provider rate between transaction submission and execution could result in a user receiving significantly fewer shares than expected. Additionally, none of these functions accept a `deadline` parameter -- pending transactions in the mempool can be executed at any future block when the share price may have changed significantly. The cached `totalAssets` design mitigates some sandwich risks but does not fully protect against delayed execution.

**Code Reference:** `BaseVault.sol:280-316`, `BaseVault.sol:481-492`

**Impact:** Users may receive fewer shares than expected if rates change between transaction submission and execution. Particularly relevant for multi-asset deposits where rate providers can return different values.

**Recommendation:** Consider adding `minSharesOut` and optional `deadline` parameters to deposit functions, especially `depositAsset`. Alternatively, document that users should use the preview functions to set appropriate gas price / deadline for transactions.

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
**Sources:** Pipeline A, G, H

**Description:**

In `_requestWithdrawalOETH()` (OriginWithdrawalLib.sol:114), the function uses `oeth.approve(address(oethVault), amount)` directly on the IERC20 interface rather than using `SafeERC20.forceApprove()`:

```solidity
oeth.approve(address(oethVault), amount);
```

While OETH is a known token that likely implements standard `approve` correctly, this pattern is inconsistent with the rest of the codebase which uses SafeERC20 throughout. If there is any residual allowance from a previous call, some tokens (like USDT) would revert on `approve` to a non-zero value when the current allowance is also non-zero. While OETH is not USDT, using `forceApprove` is a defensive best practice. Additionally, if `requestWithdrawal` does not consume the full amount, a residual allowance remains on the OETHVault, creating unnecessary exposure.

**Code Reference:** `OriginWithdrawalLib.sol:114`

**Impact:** Low. If OETH ever changes its approve behavior or if the pattern is copied for other tokens, it could cause reverts. Residual allowance could be exploited if the OETHVault contract is upgraded maliciously.

**Recommendation:** Use `SafeERC20.forceApprove(oeth, address(oethVault), amount)` for consistency and defensive coding. Consider resetting the approval to zero after the withdrawal request is made.

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
**Sources:** Pipeline C, G

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

No shares are minted for the ETH received, so this ETH effectively accrues as yield to existing shareholders (after `processAccounting()`). While this may be the intended behavior for handling native ETH rewards, it creates a window of stale accounting. ETH sent directly to the vault inflates the computed total assets without minting any shares; the next `processAccounting()` call will include this balance, effectively distributing the donated ETH value to all existing shareholders.

**Code Reference:** `BaseVault.sol:1010-1012`

**Impact:** Temporary accounting staleness when ETH is received and `countNativeAsset` is true with cached mode. Not a loss of funds since the ETH accrues to shareholders. Consider whether the `receive()` function should be restricted to only accept ETH from known sources.

**Recommendation:** Document that `processAccounting()` should be called after significant ETH deposits. Alternatively, update cached total in the `receive()` function or restrict the `receive()` function to known sources (e.g., buffer or processor).

---

### YNV-15: Withdrawal fee not applied in `withdrawAsset` (ASSET_WITHDRAWER_ROLE path)

**Severity:** High
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `withdrawAsset()`
**Sources:** Pipeline G

**Description:**

The `withdrawAsset` function on BaseVault, callable by accounts with `ASSET_WITHDRAWER_ROLE`, converts assets to shares using `_convertToShares` with `Rounding.Ceil` but does NOT apply the withdrawal fee. Compare with the standard `withdraw()` path which calls `previewWithdraw()` that adds the fee:

```solidity
// Standard withdraw path - includes fee
function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
    uint256 fee = _feeOnRaw(assets, _msgSender());
    (shares,) = _convertToShares(asset(), assets + fee, Math.Rounding.Ceil);
}

// withdrawAsset path - NO fee
function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
    public virtual onlyRole(ASSET_WITHDRAWER_ROLE) returns (uint256 shares) {
    // ...
    (shares,) = _convertToShares(asset_, assets, Math.Rounding.Ceil);  // No fee!
    // ...
}
```

The `_withdrawAsset` internal function subsequently called also does not apply any fee calculation. This creates an asymmetry: the ASSET_WITHDRAWER_ROLE can withdraw assets from any owner without paying the withdrawal fee that normal users must pay.

**Code Reference:** `BaseVault.sol:613-629`

**Impact:** An entity with ASSET_WITHDRAWER_ROLE can perform fee-free withdrawals. If this role is granted to a contract or entity that processes withdrawals on behalf of users, the protocol misses fee revenue. More critically, this creates an economic asymmetry where certain withdrawal paths bypass the fee mechanism entirely. If a user's shares are redeemed through this path, fewer shares are burned (no fee overhead), effectively leaking value from the vault to the benefit of the withdrawer.

**Recommendation:** Apply withdrawal fee calculation in the `withdrawAsset` function, or document this as an intentional design decision for privileged withdrawal processing. If intentional, ensure the ASSET_WITHDRAWER_ROLE is only granted to trusted contracts that handle fee collection externally.

---

### YNV-16: Provider.getRate uses spot prices without staleness or manipulation checks

**Severity:** High
**Confidence:** High
**Affected Contract(s):** `Provider.sol`
**Function(s):** `getRate()`
**Sources:** Pipeline G, H

**Description:**

The `Provider.getRate()` function fetches exchange rates from various external protocols using their spot conversion functions (`convertToAssets(1e18)`, `getPooledEthByShares(1e18)`, `getExchangeRate()`, etc.) without any staleness checks, sanity bounds, or manipulation resistance:

```solidity
if (asset == MC.BUFFER || asset == MC.MORPHO_MEV_CAPITAL_WETH || ...) {
    return IERC4626(asset).convertToAssets(1e18);  // Spot rate, no checks
}

if (asset == MC.WSTETH) {
    return IStETH(MC.STETH).getPooledEthByShares(1e18);  // No staleness check
}

if (asset == MC.SFRXETH) {
    uint256 frxETHPriceInETH = IFrxEthWethDualOracle(MC.FRX_ETH_WETH_DUAL_ORACLE).getCurveEmaEthPerFrxEth();
    return IsfrxETH(MC.SFRXETH).pricePerShare() * frxETHPriceInETH / 1e18;  // No bounds check
}
```

Key concerns:
1. ERC4626 `convertToAssets` on external vaults (BUFFER, MORPHO, EULER, etc.) can be manipulated within a single transaction through donation attacks on those vaults.
2. The Curve EMA oracle for frxETH (`getCurveEmaEthPerFrxEth`) can be lagged or manipulated through concentrated trading.
3. No rate returned from any source is bounded against a maximum expected deviation from 1e18.
4. If any external contract is paused, upgraded, or returns an anomalous value, the rate propagates directly into the vault's share price calculations.

When `alwaysComputeTotalAssets = true`, every deposit/withdraw reads live rates, making manipulation within the same block more feasible. The cached `totalAssets` mechanism mitigates some risk when `alwaysComputeTotalAssets = false`.

**Code Reference:** `Provider.sol:45-127`

**Impact:** An attacker who can temporarily manipulate the exchange rate of any supported asset (via flash loan donation to an external ERC4626 vault, or Curve pool manipulation) can inflate the apparent rate returned by `getRate()`. Since this rate feeds directly into `convertAssetToBase` and `convertBaseToAsset`, which are used in share minting and burning, the attacker can mint more shares than deserved during deposit or burn fewer shares during withdrawal, extracting value from the vault at the expense of other depositors.

**Recommendation:**
1. Implement rate sanity bounds: reject rates that deviate more than a configurable threshold from a TWAP or cached expected rate.
2. For ERC4626-based rates, consider using a cached rate updated periodically rather than spot `convertToAssets`.
3. Add staleness detection for oracle-based rates (e.g., check `updatedAt` for the Curve EMA oracle).
4. Consider implementing a rate deviation circuit breaker that pauses deposits if rate deviates beyond expected bounds.
5. Document that `alwaysComputeTotalAssets = true` increases manipulation risk and should only be used with trusted/manipulation-resistant rate sources.

---

### YNV-17: FeeHooks performance fee minting uses stale totalSupply snapshot, allowing fee dilution

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `FeeHooks.sol`
**Function(s):** `afterProcessAccounting()`
**Sources:** Pipeline G, H

**Description:**

The `afterProcessAccounting` hook in FeeHooks calculates performance fee shares using `params.totalSupplyBeforeAccounting`:

```solidity
uint256 sharesToMint = feesAccruedInBaseAsset.mulDiv(
    params.totalSupplyBeforeAccounting,
    params.totalBaseAssetsAfterAccounting - feesAccruedInBaseAsset,
    Math.Rounding.Floor
);
```

However, `processAccounting()` in VaultLib is `nonReentrant` but the `totalSupplyBeforeAccounting` is captured before the hook fires. If a deposit transaction lands between the `totalSupplyBeforeAccounting` snapshot and the `afterProcessAccounting` callback (in a different transaction within the same block), the actual total supply at the time of fee share minting will be higher than `totalSupplyBeforeAccounting`. This means the fee shares are calculated on a stale supply value.

More subtly, because `processAccounting()` fires `beforeProcessAccounting` before computing new total assets, a hooks contract at `beforeProcessAccounting` that has side effects can desynchronize the supply from the snapshot. The `totalSupplyAfterAccounting` parameter is computed after the hook fires via `_vault.totalSupply()`, which will already include the fee shares just minted, creating a circular dependency in the event data.

Additionally, if `processAccounting()` is called multiple times in rapid succession with small yield increments, the `Floor` rounding can cause `sharesToMint` to round to 0 on each call, effectively forfeiting small fee amounts. Over many small accounting updates, accumulated fees could be lost.

**Code Reference:** `FeeHooks.sol:96-116`

**Impact:** In normal operation, this is low impact because `processAccounting` is atomic. However, the supply snapshot model means that large deposits landing just before `processAccounting` (in the same block) result in the fee shares being calculated against a supply that excludes those deposits, slightly undercounting the fee dilution effect. Over many accounting cycles with high deposit volume, this could result in marginal fee overpayment or underpayment to the performance fee recipient. Small fee increments may also be lost to rounding.

**Recommendation:** Use `_vault.totalSupply()` at the point of fee calculation rather than the pre-snapshotted value, or document the known limitation. Consider accumulating fee amounts across accounting periods and minting shares only when the accumulated fee exceeds a minimum threshold.

---

### YNV-18: `_deposit` adds to totalAssets before token transfer, creating brief accounting inflation window

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `_deposit()`
**Sources:** Pipeline G

**Description:**

In the `_deposit` function, `_addTotalAssets(baseAssets)` is called BEFORE the actual token transfer:

```solidity
function _deposit(address asset_, address caller, address receiver, uint256 assets, uint256 shares, uint256 baseAssets) internal virtual {
    if (!_getAssetStorage().assets[asset_].active) revert AssetNotActive();

    _addTotalAssets(baseAssets);  // State update FIRST

    SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);  // Transfer SECOND
    _mint(receiver, shares);
    // ...
}
```

This ordering means that during the `safeTransferFrom` external call, the vault's `totalAssets` storage reflects the incoming deposit, but the tokens have not yet arrived. If the deposit token has callback mechanics (ERC-777 `tokensToSend` on the sender), the sender could observe an inflated `totalAssets` value relative to actual token holdings.

While `nonReentrant` guards on `deposit` and `depositAsset` prevent direct reentrancy into deposit/withdraw, any view function reading `totalBaseAssets()` during this window would see the inflated value. Read-only reentrancy through external contracts that call `totalBaseAssets()` during the transfer callback is possible.

**Code Reference:** `BaseVault.sol:535-557`

**Impact:** In the context of a read-only reentrancy scenario, an external protocol reading the vault's `totalBaseAssets()` or `totalAssets()` during a deposit's transfer callback would see an inflated value (tokens counted but not yet received). This could affect downstream protocols that use the vault's total assets for their own pricing logic. The impact is limited by the `nonReentrant` guard preventing direct state-changing reentrancy.

**Recommendation:** Follow the Checks-Effects-Interactions pattern more strictly by performing the token transfer before updating internal accounting, or document the known ordering and confirm that the `nonReentrant` guard sufficiently mitigates the risk for all integration scenarios.

---

### YNV-19: `processAccounting` deep external call chain creates manipulation surface

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `VaultLib.sol`, `Provider.sol`
**Function(s):** `processAccounting()`, `computeTotalAssets()`, `getRate()`
**Sources:** Pipeline G

**Description:**

In `VaultLib.processAccounting()`, the function reads `_vault.totalAssets()` (line 398) and `_vault.totalSupply()` (line 399) before computing new total assets. `totalAssets()` calls `_convertBaseToAsset(asset(), totalBaseAssets(), ...)` which calls `VaultLib.convertBaseToAsset` which calls `IProvider(provider).getRate(asset)`.

This creates a deep external call chain during accounting:
1. `processAccounting()` -> `_vault.totalAssets()` -> `_convertBaseToAsset()` -> `Provider.getRate()` -> external protocol calls
2. `processAccounting()` -> `computeTotalAssets()` -> for each asset: `IERC20.balanceOf()` + `convertAssetToBase()` -> `Provider.getRate()` -> external protocol calls
3. `processAccounting()` -> hooks: `beforeProcessAccounting()` + `afterProcessAccounting()` -> external hook contract calls

The `beforeProcessAccounting` hook fires BEFORE `computeTotalAssets()` updates the cached value, meaning a malicious or buggy hook could observe stale state. The `afterProcessAccounting` hook fires AFTER the update but BEFORE the function returns, and the hook itself could trigger further external calls (as FeeHooks.afterProcessAccounting does with `VAULT.mintShares`).

**Code Reference:** `VaultLib.sol:394-432`

**Impact:** The deep external call chain increases the attack surface for view-function manipulation during accounting. If any external protocol called during the Provider rate lookup returns a manipulated value (e.g., through a flash loan attack on an underlying ERC4626 vault), the manipulated rate propagates into the vault's cached totalAssets. Combined with the permissionless nature of `processAccounting()` (YNV-03), this creates a multi-step attack path: manipulate an external rate source, call `processAccounting()` to lock in the manipulated value, then deposit/withdraw at the distorted rate.

**Recommendation:**
1. Consider adding access control to `processAccounting()` (e.g., a dedicated ACCOUNTING_ROLE) or implementing a rate deviation check that reverts if the newly computed total assets differs from the cached value by more than a configurable threshold.
2. Implement rate caching with maximum age for the Provider to reduce the window of manipulation.

---

### YNV-20: `BaseVault.hasAsset` reverts when asset list is empty instead of returning false

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `hasAsset()`
**Sources:** Pipeline G

**Description:**

The `hasAsset` function checks if an asset exists by comparing the asset at the stored index against the queried address:

```solidity
function hasAsset(address asset_) public view virtual returns (bool) {
    AssetStorage storage assetStorage = _getAssetStorage();
    AssetParams memory assetParams = assetStorage.assets[asset_];
    return assetStorage.list[assetParams.index] == asset_;
}
```

For any address not in the assets mapping, `assetParams.index` defaults to 0, and `assetParams` returns default values (index=0, active=false, decimals=0). The function then checks `assetStorage.list[0] == asset_`. If the asset list is empty, accessing `list[0]` will revert with an out-of-bounds error.

**Code Reference:** `BaseVault.sol:418-422`

**Impact:** Calling `hasAsset()` before any assets are added to the vault will cause an out-of-bounds revert. This could affect initialization scripts or off-chain tooling that queries the vault before setup is complete. The actual deployed behavior after initialization is correct.

**Recommendation:** Add a bounds check: `if (assetStorage.list.length == 0) return false;` at the beginning of the function. Also consider adding `if (assetParams.index == 0 && assetStorage.list.length > 0 && assetStorage.list[0] != asset_) return false;` for explicit handling of the default-index case.

---

### YNV-21: `VaultLib.addAsset` duplicate check has subtle gap after asset deletion

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `VaultLib.sol`
**Function(s):** `addAsset()`
**Sources:** Pipeline G

**Description:**

The `addAsset` function checks for duplicate assets with two conditions:

```solidity
// Check if trying to add the Base Asset again
if (index > 0 && asset_ == assetStorage.list[0]) {
    revert IVault.DuplicateAsset(asset_);
}

if (index > 0 && assetStorage.assets[asset_].index != 0) {
    revert IVault.DuplicateAsset(asset_);
}
```

The second check `assetStorage.assets[asset_].index != 0` relies on the fact that a previously added asset would have a non-zero index. However, when `deleteAsset` is called, it executes `delete assetStorage.assets[asset_]` which resets the index to 0. If the same asset is later re-added, the duplicate check passes because `index` is 0 (the default).

The logic is functionally correct for the vault's usage patterns: the base asset at index 0 is caught by the first check, and the re-addition after deletion may be intentional behavior. However, the code lacks documentation of this behavior.

**Code Reference:** `VaultLib.sol:121-161`

**Impact:** Low. The duplicate detection logic has a subtle structural weakness but is functionally correct for the vault's usage patterns. The asset can be re-added after deletion, which may be intentional. A future developer might not realize that the duplicate check has this gap.

**Recommendation:** Add a comment documenting that re-adding a previously deleted asset is intentional behavior. Alternatively, use a separate `mapping(address => bool) isRegistered` that is set to true on add and false on delete for clearer duplicate detection.

---

### YNV-22: `MaxVaultViewer.getStrategies` reverts instead of returning empty array

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `MaxVaultViewer.sol`
**Function(s):** `getStrategies()`
**Sources:** Pipeline G

**Description:**

The `getStrategies` function computes `strategiesLength = assetsLength - underlyingAssetsLength` and reverts with `InvalidAssets()` if `assetsLength <= underlyingAssetsLength`:

```solidity
function getStrategies() public view returns (AssetInfo[] memory) {
    // ...
    uint256 underlyingAssetsLength = _getAssetStorage().underlyingAssetsLength;
    if (assetsLength <= underlyingAssetsLength) revert InvalidAssets();
    // ...
}
```

If all vault assets are classified as underlying assets (or if the underlying count equals the asset count), this view function reverts instead of returning an empty array. This is a view-function DoS that affects off-chain integrations and UIs that call this function.

Furthermore, the function allocates arrays of size `strategiesLength` but then fills them via a counter `j` that only increments for non-underlying assets. If the `underlyingAssetsLength` tracking is out of sync with the actual number of underlying assets in the mapping, the `strategies` array will have trailing zero-address entries.

**Code Reference:** `MaxVaultViewer.sol:31-55`

**Impact:** Front-end integrations and monitoring tools calling `getStrategies()` will encounter reverts when the vault has no strategies deployed, causing UX degradation. The data integrity issue with out-of-sync lengths could cause incorrect asset information to be displayed.

**Recommendation:** Return an empty array when there are no strategies instead of reverting. Add a check that `j == strategiesLength` at the end to validate consistency between the counter and the underlyingAssetsLength tracking.

---

### YNV-23: `AsyncWithdrawalLib` uses hardcoded fee denominator inconsistent with FeeStorage

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `AsyncWithdrawalLib.sol`
**Function(s):** `_asyncWithdrawalBalanceYNAsset()`
**Sources:** Pipeline G

**Description:**

The function calculates the net base amount for pending YN withdrawal requests using a hardcoded fee denominator of `1000000`:

```solidity
uint256 fee = baseAmount * requests[i].feeAtRequestTime / 1000000;
baseAssets += baseAmount - fee;
```

Meanwhile, the vault's withdrawal fee system uses `FeeMath.BASIS_POINT_SCALE = 1e8` (100,000,000) as its denominator. The `feeAtRequestTime` from the `IWithdrawalQueueManager` uses a different fee scale (`1000000` = 1e6) than the vault's internal fee system (`1e8`).

While these are different systems (the withdrawal queue manager vs the vault's own fee mechanism), the semantic inconsistency means the code implicitly depends on the withdrawal queue manager using a 1e6 fee scale. If the withdrawal queue manager is upgraded or if a new queue manager with a different fee scale is integrated, this hardcoded assumption will produce incorrect balance calculations.

**Code Reference:** `AsyncWithdrawalLib.sol:39-48`

**Impact:** If the withdrawal queue manager's fee denominator changes (through an upgrade or new integration), the `asyncWithdrawalBalance` will be miscalculated, leading to incorrect `computeTotalAssets()` values in the Withdrawer contract. This would affect share pricing for deposits and withdrawals.

**Recommendation:** Use a named constant for the fee denominator and document its dependency on the withdrawal queue manager's fee scale. Consider reading the fee denominator from the queue manager contract if it provides such a function.

---

### YNV-24: `OriginWithdrawalLib._removeRequestId` linear search creates O(n) gas cost per claim

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `OriginWithdrawalLib.sol`
**Function(s):** `_removeRequestId()`, `claimWithdrawalsWOETH()`
**Sources:** Pipeline G

**Description:**

The `_removeRequestId` function iterates over the entire `requestIds` array to find and remove a single ID:

```solidity
function _removeRequestId(uint256 id) private {
    uint256[] storage requestIds = getOriginWithdrawalStorage().requestIds;
    for (uint256 i = 0; i < requestIds.length; i++) {
        if (requestIds[i] == id) {
            requestIds[i] = requestIds[requestIds.length - 1];
            requestIds.pop();
            break;
        }
    }
}
```

The `claimWithdrawalsWOETH` function calls `_removeRequestIds` which calls `_removeRequestId` for each ID in the claim batch. This creates O(n*m) gas complexity where n = total pending requests and m = requests being claimed.

**Code Reference:** `OriginWithdrawalLib.sol:57-67`

**Impact:** If the Withdrawer accumulates many pending OETH withdrawal requests, claiming becomes increasingly expensive. With hundreds of pending requests, the gas cost could approach block limits, potentially delaying or preventing claims.

**Recommendation:** Use a mapping-based approach (`mapping(uint256 => uint256) requestIdIndex`) to enable O(1) removal, or accept the quadratic complexity with a documented maximum request count.

---

### YNV-25: `XReferralAdapter` does not validate that asset is supported by target vault

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `XReferralAdapter.sol`
**Function(s):** `depositAssetWithReferral()`
**Sources:** Pipeline G

**Description:**

The `depositAssetWithReferral` function validates that `vault.asset() != address(0)` and that the asset, receiver, and referrer are non-zero, but does not check whether the specified `asset` is actually a supported asset of the target vault:

```solidity
function depositAssetWithReferral(address _vault, address asset, uint256 assets, address referrer, address receiver)
    public nonReentrant returns (uint256 shares) {
    IVault vault = IVault(_vault);
    if (IVault(vault).asset() == address(0)) revert InvalidVault(_vault);
    // ... other checks ...
    SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), assets);
    SafeERC20.forceApprove(IERC20(asset), _vault, assets);
    shares = vault.depositAsset(asset, assets, receiver);
    // ...
}
```

If the vault's `depositAsset` reverts for an unsupported asset, the user's tokens have already been transferred to the adapter. While the entire transaction would revert in this case (atomic), the lack of upfront validation means users get an unhelpful revert message from deep in the vault rather than a clear error from the adapter.

**Code Reference:** `XReferralAdapter.sol:42-87`

**Impact:** Poor UX for users who attempt to deposit unsupported assets through the referral adapter. The transaction reverts after the token transfer attempt, wasting gas. No funds are at risk due to transaction atomicity.

**Recommendation:** Add an upfront check: `if (!IVault(_vault).hasAsset(asset)) revert InvalidAsset(asset);` before the token transfer.

---

### YNV-26: `VaultLib` storage slot comment mismatch for ProcessorStorage

**Severity:** Informational
**Confidence:** High
**Affected Contract(s):** `VaultLib.sol`
**Function(s):** `getProcessorStorage()`
**Sources:** Pipeline G

**Description:**

The `getProcessorStorage` function has a comment indicating the slot is `keccak256("yieldnest.storage.vault")`, which is the SAME string used for `getVaultStorage`:

```solidity
function getVaultStorage() public pure returns (IVault.VaultStorage storage $) {
    assembly {
        // keccak256("yieldnest.storage.vault")
        $.slot := 0x22cdba5640455d74cb7564fb236bbbbaf66b93a0cc1bd221f1ee2a6b2d0a2427
    }
}

function getProcessorStorage() public pure returns (IVault.ProcessorStorage storage $) {
    assembly {
        // keccak256("yieldnest.storage.vault")  // <-- WRONG comment
        $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
    }
}
```

The actual slot values are different (0x22cd... vs 0x52bb...), so there is no collision. However, the comment is misleading -- the processor storage slot hash `0x52bb...` does NOT correspond to `keccak256("yieldnest.storage.vault")`. The comment should reference the correct string (likely `"yieldnest.storage.processor"` or similar).

**Code Reference:** `VaultLib.sol:60-65`

**Impact:** No runtime impact. Misleading developer documentation that could cause confusion during audits or upgrades. If a developer relied on the comment to recompute the slot hash, they would get the VaultStorage slot instead of the ProcessorStorage slot.

**Recommendation:** Correct the comment to reflect the actual string that was hashed to produce slot `0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5`.

---

### YNV-27: Hooks system allows arbitrary external calls during state transitions (read-only reentrancy)

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `HooksLib.sol`, `FeeHooks.sol`, `VaultLib.sol`
**Function(s):** `callHook()`, `afterProcessAccounting()`, `processAccounting()`
**Sources:** Pipeline H

**Description:**

The `HooksLib.callHook()` function executes a low-level `.call()` to the hooks contract during deposit, withdraw, redeem, mint, and processAccounting flows. The hooks contract is set by `HOOKS_MANAGER_ROLE` and could be any contract implementing the `IHooks` interface. During `processAccounting()`, `afterProcessAccounting` is called after `vaultStorage.totalAssets` has been updated (line VaultLib.sol:415), but before the function returns. The `FeeHooks.afterProcessAccounting()` calls `VAULT.mintShares()` which mints new shares, modifying `totalSupply` while `totalAssets` has already been set. Any external protocol reading the vault's `convertToAssets()` or `convertToShares()` during the `mintShares` callback will see the post-accounting `totalAssets` but the pre-mint `totalSupply`, resulting in an inflated share price.

While `nonReentrant` prevents re-entering the vault's own functions, the hooks contract can make arbitrary external calls that read stale view function values.

**Code Reference:** `HooksLib.sol:53-57`

**Impact:** External DeFi protocols that use the vault's share price (e.g., as collateral valuation) could be manipulated during `processAccounting()` if they are called within the hook execution window. This is a classic read-only reentrancy vector. The actual exploitability depends on which protocols integrate with the vault and whether they read the share price in a composable manner.

**Recommendation:** Consider adding a reentrancy lock check to critical view functions like `totalBaseAssets()`, `convertToAssets()`, and `convertToShares()` that returns a cached value or reverts when the lock is active. Alternatively, restructure `processAccounting` to complete all state changes (including fee share minting) before any external callbacks.

---

### YNV-28: Fee-on-transfer tokens break vault accounting

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `BaseVault.sol`
**Function(s):** `_deposit()`
**Sources:** Pipeline H

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

**Code Reference:** `BaseVault.sol:535-557`

**Impact:** If a fee-on-transfer token is ever added as a vault asset, the vault's accounting becomes permanently inflated. The last withdrawers would be unable to withdraw their full balance, effectively losing funds. This is a latent vulnerability that manifests upon asset configuration.

**Recommendation:** Measure the actual balance change before and after the transfer:
```solidity
uint256 balanceBefore = IERC20(asset_).balanceOf(address(this));
SafeERC20.safeTransferFrom(IERC20(asset_), caller, address(this), assets);
uint256 actualReceived = IERC20(asset_).balanceOf(address(this)) - balanceBefore;
```
Then use `actualReceived` for accounting. Alternatively, document that fee-on-transfer tokens are explicitly unsupported and add a validation check in `addAsset()`.

---

### YNV-29: Zero-share deposits inflate totalAssets without minting shares

**Severity:** Medium
**Confidence:** Medium
**Affected Contract(s):** `BaseVault.sol`, `VaultLib.sol`
**Function(s):** `_depositAsset()`, `convertToShares()`
**Sources:** Pipeline H

**Description:**

The `_depositAsset()` function computes shares via `_convertToShares(asset_, assets, Math.Rounding.Floor)` which rounds down. For very small deposit amounts (especially with multi-asset decimal differences), the computed `shares` could round to 0 while `baseAssets` remains non-zero. The function proceeds to call `_deposit()` which adds `baseAssets` to `totalAssets` and mints 0 shares. This permanently increases the vault's `totalAssets` without issuing corresponding shares, causing all existing share holders' shares to be worth slightly more (value donated to the vault).

In `VaultLib.convertToShares()` (line 304-313):
```solidity
baseAssets = convertAssetToBase(asset_, assets, rounding);
shares = baseAssets.mulDiv(totalSupply + 1, totalAssets + 1, rounding);
```
When `totalAssets` is very large relative to `baseAssets * (totalSupply + 1)`, `shares` rounds to 0.

There is no `require(shares > 0)` check anywhere in the deposit path.

**Code Reference:** `BaseVault.sol:503-524`

**Impact:** An attacker could repeatedly deposit dust amounts of a low-decimal asset to slowly inflate `totalAssets` without minting shares. While each individual deposit is negligible, automated griefing over many transactions would slowly donate value to existing holders and waste gas. More importantly, this violates the ERC4626 invariant that deposits should always mint shares > 0 (or revert).

**Recommendation:** Add a check in `_depositAsset()` or `_deposit()`:
```solidity
if (shares == 0) revert ZeroAmount();
```

---

### YNV-30: `processor()` missing array length validation

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `VaultLib.sol`
**Function(s):** `processor()`
**Sources:** Pipeline H

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

**Code Reference:** `VaultLib.sol:441-458`

**Impact:** This is a usability issue affecting the `PROCESSOR_ROLE` holder. Mismatched array lengths cause opaque reverts. Since only a privileged role can call this function, exploitation risk is minimal.

**Recommendation:** Add explicit length validation:
```solidity
if (targets.length != values.length || targets.length != data.length) revert IVault.InvalidArray();
if (targets.length == 0) revert IVault.InvalidArray();
```

---

### YNV-31: Withdrawal fee can be set to 100% via `overrideBaseWithdrawalFee`

**Severity:** Informational
**Confidence:** Medium
**Affected Contract(s):** `LinearWithdrawalFeeLib.sol`
**Function(s):** `overrideBaseWithdrawalFee()`, `setBaseWithdrawalFee()`
**Sources:** Pipeline H

**Description:**

The `overrideBaseWithdrawalFee()` function validates that `baseWithdrawalFee_ <= FeeMath.BASIS_POINT_SCALE` (i.e., `<= 1e8`). Since `BASIS_POINT_SCALE = 1e8` represents 100%, this allows setting a 100% withdrawal fee for a specific user via the `FEE_MANAGER_ROLE`. With a 100% fee, the user's `previewRedeem` would return 0 assets for any amount of shares, effectively bricking their withdrawal.

The same validation exists in `setBaseWithdrawalFee()` which could set the global fee to 100%.

**Code Reference:** `LinearWithdrawalFeeLib.sol:56-62`

**Impact:** A malicious or compromised `FEE_MANAGER_ROLE` holder could brick withdrawals for specific users or all users by setting the fee to 100%. This is a privileged operation and severity is informational given the trust assumption in role holders.

**Recommendation:** Consider adding a maximum fee cap well below 100% (e.g., 10% or 20%) to limit potential governance attacks:
```solidity
uint64 public constant MAX_WITHDRAWAL_FEE = 0.2e8; // 20%
if (baseWithdrawalFee_ > MAX_WITHDRAWAL_FEE) revert ExceedsMaxBasisPoints(baseWithdrawalFee_);
```

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
