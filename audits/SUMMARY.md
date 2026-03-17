# YieldNest Smart Contracts — Multi-Pipeline Security Audit Summary

**Date:** 2026-03-17
**Auditor:** Automated Multi-Pipeline AI Audit Framework
**Scope:** 8 repositories, ~16,000 LOC Solidity

## Methodology

Six independent AI-driven audit pipelines were applied to each repository:

| Pipeline | Methodology | Focus |
|----------|-------------|-------|
| A | SCV Scan | 36 vulnerability pattern matching (reentrancy, overflow, access control, etc.) |
| B | Feynman Business Logic | First-principles interrogation of every function's business logic |
| C | State Inconsistency | Coupled state variable desynchronization detection |
| D | Pashov Multi-Vector | Access control, reentrancy, arithmetic, and logic flow analysis |
| E | QuillAI Modules | Behavioral state, DoS/griefing, oracle safety, proxy safety, input validation |
| F | Token Integration | ERC20/ERC4626 conformance, weird token handling, centralization risks |

Findings confirmed by multiple independent pipelines receive higher confidence scores. Findings were deduplicated by root cause across pipelines.

---

## Cross-Repo Severity Matrix

| Repository | Branch | Commit | LOC | Critical | High | Medium | Low | Info | Total |
|------------|--------|--------|-----|----------|------|--------|-----|------|-------|
| yieldnest-vault | eth-max-vault-release-candidate | `89854df` | 4,348 | 0 | 0 | 4 | 7 | 3 | 14 |
| yieldnest-eigenlayer-lrt | release-candidate | `31f7719` | 8,332 | 0 | 0 | 4 | 6 | 4 | 14 |
| yieldnest-flex-strategy | release-candidate | `8c53830` | 1,074 | 0 | 0 | 1 | 4 | 4 | 9 |
| yieldnest-vault-periphery | eth-max-vault-release-candidate | `f8e9cf7` | 1,055 | 0 | 0 | 1 | 4 | 3 | 8 |
| yieldnest-erc4626-wrapper-strategy | release-candidate | `7a5231d` | ~600 | 0 | 0 | 2 | 4 | 2 | 8 |
| safeguard | dev | `1fb2d4f` | ~400 | 0 | 0 | 2 | 3 | 6 | 11 |
| yieldnest-airdrop | dev | `221599c` | ~300 | 0 | 0 | 1 | 3 | 11 | 15 |
| wrapped-token | main | `1d19654` | ~250 | 0 | 0 | 2 | 3 | 2 | 7 |
| **TOTAL** | | | **~16,359** | **0** | **0** | **17** | **34** | **35** | **86** |

---

## Highest-Priority Findings (Medium Severity)

### Cross-Repo Patterns

Several finding categories recur across multiple repositories, indicating systemic patterns:

#### 1. Stale Accounting / Permissionless processAccounting (yieldnest-vault, yieldnest-eigenlayer-lrt)

| ID | Repo | Finding |
|----|------|---------|
| YNV-01 | yieldnest-vault | Deposit front-running via stale cached `totalAssets` |
| YNV-03 | yieldnest-vault | `processAccounting()` is permissionless and can be sandwiched |
| F-01 | yieldnest-eigenlayer-lrt | Permissionless `processRewards()` enables donation attack |

**Pattern:** Multiple contracts expose permissionless accounting/reward functions that update share price. Attackers can sandwich these calls with deposits and redemptions to extract value. This is the highest-impact cross-repo theme.

**Recommendation:** Add access control or time-gating to all functions that update cached asset totals or share prices.

#### 2. Unsafe `approve` / Non-Standard Token Handling (yieldnest-vault, yieldnest-flex-strategy)

| ID | Repo | Finding |
|----|------|---------|
| YNV-11 | yieldnest-vault | `OriginWithdrawalLib` uses `approve` instead of `forceApprove` |
| FLEX-03 | yieldnest-flex-strategy | Unsafe `approve` pattern in `setAccountingModule` |

**Pattern:** Inconsistent use of `SafeERC20.forceApprove()` vs raw `IERC20.approve()`. Some callsites would revert for non-standard tokens (USDT).

**Recommendation:** Standardize on `SafeERC20.forceApprove()` across all repositories.

#### 3. Missing Array Length Validation (yieldnest-vault-periphery, safeguard)

| ID | Repo | Finding |
|----|------|---------|
| VPH-01 | yieldnest-vault-periphery | Missing array length validation in `addAssets()` |
| SG-02 | safeguard | Non-ADDRESS parameter types silently skipped during validation |

**Pattern:** Functions accepting parallel arrays lack length-mismatch checks, causing unhelpful panics.

#### 4. Naming Convention Violations — Public `_underscore` Functions (yieldnest-vault, yieldnest-vault-periphery, yieldnest-erc4626-wrapper-strategy)

| ID | Repo | Finding |
|----|------|---------|
| YNV-02 | yieldnest-vault | Public `_feeOnRaw` and `_feeOnTotal` in interface |
| VPH-03 | yieldnest-vault-periphery | Internal-naming convention on public functions |
| L-01 | yieldnest-erc4626-wrapper-strategy | `_feeOnRaw` and `_feeOnTotal` have public visibility |

**Pattern:** Functions prefixed with `_` declared as `public` and exposed in interfaces. Creates confusion for integrators.

#### 5. No Slippage Protection on Deposits (yieldnest-vault, yieldnest-erc4626-wrapper-strategy)

| ID | Repo | Finding |
|----|------|---------|
| YNV-08 | yieldnest-vault | No slippage protection on deposit/mint operations |
| L-03 | yieldnest-erc4626-wrapper-strategy | No slippage protection on hook deposit/withdraw to targetVault |

**Pattern:** Deposit functions lack `minSharesOut` parameters, exposing users to rate manipulation.

---

### Per-Repo Medium Findings

#### yieldnest-vault (4 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| YNV-01 | Deposit front-running via stale cached `totalAssets` | High |
| YNV-02 | Public `_feeOnRaw`/`_feeOnTotal` naming convention violation in interface | High |
| YNV-03 | `processAccounting()` is permissionless and can be sandwiched | High |
| YNV-04 | Storage slot collision between MaxVaultViewer and VaultLib AssetStorage | High |

#### yieldnest-eigenlayer-lrt (4 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| F-01 | Permissionless `processRewards()` enables donation attack on non-bootstrapped system | High |
| F-02 | Trusted off-chain `rewardsAmount` in principal withdrawals can misattribute principal as rewards | High |
| F-03 | `pendingRequestedRedemptionAmount` desync from actual claims due to rate-minimum logic | Medium |
| F-04 | `finalizeRequestsUpToIndex` creates Finalization before validation (CEI violation) | High |

#### yieldnest-flex-strategy (1 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| FLEX-01 | APR cap bypass via snapshot index selection in `processRewards` | High |

#### yieldnest-vault-periphery (1 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| VPH-01 | Missing array length validation in `addAssets()` causes silent revert | High |

#### yieldnest-erc4626-wrapper-strategy (2 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| M-01 | Silent withdrawal amount capping in `handleBeforeRedeem` can cause user fund loss | High |
| M-02 | Hooks `processor` call uses memory arrays for calldata parameters — fragile ABI encoding | Medium |

#### safeguard (2 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| SG-01 | DelegateCall operations not blocked or differentiated by the guard | High |
| SG-02 | Non-ADDRESS parameter types (UINT256) silently skipped during validation | High |

#### yieldnest-airdrop (1 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| M-01 | Owner can silently reduce/zero-out user allocations without on-chain accountability | High |

#### wrapped-token (2 Medium)
| ID | Title | Confidence |
|----|-------|------------|
| WT-01 | Storage slot occupies ERC-1967 implementation namespace | High |
| WT-02 | Fee-on-transfer token incompatibility in `deposit()` | High |

---

## Overall Risk Assessment

| Risk Level | Description |
|------------|-------------|
| **Critical** | None identified |
| **High** | None identified |
| **Overall** | **MODERATE** — No immediate fund loss vectors, but the stale accounting/permissionless processAccounting pattern across yieldnest-vault and yieldnest-eigenlayer-lrt creates windows for value extraction that should be addressed before mainnet deployment. |

### Strengths Observed Across Repos
- Consistent use of OpenZeppelin's `ReentrancyGuardUpgradeable` on state-modifying functions
- Proper `SafeERC20` usage for token transfers (with minor exceptions noted above)
- Comprehensive role-based access control with granular roles
- ERC-7201 namespaced storage pattern for upgrade safety
- Virtual inflation attack mitigation via `+1` offset in share conversions
- Proper `_disableInitializers()` in all upgradeable contract constructors
- Vault starts paused by default, requiring explicit configuration before operation

### Areas Requiring Attention
1. **Permissionless accounting updates** — The most impactful cross-repo concern. `processAccounting()` and `processRewards()` should be access-controlled or time-gated.
2. **Off-chain trust dependencies** — yieldnest-eigenlayer-lrt's `rewardsAmount` in withdrawal processing relies entirely on off-chain calculation integrity.
3. **Unbounded iteration** — Multiple contracts iterate unbounded arrays (async withdrawals, staking nodes) that could cause DoS at scale.
4. **Storage slot management** — The MaxVaultViewer/VaultLib collision is a latent risk that should be fixed proactively.

---

## Methodology Coverage Matrix

| Vulnerability Class | Pipeline(s) | Repos Where Found |
|---------------------|-------------|-------------------|
| Access Control | A, B, D | eigenlayer-lrt, vault, safeguard, airdrop |
| Reentrancy | A, D, E | flex-strategy (informational only — mitigated) |
| Arithmetic/Precision | B, C, D | vault, flex-strategy, eigenlayer-lrt, erc4626-wrapper |
| DoS/Griefing | A, E | vault, vault-periphery, eigenlayer-lrt |
| Business Logic | B, C | vault, flex-strategy, eigenlayer-lrt, erc4626-wrapper |
| Token Integration | F | vault, flex-strategy, erc4626-wrapper, wrapped-token |
| Storage Layout | A, C | vault, wrapped-token |
| CEI Pattern Violations | A, B | eigenlayer-lrt |
| Naming/Convention | A, B, D | vault, vault-periphery, erc4626-wrapper |
| Centralization Risk | B | airdrop, eigenlayer-lrt |
| Input Validation | A, B, D | vault-periphery, safeguard, airdrop |

---

## Audit Reports

| Repository | Report |
|------------|--------|
| yieldnest-vault | [`audits/yieldnest-vault-audit-report.md`](yieldnest-vault-audit-report.md) |
| yieldnest-eigenlayer-lrt | [`audits/yieldnest-eigenlayer-lrt-audit-report.md`](yieldnest-eigenlayer-lrt-audit-report.md) |
| yieldnest-flex-strategy | [`audits/yieldnest-flex-strategy-audit-report.md`](yieldnest-flex-strategy-audit-report.md) |
| yieldnest-vault-periphery | [`audits/yieldnest-vault-periphery-audit-report.md`](yieldnest-vault-periphery-audit-report.md) |
| yieldnest-erc4626-wrapper-strategy | [`audits/yieldnest-erc4626-wrapper-strategy-audit-report.md`](yieldnest-erc4626-wrapper-strategy-audit-report.md) |
| safeguard | [`audits/safeguard-audit-report.md`](safeguard-audit-report.md) |
| yieldnest-airdrop | [`audits/yieldnest-airdrop-audit-report.md`](yieldnest-airdrop-audit-report.md) |
| wrapped-token | [`audits/wrapped-token-audit-report.md`](wrapped-token-audit-report.md) |
