# OpenAudit SafeGuard Findings

**Target:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`
**Date:** 2026-03-17
**Pipelines:** Forefy Smart Contract Audit, Archethect SC Auditor (Map-Hunt-Attack)
**Solidity Version:** ^0.8.0
**Existing Findings (excluded):** SG-01 (DelegateCall not blocked), SG-02 (Non-ADDRESS params silently skipped)

---

## Findings

---

### [HIGH] OA-SG-03: `validateCall` is `public` with no access control, allowing anyone to bypass the self-call pattern and probe rule configurations

**Pipeline:** Forefy
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:182-184

**Description:**
The `validateCall(address target, uint256 value, bytes calldata data)` function is declared `public view` with no access restriction. It is designed to be called by the guard itself via the self-call pattern (`SafeGuard(address(this)).validateCall(...)`) to convert `memory` data to `calldata`. However, because it is unrestricted, any external caller can invoke it directly. This creates an information-disclosure oracle: an attacker can systematically probe which `(target, functionSig)` pairs have active rules and which address values appear in allowlists by observing whether the call reverts with `RuleNotActive` or `AddressNotInAllowlist`. This directly leaks the guard's entire policy configuration to any external observer.

More critically, because `validateCall` is `public` and unrestricted, if a future upgrade or integration expects that only the Safe or the guard itself calls `validateCall`, the lack of access control becomes an authorization bypass surface. The function is effectively part of the external API but serves purely as an internal routing mechanism.

**Impact:**
- Complete disclosure of the guard's rule configuration (active targets, function selectors, address allowlists) to any external party without requiring any privileged role.
- An attacker preparing to exploit the Safe can first map the entire rule set to identify which transactions are permitted and craft attacks that fit within allowed patterns.
- If a custom `IValidator` implementation has side effects or state-dependent behavior, arbitrary callers can trigger validator logic by calling `validateCall` directly.

**Recommendation:**
Restrict `validateCall` so it can only be called by `address(this)` (the self-call pattern). For example:

```solidity
function validateCall(address target, uint256 value, bytes calldata data) external view {
    require(msg.sender == address(this), "SafeGuard: only self-call");
    Guard.validateCall(target, value, data);
}
```

Alternatively, use an `internal` helper with an `external` wrapper that enforces the self-call constraint.

---

### [HIGH] OA-SG-04: Guard can be fully disabled by `GUARD_ADMIN_ROLE` without timelock, enabling instant bypass of all transaction validation

**Pipeline:** Forefy / Archethect
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:145-153

**Description:**
The functions `setCheckTransactionEnabled(bool)` and `setCheckModuleTransactionEnabled(bool)` allow a holder of `GUARD_ADMIN_ROLE` to instantly disable all transaction validation by setting either flag to `false`. When `checkTransactionEnabled` is `false`, `checkTransaction` returns immediately without any validation (line 101). Similarly, when `checkModuleTransactionEnabled` is `false`, `checkModuleTransaction` returns `bytes32(0)` without validation (line 126).

This is not a direct privileged-role malicious-action finding. Rather, it is an authority propagation and composition risk: if the `GUARD_ADMIN_ROLE` is held by a governance multisig, a compromised signer (or a social engineering attack on the timelock proposer) can disable all guards in a single transaction. There is no cooling-off period, no event-driven alert window for monitoring systems to react before the disable takes effect, and no minimum-enabled duration. The disable is effective immediately within the same block.

The Archethect adversarial-deep analysis identifies this as a config-interaction vector: the combination of (1) instant disable capability and (2) no timelock creates a window where a compromised admin can disable guards and execute a malicious Safe transaction atomically in the same block, leaving no time for defensive monitoring.

**Impact:**
- A compromised `GUARD_ADMIN_ROLE` holder can atomically disable all guard checks and execute arbitrary transactions through the Safe in the same block.
- No external monitoring system can detect and react to the guard being disabled before the malicious transaction executes.
- This effectively reduces the security of the entire guard system to the security of the `GUARD_ADMIN_ROLE` key, with no defense-in-depth.

**Recommendation:**
Implement a timelock or a two-step process for disabling the guard:
1. Add a `pendingDisable` state with a minimum delay (e.g., 24 hours) before the disable takes effect.
2. Emit events on the pending state change so monitoring systems can alert.
3. Alternatively, require a separate role (e.g., a security council multisig) to confirm the disable action.

---

### [MEDIUM] OA-SG-05: `checkTransaction` reverts on ETH transfers with empty calldata, but does not validate ETH value on calls with data, allowing unrestricted ETH drainage via permitted function calls

**Pipeline:** Archethect
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:88-104 and `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/module/Guard.sol`:9-29

**Description:**
The `Guard.validateCall` function extracts a 4-byte function selector from `data[:4]` (line 10 of Guard.sol) and validates the target + selector against configured rules. However, the `value` parameter (amount of ETH sent with the call) is only passed to a custom `IValidator` if one is configured (line 18). When no custom validator is set (the common case with just `paramRules`), the `value` parameter is completely ignored by the validation logic.

This means a Safe transaction calling a permitted function on a permitted target can attach arbitrary ETH value. For example, if a rule permits calling `token.transfer(address,uint256)` on a specific target, the transaction can also send the Safe's entire ETH balance along with that call. The NatSpec on `checkTransaction` (line 83) states "Reverts on empty calldata (data.length < 4). ETH transfers with empty data are blocked." This confirms that plain ETH transfers are blocked, but it implicitly acknowledges that ETH sent alongside function calls is not validated.

The Archethect economic-differential analysis flags this as a boundary-behavior issue: the guard creates a false sense of security by blocking plain ETH transfers while allowing the same economic outcome (draining ETH) through any permitted function call.

**Impact:**
- An operator with access to submit Safe transactions can drain the Safe's entire ETH balance by piggy-backing ETH value onto any permitted function call.
- The guard's intent to restrict ETH movements is incomplete -- plain transfers are blocked but ETH attached to function calls is not.
- If the Safe holds significant ETH, this is a direct fund-loss vector for any party that can submit transactions to the Safe (subject to signature thresholds).

**Recommendation:**
Add ETH value validation to the `Guard.validateCall` function, either:
1. Reject any call with `value > 0` unless the rule explicitly allows ETH transfer for that function.
2. Add a `maxValue` field to `FunctionRule` that caps the ETH that can be sent with each call.
3. At minimum, add a global `allowETHTransfer` flag per rule that must be explicitly set.

---

### [MEDIUM] OA-SG-06: Missing storage gap in `SafeGuard` risks storage collision on upgrade due to multiple inheritance with `AccessControlUpgradeable`

**Pipeline:** Forefy
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:15

**Description:**
`SafeGuard` inherits from `BaseTransactionGuard`, `BaseModuleGuard`, and `AccessControlUpgradeable`. The contract uses an upgradeable pattern (evidenced by `_disableInitializers()` in the constructor at line 57 and the `initializer` modifier on `initialize` at line 65). While the contract's own state uses a diamond storage pattern (`_getSafeGuardStorage()` with an assembly-set slot at line 36), the parent contracts `BaseTransactionGuard` and `BaseModuleGuard` from the Gnosis Safe codebase may use sequential storage slots.

The contract declares no `__gap` array to reserve storage slots for future state variables. If `SafeGuard` is upgraded to a V2 that adds new state variables in the contract body (not in the diamond storage struct), these variables could collide with storage slots used by the inherited contracts or by variables added in a later version of `AccessControlUpgradeable`.

The `AccessControlUpgradeable` from OpenZeppelin does include its own `__gap`, but the Safe base contracts (`BaseTransactionGuard`, `BaseModuleGuard`) may not. Without a `__gap` in `SafeGuard` itself, any future V2 implementation adding state variables at the contract level risks corrupting the storage layout.

**Impact:**
- A future upgrade adding state variables to `SafeGuard` (outside the diamond storage struct) could overwrite storage used by parent contracts, corrupting access control state or guard configuration.
- The severity depends on whether future upgrades add contract-level state variables. The current implementation is safe because it only uses diamond storage for its own state.

**Recommendation:**
Add a `__gap` array at the end of the contract to reserve storage slots for future upgrades:

```solidity
uint256[50] private __gap;
```

This is a low-cost defensive measure that prevents storage collision if the contract is later extended with additional state variables outside the diamond storage struct.

---

### [MEDIUM] OA-SG-07: Self-call in `checkTransaction`/`checkModuleTransaction` converts `view` to an external call, risking unexpected behavior if the guard contract is behind a proxy with fallback logic

**Pipeline:** Archethect
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:103, 128

**Description:**
Both `checkTransaction` (line 103) and `checkModuleTransaction` (line 128) perform external self-calls via `SafeGuard(address(this)).validateCall(to, value, data)`. The comment explains this is done to convert `memory` parameters to `calldata` for the `Guard.validateCall` library function. While this is a valid workaround, it introduces several subtle risks:

1. **Gas overhead and out-of-gas risk:** Each external self-call incurs the overhead of an external CALL opcode (~2600 gas for a warm address, plus calldata encoding costs). For every Safe transaction, this extra gas is consumed. If the Safe sets a tight `safeTxGas` limit, the guard check itself could run out of gas, causing the guard check to revert and blocking the transaction even if it would be permitted.

2. **Reentrancy surface through the self-call:** The external call to `address(this)` means the guard contract is calling itself. If the guard is deployed behind a proxy (which is the case given the upgradeable pattern), the call goes through the proxy's `fallback`, then to the implementation's `validateCall`. This creates a surface where the proxy could be manipulated (e.g., during an upgrade) to route the self-call differently.

3. **`STATICCALL` semantics:** The `checkTransaction` function is `view`, so the self-call via `SafeGuard(address(this)).validateCall(...)` uses `STATICCALL`. If a custom `IValidator.validate()` attempts any state modification, it will silently fail inside the `STATICCALL` context without reverting, potentially leading to validators that appear to pass but actually do not execute their intended checks.

**Impact:**
- Custom validators that require state writes (e.g., rate limiting, nonce tracking) will silently fail within the `STATICCALL` context, providing a false sense of security.
- Increased gas consumption per transaction could push borderline transactions over gas limits.
- The self-call pattern through a proxy adds an extra trust assumption on the proxy's routing behavior.

**Recommendation:**
1. Document clearly that custom `IValidator` implementations MUST be pure/view functions and cannot rely on state modifications.
2. Consider changing `checkTransaction` and `checkModuleTransaction` from `view` to `external` (non-view) if custom validators need state-writing capability. This would require the Safe to call the guard without `STATICCALL`.
3. Alternatively, refactor to avoid the self-call pattern entirely by accepting `calldata` parameters directly or using `abi.decode` internally.

---

### [LOW] OA-SG-08: `initialize` does not validate that `_admin` is not `address(0)`, allowing deployment of a permanently unmanageable guard

**Pipeline:** Forefy
**Confidence:** High
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:65-77

**Description:**
The `initialize` function grants `DEFAULT_ADMIN_ROLE`, `PROCESSOR_MANAGER_ROLE`, and `GUARD_ADMIN_ROLE` to the `_admin` parameter (lines 71-73). However, there is no check that `_admin != address(0)`. If `address(0)` is passed as `_admin`, all three roles are granted to the zero address. Since no one controls the zero address, the guard becomes permanently unmanageable:
- No new processor rules can be set (requires `PROCESSOR_MANAGER_ROLE`).
- The guard cannot be enabled or disabled (requires `GUARD_ADMIN_ROLE`).
- No new roles can be granted (requires `DEFAULT_ADMIN_ROLE`).

Since `initialize` can only be called once (due to the `initializer` modifier), this misconfiguration is irreversible. The guard would be permanently locked in whatever state was set during initialization.

**Impact:**
- A deployment error passing `address(0)` as admin permanently locks the guard configuration.
- The guard would remain enabled (as set by `_setCheckTransactionEnabled(true)` during init) but with no ability to update rules, potentially blocking all Safe transactions permanently if no rules are configured.
- While this requires a deployment error, the immutable and irreversible nature of the consequence warrants defensive validation.

**Recommendation:**
Add a zero-address check in `initialize`:

```solidity
require(_admin != address(0), "SafeGuard: admin is zero address");
```

---

### [LOW] OA-SG-09: `supportsInterface` does not include `BaseModuleGuard`'s actual interface ID, potentially causing incorrect ERC-165 responses for module guard detection

**Pipeline:** Archethect
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:229-240

**Description:**
The `supportsInterface` function overrides the implementations from `BaseTransactionGuard`, `BaseModuleGuard`, and `AccessControlUpgradeable`. The override explicitly checks for `ITransactionGuard`, `IModuleGuard`, `IERC165`, and `IAccessControl` interface IDs. However, the function does not call `super.supportsInterface(interfaceId)`, which means any interface IDs registered by the parent contracts' own `supportsInterface` implementations (beyond those explicitly listed) are not recognized.

If `AccessControlUpgradeable.supportsInterface` registers additional interface IDs (such as `IAccessControlEnumerable` if the contract were to later inherit it), the override would silently drop those. More immediately, the hardcoded interface ID values in the comments (`0xe6d7a83a` for `ITransactionGuard`, `0x58401ed8` for `IModuleGuard`) should be verified against the actual interface definitions in the Safe codebase. If the Safe updates these interface IDs in a future version, the guard's `supportsInterface` would return incorrect results.

**Impact:**
- If the Safe's `ModuleManager` or `GuardManager` uses `supportsInterface` to verify that the guard supports the correct interface before setting it, an incorrect response could prevent the guard from being set on the Safe. Conversely, if a parent interface ID changes, the guard could be incorrectly accepted or rejected.
- The practical risk is limited because the Safe currently checks for these exact interface IDs and they are unlikely to change.

**Recommendation:**
Call `super.supportsInterface(interfaceId)` as a fallback to ensure all parent-registered interfaces are supported:

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override(...) returns (bool) {
    return interfaceId == type(ITransactionGuard).interfaceId
        || interfaceId == type(IModuleGuard).interfaceId
        || super.supportsInterface(interfaceId);
}
```

---

### [LOW] OA-SG-10: `setProcessorRules` does not validate that `target` addresses are non-zero, allowing rules to be set for `address(0)` which would never match real transactions

**Pipeline:** Forefy
**Confidence:** Medium
**File:** `/home/claudeuser/source/smart-contracts-mirror/safeguard/src/SafeGuard.sol`:193-199 and `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/library/VaultLib.sol`:332-344

**Description:**
The `setProcessorRules` function delegates to `VaultLib.setProcessorRules`, which iterates over the input arrays and calls `setProcessorRule` for each element. Neither function validates that the `target` address is non-zero. A rule set for `address(0)` would be stored in the mapping but would never match any real Safe transaction (since `to` in a real transaction would never be `address(0)` for a meaningful call).

Additionally, `functionSig` is not validated against `bytes4(0)`, and the arrays are not checked for duplicates. This means an admin could accidentally configure rules for invalid targets or overwrite rules by including the same target+functionSig pair twice in the arrays (with potentially different rules, where the last one wins).

**Impact:**
- Rules set for `address(0)` waste gas and create configuration noise without providing any security benefit.
- Duplicate entries in the arrays silently overwrite each other, potentially causing the admin to believe a rule is configured one way when it was actually overwritten.
- This is a defensive-coding concern rather than an exploitable vulnerability.

**Recommendation:**
Add input validation in `setProcessorRules`:
1. Validate `target[i] != address(0)` for each entry.
2. Consider validating `functionSig[i] != bytes4(0)`.
3. Document the last-writer-wins behavior for duplicate entries, or check for duplicates.

---

### [LOW] OA-SG-11: Guard validation relies on positional ABI parameter decoding, which can be bypassed with non-standard ABI encoding

**Pipeline:** Archethect
**Confidence:** Low
**File:** `/home/claudeuser/source/smart-contracts-mirror/yieldnest-vault/src/module/Guard.sol`:22-28

**Description:**
The `Guard.validateCall` function validates parameters by decoding them at fixed offsets: `abi.decode(data[4 + i * 32:], (address))` (line 24). This assumes that parameters are ABI-encoded in standard sequential format, where parameter `i` starts at byte offset `4 + i * 32`.

However, the ABI specification allows dynamic types (arrays, bytes, strings) to use offset pointers. If a function signature includes dynamic types before an ADDRESS parameter, the ADDRESS parameter's actual data will not be at the expected fixed offset. The guard would decode the wrong bytes as an address, potentially validating an incorrect value.

For example, consider a function `foo(bytes data, address recipient)`. The `paramRules[1]` (for the address parameter at index 1) would decode `data[4 + 1*32:]` which would actually contain the offset pointer for the `bytes` parameter's data, not the `address` value. The actual address would be at a different offset determined by the dynamic encoding.

Note: This issue is partially related to SG-02 (non-ADDRESS types silently skipped). While SG-02 covers the `UINT256` type being skipped, this finding addresses the broader issue that even ADDRESS validation is incorrect when dynamic types precede it in the function signature.

**Impact:**
- Rules for functions with dynamic-type parameters preceding ADDRESS parameters will validate incorrect data, potentially allowing unauthorized addresses to pass allowlist checks.
- The severity depends on which function signatures are configured as rules. If all configured functions use only fixed-size types (address, uint256, bool, etc.) in the correct order, this issue does not manifest.

**Recommendation:**
1. Document that `Guard.validateCall` only supports function signatures with fixed-size parameter types, and that dynamic types (bytes, string, arrays) must not precede validated ADDRESS parameters.
2. Consider implementing proper ABI decoding that respects offset pointers for dynamic types.
3. Alternatively, restrict `paramRules` validation to only the first N parameters and require that validated parameters appear before any dynamic types in the function signature.

---

## Summary

| ID | Severity | Title | Pipeline |
|----|----------|-------|----------|
| OA-SG-03 | HIGH | `validateCall` is public with no access control | Forefy |
| OA-SG-04 | HIGH | Guard can be fully disabled without timelock | Forefy / Archethect |
| OA-SG-05 | MEDIUM | ETH value not validated on permitted function calls | Archethect |
| OA-SG-06 | MEDIUM | Missing `__gap` for upgradeable storage safety | Forefy |
| OA-SG-07 | MEDIUM | Self-call pattern risks with STATICCALL and proxy routing | Archethect |
| OA-SG-08 | LOW | `initialize` does not validate `_admin != address(0)` | Forefy |
| OA-SG-09 | LOW | `supportsInterface` does not call `super` | Archethect |
| OA-SG-10 | LOW | No validation of `address(0)` in `setProcessorRules` | Forefy |
| OA-SG-11 | LOW | Positional ABI decoding fails with dynamic-type parameters | Archethect |

**Total: 2 High, 3 Medium, 4 Low**
