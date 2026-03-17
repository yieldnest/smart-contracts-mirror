# OpenAudit: YieldNest Vault Periphery -- Combined Findings

**Repository:** yieldnest-vault-periphery
**Scope:** `src/admin/VaultManager.sol`, `src/hooks/MetaHooks.sol`, `src/hooks/ProcessAccountingGuardHook.sol`, `src/interface/IVaultForHooks.sol`, `src/lib/TStore.sol`
**Solidity Version:** ^0.8.24
**LOC:** ~1,055
**Pipelines:** Forefy Smart Contract Audit, Archethect SC Auditor (Map-Hunt-Attack)
**Date:** 2026-03-17

**Existing findings (excluded from this report):**
- VPH-01: Missing array length validation in addAssets() causes silent revert

---

## Findings

---

### [MEDIUM] OA-VP-01: Internal helper functions `_isVaultAsset` and `_erc4626AssetMatchesVaultAsset` have `public` visibility instead of `internal`

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/admin/VaultManager.sol:58,68`

**Description:**
The functions `_isVaultAsset` (line 58) and `_erc4626AssetMatchesVaultAsset` (line 68) are prefixed with an underscore, following the Solidity convention for internal/private functions. However, both are declared as `public view`. This creates an inconsistency between naming convention and actual visibility. More importantly, since `VaultManager` is intended to act as a guarded admin wrapper around the vault, exposing these helper functions publicly allows anyone to call them. While they are view-only and do not modify state, the naming convention mismatch indicates a developer intent for these to be internal. If future upgrades or inheriting contracts rely on the underscore convention to determine access scope, this could lead to misuse.

Additionally, `_isVaultAsset` calls `vault.getAssets()` which returns the full asset array. If the vault has a large number of assets, external callers could use this as a view-only griefing vector to waste node resources, though the practical impact is low.

**Impact:**
Deviation from naming convention signals developer intent for internal visibility. Public exposure of internal helpers can cause confusion for integrators and downstream contracts that inherit `VaultManager`. Represents a code quality and maintainability issue.

**Recommendation:**
Change visibility of both functions from `public` to `internal`:
```solidity
function _isVaultAsset(address asset) internal view returns (bool) { ... }
function _erc4626AssetMatchesVaultAsset(address _buffer) internal view returns (bool) { ... }
```

---

### [MEDIUM] OA-VP-02: `ProcessAccountingGuardHook` owner is immutable with no transfer mechanism, creating a single point of failure

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/hooks/ProcessAccountingGuardHook.sol:47,57-59`

**Description:**
The `ProcessAccountingGuardHook` contract uses an immutable `owner` variable set in the constructor (line 47: `address public immutable owner`). The `onlyOwner` modifier (lines 57-59) restricts configuration functions (`setMaxTotalAssetsDecreaseRatio`, `setMaxTotalAssetsIncreaseRatio`, `setMaxTotalSupplyIncreaseRatio`, `setExpectedPerformanceFee`) to this single address.

Because `owner` is `immutable`, it cannot be changed after deployment. If the owner's private key is lost or compromised, there is no mechanism to:
1. Transfer ownership to a new address
2. Renounce ownership
3. Use a multi-sig or governance mechanism for configuration changes

This contrasts with `MetaHooks` and `VaultManager`, which use OpenZeppelin's `AccessControl` with role-based mechanisms that support role transfer.

**Impact:**
If the owner key is lost, the guard hook parameters become permanently frozen. If vault conditions change (e.g., new asset integrations requiring different thresholds), the hook would need to be redeployed and the vault reconfigured to point to the new hook. If the key is compromised, an attacker can set `maxTotalAssetsDecreaseRatio` and `maxTotalAssetsIncreaseRatio` to `type(uint256).max`, effectively disabling all guard protections and allowing unlimited totalAssets manipulation through `processAccounting`.

**Recommendation:**
Replace the immutable owner pattern with OpenZeppelin's `Ownable2Step` or `AccessControl` to allow ownership transfer and provide recovery mechanisms. Alternatively, add bounds validation on setter functions to prevent configuration values from being set to values that would nullify the guard.

---

### [MEDIUM] OA-VP-03: No upper bound validation on `ProcessAccountingGuardHook` configuration parameters allows guard to be effectively disabled

**Pipeline:** Archethect (Hunt: Semantic Consistency + Economic Differential)
**Confidence:** High
**File:** `src/hooks/ProcessAccountingGuardHook.sol:102-136`

**Description:**
The four setter functions in `ProcessAccountingGuardHook` accept any `uint256` value without bounds validation:
- `setMaxTotalAssetsDecreaseRatio` (line 102)
- `setMaxTotalAssetsIncreaseRatio` (line 112)
- `setMaxTotalSupplyIncreaseRatio` (line 122)
- `setExpectedPerformanceFee` (line 132)

Since `RATIO_DENOMINATOR = 1e18` (representing 100%), setting any ratio parameter to a value >= 1e18 effectively disables that specific guard check. Setting `expectedPerformanceFee` to `FEE_DENOMINATOR` (1e18 = 100%) would allow the minting of shares equal to the entire base asset increase. There are no `require` statements or range checks to prevent this.

While these functions are owner-restricted, the lack of bounds allows honest configuration mistakes to silently disable safety guards. Under the Forefy conservative severity framework, this is a config interaction vector where individually-valid parameter changes can combine to nullify the hook's entire purpose.

**Impact:**
If ratios are set too high (even by honest mistake), the `ProcessAccountingGuardHook` becomes a no-op, silently failing to protect the vault from anomalous `processAccounting` fluctuations. An oracle manipulation or third-party protocol failure could go unchecked.

**Recommendation:**
Add upper bound constants and validate in each setter:
```solidity
uint256 public constant MAX_RATIO = 0.5e18; // 50% max change
uint256 public constant MAX_FEE = 0.5e18;   // 50% max fee

function setMaxTotalAssetsDecreaseRatio(uint256 _ratio) external onlyOwner {
    require(_ratio <= MAX_RATIO, "ratio too high");
    ...
}
```

---

### [MEDIUM] OA-VP-04: `VaultManager.setProvider` uses stale `totalBaseAssets` for comparison due to assumption that `processAccounting` was called externally

**Pipeline:** Archethect (Hunt: Accounting Entitlement + Token Oracle Statefulness)
**Confidence:** Medium
**File:** `src/admin/VaultManager.sol:85-112`

**Description:**
The `setProvider` function (line 85) compares `vault.totalBaseAssets()` before the provider change (line 102) with `vault.computeTotalAssets()` after the change (line 107). The function comment at line 83 states: "Assumes that vault.processAccounting() is called before this function is called."

This is a critical assumption that is not enforced on-chain. If `processAccounting` has not been called recently, `vault.totalBaseAssets()` returns a cached/stale value, while `vault.computeTotalAssets()` forces a fresh recomputation. The comparison between a stale cached value and a fresh computed value could yield a false equality (if the cache happens to match despite changed conditions) or a false inequality (if the cache is stale from a previous epoch).

The same pattern exists in `addAssets` (line 122, comment at line 118) and `deleteAsset` (line 147, comment at line 144).

**Impact:**
If `processAccounting` was not called before `setProvider`, the before/after comparison is between values computed under different conditions. The stale `totalBaseAssets` might match the fresh `computeTotalAssets` by coincidence, allowing a provider change that actually alters asset valuations. Conversely, a legitimate provider change could be incorrectly blocked. The economic impact depends on how stale the cached values are and the delta between provider rate calculations.

**Recommendation:**
Enforce the precondition on-chain by calling `processAccounting` within the function or adding a staleness check:
```solidity
function setProvider(address _provider) public onlyRole(MODULE_MANAGER_ROLE) {
    // Force fresh accounting before comparison
    vault.processAccounting();
    uint256 beforeBaseAssets = vault.totalBaseAssets();
    vault.setProvider(_provider);
    uint256 afterBaseAssets = vault.computeTotalAssets();
    if (beforeBaseAssets != afterBaseAssets) {
        revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
    }
}
```

---

### [MEDIUM] OA-VP-05: `ProcessAccountingGuardHook.checkTotalAssetsChange` and `checkTotalSupplyChange` are `public` allowing external bypass of the `onlyVault` gate

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/hooks/ProcessAccountingGuardHook.sol:178,207`

**Description:**
The `afterProcessAccounting` function (line 161) is correctly protected by the `onlyVault` modifier. However, the two functions it delegates to -- `checkTotalAssetsChange` (line 178) and `checkTotalSupplyChange` (line 207) -- are both declared `public view`.

While these are view functions that do not modify state, they expose internal validation logic to arbitrary callers. More critically, `checkTotalSupplyChange` reads live state from the vault (`VAULT.totalSupply()` at line 208) and compares it against the `params` argument. An external caller can pass arbitrary `params` to probe the guard's thresholds and determine the exact boundaries that would trigger a revert. This provides an attacker preparing an oracle manipulation attack with precise knowledge of the maximum manipulation they can perform without triggering the guard.

Additionally, `checkTotalSupplyIncreaseRatio` (line 232) and `checkTotalSupplyIncreaseGivenPerformanceFee` (line 252) are also `public view`, providing the same information leakage.

**Impact:**
An attacker can call these functions off-chain to determine the exact threshold at which `processAccounting` would be blocked. This allows them to calibrate a manipulation to stay just below the guard's limits. While all on-chain state is technically public, exposing the guard's decision logic as callable functions makes it trivially easy to probe.

**Recommendation:**
Change visibility of internal guard checks from `public` to `internal`:
```solidity
function checkTotalAssetsChange(...) internal view { ... }
function checkTotalSupplyChange(...) internal view { ... }
function checkTotalSupplyIncreaseRatio(...) internal view { ... }
function checkTotalSupplyIncreaseGivenPerformanceFee(...) internal view { ... }
```

---

### [LOW] OA-VP-06: `MetaHooks.setHooks` uses O(n^2) duplicate check that becomes expensive for maximum hook count

**Pipeline:** Archethect (Hunt: Callback Liveness)
**Confidence:** High
**File:** `src/hooks/MetaHooks.sol:128-132`

**Description:**
The `setHooks` function (line 121) checks for duplicates in the input `hooks_` array using a nested loop (lines 128-132):
```solidity
for (uint256 i = 0; i < hooks_.length; i++) {
    for (uint256 j = i + 1; j < hooks_.length; j++) {
        if (hooks_[i] == hooks_[j]) revert DuplicateInInput(hooks_[i]);
    }
}
```

With a maximum of 16 hooks (enforced at line 125), this produces up to 120 comparisons (16 * 15 / 2). While 16 is a bounded maximum, the quadratic behavior combined with the subsequent clearing loop (lines 135-138), deletion (line 141), and re-population loop (lines 144-148) means that calling `setHooks` with 16 hooks performs significant gas work.

This is mitigated by the fact that `setHooks` is restricted to `HOOK_MANAGER_ROLE` and 16 is a small constant. However, the gas cost is still notable for an admin operation.

**Impact:**
Low. The function is admin-only and the maximum is bounded at 16. Gas cost is elevated but the operation is infrequent.

**Recommendation:**
Consider using a mapping-based duplicate check for O(n) complexity:
```solidity
for (uint256 i = 0; i < hooks_.length; i++) {
    if (hookData[hooks_[i]].active) revert DuplicateInInput(hooks_[i]);
    // Mark as active temporarily for duplicate detection
    hookData[hooks_[i]].active = true;
}
// Then clear and re-set properly
```
Note: This requires care around the existing `hookData` clearing that precedes it.

---

### [LOW] OA-VP-07: `MetaHooks.mintShares` provides unrestricted share minting capability to any registered hook

**Pipeline:** Archethect (Hunt: Accounting Entitlement + Adversarial Deep)
**Confidence:** Medium
**File:** `src/hooks/MetaHooks.sol:407-409`

**Description:**
The `mintShares` function (line 407) allows any contract registered as an active hook to mint arbitrary shares to any address:
```solidity
function mintShares(address to, uint256 shares) external override onlyHook {
    VAULT.mintShares(to, shares);
    emit SharesMinted(to, shares, msg.sender);
}
```

The `onlyHook` modifier (line 92-95) only checks that `hookData[IHooks(msg.sender)].active` is true. Any hook in the `hooks` array has unrestricted access to mint any amount of shares to any address.

While hooks are registered by the `HOOK_MANAGER_ROLE` and are presumably trusted, this design creates a single-point-of-failure for share integrity: a single malicious or compromised hook can inflate the vault's share supply without bound. There is no per-hook rate limit, no maximum shares-per-call limit, and no validation that the minted shares correspond to actual deposited assets.

This is not a direct exploit under the "privileged roles act in good faith" principle. However, per the Archethect methodology, this is an authority propagation vector: if the `HOOK_MANAGER_ROLE` honestly adds a hook that itself has a vulnerability, the compromised hook gains unlimited minting power. The blast radius of a single hook vulnerability extends to the entire vault's share supply.

**Impact:**
A bug in any registered hook contract could be leveraged to mint unbounded shares, diluting all existing shareholders. The attack vector is through authority propagation (honest admin + vulnerable hook = vault compromise), not direct admin abuse.

**Recommendation:**
Consider adding a per-operation or per-epoch cap on `mintShares` calls:
```solidity
uint256 public maxSharesPerMint;
function mintShares(address to, uint256 shares) external override onlyHook {
    require(shares <= maxSharesPerMint, "exceeds mint cap");
    VAULT.mintShares(to, shares);
    ...
}
```
Alternatively, implement an allowance system where the `HOOK_MANAGER_ROLE` grants specific hooks a share minting budget.

---

### [LOW] OA-VP-08: `ProcessAccountingGuardHook.checkTotalSupplyIncreaseGivenPerformanceFee` uses post-mint values for share conversion, creating a less strict bound

**Pipeline:** Forefy
**Confidence:** Medium
**File:** `src/hooks/ProcessAccountingGuardHook.sol:252-281`

**Description:**
The `checkTotalSupplyIncreaseGivenPerformanceFee` function computes `maxShares` by calling the internal `convertToShares` (line 273-275) with `totalSupplyAfterAccounting` and `totalBaseAssetsAfterAccounting`. The comment at line 271 acknowledges this: "maxShares is a looser bound that ensures the fee asset amount converted to vault shares at rate post mint is less than or equal to the total supply increase."

Using post-mint values for the conversion introduces a circularity: the `totalSupplyAfterAccounting` already includes the minted fee shares, so the conversion rate is diluted. This makes the bound looser than necessary. If the conversion used pre-mint values (`totalSupplyBeforeAccounting` and `totalBaseAssetsBeforeAccounting`), it would produce a tighter bound that more accurately reflects the maximum legitimate minting.

Specifically, the `convertToShares` formula is:
```solidity
assets.mulDiv(totalSupply + 1, totalAssets + 1, rounding)
```

With post-mint `totalSupply` (inflated by fee shares) and post-accounting `totalAssets` (increased by gains), the share-per-asset rate is lower than pre-mint, resulting in a higher `maxShares` allowance.

**Impact:**
The guard allows slightly more shares to be minted than the strict mathematical bound would permit. This looseness means the guard might not catch marginally excessive fee minting. The practical impact is bounded because the `maxTotalSupplyIncreaseRatio` check (line 232-243) provides a secondary cap.

**Recommendation:**
Document the intentional looseness clearly in NatSpec. If a tighter bound is desired, use pre-mint supply and pre-accounting total assets for the conversion:
```solidity
uint256 maxShares = convertToShares(
    maxFeeInBaseAssets,
    totalSupplyBeforeAccounting,
    totalBaseAssetsBeforeAccounting,
    Math.Rounding.Ceil  // Round up for conservative bound
);
```

---

### [LOW] OA-VP-09: `ProcessAccountingGuardHook` does not verify constructor parameter consistency

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/hooks/ProcessAccountingGuardHook.sol:76-91`

**Description:**
The constructor accepts six parameters but performs no validation:
```solidity
constructor(
    address _vault,
    address _owner,
    uint256 _maxTotalAssetsDecreaseRatio,
    uint256 _maxTotalAssetsIncreaseRatio,
    uint256 _maxTotalSupplyIncreaseRatio,
    uint256 _expectedPerformanceFee
) {
    VAULT = IVault(_vault);
    owner = _owner;
    ...
}
```

Missing checks:
1. `_vault != address(0)` -- a zero vault address makes the hook permanently non-functional
2. `_owner != address(0)` -- a zero owner permanently locks all configuration setters
3. Ratio parameters are within reasonable bounds (e.g., <= 1e18)
4. `_expectedPerformanceFee` is within a reasonable range

By contrast, `MetaHooks` validates `vault_ == address(0)` in its constructor (line 104).

**Impact:**
Misconfiguration at deployment time creates an irreversible broken state because `VAULT` and `owner` are both `immutable`. Since the contract cannot be upgraded or reconfigured, it must be redeployed.

**Recommendation:**
Add constructor validation:
```solidity
constructor(...) {
    require(_vault != address(0), "zero vault");
    require(_owner != address(0), "zero owner");
    require(_maxTotalAssetsDecreaseRatio <= RATIO_DENOMINATOR, "decrease ratio too high");
    require(_maxTotalAssetsIncreaseRatio <= RATIO_DENOMINATOR, "increase ratio too high");
    ...
}
```

---

### [LOW] OA-VP-10: `VaultManager` constructor does not validate that the vault address is non-zero

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/admin/VaultManager.sol:35-40`

**Description:**
The constructor of `VaultManager`:
```solidity
constructor(address _vault, address defaultAdmin, address bufferAdmin, address moduleManager) {
    vault = IVault(_vault);
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(BUFFER_ADMIN_ROLE, bufferAdmin);
    _grantRole(MODULE_MANAGER_ROLE, moduleManager);
}
```

There is no check for `_vault != address(0)`. Since `vault` is `immutable`, a zero-address vault would make the entire contract non-functional, and the contract would need to be redeployed. Similarly, `defaultAdmin`, `bufferAdmin`, and `moduleManager` are not validated.

**Impact:**
Low -- deployment error results in a non-functional contract that must be redeployed. No funds are at risk as the contract holds no assets.

**Recommendation:**
Add zero-address checks:
```solidity
require(_vault != address(0), "zero vault");
require(defaultAdmin != address(0), "zero admin");
```

---

### [LOW] OA-VP-11: `VaultManager._isVaultAsset` uses an unreliable index-based asset verification approach

**Pipeline:** Archethect (Hunt: Semantic Consistency)
**Confidence:** Medium
**File:** `src/admin/VaultManager.sol:58-63`

**Description:**
The `_isVaultAsset` function verifies an asset by:
1. Getting the asset's stored index via `vault.getAsset(asset).index`
2. Getting the full assets array via `vault.getAssets()`
3. Checking `vaultIndex < allAssets.length && allAssets[vaultIndex] == asset`

The TODO comment at line 59 acknowledges this: "TODO: optimizse using vault.hasAsset() post upgrade."

This approach has an edge case: if an asset has been deleted from the vault (leaving a zero slot in the assets array per Solidity's `delete` behavior on arrays), a different asset that happens to be at the same index could pass the check incorrectly. The function also relies on the vault's internal index mapping being consistent with the array order, which is an assumption about the vault's implementation.

Additionally, `vault.getAssets()` copies the entire assets array into memory. For vaults with many assets, this is gas-expensive for a validation check.

**Impact:**
If the vault's asset management creates inconsistencies between the index mapping and the array (e.g., after deletions), the check could produce false positives or false negatives. Practical impact depends on the vault implementation.

**Recommendation:**
Replace with the planned `vault.hasAsset()` call when available. In the meantime, add additional validation or document the assumptions about the vault's index consistency.

---

### [INFORMATIONAL] OA-VP-12: `TStore` library uses transient storage (EIP-1153) but is not imported by any in-scope contract

**Pipeline:** Archethect (MAP phase)
**Confidence:** High
**File:** `src/lib/TStore.sol`

**Description:**
The `TStore` library provides wrappers around the `tstore` and `tload` opcodes (EIP-1153, activated in the Dencun upgrade). However, none of the in-scope contracts (`VaultManager`, `MetaHooks`, `ProcessAccountingGuardHook`) import or use this library.

The library itself is well-implemented -- the `store`, `loadUint256`, `loadBool`, and `clear` functions correctly wrap the transient storage opcodes. However, its presence as dead code in the repository suggests either:
1. It is intended for future use (e.g., transient reentrancy guards)
2. It was part of a removed feature

**Impact:**
No security impact. Dead code that increases codebase surface area without benefit.

**Recommendation:**
Either integrate `TStore` where appropriate (e.g., as a transient reentrancy guard in MetaHooks' hook dispatch) or remove it from the repository to reduce codebase surface area.

---

### [INFORMATIONAL] OA-VP-13: `MetaHooks.setConfig` always reverts, preventing standard IHooks configuration flow

**Pipeline:** Forefy
**Confidence:** High
**File:** `src/hooks/MetaHooks.sol:205-207`

**Description:**
The `setConfig` function always reverts with `NotSupported()`:
```solidity
function setConfig(Config memory) public pure override {
    revert NotSupported();
}
```

This is intentional -- MetaHooks derives its config from the aggregated configs of its child hooks via `_syncConfigBitmap()`. However, this breaks the `IHooks` interface contract: any caller that expects to configure a hook via `setConfig` will receive an unexpected revert.

The same pattern exists in `ProcessAccountingGuardHook.setConfig` (line 154).

**Impact:**
No security impact. Both contracts intentionally override this interface method to prevent external configuration. The `getConfig` function correctly returns the aggregated/static config.

**Recommendation:**
Document the intentional deviation from the `IHooks` interface in NatSpec comments to prevent confusion for integrators.

---

### [INFORMATIONAL] OA-VP-14: `VaultManager.setProvider` compares `totalBaseAssets()` with `computeTotalAssets()`, which may use different computation paths

**Pipeline:** Archethect (Hunt: Semantic Consistency)
**Confidence:** Low
**File:** `src/admin/VaultManager.sol:102,107`

**Description:**
In `setProvider`, the before-value is obtained via `vault.totalBaseAssets()` (line 102) and the after-value via `vault.computeTotalAssets()` (line 107). The comment at line 106 explains: "using computeTotalAssets (forces recompute)."

These two functions likely have different behaviors:
- `totalBaseAssets()` returns a cached/stored value
- `computeTotalAssets()` forces a fresh computation

The same asymmetric comparison pattern appears in `addAssets` (lines 122, 135) and `deleteAsset` (lines 149, 154).

If the intent is to ensure the operation does not change the total assets, both the before and after values should use the same computation method. Using a cached value for "before" and a fresh computation for "after" could mask a scenario where the cached value was already stale.

**Impact:**
Informational. The asymmetric comparison is documented and intentional, but could lead to subtle false positives/negatives in the invariant check.

**Recommendation:**
Consider using `computeTotalAssets()` for both the before and after measurements to ensure an apples-to-apples comparison, or document clearly why the asymmetric approach is preferred.

---

## Summary

| ID | Severity | Title | Pipeline |
|----|----------|-------|----------|
| OA-VP-01 | Medium | Public visibility on internal helper functions in VaultManager | Forefy |
| OA-VP-02 | Medium | Immutable owner with no transfer mechanism in ProcessAccountingGuardHook | Forefy |
| OA-VP-03 | Medium | No upper bound validation on guard hook configuration parameters | Archethect |
| OA-VP-04 | Medium | Stale totalBaseAssets comparison due to unverified processAccounting assumption | Archethect |
| OA-VP-05 | Medium | Public guard check functions expose threshold probing | Forefy |
| OA-VP-06 | Low | O(n^2) duplicate check in setHooks | Archethect |
| OA-VP-07 | Low | Unrestricted share minting by any registered hook | Archethect |
| OA-VP-08 | Low | Post-mint values create looser bound in fee share validation | Forefy |
| OA-VP-09 | Low | Missing constructor parameter validation in ProcessAccountingGuardHook | Forefy |
| OA-VP-10 | Low | Missing zero-address check in VaultManager constructor | Forefy |
| OA-VP-11 | Low | Unreliable index-based asset verification in _isVaultAsset | Archethect |
| OA-VP-12 | Informational | Unused TStore library | Archethect |
| OA-VP-13 | Informational | setConfig always reverts breaking IHooks interface | Forefy |
| OA-VP-14 | Informational | Asymmetric totalBaseAssets vs computeTotalAssets comparison | Archethect |

**Total: 5 Medium, 6 Low, 3 Informational**
