# Security Audit Report: yieldnest-vault-periphery

## Metadata
- **Repository:** yieldnest-vault-periphery
- **Commit:** f8e9cf7f265fe5c4bddf11e666994f2048009b06
- **Branch:** eth-max-vault-release-candidate
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.24
- **Auditor:** Multi-Pipeline Automated Security Audit (incl. Forefy + Archethect)

## Audit Scope

| File | Path | LOC |
|------|------|-----|
| VaultManager.sol | `src/admin/VaultManager.sol` | 160 |
| MetaHooks.sol | `src/hooks/MetaHooks.sol` | 500 |
| ProcessAccountingGuardHook.sol | `src/hooks/ProcessAccountingGuardHook.sol` | 346 |
| IVaultForHooks.sol | `src/interface/IVaultForHooks.sol` | 15 |
| TStore.sol | `src/lib/TStore.sol` | 34 |
| **Total** | | **1055** |

## Methodologies Applied

| Pipeline | Methodology | Findings |
|----------|-------------|----------|
| A | SCV Scan (Vulnerability Pattern Matching) | 2 |
| B | Feynman Business Logic Audit | 3 |
| C | State Inconsistency Analysis | 1 |
| D | Pashov Multi-Vector Scan | 2 |
| E | QuillAI Modules | 1 |
| F | Token Integration Analysis | 1 |
| G | Forefy + Archethect | Protocol-specific 5-layer audit + SETUP-MAP-HUNT-ATTACK methodology |
| **Total unique findings** | | **17** |

## Executive Summary

The yieldnest-vault-periphery repository implements three primary contracts: a `VaultManager` for administrative operations with role-based access control, a `MetaHooks` contract for composing and dispatching multiple hook contracts in sequence, and a `ProcessAccountingGuardHook` that validates total asset and supply changes during the vault's `processAccounting` cycle.

The codebase demonstrates competent Solidity engineering with appropriate use of immutables, access control, and defensive checks. However, the audit identified **17 findings**: **3 Medium**, **10 Low**, and **4 Informational**. The most significant finding is a missing array length validation in `VaultManager.addAssets()` that can cause an out-of-bounds array access revert, potentially creating a denial-of-service condition for the module manager role. Additional medium findings include missing upper bound validation on guard hook configuration parameters that could allow the guard to be silently disabled, and public visibility on internal guard check functions that expose threshold probing to potential attackers. Other findings involve naming convention violations, missing zero-address checks, unrestricted share minting authority, and potential DoS vectors through hook interactions.

No critical or high-severity vulnerabilities were identified. The trust assumptions between MetaHooks and registered hooks are appropriate given the admin-gated hook registration model.

## Findings Summary

| ID | Severity | Title | Sources | Confidence |
|----|----------|-------|---------|------------|
| VPH-01 | Medium | Missing array length validation in `addAssets()` causes silent revert | A, B, D | High |
| VPH-02 | Low | `ProcessAccountingGuardHook` guard bypass when `totalSupplyBeforeAccounting` is zero | B, E | Medium |
| VPH-03 | Low | Internal-naming convention on public functions in `VaultManager` | B, D, G | High |
| VPH-04 | Low | `ProcessAccountingGuardHook` owner is immutable with no transfer mechanism | C, D, G | High |
| VPH-05 | Low | Malicious or reverting hook can DoS all vault operations via MetaHooks | A, E | Medium |
| VPH-06 | Informational | TStore library is unused in the current source scope | C, G | High |
| VPH-07 | Informational | `VaultManager.setProvider()` assumes `processAccounting()` was called prior | B, F, G | Medium |
| VPH-08 | Informational | `ProcessAccountingGuardHook` reads live `totalSupply()` instead of using params value | B, F | Medium |
| VPH-09 | Medium | No upper bound validation on `ProcessAccountingGuardHook` configuration parameters allows guard to be effectively disabled | G | High |
| VPH-10 | Medium | `ProcessAccountingGuardHook.checkTotalAssetsChange` and `checkTotalSupplyChange` are `public` allowing external threshold probing | G | High |
| VPH-11 | Low | `MetaHooks.setHooks` uses O(n^2) duplicate check that becomes expensive for maximum hook count | G | High |
| VPH-12 | Low | `MetaHooks.mintShares` provides unrestricted share minting capability to any registered hook | G | Medium |
| VPH-13 | Low | `ProcessAccountingGuardHook.checkTotalSupplyIncreaseGivenPerformanceFee` uses post-mint values for share conversion, creating a less strict bound | G | Medium |
| VPH-14 | Low | `ProcessAccountingGuardHook` does not verify constructor parameter consistency | G | High |
| VPH-15 | Low | `VaultManager` constructor does not validate that the vault address is non-zero | G | High |
| VPH-16 | Low | `VaultManager._isVaultAsset` uses an unreliable index-based asset verification approach | G | Medium |
| VPH-17 | Informational | `MetaHooks.setConfig` always reverts, preventing standard IHooks configuration flow | G | High |

## Detailed Findings

---

### VPH-01: Missing array length validation in `addAssets()` causes silent revert

**Severity:** Medium
**Confidence:** High
**Affected Contract:** `VaultManager.sol`
**Function:** `addAssets(address[] memory _assets, bool[] memory _active)`
**Sources:** Pipeline A (SCV Scan), Pipeline B (Feynman), Pipeline D (Pashov)

**Description:**

The `addAssets` function accepts two arrays `_assets` and `_active` but never validates that they have the same length. The loop iterates using `_assets.length` as the bound and accesses `_active[i]` on each iteration. If `_active` is shorter than `_assets`, the function will revert with an out-of-bounds memory access panic (Panic(0x32)) rather than a descriptive error.

If `_active` is longer than `_assets`, the extra elements are silently ignored, which could mask a caller error where the arrays were inadvertently misaligned.

**Code Reference:**

```solidity
// src/admin/VaultManager.sol, lines 120-132
function addAssets(address[] memory _assets, bool[] memory _active) public onlyRole(MODULE_MANAGER_ROLE) {
    // Get totalBaseAssets before changing provider
    uint256 beforeBaseAssets = vault.totalBaseAssets();

    for (uint256 i = 0; i < _assets.length; ++i) {
        // Check that the provider returns a rate > 0 for the asset before adding
        try IProvider(vault.provider()).getRate(_assets[i]) returns (uint256 rate) {
            if (rate == 0) revert ProviderRateNotDefined(_assets[i]);
        } catch {
            revert ProviderRateNotDefined(_assets[i]);
        }
        vault.addAsset(_assets[i], _active[i]); // <-- _active[i] may be OOB
    }
    // ...
}
```

**Impact:**

- If a MODULE_MANAGER_ROLE holder provides mismatched arrays, the transaction silently panics with an unhelpful error instead of reverting with a clear message. In a governance/multisig context, this wastes gas and complicates debugging.
- If `_active` is longer, the caller may believe they set activity status for N assets when only M < N were processed.

**Recommendation:**

Add an explicit length check at the start of the function:

```solidity
error ArrayLengthMismatch();

function addAssets(address[] memory _assets, bool[] memory _active) public onlyRole(MODULE_MANAGER_ROLE) {
    if (_assets.length != _active.length) revert ArrayLengthMismatch();
    // ...
}
```

---

### VPH-02: `ProcessAccountingGuardHook` guard bypass when `totalSupplyBeforeAccounting` is zero

**Severity:** Low
**Confidence:** Medium
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Function:** `checkTotalSupplyIncreaseRatio()`, `checkTotalSupplyIncreaseGivenPerformanceFee()`
**Sources:** Pipeline B (Feynman), Pipeline E (QuillAI)

**Description:**

The function `checkTotalSupplyIncreaseRatio` computes `totalSupplyIncreaseRatio` by dividing by `totalSupplyBeforeAccounting`. If the vault's total supply before accounting is zero (e.g., a freshly initialized vault with no depositors), this division will revert with a division-by-zero panic.

While `afterProcessAccounting` has a guard for `params.totalAssetsBeforeAccounting == 0`, there is no equivalent guard for `totalSupplyBeforeAccounting == 0`. In a scenario where the vault has assets but zero supply (unlikely but theoretically possible if all shares were burned or in edge-case initialization), `processAccounting` would be permanently blocked.

**Code Reference:**

```solidity
// src/hooks/ProcessAccountingGuardHook.sol, lines 236-238
function checkTotalSupplyIncreaseRatio(uint256 totalSupplyBeforeAccounting, uint256 totalSupplyAfterAccounting)
    public view
{
    uint256 totalSupplyIncrease = totalSupplyAfterAccounting - totalSupplyBeforeAccounting;
    uint256 _maxTotalSupplyIncreaseRatio = maxTotalSupplyIncreaseRatio;
    uint256 totalSupplyIncreaseRatio = (totalSupplyIncrease * RATIO_DENOMINATOR) / totalSupplyBeforeAccounting;
    //                                                                              ^^^ division by zero if zero
```

**Impact:**

If this guard hook is active on a vault with zero total supply, `processAccounting()` will permanently revert, creating a denial-of-service on the accounting cycle. The vault would need to have the hook removed or replaced to recover.

**Recommendation:**

Add an early return in `checkTotalSupplyChange` when `totalSupplyBeforeAccounting` is zero:

```solidity
function checkTotalSupplyChange(AfterProcessAccountingParams memory params) public view {
    uint256 totalSupplyAfterAccounting = VAULT.totalSupply();
    if (params.totalSupplyBeforeAccounting == 0) return; // Skip check if starting from zero supply
    // ...
}
```

---

### VPH-03: Internal-naming convention on public functions in `VaultManager`

**Severity:** Low
**Confidence:** High
**Affected Contract:** `VaultManager.sol`
**Functions:** `_isVaultAsset()`, `_erc4626AssetMatchesVaultAsset()`
**Sources:** Pipeline B (Feynman), Pipeline D (Pashov), Pipeline G (Forefy + Archethect)

**Description:**

Two functions prefixed with an underscore (`_isVaultAsset` and `_erc4626AssetMatchesVaultAsset`) are declared with `public` visibility. By Solidity convention, underscore-prefixed functions are expected to be `internal` or `private`. Making them `public` creates a confusing API surface.

**Code Reference:**

```solidity
// src/admin/VaultManager.sol, lines 58-63
function _isVaultAsset(address asset) public view returns (bool) {
    // ...
}

// src/admin/VaultManager.sol, lines 68-75
function _erc4626AssetMatchesVaultAsset(address _buffer) public view returns (bool) {
    // ...
}
```

**Impact:**

- Confuses integrators and auditors about the intended visibility and trust boundary of these functions.
- These functions are exposed in the ABI and could be called externally, though they are view-only and cause no state changes.

**Recommendation:**

Either rename the functions to remove the underscore prefix (e.g., `isVaultAsset`, `erc4626AssetMatchesVaultAsset`) or change their visibility to `internal` if they are not intended for external use.

---

### VPH-04: `ProcessAccountingGuardHook` owner is immutable with no transfer mechanism

**Severity:** Low
**Confidence:** High
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Storage Variable:** `owner`
**Sources:** Pipeline C (State Inconsistency), Pipeline D (Pashov), Pipeline G (Forefy + Archethect)

**Description:**

The `owner` state variable in `ProcessAccountingGuardHook` is declared as `immutable`, meaning the owner address is permanently set at construction time and can never be changed. There is no ownership transfer mechanism. If the owner key is lost or compromised, the guard parameters (`maxTotalAssetsDecreaseRatio`, `maxTotalAssetsIncreaseRatio`, `maxTotalSupplyIncreaseRatio`, `expectedPerformanceFee`) can never be updated.

**Code Reference:**

```solidity
// src/hooks/ProcessAccountingGuardHook.sol, line 48
address public immutable owner;
```

**Impact:**

- If the owner key is compromised, an attacker could set `maxTotalAssetsDecreaseRatio` and `maxTotalAssetsIncreaseRatio` to extremely high values, effectively disabling the guard.
- If the owner key is lost, the guard parameters become permanently fixed, requiring the hook to be replaced entirely via MetaHooks reconfiguration.
- The mitigation path (replacing the hook via MetaHooks) exists but involves a more complex governance action than a simple ownership transfer would.

**Recommendation:**

Consider using OpenZeppelin's `Ownable` or `Ownable2Step` instead of a raw immutable owner, allowing secure ownership transfer. Alternatively, document this as an intentional design decision if the hook is meant to be replaced rather than reconfigured.

---

### VPH-05: Malicious or reverting hook can DoS all vault operations via MetaHooks

**Severity:** Low
**Confidence:** Medium
**Affected Contract:** `MetaHooks.sol`
**Functions:** All hook dispatch functions (`beforeDeposit`, `afterDeposit`, etc.)
**Sources:** Pipeline A (SCV Scan - DoS with Revert), Pipeline E (QuillAI - DoS/Griefing)

**Description:**

MetaHooks iterates through all registered hooks in sequence and calls each one. If any hook in the chain reverts (whether maliciously or due to a bug), the entire transaction reverts, blocking the vault operation. Since the vault calls `MetaHooks` as its hook contract, a single broken hook in the chain can effectively freeze deposits, withdrawals, redemptions, and accounting.

The trust model relies on the `HOOK_MANAGER_ROLE` to only register trustworthy hooks. However, if a registered hook has a latent bug that causes it to revert under certain conditions, the entire vault operation set becomes unavailable until the hook manager removes or replaces the problematic hook.

**Code Reference:**

```solidity
// src/hooks/MetaHooks.sol, lines 270-280 (representative example)
function beforeDeposit(DepositParams memory params) external override onlyVault {
    uint16 bitmap = configBitmap.beforeDeposit;
    if (bitmap == 0) return;

    uint256 _hooksLength = hooks.length;
    for (uint256 i = 0; i < _hooksLength; i++) {
        if (supportsHook(i, bitmap)) {
            hooks[i].beforeDeposit(params); // <-- revert here blocks all deposits
        }
    }
}
```

**Impact:**

A single reverting hook blocks all vault operations that go through the corresponding hook type. This is a systemic risk for vault availability.

**Recommendation:**

This is somewhat inherent to the guard/hook design pattern (hooks are *meant* to be able to block operations). However, consider:
1. Adding an emergency "bypass" mechanism controlled by a separate admin role that can disable a specific hook index.
2. Documenting the risk clearly and ensuring the hook manager role has rapid response capabilities.
3. Adding a try/catch option per-hook that the hook manager can configure for non-critical hooks.

---

### VPH-06: TStore library is unused in the current source scope

**Severity:** Informational
**Confidence:** High
**Affected Contract:** `TStore.sol`
**Sources:** Pipeline C (State Inconsistency), Pipeline G (Forefy + Archethect)

**Description:**

The `TStore` library provides transient storage (`tstore`/`tload`) helper functions but is not imported or used by any contract in the `src/` directory. It appears to be dead code or intended for future use.

**Code Reference:**

```solidity
// src/lib/TStore.sol (entire file)
library TStore {
    function store(bytes32 key, uint256 value) internal { ... }
    function store(bytes32 key, bool value) internal { ... }
    function loadUint256(bytes32 key) internal view returns (uint256 value) { ... }
    function loadBool(bytes32 key) internal view returns (bool value) { ... }
    function clear(bytes32 key) internal { ... }
}
```

A search across all `src/` files confirms no contract imports `TStore`.

**Impact:**

No security impact. Increases bytecode size if deployed and adds maintenance burden.

**Recommendation:**

Remove the file if unused, or document its intended future use.

---

### VPH-07: `VaultManager.setProvider()` assumes `processAccounting()` was called prior

**Severity:** Informational
**Confidence:** Medium
**Affected Contract:** `VaultManager.sol`
**Functions:** `setProvider()`, `addAssets()`, `deleteAsset()`
**Sources:** Pipeline B (Feynman), Pipeline F (Token Integration), Pipeline G (Forefy + Archethect)

**Description:**

The `setProvider`, `addAssets`, and `deleteAsset` functions all rely on comparing `vault.totalBaseAssets()` before and after the state change to ensure consistency. The NatSpec comments explicitly state: "Assumes that vault.processAccounting() is called before this function is called."

However, this assumption is not enforced programmatically. If `processAccounting()` has not been called recently and the underlying asset rates have changed, `vault.totalBaseAssets()` returns a stale cached value. The before/after comparison would then compare a stale "before" against a freshly computed "after", potentially causing a legitimate provider change to be rejected (false positive revert) or a malicious one to pass (if the stale and new values happen to match).

**Code Reference:**

```solidity
// src/admin/VaultManager.sol, lines 85-112
/**
 * @dev Assumes that vault.processAccounting() is called before this function is called.
 */
function setProvider(address _provider) public onlyRole(MODULE_MANAGER_ROLE) {
    // ...
    uint256 beforeBaseAssets = vault.totalBaseAssets(); // may be stale
    vault.setProvider(_provider);
    uint256 afterBaseAssets = vault.computeTotalAssets(); // freshly computed
    if (beforeBaseAssets != afterBaseAssets) {
        revert TotalBaseAssetsMismatch(beforeBaseAssets, afterBaseAssets);
    }
}
```

**Impact:**

- A stale `totalBaseAssets` could cause false positive reverts, blocking legitimate provider changes.
- In theory, a provider change that should have been caught could pass if the stale cached value happens to match the new computed value (low probability).

**Recommendation:**

Consider calling `vault.processAccounting()` at the start of these functions to ensure freshness, or use `vault.computeTotalAssets()` for both the before and after snapshots. If the assumption is intentional (to force callers to sequence the calls), consider adding an explicit staleness check (e.g., comparing block.timestamp with the vault's `lastAccounting` timestamp).

---

### VPH-08: `ProcessAccountingGuardHook` reads live `totalSupply()` instead of using params value

**Severity:** Informational
**Confidence:** Medium
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Function:** `checkTotalSupplyChange()`
**Sources:** Pipeline B (Feynman), Pipeline F (Token Integration)

**Description:**

The `AfterProcessAccountingParams` struct includes a `totalSupplyAfterAccounting` field that is populated by the vault at the time the hook is called. However, `ProcessAccountingGuardHook.checkTotalSupplyChange()` ignores this parameter and instead reads `VAULT.totalSupply()` live at line 208.

When this hook is used standalone (directly registered with the vault), these values are identical. However, when used within `MetaHooks`, a prior hook in the chain could call `MetaHooks.mintShares()` to mint additional shares between the time the params were populated and when this guard hook executes. In that case, `VAULT.totalSupply()` would return a higher value than `params.totalSupplyAfterAccounting`.

The MetaHooks documentation states that hook ordering is critical and that a verifying hook should be placed *after* a hook that mints shares. This design is intentional -- the guard reads the live value to capture shares minted by preceding hooks. However, it creates a subtle coupling: the guard's behavior changes depending on its position in the hook chain and the behavior of preceding hooks.

**Code Reference:**

```solidity
// src/hooks/ProcessAccountingGuardHook.sol, lines 207-208
function checkTotalSupplyChange(AfterProcessAccountingParams memory params) public view {
    uint256 totalSupplyAfterAccounting = VAULT.totalSupply(); // live read, not from params
    // ...
}
```

Compared to the params that were populated in VaultLib.sol:

```solidity
// yieldnest-vault/src/library/VaultLib.sol, line 427
totalSupplyAfterAccounting: _vault.totalSupply(), // snapshot at time of param construction
```

**Impact:**

No direct security impact if hooks are ordered correctly. However, if the guard hook is accidentally placed before a share-minting hook in the MetaHooks chain, it would validate against a total supply that does not yet include the minted shares, potentially allowing more minting than intended to pass the guard.

**Recommendation:**

Document this behavior explicitly in the contract's NatSpec. Consider adding a comment in the code explaining why the live read is used instead of the params value, to prevent future maintainers from "fixing" it to use params.

---

### VPH-09: No upper bound validation on `ProcessAccountingGuardHook` configuration parameters allows guard to be effectively disabled

**Severity:** Medium
**Confidence:** High
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Functions:** `setMaxTotalAssetsDecreaseRatio()`, `setMaxTotalAssetsIncreaseRatio()`, `setMaxTotalSupplyIncreaseRatio()`, `setExpectedPerformanceFee()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The four setter functions in `ProcessAccountingGuardHook` accept any `uint256` value without bounds validation:
- `setMaxTotalAssetsDecreaseRatio` (line 102)
- `setMaxTotalAssetsIncreaseRatio` (line 112)
- `setMaxTotalSupplyIncreaseRatio` (line 122)
- `setExpectedPerformanceFee` (line 132)

Since `RATIO_DENOMINATOR = 1e18` (representing 100%), setting any ratio parameter to a value >= 1e18 effectively disables that specific guard check. Setting `expectedPerformanceFee` to `FEE_DENOMINATOR` (1e18 = 100%) would allow the minting of shares equal to the entire base asset increase. There are no `require` statements or range checks to prevent this.

While these functions are owner-restricted, the lack of bounds allows honest configuration mistakes to silently disable safety guards. Under the Forefy conservative severity framework, this is a config interaction vector where individually-valid parameter changes can combine to nullify the hook's entire purpose.

**Code Reference:**

```solidity
// src/hooks/ProcessAccountingGuardHook.sol, lines 102-136
function setMaxTotalAssetsDecreaseRatio(uint256 _maxTotalAssetsDecreaseRatio) external onlyOwner {
    maxTotalAssetsDecreaseRatio = _maxTotalAssetsDecreaseRatio;
    emit MaxTotalAssetsDecreaseRatioSet(_maxTotalAssetsDecreaseRatio);
}

function setMaxTotalAssetsIncreaseRatio(uint256 _maxTotalAssetsIncreaseRatio) external onlyOwner {
    maxTotalAssetsIncreaseRatio = _maxTotalAssetsIncreaseRatio;
    emit MaxTotalAssetsIncreaseRatioSet(_maxTotalAssetsIncreaseRatio);
}

function setMaxTotalSupplyIncreaseRatio(uint256 _maxTotalSupplyIncreaseRatio) external onlyOwner {
    maxTotalSupplyIncreaseRatio = _maxTotalSupplyIncreaseRatio;
    emit MaxTotalSupplyIncreaseRatioSet(_maxTotalSupplyIncreaseRatio);
}

function setExpectedPerformanceFee(uint256 _expectedPerformanceFee) external onlyOwner {
    expectedPerformanceFee = _expectedPerformanceFee;
    emit ExpectedPerformanceFeeSet(_expectedPerformanceFee);
}
```

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

### VPH-10: `ProcessAccountingGuardHook.checkTotalAssetsChange` and `checkTotalSupplyChange` are `public` allowing external threshold probing

**Severity:** Medium
**Confidence:** High
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Functions:** `checkTotalAssetsChange()`, `checkTotalSupplyChange()`, `checkTotalSupplyIncreaseRatio()`, `checkTotalSupplyIncreaseGivenPerformanceFee()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The `afterProcessAccounting` function (line 161) is correctly protected by the `onlyVault` modifier. However, the two functions it delegates to -- `checkTotalAssetsChange` (line 178) and `checkTotalSupplyChange` (line 207) -- are both declared `public view`.

While these are view functions that do not modify state, they expose internal validation logic to arbitrary callers. More critically, `checkTotalSupplyChange` reads live state from the vault (`VAULT.totalSupply()` at line 208) and compares it against the `params` argument. An external caller can pass arbitrary `params` to probe the guard's thresholds and determine the exact boundaries that would trigger a revert. This provides an attacker preparing an oracle manipulation attack with precise knowledge of the maximum manipulation they can perform without triggering the guard.

Additionally, `checkTotalSupplyIncreaseRatio` (line 232) and `checkTotalSupplyIncreaseGivenPerformanceFee` (line 252) are also `public view`, providing the same information leakage.

**Code Reference:**

```solidity
// src/hooks/ProcessAccountingGuardHook.sol, lines 178, 207
function checkTotalAssetsChange(AfterProcessAccountingParams memory params) public view {
    // ...
}

function checkTotalSupplyChange(AfterProcessAccountingParams memory params) public view {
    uint256 totalSupplyAfterAccounting = VAULT.totalSupply();
    // ...
}
```

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

### VPH-11: `MetaHooks.setHooks` uses O(n^2) duplicate check that becomes expensive for maximum hook count

**Severity:** Low
**Confidence:** High
**Affected Contract:** `MetaHooks.sol`
**Function:** `setHooks()`
**Sources:** Pipeline G (Forefy + Archethect)

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

This is mitigated by the fact that `setHooks` is restricted to `HOOK_MANAGER_ROLE` and 16 is a small constant.

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

### VPH-12: `MetaHooks.mintShares` provides unrestricted share minting capability to any registered hook

**Severity:** Low
**Confidence:** Medium
**Affected Contract:** `MetaHooks.sol`
**Function:** `mintShares()`
**Sources:** Pipeline G (Forefy + Archethect)

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

This is not a direct exploit under the "privileged roles act in good faith" principle. However, this is an authority propagation vector: if the `HOOK_MANAGER_ROLE` honestly adds a hook that itself has a vulnerability, the compromised hook gains unlimited minting power. The blast radius of a single hook vulnerability extends to the entire vault's share supply.

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

### VPH-13: `ProcessAccountingGuardHook.checkTotalSupplyIncreaseGivenPerformanceFee` uses post-mint values for share conversion, creating a less strict bound

**Severity:** Low
**Confidence:** Medium
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Function:** `checkTotalSupplyIncreaseGivenPerformanceFee()`
**Sources:** Pipeline G (Forefy + Archethect)

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

### VPH-14: `ProcessAccountingGuardHook` does not verify constructor parameter consistency

**Severity:** Low
**Confidence:** High
**Affected Contract:** `ProcessAccountingGuardHook.sol`
**Function:** `constructor()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The constructor accepts six parameters but performs no validation:

```solidity
// src/hooks/ProcessAccountingGuardHook.sol, lines 76-91
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

### VPH-15: `VaultManager` constructor does not validate that the vault address is non-zero

**Severity:** Low
**Confidence:** High
**Affected Contract:** `VaultManager.sol`
**Function:** `constructor()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The constructor of `VaultManager`:

```solidity
// src/admin/VaultManager.sol, lines 35-40
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

### VPH-16: `VaultManager._isVaultAsset` uses an unreliable index-based asset verification approach

**Severity:** Low
**Confidence:** Medium
**Affected Contract:** `VaultManager.sol`
**Function:** `_isVaultAsset()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The `_isVaultAsset` function verifies an asset by:
1. Getting the asset's stored index via `vault.getAsset(asset).index`
2. Getting the full assets array via `vault.getAssets()`
3. Checking `vaultIndex < allAssets.length && allAssets[vaultIndex] == asset`

The TODO comment at line 59 acknowledges this: "TODO: optimizse using vault.hasAsset() post upgrade."

This approach has an edge case: if an asset has been deleted from the vault (leaving a zero slot in the assets array per Solidity's `delete` behavior on arrays), a different asset that happens to be at the same index could pass the check incorrectly. The function also relies on the vault's internal index mapping being consistent with the array order, which is an assumption about the vault's implementation.

Additionally, `vault.getAssets()` copies the entire assets array into memory. For vaults with many assets, this is gas-expensive for a validation check.

**Code Reference:**

```solidity
// src/admin/VaultManager.sol, lines 58-63
function _isVaultAsset(address asset) public view returns (bool) {
    // TODO: optimizse using vault.hasAsset() post upgrade
    uint256 vaultIndex = vault.getAsset(asset).index;
    address[] memory allAssets = vault.getAssets();
    return vaultIndex < allAssets.length && allAssets[vaultIndex] == asset;
}
```

**Impact:**

If the vault's asset management creates inconsistencies between the index mapping and the array (e.g., after deletions), the check could produce false positives or false negatives. Practical impact depends on the vault implementation.

**Recommendation:**

Replace with the planned `vault.hasAsset()` call when available. In the meantime, add additional validation or document the assumptions about the vault's index consistency.

---

### VPH-17: `MetaHooks.setConfig` always reverts, preventing standard IHooks configuration flow

**Severity:** Informational
**Confidence:** High
**Affected Contract:** `MetaHooks.sol`
**Function:** `setConfig()`
**Sources:** Pipeline G (Forefy + Archethect)

**Description:**

The `setConfig` function always reverts with `NotSupported()`:

```solidity
// src/hooks/MetaHooks.sol, lines 205-207
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

## Informational Notes

1. **Solidity Version:** All contracts use `^0.8.24`, which includes built-in overflow protection and supports transient storage opcodes (`tstore`/`tload`). This is an appropriate compiler version.

2. **Access Control Model:** The system uses a multi-tier access control model:
   - `VaultManager`: Uses OpenZeppelin `AccessControl` with `DEFAULT_ADMIN_ROLE`, `BUFFER_ADMIN_ROLE`, and `MODULE_MANAGER_ROLE`.
   - `MetaHooks`: Uses OpenZeppelin `AccessControl` with `DEFAULT_ADMIN_ROLE` and `HOOK_MANAGER_ROLE`.
   - `ProcessAccountingGuardHook`: Uses a custom immutable `owner`.
   - The vault itself has separate roles (`PROVIDER_MANAGER_ROLE`, `BUFFER_MANAGER_ROLE`, `ASSET_MANAGER_ROLE`, `HOOKS_MANAGER_ROLE`) and the `VaultManager` contract must hold these roles on the vault to function.

3. **No Reentrancy Vectors in Periphery:** The vault's `processAccounting()` is protected by `nonReentrant`. The periphery contracts make external calls only to the trusted vault contract (immutable reference) and to hooks registered by an admin role. No user-controlled external calls exist in the periphery.

4. **No Signature, tx.origin, or delegatecall Patterns:** None of the source contracts use `ecrecover`, `tx.origin`, or `delegatecall`. The SCV scan for these patterns returned clean.

5. **No Unchecked Blocks:** No `unchecked` blocks are present in the periphery source. All arithmetic benefits from Solidity 0.8.x's built-in overflow protection.

6. **MetaHooks Bitmap Design:** The 16-hook limit enforced by `uint16` bitmaps is well-designed and prevents gas limit issues from unbounded iteration. The duplicate check in `setHooks` uses O(n^2) comparison but is bounded by n <= 16, making it acceptable.

7. **Hook Trust Model:** The `MetaHooks.mintShares()` function is gated by the `onlyHook` modifier, which checks that `msg.sender` is a registered hook. This means any registered hook can mint arbitrary shares to any address. The security of the vault's share supply depends entirely on the correctness and trustworthiness of all registered hooks.

8. **ERC4626 Interaction:** The `VaultManager.setCurrentBuffer()` correctly validates that the buffer is both a recognized vault asset and that its `IERC4626.asset()` matches the vault's base asset. The try/catch pattern handles non-ERC4626 contracts gracefully.
