# Security Audit Report: safeguard

## Metadata
- **Repository:** safeguard
- **Commit:** 2cf82cb2bbe91cee7fded1f84407854c1429b7c6 (monorepo HEAD; safeguard pinned at 1fb2d4fc6ab66b6c551c56d76b896b519c43aa10)
- **Branch:** dev
- **Date:** 2026-03-17
- **Solidity Version:** ^0.8.0 (SafeGuard.sol), ^0.8.24 (Guard.sol, VaultLib.sol dependencies)
- **Framework:** Foundry

## Audit Scope

| File | Path | LOC |
|------|------|-----|
| SafeGuard.sol | `src/SafeGuard.sol` | 241 |
| Guard.sol (dependency) | `yieldnest-vault/src/module/Guard.sol` | 46 |
| VaultLib.sol (dependency, partial) | `yieldnest-vault/src/library/VaultLib.sol` | 459 (only `setProcessorRule(s)` and `getProcessorStorage` in scope) |
| IVault.sol (interface) | `yieldnest-vault/src/interface/IVault.sol` | 183 |
| IValidator.sol (interface) | `yieldnest-vault/src/interface/IValidator.sol` | 12 |

**Note:** The `lib/` submodules for `safe-smart-account` and `openzeppelin-contracts-upgradeable` were not checked out in the monorepo. The audit relies on documented interfaces (`BaseTransactionGuard`, `BaseModuleGuard`, `AccessControlUpgradeable`) and known Gnosis Safe behavior.

## Methodologies Applied

| Pipeline | Description | Status |
|----------|-------------|--------|
| **A: SCV Scan** | Vulnerability pattern matching against 30+ known vulnerability classes from CHEATSHEET.md | Completed |
| **B: Feynman Business Logic Audit** | Line-by-line "why does this exist" analysis of every function, checking for bypass paths and ordering issues | Completed |
| **C: State Inconsistency Analysis** | Diamond/ERC-7201 storage mapping, cross-slot coupling analysis | Completed |
| **D: Pashov Multi-Vector Scan** | 4-perspective analysis: access control, reentrancy, arithmetic, logic/business flow | Completed |
| **E: QuillAI Modules** | semantic-guard-analysis, dos-griefing-analysis, external-call-safety | Completed |

## Executive Summary

SafeGuard is a Gnosis Safe transaction guard that enforces allowlist-based rules on both owner-initiated (`execTransaction`) and module-initiated (`execTransactionFromModule`) transactions. It uses the yieldnest-vault `Guard` library for rule validation and OpenZeppelin's `AccessControlUpgradeable` for role-based permission management.

The contract is relatively simple with a focused attack surface. The architecture delegates core validation to the `Guard` library which checks target+selector+parameters against pre-configured rules. The main security concern areas are: (1) the `validateCall` function being publicly callable, (2) delegatecall transactions not being distinguished from regular calls in guard validation, (3) the `Enum.Operation` parameter being entirely ignored, (4) non-ADDRESS parameter types being silently skipped during validation, and (5) potential DoS vectors in the linear-scan allowlist validation.

Five confirmed findings were identified across the pipelines, ranging from Medium to Informational severity. No Critical or High severity issues were found.

## Findings Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 3 |
| Informational | 6 |
| **Total** | **11** |

## Detailed Findings

---

### [M-01] DelegateCall Operations Are Not Blocked or Differentiated by the Guard

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `SafeGuard.sol` (lines 88-104, 120-130), `Guard.sol` (line 9-28)
**Sources:** Pipeline A (SCV - delegatecall-untrusted-callee), Pipeline B (Feynman), Pipeline D (Pashov - Logic)

**Description:**

The `checkTransaction` and `checkModuleTransaction` functions receive the `Enum.Operation` parameter from the Gnosis Safe but completely ignore it. The parameter is unnamed (`Enum.Operation, /* operation */`). The guard validates only `target + funcSig + parameters` -- but a `DelegateCall` operation executes the target contract's code in the **Safe's context**, meaning its storage, its balances, and its identity (`address(this)` == Safe).

```solidity
// SafeGuard.sol:88-104
function checkTransaction(
    address to,
    uint256 value,
    bytes memory data,
    Enum.Operation, /* operation */  // <-- IGNORED
    ...
) external view override {
    if (!_getSafeGuardStorage().checkTransactionEnabled) return;
    SafeGuard(address(this)).validateCall(to, value, data);
}
```

If a PROCESSOR_MANAGER configures a rule allowing calls to contract X with selector Y, a Safe owner can invoke that same (X, Y) combination as a `DelegateCall`, which would execute X's code in the Safe's storage context. If X's function Y writes to storage, those writes happen to the Safe's storage slots, potentially corrupting Safe state (owners, threshold, modules, guard, fallback handler).

The developer has documented awareness of this in the NatDoc (`@dev DelegateCall is not blocked`), but the risk is still present in the system design.

**Impact:**

If a rule is configured for a target that has state-modifying logic, a Safe owner could use `DelegateCall` to execute that logic in the Safe's context, potentially corrupting Safe internal state (owner list, threshold, guard, modules). This could lead to a complete Safe takeover or guard removal.

**Recommendation:**

Add an explicit check to reject `DelegateCall` operations unless specifically permitted:

```solidity
function checkTransaction(
    address to,
    uint256 value,
    bytes memory data,
    Enum.Operation operation,
    ...
) external view override {
    if (!_getSafeGuardStorage().checkTransactionEnabled) return;
    if (operation == Enum.Operation.DelegateCall) revert DelegateCallNotAllowed();
    SafeGuard(address(this)).validateCall(to, value, data);
}
```

Alternatively, maintain a separate allowlist of targets permitted for delegatecall.

---

### [M-02] Non-ADDRESS Parameter Types (UINT256) Are Silently Skipped During Validation

**Severity:** Medium
**Confidence:** High
**Affected Contract(s):** `Guard.sol` (lines 22-28)
**Sources:** Pipeline B (Feynman), Pipeline D (Pashov - Logic), Pipeline E (QuillAI - semantic-guard-analysis)

**Description:**

The `Guard.validateCall` function iterates over `paramRules` but only validates parameters of type `ADDRESS`. Parameters of type `UINT256` are silently skipped because there is no matching branch:

```solidity
// Guard.sol:22-28
for (uint256 i = 0; i < rule.paramRules.length; i++) {
    if (rule.paramRules[i].paramType == IVault.ParamType.ADDRESS) {
        address addressValue = abi.decode(data[4 + i * 32:], (address));
        _validateAddress(addressValue, rule.paramRules[i]);
        continue;
    }
    // UINT256 falls through with no validation
}
```

This means that any `UINT256` parameter (amounts, indices, thresholds) passes through the guard unchecked regardless of what value is provided. While this is likely by design (the guard focuses on "where" rather than "how much"), it means the guard provides no protection against unauthorized amounts.

The `value` field (ETH sent with the transaction) is also passed to `validateCall` but never checked within `Guard.validateCall` -- it is available as a parameter but unused.

**Impact:**

A Safe owner can send any amount of ETH alongside a permitted function call, or pass any uint256 value for function parameters. For example, if `approve(address,uint256)` is allowed with spender X, the owner can approve an unlimited amount to X. This is documented design behavior but worth flagging for rule administrators.

**Recommendation:**

Consider either:
1. Documenting this explicitly in the SafeGuard contract itself (not just in the library), so rule administrators understand uint256 parameters are not restricted.
2. Adding optional uint256 range validation (min/max bounds) in the `ParamRule` struct for cases where amount limiting is desired.
3. At minimum, rename `ParamType.UINT256` to something like `ParamType.UNCHECKED` to make the non-validation semantics explicit.

---

### [L-01] `validateCall` Is Public and Externally Callable by Anyone

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `SafeGuard.sol` (line 182-184)
**Sources:** Pipeline A (SCV - insufficient-access-control), Pipeline D (Pashov - Access Control)

**Description:**

The `validateCall` function is declared `public view`, meaning anyone can call it directly:

```solidity
// SafeGuard.sol:182-184
function validateCall(address target, uint256 value, bytes calldata data) public view {
    Guard.validateCall(target, value, data);
}
```

This function is made public intentionally so that `checkTransaction` can call it on `address(this)` to convert `memory` data to `calldata` (noted in the comment on line 102: "calls back to itself to be able to pass in a calldata parameter"). However, this means anyone can probe whether a specific (target, selector, parameters) combination would be allowed by the guard, leaking the full rule configuration.

**Impact:**

An attacker can enumerate all configured rules by testing different target/selector combinations against `validateCall`, revealing which contracts and functions the Safe is allowed to interact with. This information disclosure could aid in crafting more targeted attacks. This is an information leak, not a direct vulnerability to fund safety.

**Recommendation:**

Consider restricting the function so only the contract itself can call it:

```solidity
function validateCall(address target, uint256 value, bytes calldata data) external view {
    require(msg.sender == address(this), "Only self-call");
    Guard.validateCall(target, value, data);
}
```

Note: The rules can also be read via `getProcessorRule`, so this is partially mitigable but `validateCall` provides a more convenient oracle for probing.

---

### [L-02] ETH Transfers with Empty Calldata Revert with an Opaque Error

**Severity:** Low
**Confidence:** High
**Affected Contract(s):** `SafeGuard.sol` (lines 88-104), `Guard.sol` (line 10)
**Sources:** Pipeline B (Feynman), Pipeline E (QuillAI - semantic-guard-analysis)

**Description:**

When the guard is enabled and a transaction has empty `data` (a plain ETH transfer), the call to `Guard.validateCall` will attempt `bytes4(data[:4])` on an empty bytes array. In Solidity ^0.8.0, slicing beyond the array bounds causes a panic revert (not a custom error).

```solidity
// Guard.sol:10
bytes4 funcSig = bytes4(data[:4]);  // panics on data.length < 4
```

The NatDoc on SafeGuard documents this: `@dev Reverts on empty calldata (data.length < 4). ETH transfers with empty data are blocked.` However, the error returned is a Solidity panic (index out of bounds) rather than a descriptive custom error, making it difficult for integrators to handle or display.

**Impact:**

Plain ETH transfers from the Safe are blocked when the guard is enabled. This is documented and intentional behavior, but the revert reason is an opaque Solidity panic rather than a descriptive custom error. Off-chain tooling and user interfaces may display confusing error messages.

**Recommendation:**

Add an explicit check before the slicing operation:

```solidity
function validateCall(address target, uint256 value, bytes calldata data) internal view {
    if (data.length < 4) revert InvalidCalldata();
    bytes4 funcSig = bytes4(data[:4]);
    ...
}
```

---

### [L-03] Potential DoS via Large Allowlist Linear Scan in Guard Validation

**Severity:** Low
**Confidence:** Medium
**Affected Contract(s):** `Guard.sol` (lines 35-42)
**Sources:** Pipeline A (SCV - dos-gas-limit), Pipeline E (QuillAI - dos-griefing-analysis)

**Description:**

The `_isInArray` function in `Guard.sol` performs a linear scan of the allowlist array:

```solidity
// Guard.sol:35-42
function _isInArray(address value, address[] storage array) private view returns (bool) {
    for (uint256 i = 0; i < array.length; i++) {
        if (array[i] == value) {
            return true;
        }
    }
    return false;
}
```

If a PROCESSOR_MANAGER adds a very large number of addresses to an allowlist (via `setProcessorRules`), the gas cost of `checkTransaction` could increase substantially. In the extreme case (thousands of entries), this could cause transactions to fail due to the gas required for the guard check exceeding the block gas limit or the Safe's configured `safeTxGas`.

This is bounded by the fact that only a `PROCESSOR_MANAGER_ROLE` holder can set rules, so the attacker would need to be a compromised or malicious privileged actor.

**Impact:**

A compromised PROCESSOR_MANAGER could set an extremely large allowlist to grief the Safe by making all guarded transactions too expensive to execute. This is a trusted-role prerequisite attack.

**Recommendation:**

Consider enforcing a maximum allowlist size per parameter rule. Alternatively, use a mapping-based set (e.g., `EnumerableSet`) for O(1) lookups, which also prevents duplicate entries.

---

## Informational Notes

### [I-01] Diamond Storage Slot Comment Mismatch in VaultLib

**Severity:** Informational
**Affected Contract(s):** `VaultLib.sol` (lines 60-65)
**Sources:** Pipeline C (State Inconsistency)

The `getProcessorStorage` function has a comment stating `keccak256("yieldnest.storage.vault")` but its slot value (`0x52bb806a...`) differs from `getVaultStorage` which uses the same comment but a different slot (`0x22cdba56...`). The actual slot value `0x52bb806a...` does not match `keccak256("yieldnest.storage.vault")`. This appears to be a copy-paste documentation error; the actual slot value is likely correct (would correspond to a different preimage), but the comment is misleading.

```solidity
// VaultLib.sol:60-65
function getProcessorStorage() public pure returns (IVault.ProcessorStorage storage $) {
    assembly {
        // keccak256("yieldnest.storage.vault")  // <-- Comment likely wrong
        $.slot := 0x52bb806a772c899365572e319d3d6f49ed2259348d19ab0da8abccd4bd46abb5
    }
}
```

**Recommendation:** Correct the comment to reflect the actual preimage used to derive the slot.

---

### [I-02] `validateCall` Self-Call Pattern Incurs Unnecessary Gas Overhead

**Severity:** Informational
**Affected Contract(s):** `SafeGuard.sol` (lines 102-103, 127-128)
**Sources:** Pipeline B (Feynman)

The contract calls `SafeGuard(address(this)).validateCall(to, value, data)` to convert `memory` data to `calldata`. This incurs the overhead of an external CALL opcode (including the 2600 gas cold-access penalty on first call, 100 gas base cost, and ABI encoding/decoding overhead). The developer has noted this: "calls back to itself to be able to pass in a calldata parameter. Less gas efficient."

An alternative approach would be to use inline assembly to perform the calldata slicing directly, avoiding the external self-call entirely.

---

### [I-03] No Validation That `_admin` Is Not `address(0)` in `initialize`

**Severity:** Informational
**Affected Contract(s):** `SafeGuard.sol` (line 65)
**Sources:** Pipeline D (Pashov - Logic)

The `initialize` function does not check whether `_admin` is `address(0)`. If called with `address(0)`, all three roles (`DEFAULT_ADMIN_ROLE`, `PROCESSOR_MANAGER_ROLE`, `GUARD_ADMIN_ROLE`) would be granted to `address(0)`, effectively making the contract unmanageable since no one could ever call role-protected functions. The `initializer` modifier prevents re-initialization, so this would brick the proxy.

```solidity
function initialize(string calldata _name, address _admin) public initializer {
    __AccessControl_init();
    _getSafeGuardStorage().name = _name;
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);  // No zero-address check
    ...
}
```

**Recommendation:** Add `require(_admin != address(0), "zero address admin")`.

---

### [I-04] `checkAfterExecution` and `checkAfterModuleExecution` Are No-Ops

**Severity:** Informational
**Affected Contract(s):** `SafeGuard.sol` (lines 109-111, 135-137)
**Sources:** Pipeline B (Feynman), Pipeline E (QuillAI - semantic-guard-analysis)

Both post-execution hooks are empty no-ops:

```solidity
function checkAfterExecution(bytes32, bool) external pure override {}
function checkAfterModuleExecution(bytes32, bool) external pure override {}
```

This means the guard cannot detect or revert on post-execution state changes. For example, if a transaction succeeds but results in an unexpected state (e.g., the Safe's ETH balance drops below a threshold), there is no mechanism to catch this. This is a design choice, but it reduces the guard's defensive surface.

---

### [I-05] `setProcessorRules` Does Not Validate Target Address or Function Signature

**Severity:** Informational
**Affected Contract(s):** `SafeGuard.sol` (line 193-199), `VaultLib.sol` (lines 321-324)
**Sources:** Pipeline D (Pashov - Logic)

The `setProcessorRules` function (and the underlying `VaultLib.setProcessorRule`) does not validate that the `target` address is non-zero or that the `functionSig` is non-zero. A PROCESSOR_MANAGER could accidentally set a rule for `address(0)` with `bytes4(0)`, which would be a meaningless rule but would consume storage.

```solidity
function setProcessorRule(address target, bytes4 functionSig, IVault.FunctionRule calldata rule) public {
    getProcessorStorage().rules[target][functionSig] = rule;  // No validation
    emit IVault.SetProcessorRule(target, functionSig, rule);
}
```

---

### [I-06] Floating Pragma Version

**Severity:** Informational
**Affected Contract(s):** `SafeGuard.sol` (line 2)
**Sources:** Pipeline A (SCV - outdated-compiler-version, floating-pragma)

The contract uses `pragma solidity ^0.8.0`, which is a wide range. While Solidity >=0.8.0 has built-in overflow checks, versions before 0.8.20 are recommended for maximum cross-chain compatibility (avoiding `PUSH0` opcode issues on some L2s). The dependency contracts use `^0.8.24`, creating a potential version mismatch.

**Recommendation:** Pin to a specific compiler version (e.g., `pragma solidity 0.8.24`) that matches the dependencies.

---

## Audit Methodology Details

### Pipeline A: SCV Vulnerability Pattern Scan

Scanned all 30+ vulnerability patterns from the cheatsheet. The following patterns were checked and found **not applicable** to the in-scope contract:

- **Reentrancy:** All guard functions are `view`/`pure`. No state modifications during external calls.
- **Unchecked return values:** No low-level calls in SafeGuard. The self-call to `validateCall` uses a Solidity-level call that auto-reverts.
- **tx.origin:** Not used anywhere.
- **Integer overflow:** Solidity ^0.8.0 with checked math. No `unchecked` blocks. No dangerous type casts.
- **Signature issues:** No signature handling in the guard.
- **Hash collisions:** No `abi.encodePacked` with dynamic types.
- **Timestamp dependence:** No timestamp usage.
- **Frontrunning:** Rule changes by PROCESSOR_MANAGER could theoretically be frontrun, but this requires a privileged role.

### Pipeline B: Feynman Business Logic Analysis

Key findings:
- The self-call pattern (`SafeGuard(address(this)).validateCall(...)`) exists solely to convert `memory` to `calldata` for the `data[:4]` slice. This is correct but gas-inefficient.
- The `checkTransactionEnabled` / `checkModuleTransactionEnabled` flags provide independent control over owner vs. module transaction validation. This is a well-designed separation.
- The guard does NOT check `msg.sender` in `checkTransaction`/`checkModuleTransaction` -- it relies on the Gnosis Safe to call the guard correctly. This is correct per the Safe guard interface.

### Pipeline C: State Inconsistency Analysis

Storage layout analysis:
- **SafeGuardStorage** at slot `0xdc30ccdf...` (keccak256("yieldnest.storage.safeguard")): Contains `name`, `checkTransactionEnabled`, `checkModuleTransactionEnabled`.
- **ProcessorStorage** at slot `0x52bb806a...`: Contains `rules` mapping (target => funcSig => FunctionRule).
- **AccessControlUpgradeable** storage: Standard OpenZeppelin ERC-7201 layout.

No storage collisions were identified between these three storage regions. The diamond storage slots use distinct preimages.

### Pipeline D: Pashov Multi-Vector Analysis

1. **Access Control:** Properly uses `onlyRole` modifiers. `initialize` protected by `initializer`. Constructor calls `_disableInitializers()`.
2. **Reentrancy:** Not applicable -- all external-facing functions are `view` or `pure` (guard interface). `setProcessorRules` modifies storage but makes no external calls.
3. **Arithmetic:** No arithmetic operations in SafeGuard.sol. Guard.sol uses `i * 32` for ABI offset calculation -- safe within uint256 range.
4. **Logic:** DelegateCall bypass identified (M-01). UINT256 parameter skip identified (M-02).

### Pipeline E: QuillAI Module Analysis

- **semantic-guard-analysis:** The guard's semantic model only covers target + selector + address parameters. It does not model transaction value, gas parameters, or operation type. This is a restricted threat model.
- **dos-griefing-analysis:** Linear allowlist scan is O(n) per address parameter. Combined with multiple address parameters, worst case is O(n*m) where n is allowlist size and m is number of address parameters.
- **external-call-safety:** The self-call pattern in `checkTransaction` is safe because it targets `address(this)` with a known function signature and is a `view` call. No callback risk.
