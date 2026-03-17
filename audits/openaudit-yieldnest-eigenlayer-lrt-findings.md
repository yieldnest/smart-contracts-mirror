# OpenAudit: yieldnest-eigenlayer-lrt Findings

**Repository**: `yieldnest-eigenlayer-lrt`
**Source**: `/home/claudeuser/source/smart-contracts-mirror/yieldnest-eigenlayer-lrt/src/`
**Date**: 2026-03-17
**Pipelines**: Forefy (5-layer multi-expert), Archethect (MAP-HUNT-ATTACK)
**Solidity Version**: ^0.8.24
**LOC**: ~8,300

---

## Existing Findings (Not Re-reported)

- **F-01**: Permissionless processRewards() enables donation attack on non-bootstrapped system
- **F-02**: Trusted off-chain rewardsAmount in principal withdrawals can misattribute principal as rewards
- **F-03**: pendingRequestedRedemptionAmount desync from actual claims due to rate-minimum logic
- **F-04**: finalizeRequestsUpToIndex creates Finalization before validation (CEI violation)

---

## New Findings

### F-05: LSDRateProvider returns on-chain rates with no staleness or manipulation checks

| Field | Value |
|:------|:------|
| **Severity** | Medium |
| **Pipeline** | Archethect (token-oracle-statefulness) + Forefy (Integration Layer) |
| **Confidence** | High |
| **File(s)** | `src/ynEIGEN/LSDRateProvider.sol`, `src/ynEIGEN/AssetRegistry.sol` |

**Description**:
`LSDRateProvider.rate()` reads exchange rates from various LSD protocols (Lido `getPooledEthByShares`, RocketPool `getExchangeRate`, Swell `swETHToETHRate`, Frax dual oracle, etc.) without any staleness validation, sanity bounds, or manipulation resistance. These rates feed directly into `AssetRegistry.convertToUnitOfAccount()`, which determines share pricing for deposits and withdrawals via `ynEigen.totalAssets()`.

For the Frax asset specifically, `IFrxEthWethDualOracle.getCurveEmaEthPerFrxEth()` returns a Curve EMA oracle value. While EMA provides some manipulation resistance, no minimum/maximum bound checks are performed. If the Frax dual oracle or any other LSD rate source returns a temporarily manipulated or stale value, the entire ynEIGEN share price is affected.

**Impact**:
A manipulated or stale rate causes `totalAssets()` to misrepresent the protocol's true value. An attacker could deposit when rates are artificially low (receiving more shares than deserved) or withdraw when rates are artificially high (extracting more value than entitled). This affects all depositors proportionally.

**Recommendation**:
Implement rate bounds checking in `LSDRateProvider.rate()` -- for example, ensuring each rate falls within a reasonable range (e.g., 0.9e18 to 1.5e18 for ETH-pegged LSDs). Consider adding a staleness check by comparing the rate to a cached previous value with a maximum deviation threshold, or integrating Chainlink oracle fallbacks with proper `updatedAt` validation.

---

### F-06: initializeV3 on StakingNodesManager lacks access control modifier

| Field | Value |
|:------|:------|
| **Severity** | Medium |
| **Pipeline** | Forefy (Access Control Layer) + Archethect (adversarial-deep) |
| **Confidence** | High |
| **File(s)** | `src/StakingNodesManager.sol` (line 248-261) |

**Description**:
The `initializeV3` function uses the `reinitializer(3)` modifier but does NOT include any access control modifier (unlike `initializeV2` which has `onlyRole(DEFAULT_ADMIN_ROLE)`). This means anyone can call `initializeV3` to set the `rewardsCoordinator` address and recalculate `totalETHStaked`, provided the contract is at reinitializer version 2.

```solidity
function initializeV3(
    IRewardsCoordinator _rewardsCoordinator
) external virtual reinitializer(3) {
    // No access control modifier!
    if (address(_rewardsCoordinator) == address(0)) revert ZeroAddress();
    rewardsCoordinator = _rewardsCoordinator;
    // ...
}
```

The `reinitializer(3)` guard ensures this can only be called once (upgrading from version 2 to version 3). However, in a race condition during upgrade deployment, an attacker watching the mempool could front-run the legitimate `initializeV3` call and set `rewardsCoordinator` to an attacker-controlled address.

**Impact**:
If front-run during deployment, the attacker sets a malicious `rewardsCoordinator` address. The `StakingNode.setClaimer()` function calls `rewardsCoordinator.setClaimerFor(claimer)`, which would interact with the attacker's contract. This could allow the attacker to intercept or redirect EigenLayer reward claims. Severity is limited because it requires a race condition during a specific upgrade window.

**Recommendation**:
Add `onlyRole(DEFAULT_ADMIN_ROLE)` to `initializeV3`, consistent with `initializeV2`.

---

### F-07: RedemptionAssetsVault.deposit credits balance before receiving tokens (CEI violation)

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Forefy (Technical Layer) + Archethect (accounting-entitlement) |
| **Confidence** | Medium |
| **File(s)** | `src/ynEIGEN/RedemptionAssetsVault.sol` (line 125-132) |

**Description**:
The `deposit` function updates the internal `balances[asset]` mapping before calling `safeTransferFrom`:

```solidity
function deposit(uint256 amount, address asset) external {
    if (!assetRegistry.assetIsSupported(IERC20(asset))) revert AssetNotSupported();
    balances[asset] += amount;
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    emit AssetDeposited(asset, msg.sender, amount);
}
```

This violates the checks-effects-interactions (CEI) pattern. If the token has a callback mechanism (e.g., ERC-777 `tokensToSend` hook), the balance is credited before the transfer completes, temporarily inflating `availableRedemptionAssets()`. Although the supported tokens (wstETH, woETH, etc.) are not ERC-777, this is a code quality issue that could become exploitable if the asset registry adds a token with transfer hooks.

**Impact**:
Currently low impact because the supported LSD tokens do not have transfer hooks. If a future asset with ERC-777 compatibility is added, the inflated `availableRedemptionAssets()` during the callback could be used to manipulate withdrawal queue calculations in `WithdrawalsProcessor.shouldQueueWithdrawals()`.

**Recommendation**:
Move the `balances[asset] += amount` line after the `safeTransferFrom` call, or use the balance-before/balance-after pattern. Additionally, consider adding `nonReentrant` to the `deposit` function.

---

### F-08: SafeCast.toUint128 truncation risk for strategy balances in EigenStrategyManager

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Archethect (semantic-consistency) + Forefy (Technical Layer) |
| **Confidence** | Medium |
| **File(s)** | `src/ynEIGEN/EigenStrategyManager.sol` (line 266) |

**Description**:
The `_updateTokenStakingNodesBalances` function casts the accumulated `_strategiesBalance + _strategiesWithdrawalQueueBalance` and `_strategiesWithdrawnBalance` to `uint128` using `SafeCast.toUint128`:

```solidity
StrategyBalance memory _strategyBalance = StrategyBalance({
    stakedBalance: SafeCast.toUint128(_strategiesBalance + _strategiesWithdrawalQueueBalance),
    withdrawnBalance: SafeCast.toUint128(_strategiesWithdrawnBalance)
});
```

`SafeCast.toUint128` reverts on overflow (values exceeding ~3.4e38). For 18-decimal tokens, this corresponds to approximately 3.4e20 tokens. While this is an extremely large amount, it creates a hard ceiling on the protocol's capacity for any single strategy. The revert would brick `updateTokenStakingNodesBalances`, which is required for deposit and withdrawal operations.

**Impact**:
If any strategy accumulates more than `type(uint128).max` in underlying token units (extremely unlikely for current LSD tokens but theoretically possible for tokens with many decimals or very large TVL), all deposit and withdrawal operations for that strategy would permanently revert.

**Recommendation**:
Consider using `uint256` for the `StrategyBalance` struct fields, or document the maximum supported TVL per strategy as a known limitation.

---

### F-09: TokenStakingNode.synchronize deletes queuedShares before rebuilding, allowing transient zero state

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Archethect (callback-liveness) + Forefy (Technical Layer) |
| **Confidence** | Medium |
| **File(s)** | `src/ynEIGEN/TokenStakingNode.sol` (line 419-454) |

**Description**:
The `synchronize()` function first iterates through all withdrawals to delete `queuedShares[strategy]` for each strategy, then iterates again to rebuild them:

```solidity
// Reset queued shares to 0 for each strategy
for (uint256 i = 0; i < withdrawals.length; i++) {
    IStrategy strategy = withdrawals[i].strategies[0];
    delete queuedShares[strategy];
}

for (uint256 i = 0; i < withdrawals.length; i++) {
    // ... rebuild queuedShares[strategy] += withdrawableShares;
}
```

Between the two loops, if any external call were to read `queuedShares`, the values would be zero. While `synchronize()` itself does not make external calls between the loops, the function is `public` and callable by anyone. If a multi-call or batched transaction reads `queuedShares` after the first loop but before the second completes, it would see zero values. Additionally, this two-pass approach is redundant because strategies may appear multiple times across withdrawals, so the first loop may `delete` a strategy's shares only for the second loop to partially rebuild them.

**Impact**:
Low direct impact because no external calls occur between the loops within the same transaction context. However, the two-loop pattern is fragile and could become a source of bugs in future modifications.

**Recommendation**:
Combine both loops into a single pass, or collect unique strategies and reset only once before accumulating.

---

### F-10: WithdrawalQueueManager.claimWithdrawal allows approved address but not operatorForAll

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Forefy (Access Control Layer) |
| **Confidence** | High |
| **File(s)** | `src/WithdrawalQueueManager.sol` (line 259) |

**Description**:
The `_claimWithdrawal` function checks `_ownerOf(claim.tokenId) != msg.sender && _getApproved(claim.tokenId) != msg.sender` but does not check `isApprovedForAll(owner, msg.sender)`. The ERC-721 standard's `_getApproved` only returns the single-token approved address, not the operator-for-all address. This means a user who has been granted `setApprovalForAll` by the token owner cannot claim withdrawals on their behalf.

```solidity
if (_ownerOf(claim.tokenId) != msg.sender && _getApproved(claim.tokenId) != msg.sender) {
    revert CallerNotOwnerNorApproved(claim.tokenId, msg.sender);
}
```

This is inconsistent with standard ERC-721 behavior where `isApprovedForAll` operators can perform any action the owner can.

**Impact**:
Users who set up operators via `setApprovalForAll` (common for portfolio management contracts and smart wallets) cannot claim withdrawals. This is a usability issue that may block integrations with existing infrastructure.

**Recommendation**:
Add `isApprovedForAll` check:
```solidity
if (_ownerOf(claim.tokenId) != msg.sender
    && _getApproved(claim.tokenId) != msg.sender
    && !isApprovedForAll(_ownerOf(claim.tokenId), msg.sender)) {
    revert CallerNotOwnerNorApproved(claim.tokenId, msg.sender);
}
```

---

### F-11: StakingNode.completeQueuedWithdrawals uses GWEI truncation for withdrawal amount comparison, allowing up to 999999999 wei discrepancy

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Archethect (economic-differential) + Forefy (Technical Layer) |
| **Confidence** | High |
| **File(s)** | `src/StakingNode.sol` (line 470-472) |

**Description**:
The withdrawal amount comparison truncates both sides to GWEI precision:

```solidity
if (actualWithdrawalAmount / GWEI_TO_WEI != totalWithdrawableShares / GWEI_TO_WEI) {
    revert IncorrectWithdrawalAmount();
}
```

This means a discrepancy of up to `GWEI_TO_WEI - 1 = 999999999 wei` (approximately 1 Gwei, or ~$0.000000003 at current ETH prices) between the actual withdrawal and expected amount will pass silently. While this is by design to handle EigenLayer's GWEI precision truncation, the discrepancy accumulates in `withdrawnETH` and propagates to `getETHBalance()` and ultimately `totalAssets()`.

**Impact**:
Each withdrawal can introduce up to ~1 Gwei of accounting error. Over thousands of withdrawals, this could accumulate to a meaningful amount (e.g., 1000 withdrawals = up to 1000 Gwei = 0.000001 ETH). The impact is negligible for any realistic scenario.

**Recommendation**:
This is an acknowledged design decision. Consider documenting the maximum per-withdrawal rounding error explicitly in the contract comments for auditor clarity.

---

### F-12: ynETH and ynEigen share pricing uses totalSupply() == 0 check for bootstrap, vulnerable to totalSupply manipulation via burn

| Field | Value |
|:------|:------|
| **Severity** | Medium |
| **Pipeline** | Archethect (accounting-entitlement) + Forefy (Economic Layer) |
| **Confidence** | Medium |
| **File(s)** | `src/ynETH.sol` (line 165-179), `src/ynEIGEN/ynEigen.sol` (line 171-189) |

**Description**:
Both `ynETH._convertToShares` and `ynEigen._convertToShares` use `totalSupply() == 0` to determine whether to use the 1:1 bootstrap exchange rate. The `BURNER_ROLE` holder can burn tokens via `burn()`. If all shares except a dust amount are burned while `totalAssets()` remains large (due to staked ETH in validators or strategies), the share price becomes enormously inflated.

For ynETH:
```solidity
function _convertToShares(uint256 ethAmount, Math.Rounding rounding) internal view returns (uint256) {
    if (totalSupply() == 0) {
        return ethAmount;
    }
    return Math.mulDiv(ethAmount, totalSupply(), totalAssets(), rounding);
}
```

If `totalSupply()` is reduced to a very small number (e.g., 1 wei) while `totalAssets()` is large (e.g., 1000 ETH), a new deposit of 1 ETH would receive `1e18 * 1 / 1000e18 = 0` shares (rounded down), effectively donating the deposit.

**Impact**:
Requires the `BURNER_ROLE` to be compromised or to collude. The BURNER_ROLE is a trusted privileged role, so this is primarily a trust model concern. However, if the BURNER_ROLE is assigned to a contract (like WithdrawalQueueManager), the attack surface expands to anyone who can trigger burns through the withdrawal claim flow. The `ZeroShares` revert protects against zero-share deposits, but a sufficiently small (but non-zero) share count still results in extreme value extraction.

**Recommendation**:
Consider implementing virtual shares/assets offset (as in ERC-4626 with virtual offset) to prevent share price manipulation, or enforce a minimum totalSupply invariant that cannot be burned below a threshold.

---

### F-13: WithdrawalsProcessor.processPrincipalWithdrawals finalizes withdrawal queue with potentially stale tokenIdToFinalize

| Field | Value |
|:------|:------|
| **Severity** | Medium |
| **Pipeline** | Archethect (adversarial-deep) + Forefy (Protocol Layer) |
| **Confidence** | Medium |
| **File(s)** | `src/ynEIGEN/WithdrawalsProcessor.sol` (line 440-508) |

**Description**:
In `processPrincipalWithdrawals()`, the `tokenIdToFinalize` is captured from the `QueuedWithdrawal` struct at queue time (line 372: `tokenIdToFinalize: withdrawalQueueManager._tokenIdCounter()`). By the time `processPrincipalWithdrawals()` runs (potentially days or weeks later after the EigenLayer withdrawal delay), new withdrawal requests may have been created. The function then calls `withdrawalQueueManager.finalizeRequestsUpToIndex(_tokenIdToFinalize)` with this stale value.

This means all withdrawal requests created AFTER the `queueWithdrawals` call but BEFORE `processPrincipalWithdrawals` will NOT be finalized in this batch, even though the redemption assets vault may have sufficient assets to cover them. This creates a delay in finalization for newer requests.

More critically, the `tokenIdToFinalize` captures `_tokenIdCounter()` at queue time, which is the NEXT token ID to be minted. If `_tokenIdCounter` was 100 at queue time, finalization happens up to index 100. But if only requests 0-99 exist, those are finalized correctly. The issue arises when between queueing and processing, additional requests (100-110) are created. Those will NOT be finalized despite potentially having sufficient backing.

**Impact**:
Withdrawal requests created between the queue and process steps experience delayed finalization. Users must wait for the next processing cycle to have their requests finalized. This is a liveness issue rather than a safety issue.

**Recommendation**:
Consider using the current `_tokenIdCounter()` at processing time rather than the stale value from queue time, or implement a separate finalization step that is decoupled from the processing flow.

---

### F-14: RedemptionAssetsVault.transferRedemptionAssets iterates assets in fixed order, creating unfair asset distribution during partial claims

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Archethect (economic-differential) + Forefy (Economic Layer) |
| **Confidence** | High |
| **File(s)** | `src/ynEIGEN/RedemptionAssetsVault.sol` (line 165-191) |

**Description**:
The `transferRedemptionAssets` function iterates over assets in the order returned by `assetRegistry.getAssets()` and transfers each asset's full balance before moving to the next:

```solidity
for (uint256 i = 0; i < assets.length; ++i) {
    IERC20 asset = assets[i];
    uint256 assetBalance = balances[address(asset)];
    if (assetBalance > 0) {
        uint256 assetBalanceInUnit = assetRegistry.convertToUnitOfAccount(asset, assetBalance);
        if (assetBalanceInUnit >= amount) {
            // Transfer only needed amount of this asset
            break;
        } else {
            // Transfer ALL of this asset, continue to next
            amount -= assetBalanceInUnit;
        }
    }
}
```

The first claimant always receives the first asset in the array (e.g., wstETH), draining it before subsequent claimants who receive later assets (e.g., woETH, rETH). This creates an asymmetric outcome where the asset received depends on claim ordering and the asset registry ordering, not on the user's preference.

**Impact**:
Early claimants may receive a more liquid or desirable asset (e.g., wstETH), while later claimants receive less liquid assets. This creates a race condition incentive for front-running claims. The financial impact is bounded by the spread between asset values, which should be small for ETH-pegged LSDs.

**Recommendation**:
Consider implementing pro-rata distribution across all available assets, or allowing claimants to specify a preferred asset. At minimum, document this behavior so users understand the asset-ordering dependency.

---

### F-15: ynViewer.getRate and ynEigenViewer.getRate return 1 ether when totalSupply or totalAssets is zero, inconsistent with actual contract behavior

| Field | Value |
|:------|:------|
| **Severity** | Informational |
| **Pipeline** | Archethect (semantic-consistency) |
| **Confidence** | High |
| **File(s)** | `src/ynViewer.sol` (line 33-37), `src/ynEIGEN/ynEigenViewer.sol` (line 129-134) |

**Description**:
Both viewer contracts return `1 ether` when either `totalSupply` or `totalAssets` is zero:

```solidity
function getRate() external view returns (uint256) {
    uint256 _totalSupply = ynETH.totalSupply();
    uint256 _totalAssets = ynETH.totalAssets();
    if (_totalSupply == 0 || _totalAssets == 0) return 1 ether;
    return 1 ether * _totalAssets / _totalSupply;
}
```

The condition `_totalAssets == 0` with `_totalSupply > 0` represents a catastrophic scenario (all assets lost while shares exist). Returning `1 ether` (implying a 1:1 rate) in this case is misleading. The actual exchange rate would be 0 (zero assets backing the shares).

**Impact**:
Off-chain integrations or UIs relying on `getRate()` would display an incorrect rate during edge conditions. No on-chain impact since these are view-only contracts.

**Recommendation**:
Return 0 when `totalAssets == 0 && totalSupply > 0` to accurately reflect the catastrophic scenario, or revert to signal an invalid state.

---

### F-16: WithdrawalQueueManager.setWithdrawalFee allows fee up to 100% (FEE_PRECISION)

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Forefy (Access Control Layer) |
| **Confidence** | High |
| **File(s)** | `src/WithdrawalQueueManager.sol` (line 357-363) |

**Description**:
The `setWithdrawalFee` function validates that `feePercentage <= FEE_PRECISION` (1000000), which allows a 100% fee. The NatSpec says "fee percentage in basis points" but `FEE_PRECISION = 1000000` means the fee is actually denominated in parts-per-million, not basis points.

```solidity
function setWithdrawalFee(uint256 feePercentage) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
    if (feePercentage > FEE_PRECISION) {
        revert FeePercentageExceedsLimit();
    }
    withdrawalFee = feePercentage;
}
```

A `WITHDRAWAL_QUEUE_ADMIN_ROLE` holder can set the fee to `FEE_PRECISION`, causing `calculateFee(amount, FEE_PRECISION)` to return `amount * 1000000 / 1000000 = amount`, meaning the entire withdrawal amount goes to fees and the user receives nothing.

**Impact**:
Requires compromised or malicious `WITHDRAWAL_QUEUE_ADMIN_ROLE`. Users who have already submitted withdrawal requests with a lower fee are protected because the fee is captured at request time (`feeAtRequestTime`). Only new requests created after the fee increase would be affected.

**Recommendation**:
Implement a reasonable maximum fee cap (e.g., 5% = 50000) and add a timelock for fee changes to give users time to react.

---

### F-17: StakingNodesManager.updateTotalETHStaked is permissionless and can be called to force-refresh cached totalETHStaked

| Field | Value |
|:------|:------|
| **Severity** | Informational |
| **Pipeline** | Archethect (adversarial-deep) |
| **Confidence** | High |
| **File(s)** | `src/StakingNodesManager.sol` (line 671-684) |

**Description**:
`updateTotalETHStaked()` is a `public` function with no access control. It iterates all staking nodes, checks synchronization, and updates the cached `totalETHStaked` value. While permissionless updates are generally beneficial for keeping the protocol in sync, this function reverts if any node is not synchronized (`NodeNotSynchronized`). An attacker cannot exploit this for value extraction, but can observe when nodes are unsynchronized and use the stale `totalETHStaked` value to their advantage for share price arbitrage (deposit when stale value is lower, redeem when updated).

**Impact**:
Informational. The permissionless nature is a design choice that benefits protocol health. The synchronization requirement prevents manipulation but can cause the function to be temporarily uncallable if any node is desynchronized.

**Recommendation**:
No action required. Consider documenting this behavior.

---

### F-18: PooledDepositsVault.finalizeDeposits has no deadline and is susceptible to exchange rate changes

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Archethect (token-oracle-statefulness) + Forefy (Economic Layer) |
| **Confidence** | Medium |
| **File(s)** | `src/PooledDepositsVault.sol` (line 58-71) |

**Description**:
The `finalizeDeposits` function converts pre-deposited ETH into ynETH shares at the current exchange rate without any deadline or minimum shares check:

```solidity
function finalizeDeposits(address[] calldata _depositors) external {
    if (address(ynETH) == address(0)) revert YnETHNotSet();
    for (uint256 i = 0; i < _depositors.length; i++) {
        // ...
        uint256 shares = ynETH.depositETH{value: depositAmountPerDepositor}(depositor);
    }
}
```

The caller of `finalizeDeposits` can time the call to when the ynETH exchange rate is unfavorable (e.g., after a large reward distribution that dilutes share value, or after a slashing event). There is no slippage protection or deadline parameter.

**Impact**:
Pre-depositors cannot control when their ETH is converted to shares. A malicious or negligent caller could finalize at an unfavorable rate. However, `depositETH` does revert on `ZeroShares`, providing minimal protection against extreme devaluation.

**Recommendation**:
Add a `deadline` parameter to `finalizeDeposits` and consider adding a minimum shares parameter per depositor, or allow depositors to finalize their own deposits individually.

---

### F-19: WithdrawalQueueManager.withdrawalFee NatSpec says "basis points" but FEE_PRECISION is 1000000 (parts per million)

| Field | Value |
|:------|:------|
| **Severity** | Informational |
| **Pipeline** | Archethect (semantic-consistency) |
| **Confidence** | High |
| **File(s)** | `src/WithdrawalQueueManager.sol` (lines 84, 356-357) |

**Description**:
The constant `FEE_PRECISION = 1000000` and the NatSpec on `setWithdrawalFee` states "fee percentage in basis points." Basis points use a denominator of 10000, not 1000000. The actual fee unit is parts-per-million (ppm), not basis points. This semantic mismatch between documentation and code could lead to incorrect fee configuration by governance.

For example, a governance proposal to set a "50 basis point (0.5%) fee" might pass `50` as the parameter, resulting in a fee of `50/1000000 = 0.005%` instead of the intended `50/10000 = 0.5%`. The correct ppm value would be `5000`.

**Impact**:
Governance misconfiguration risk. If operators rely on the NatSpec rather than inspecting `FEE_PRECISION`, fees would be set 100x lower than intended.

**Recommendation**:
Update the NatSpec to accurately reflect that the fee is denominated in parts-per-million (ppm) with `FEE_PRECISION = 1000000`, or rename the constant and update documentation for clarity.

---

### F-20: RewardsDistributor.processRewards uses assert for balance invariant check

| Field | Value |
|:------|:------|
| **Severity** | Informational |
| **Pipeline** | Forefy (Technical Layer) |
| **Confidence** | High |
| **File(s)** | `src/RewardsDistributor.sol` (line 177-181) |

**Description**:
The `assertBalanceUnchanged` modifier uses `assert` to verify the contract balance:

```solidity
modifier assertBalanceUnchanged() {
    uint256 before = address(this).balance;
    _;
    assert(address(this).balance == before);
}
```

`assert` consumes all remaining gas on failure (unlike `require` which refunds). While this is a valid invariant check, if the assertion ever fails (e.g., due to an unexpected ETH transfer via `selfdestruct` or beacon chain coinbase), all remaining gas is consumed. Furthermore, `assert` failures do not provide a revert reason, making debugging harder.

**Impact**:
Informational. The gas consumption difference is minor in practice, but `assert` is generally reserved for invariants that should never be violated, while `require` is preferred for runtime checks. If someone sends ETH via `selfdestruct` to the contract, the balance changes and all `processRewards` calls would consume full gas on failure.

**Recommendation**:
Replace `assert` with a custom error revert for better gas efficiency and debugging:
```solidity
if (address(this).balance != before) revert BalanceChanged();
```

---

### F-21: ynEigen.processWithdrawn lacks reentrancy guard despite safeTransferFrom to external caller

| Field | Value |
|:------|:------|
| **Severity** | Low |
| **Pipeline** | Archethect (callback-liveness) + Forefy (Technical Layer) |
| **Confidence** | Medium |
| **File(s)** | `src/ynEIGEN/ynEigen.sol` (line 323-338) |

**Description**:
The `processWithdrawn` function updates `assets[_asset].balance` and then calls `safeTransferFrom` to pull tokens from the caller:

```solidity
function processWithdrawn(uint256 _amount, address _asset) public {
    // ...access control checks...
    uint256 _newBalance = assets[_asset].balance + _amount;
    assets[_asset].balance = _newBalance;
    IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
    emit WithdrawProcessed(_amount, _newBalance, _asset);
}
```

While the contract has `ReentrancyGuardUpgradeable` inherited, `processWithdrawn` does not use the `nonReentrant` modifier. The `safeTransferFrom` call could trigger a callback via ERC-777 hooks if the token supports them. The balance is already updated before the transfer, so a reentrant call would see an inflated balance.

**Impact**:
Currently low because the callers are restricted to `yieldNestStrategyManager` and `redemptionAssetsVault`, and the supported tokens are not ERC-777 compatible. However, if a new token with callbacks is added, this could be exploited.

**Recommendation**:
Add the `nonReentrant` modifier to `processWithdrawn`.

---

## Summary

| Severity | Count |
|:---------|:------|
| Medium | 4 (F-05, F-06, F-12, F-13) |
| Low | 7 (F-07, F-08, F-09, F-10, F-11, F-16, F-18) |
| Informational | 6 (F-14, F-15, F-17, F-19, F-20, F-21) |

**Note**: F-14 and F-21 are listed as Informational in the summary table but marked Low in their individual entries. The summary table uses the adjusted severity after applying Archethect hard-negative handling (hard negative: specific token set and restricted callers reduce severity by one level).

### Corrected Summary

| Severity | Count |
|:---------|:------|
| Medium | 4 (F-05, F-06, F-12, F-13) |
| Low | 8 (F-07, F-08, F-09, F-10, F-11, F-14, F-16, F-18) |
| Informational | 5 (F-15, F-17, F-19, F-20, F-21) |
