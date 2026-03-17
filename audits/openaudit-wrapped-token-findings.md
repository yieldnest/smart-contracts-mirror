# OpenAudit -- WrappedToken Findings

**Target:** `/home/claudeuser/source/smart-contracts-mirror/wrapped-token/src/`
**Contracts in scope:** `WrappedToken.sol`, `IWrappedToken.sol`
**Date:** 2026-03-17
**Pipelines:** Forefy Smart Contract Audit, Archethect SC Auditor (Map-Hunt-Attack)

## Existing Findings (NOT re-reported)

- **WT-01 [Medium]:** Storage slot occupies ERC-1967 implementation namespace
- **WT-02 [Medium]:** Fee-on-transfer token incompatibility in deposit()

---

## New Findings

### [MEDIUM] OA-WT-03: redeem() burns shares when convertToAssets rounds to zero, causing permanent loss of user funds

**Pipeline:** Forefy (Precision Errors layer), confirmed by Archethect (accounting-entitlement hunt lane)
**Confidence:** High
**File:** `wrapped-token/src/WrappedToken.sol:110-123` (redeem function) and `:140-143` (convertToAssets)

**Description:**

When `decimalsOffset > 0`, the `convertToAssets()` function divides shares by `10 ** decimalsOffset` using `Math.mulDiv` with `Rounding.Floor`. If a user calls `redeem()` with a `shares` amount smaller than `10 ** decimalsOffset`, the computed `assets` value rounds down to zero. Despite this, the function proceeds to burn the user's shares via `_burn(owner, shares)` and then transfers zero underlying tokens to the receiver via `safeTransfer(asset, receiver, 0)`. The user permanently loses their shares and receives nothing in return.

This situation arises naturally because ERC-20 tokens permit transfers of arbitrary amounts. A user can receive shares via a standard `transfer()` call in any quantity, including amounts that are not aligned to the `10 ** decimalsOffset` granularity. For example, with `decimalsOffset = 12` (wrapping a 6-decimal token like USDC into 18 decimals), any user holding fewer than `10^12` shares (worth less than 1 USDC unit but still potentially valuable fractions) will lose them entirely upon redemption.

The vulnerable code path is:

```solidity
function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
    uint256 assets = convertToAssets(shares); // rounds to 0 for small shares
    // ... allowance check ...
    _burn(owner, shares);                     // burns user's shares
    SafeERC20.safeTransfer(IERC20(asset()), receiver, assets); // transfers 0
    return assets;                            // returns 0
}
```

There is no `require(assets > 0)` guard to prevent this zero-value redemption.

**Impact:**

Users who hold wrapped token shares in amounts not aligned to the decimal offset granularity will permanently lose those shares when attempting to redeem. With `decimalsOffset = 12`, up to `999,999,999,999` shares (worth approximately 0.999999 of the underlying token) can be silently destroyed per redemption. While individually these amounts may seem small, they accumulate across many users and represent real value extraction from the system -- the underlying tokens backing those burned shares become unclaimable surplus that benefits no one.

Additionally, this enables a griefing vector: an attacker can send dust share amounts to a victim's address. When the victim redeems their full balance (which may now not be cleanly divisible by `10 ** decimalsOffset`), the remainder is trapped and must be redeemed separately at a loss.

**Recommendation:**

Add a zero-amount check in `redeem()`:
```solidity
function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
    uint256 assets = convertToAssets(shares);
    require(assets > 0, "WrappedToken: zero assets");
    // ... rest of function
}
```

---

### [LOW] OA-WT-04: No validation of decimalsOffset in initialize() allows permanent bricking via overflow

**Pipeline:** Archethect (semantic-consistency hunt lane, boundary behavior analysis)
**Confidence:** High
**File:** `wrapped-token/src/WrappedToken.sol:57-84` (initialize and _initialize)

**Description:**

The `initialize()` and `_initialize()` functions accept a `uint8 tokenDecimalsOffset` parameter but do not validate that the value is within a safe range. The `convertToShares()` function computes `assets * (10 ** ts.decimalsOffset)`, and `convertToAssets()` computes `Math.mulDiv(shares, 1, 10 ** ts.decimalsOffset)`. Since `10 ** decimalsOffset` is computed at runtime using Solidity 0.8's checked arithmetic, any `decimalsOffset` value greater than 77 causes `10 ** decimalsOffset` to overflow `uint256`, making both `convertToShares()` and `convertToAssets()` permanently revert.

If a proxy is initialized with `decimalsOffset > 77`:
- `deposit()` will always revert (cannot compute shares)
- `redeem()` will always revert (cannot compute assets)
- Any underlying tokens sent to the contract before or during initialization become permanently locked

While `decimalsOffset` is set during initialization (a privileged operation), the ERC-7201 namespaced storage pattern and proxy architecture suggest this contract will be deployed by factories or governance systems. A configuration error (e.g., passing raw decimal values instead of the offset) could brick the deployment.

The practical range for `decimalsOffset` should be 0-18 (covering the span from equal-decimal tokens to the maximum ERC-20 decimal difference). Any value above ~60 is nonsensical for token decimal normalization, and values above 77 are mathematically impossible.

**Impact:**

Misconfiguration permanently bricks the wrapped token contract. If any underlying tokens are sent to the contract address before the issue is detected, those tokens are permanently locked. This is a deployment-phase risk mitigated by careful deployment practices, but the lack of any on-chain guard makes it a latent hazard.

**Recommendation:**

Add validation in `_initialize()`:
```solidity
function _initialize(
    IERC20 underlyingToken,
    string memory name,
    string memory symbol,
    uint8 decimalsValue,
    uint8 tokenDecimalsOffset
) internal {
    if (address(underlyingToken) == address(this)) {
        revert ERC20InvalidUnderlying(address(this));
    }
    require(tokenDecimalsOffset <= 18, "WrappedToken: offset too large");
    require(address(underlyingToken) != address(0), "WrappedToken: zero address");
    // ... rest of initialization
}
```

---

### [LOW] OA-WT-05: Missing zero-address validation for underlyingToken in initialize()

**Pipeline:** Forefy (Access Control layer), confirmed by Archethect (semantic-consistency lane)
**Confidence:** High
**File:** `wrapped-token/src/WrappedToken.sol:67-84` (_initialize function)

**Description:**

The `_initialize()` function validates that `address(underlyingToken) != address(this)` but does not check that `address(underlyingToken) != address(0)`. If the underlying token is set to `address(0)`:

1. `asset()` returns `address(0)`
2. `deposit()` calls `SafeERC20.safeTransferFrom(IERC20(address(0)), ...)` which will revert because `address(0)` has no code, causing the low-level call to return empty data. SafeERC20 handles this differently depending on the OpenZeppelin version -- in some versions it reverts, in others it may not.
3. `backing()` calls `IERC20(address(0)).balanceOf(address(this))` which similarly may revert or return 0.

While `deposit()` would likely revert, the contract would be in a partially functional but broken state. The `backing()` view function behavior is unpredictable, and any integrating contracts that check `backing()` before depositing could receive misleading data.

**Impact:**

Initializing with `address(0)` as the underlying token creates a permanently non-functional contract. While this requires a deployment error, the missing validation violates defensive programming principles, especially for a contract designed to be deployed behind proxies where initialization parameters are passed externally.

**Recommendation:**

Add a zero-address check in `_initialize()`:
```solidity
if (address(underlyingToken) == address(0)) {
    revert ERC20InvalidUnderlying(address(0));
}
```

---

### [INFORMATIONAL] OA-WT-06: ALLOCATOR_ROLE constant is declared but never used

**Pipeline:** Forefy (Technical layer), confirmed by Archethect (semantic-consistency lane)
**Confidence:** High
**File:** `wrapped-token/src/WrappedToken.sol:42`

**Description:**

The contract declares a public constant `ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE")` on line 42, but this role is never referenced in any function modifier, access control check, or role assignment. There is no `AccessControl` or similar role-based access system inherited by the contract. The constant occupies bytecode space and may mislead auditors or integrators into believing the contract has role-based access control when it does not.

**Impact:**

No security impact. This is dead code that increases deployment gas cost marginally and reduces code clarity.

**Recommendation:**

Remove the unused `ALLOCATOR_ROLE` constant, or implement the intended access control functionality if allocator management was a planned feature.

---

### [INFORMATIONAL] OA-WT-07: deposit() follows Check-Interaction-Effect ordering instead of Check-Effect-Interaction

**Pipeline:** Forefy (Technical layer, reentrancy analysis), Archethect (callback-liveness hunt lane)
**Confidence:** Medium
**File:** `wrapped-token/src/WrappedToken.sol:92-101` (deposit function)

**Description:**

The `deposit()` function performs the external token transfer (`safeTransferFrom`) before the state-modifying `_mint()` call:

```solidity
function deposit(uint256 amount, address receiver) public returns (uint256) {
    uint256 shares = convertToShares(amount);
    SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount); // external call
    _mint(receiver, shares); // state change
    emit Deposit(msg.sender, receiver, amount, shares);
    return shares;
}
```

This violates the recommended Checks-Effects-Interactions (CEI) pattern by performing the interaction (token transfer) before the effect (share minting). If the underlying token implements ERC-777 hooks or similar callback mechanisms, the `tokensToSend` hook on `msg.sender` fires before shares are minted.

However, after applying the Archethect skeptic analysis and hard-negative filtering:

- The callback fires on `msg.sender` (the depositor), not on a third party. The depositor can only re-enter with their own funds.
- During the callback window, no shares have been minted yet, so re-entering `redeem()` would attempt to burn non-existent shares and revert.
- Re-entering `deposit()` again during the callback is a self-call that transfers more of the caller's own tokens -- this is not exploitable.
- The `redeem()` function correctly follows CEI (burn before transfer).

This is classified as informational rather than a vulnerability because the CIE ordering in `deposit()` does not create an exploitable reentrancy path in the current contract. However, if the contract is extended with additional state-reading functions or if future upgrades add complexity, this ordering could become a vector.

**Impact:**

No immediate exploitable impact. This is a code quality concern that represents a latent risk for future modifications.

**Recommendation:**

Reorder `deposit()` to follow CEI -- mint shares before transferring tokens:
```solidity
function deposit(uint256 amount, address receiver) public returns (uint256) {
    uint256 shares = convertToShares(amount);
    _mint(receiver, shares);
    SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
    emit Deposit(msg.sender, receiver, amount, shares);
    return shares;
}
```

Note: This reordering means shares are minted before the underlying transfer succeeds. If the transfer reverts, the entire transaction reverts including the mint, so atomicity is preserved. However, during a callback from the transferFrom, the receiver would hold shares without the contract holding the underlying tokens -- this is the opposite tradeoff and should be evaluated in context.

---

## Audit Coverage Summary

### Forefy 5-Layer Analysis

| Layer | Status | Key Observations |
|-------|--------|------------------|
| **Protocol** | Covered | Wrapped token with decimal normalization; fixed 1:1 exchange rate adjusted by offset; no variable share pricing |
| **Economic** | Covered | No fee mechanism; no exchange rate manipulation surface (fixed offset); rounding loss in convertToAssets identified (OA-WT-03) |
| **Access Control** | Covered | No admin functions post-initialization; initializer-guarded; unused ALLOCATOR_ROLE (OA-WT-06); missing zero-address validation (OA-WT-05) |
| **Integration** | Covered | SafeERC20 used throughout; fee-on-transfer covered by existing WT-02; ERC-20 conformance verified |
| **Technical** | Covered | Storage layout collision covered by existing WT-01; CEI ordering analyzed (OA-WT-07); overflow in decimalsOffset (OA-WT-04) |

### Archethect MAP-HUNT-ATTACK Analysis

**MAP Phase -- Architecture:**
- Single contract (`WrappedToken`) inheriting `Initializable` and `ERC20Upgradeable`
- Custom storage via ERC-7201-style namespaced slot (but with incorrect derivation, see WT-01)
- External surfaces: `deposit()`, `redeem()`, `convertToShares()`, `convertToAssets()`, `asset()`, `decimals()`, `decimalsOffset()`, `backing()`
- Value flow: underlying token IN via safeTransferFrom, wrapped shares minted; shares burned, underlying OUT via safeTransfer
- Key invariant: `IERC20(asset()).balanceOf(address(this)) >= convertToAssets(totalSupply())`

**HUNT Phase -- 6 Lanes:**

| Lane | Hotspots Found | Disposition |
|------|----------------|-------------|
| **accounting-entitlement** | 1 | OA-WT-03 (rounding to zero in redeem) -- confirmed as new finding |
| **adversarial-deep** | 0 | No cross-contract interactions; single-contract system |
| **callback-liveness** | 1 | OA-WT-07 (CIE ordering in deposit) -- downgraded to informational after skeptic analysis |
| **economic-differential** | 1 | Rounding asymmetry in deposit/redeem pair -- deduplicated with OA-WT-03 |
| **semantic-consistency** | 2 | OA-WT-04 (unbounded decimalsOffset), OA-WT-06 (unused ALLOCATOR_ROLE) |
| **token-oracle-statefulness** | 1 | Fee-on-transfer handling -- deduplicated with existing WT-02 |

**ATTACK Phase:**
- OA-WT-03: Sustained through DA protocol. Exploit sketch confirmed: transfer dust shares to victim, victim redeems, loses shares.
- OA-WT-04: Sustained through DA protocol. Configuration-dependent, reduced from medium to low per conservative calibration.
- OA-WT-07: Invalidated as exploitable vulnerability through DA protocol. Reclassified as informational.

**SKEPTIC Phase:**
- OA-WT-03: Skeptic attempted negation by checking if OpenZeppelin's _mint/ERC20 reverts on zero. It does not -- zero-amount operations are permitted. Finding confirmed.
- OA-WT-04: Skeptic noted this requires privileged misconfiguration. Maintained as low severity per "privileged roles act in good faith" principle, but the missing validation is a real gap.

### Vulnerability Categories Checked (No Issues Found)

- **Reentrancy**: No exploitable reentrancy paths. `redeem()` correctly follows CEI. `deposit()` CIE ordering is safe in current implementation.
- **Oracle manipulation**: No oracle dependencies. Fixed decimal offset conversion.
- **Flash loan attacks**: No variable exchange rate to manipulate. Fixed conversion means no price manipulation surface.
- **First-depositor / share inflation**: Not applicable. Exchange rate is fixed by `decimalsOffset`, not by `totalSupply / totalAssets` ratio. Donation of underlying tokens does not affect the share price.
- **Proxy upgrade safety**: Covered by existing WT-01. No `_authorizeUpgrade` function (UUPS) present. Contract relies on external proxy for upgradeability.
- **Signature replay**: No signature-based operations.
- **Unbounded loops**: No loops in the contract.
- **Governance manipulation**: No governance mechanisms.
- **Slippage / MEV**: No swaps or price-dependent operations.
