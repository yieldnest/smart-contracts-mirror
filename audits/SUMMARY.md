# YieldNest Smart Contracts — Multi-Pipeline Security Audit Summary

**Date:** 2026-03-17
**Auditor:** Automated Multi-Pipeline AI Audit Framework
**Scope:** 8 repositories, ~16,000 LOC Solidity

## Methodology

Eight independent AI-driven audit pipelines were applied to each repository:

| Pipeline | Methodology | Focus |
|----------|-------------|-------|
| A | SCV Scan | 36 vulnerability pattern matching (reentrancy, overflow, access control, etc.) |
| B | Feynman Business Logic | First-principles interrogation of every function's business logic |
| C | State Inconsistency | Coupled state variable desynchronization detection |
| D | Pashov Multi-Vector | Access control, reentrancy, arithmetic, and logic flow analysis |
| E | QuillAI Modules | Behavioral state, DoS/griefing, oracle safety, proxy safety, input validation |
| F | Token Integration | ERC20/ERC4626 conformance, weird token handling, centralization risks |
| G | Forefy + Archethect (OpenAudit) | Protocol-specific 5-layer audit + SETUP-MAP-HUNT-ATTACK methodology |
| H | Auditmos DeFi Checklists (OpenAudit) | 14 DeFi-specific vulnerability checklists (staking, slippage, oracle, math-precision, reentrancy, state-validation) |

Pipelines A–F were run across all 8 repos. Pipeline G was run across all 8 repos. Pipeline H was run on the 4 vault/DeFi repos where its checklists are most applicable (yieldnest-vault, yieldnest-eigenlayer-lrt, yieldnest-flex-strategy, yieldnest-erc4626-wrapper-strategy).

Findings confirmed by multiple independent pipelines receive higher confidence scores. Findings were deduplicated by root cause across pipelines.

---

## Cross-Repo Severity Matrix

| Repository | Branch | Commit | LOC | Critical | High | Medium | Low | Info | Total |
|------------|--------|--------|-----|----------|------|--------|-----|------|-------|
| yieldnest-vault | eth-max-vault-release-candidate | `89854df` | 4,348 | 0 | 2 | 10 | 14 | 5 | 31 |
| yieldnest-eigenlayer-lrt | release-candidate | `31f7719` | 8,332 | 0 | 0 | 9 | 17 | 6 | 32 |
| yieldnest-flex-strategy | release-candidate | `8c53830` | 1,074 | 0 | 0 | 6 | 10 | 5 | 21 |
| yieldnest-vault-periphery | eth-max-vault-release-candidate | `f8e9cf7` | 1,055 | 0 | 0 | 3 | 10 | 4 | 17 |
| yieldnest-erc4626-wrapper-strategy | release-candidate | `7a5231d` | ~600 | 0 | 2 | 5 | 7 | 2 | 16 |
| safeguard | dev | `1fb2d4f` | ~400 | 0 | 1 | 4 | 5 | 6 | 16 |
| yieldnest-airdrop | dev | `221599c` | ~300 | 0 | 0 | 3 | 5 | 0 | 8 |
| wrapped-token | main | `1d19654` | ~250 | 0 | 0 | 2 | 3 | 2 | 7 |
| **TOTAL** | | | **~16,359** | **0** | **5** | **42** | **71** | **30** | **148** |

---

## Highest-Priority Findings (High Severity)

The OpenAudit pipelines (G, H) identified 5 new High-severity findings not detected by the initial 6 pipelines:

### High-Severity Findings

#### yieldnest-vault (2 High)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| YNV-15 | Withdrawal fee bypass via direct `withdraw()` path | High | G |
| YNV-16 | Provider spot price manipulation via flash loan | High | G |

#### yieldnest-erc4626-wrapper-strategy (2 High)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| H-01 | USDT-incompatible `approve()` pattern in hook operations | High | G |
| H-02 | Read-only reentrancy via ERC4626 share price manipulation | High | G, H |

#### safeguard (1 High)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| H-01 | Guard can be disabled without timelock, single-tx multisig bypass | High | G |

---

## Cross-Repo Patterns (Medium Severity)

Several finding categories recur across multiple repositories, indicating systemic patterns:

#### 1. Stale Accounting / Permissionless processAccounting (yieldnest-vault, yieldnest-eigenlayer-lrt)

| ID | Repo | Finding |
|----|------|---------|
| YNV-01 | yieldnest-vault | Deposit front-running via stale cached `totalAssets` |
| YNV-03 | yieldnest-vault | `processAccounting()` is permissionless and can be sandwiched |
| F-01 | yieldnest-eigenlayer-lrt | Permissionless `processRewards()` enables donation attack |

**Pattern:** Multiple contracts expose permissionless accounting/reward functions that update share price. Attackers can sandwich these calls with deposits and redemptions to extract value. This is the highest-impact cross-repo theme.

**Recommendation:** Add access control or time-gating to all functions that update cached asset totals or share prices.

#### 2. Unsafe `approve` / Non-Standard Token Handling (yieldnest-vault, yieldnest-flex-strategy, yieldnest-erc4626-wrapper-strategy)

| ID | Repo | Finding |
|----|------|---------|
| YNV-11 | yieldnest-vault | `OriginWithdrawalLib` uses `approve` instead of `forceApprove` |
| FLEX-03 | yieldnest-flex-strategy | Unsafe `approve` pattern in `setAccountingModule` |
| H-01 | yieldnest-erc4626-wrapper-strategy | USDT-incompatible `approve()` in hook operations |

**Pattern:** Inconsistent use of `SafeERC20.forceApprove()` vs raw `IERC20.approve()`. Some callsites would revert for non-standard tokens (USDT). Pipeline G elevated this to High severity for erc4626-wrapper-strategy.

**Recommendation:** Standardize on `SafeERC20.forceApprove()` across all repositories.

#### 3. Oracle Staleness / No Bounds Checking (yieldnest-eigenlayer-lrt, yieldnest-flex-strategy)

| ID | Repo | Finding |
|----|------|---------|
| F-15 | yieldnest-eigenlayer-lrt | LSDRateProvider has no staleness, bounds, or revert handling |
| FLEX-10 | yieldnest-flex-strategy | APR oracle snapshots lack staleness detection |

**Pattern:** Rate oracles and price feeds lack staleness checks, min/max bounds validation, and try/catch error handling. Pipeline H (Auditmos oracle checklist) independently flagged these.

**Recommendation:** Add staleness thresholds, circuit breakers, and fallback mechanisms to all oracle-dependent price feeds.

#### 4. Missing Array Length Validation (yieldnest-vault-periphery, safeguard)

| ID | Repo | Finding |
|----|------|---------|
| VPH-01 | yieldnest-vault-periphery | Missing array length validation in `addAssets()` |
| SG-02 | safeguard | Non-ADDRESS parameter types silently skipped during validation |

**Pattern:** Functions accepting parallel arrays lack length-mismatch checks, causing unhelpful panics.

#### 5. Naming Convention Violations — Public `_underscore` Functions (yieldnest-vault, yieldnest-vault-periphery, yieldnest-erc4626-wrapper-strategy)

| ID | Repo | Finding |
|----|------|---------|
| YNV-02 | yieldnest-vault | Public `_feeOnRaw` and `_feeOnTotal` in interface |
| VPH-03 | yieldnest-vault-periphery | Internal-naming convention on public functions |
| L-01 | yieldnest-erc4626-wrapper-strategy | `_feeOnRaw` and `_feeOnTotal` have public visibility |

**Pattern:** Functions prefixed with `_` declared as `public` and exposed in interfaces. Creates confusion for integrators.

#### 6. No Slippage Protection on Deposits (yieldnest-vault, yieldnest-erc4626-wrapper-strategy)

| ID | Repo | Finding |
|----|------|---------|
| YNV-08 | yieldnest-vault | No slippage protection on deposit/mint operations |
| L-03 | yieldnest-erc4626-wrapper-strategy | No slippage protection on hook deposit/withdraw to targetVault |

**Pattern:** Deposit functions lack `minSharesOut` parameters, exposing users to rate manipulation.

---

### Per-Repo Medium Findings

#### yieldnest-vault (10 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| YNV-01 | Deposit front-running via stale cached `totalAssets` | High | B, C, D |
| YNV-02 | Public `_feeOnRaw`/`_feeOnTotal` naming convention violation in interface | High | A, F |
| YNV-03 | `processAccounting()` is permissionless and can be sandwiched | High | B, D |
| YNV-04 | Storage slot collision between MaxVaultViewer and VaultLib AssetStorage | High | A, C |
| YNV-17 | Withdrawal queue rate manipulation via processAccounting sandwich | High | G |
| YNV-18 | Provider oracle trust assumption without validation | High | G |
| YNV-19 | Hook reentrancy through external contract callbacks | Medium | G |
| YNV-20 | Flash loan share price manipulation via deposit/redeem in same block | High | G, H |
| YNV-21 | MaxVaultViewer `getVaultAsset` storage collision with VaultLib | High | G |
| YNV-22 | Unbounded loop in processAccounting with many assets | Medium | H |

#### yieldnest-eigenlayer-lrt (9 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| F-01 | Permissionless `processRewards()` enables donation attack | High | B, C, D, G |
| F-02 | Trusted off-chain `rewardsAmount` in principal withdrawals can misattribute principal as rewards | High | B, D |
| F-03 | `pendingRequestedRedemptionAmount` desync from actual claims due to rate-minimum logic | Medium | B, C |
| F-04 | `finalizeRequestsUpToIndex` creates Finalization before validation (CEI violation) | High | B, D |
| F-11 | Missing access control on `initializeV3` in StakingNode — front-running risk | High | A, G |
| F-15 | LSDRateProvider no staleness/bounds/revert handling on oracle sources | High | G, H |
| F-16 | `secondsToFinalization` declared but never enforced in withdrawal queue | Medium | H |
| F-17 | Share pricing vulnerable to `totalSupply` manipulation via privileged burn | High | G |
| F-18 | Stale `tokenIdToFinalize` in WithdrawalsProcessor | Medium | G |

#### yieldnest-flex-strategy (6 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| FLEX-01 | APR cap bypass via snapshot index selection in `processRewards` | High | B, D |
| FLEX-10 | Stale APR oracle snapshots without staleness detection | High | G, H |
| FLEX-11 | Unbounded asset iteration in reward processing | Medium | G, H |
| FLEX-12 | Missing slippage protection on strategy rebalancing | High | G |
| FLEX-13 | Reward processing race condition with accounting module | Medium | G |
| FLEX-14 | Strategy deposit/withdraw without deadline protection | Medium | H |

#### yieldnest-vault-periphery (3 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| VPH-01 | Missing array length validation in `addAssets()` | High | A, B, G |
| VPH-09 | Unbounded loop in batch operations without gas limit checks | Medium | G |
| VPH-10 | Missing return value validation on external vault calls | High | G |

#### yieldnest-erc4626-wrapper-strategy (5 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| M-01 | Silent withdrawal amount capping in `handleBeforeRedeem` can cause user fund loss | High | B, C |
| M-02 | Hooks `processor` call uses memory arrays for calldata parameters — fragile ABI encoding | Medium | B |
| M-03 | Deposit/withdraw hook operations lack deadline protection | Medium | G |
| M-04 | Share price manipulation via ERC4626 totalAssets inflation | High | G, H |
| M-05 | Missing balance validation after external vault interactions | Medium | G |

#### safeguard (4 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| SG-01 | DelegateCall operations not blocked or differentiated by the guard | High | A, B, D |
| SG-02 | Non-ADDRESS parameter types (UINT256) silently skipped during validation | High | A, D, G |
| SG-03 | ETH value in transactions not validated by the guard | Medium | G |
| SG-04 | Missing `__gap` storage variable for future upgradeability | Medium | G |

#### yieldnest-airdrop (3 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| M-01 | Owner can silently reduce/zero-out user allocations without on-chain accountability | High | B, C, D, G |
| M-02 | Pause-unpause frontrunning window allows atomic allocation manipulation | High | G |
| M-03 | Safe's token allowance is single point of failure with no on-chain validation | Medium | G |

#### wrapped-token (2 Medium)
| ID | Title | Confidence | Sources |
|----|-------|------------|---------|
| WT-01 | Storage slot occupies ERC-1967 implementation namespace | High | A, C |
| WT-02 | Fee-on-transfer token incompatibility in `deposit()` | High | A, F, G |

---

## Overall Risk Assessment

| Risk Level | Description |
|------------|-------------|
| **Critical** | None identified |
| **High** | **5 findings** — Withdrawal fee bypass and provider price manipulation in yieldnest-vault, USDT-incompatible approve and read-only reentrancy in erc4626-wrapper-strategy, guard disable without timelock in safeguard |
| **Overall** | **MODERATE-HIGH** — The addition of Pipelines G and H revealed 5 High-severity findings and significantly expanded the Medium finding count (from 17 to 42). Key concerns: (1) withdrawal fee bypass paths in yieldnest-vault, (2) USDT/non-standard token incompatibilities across multiple repos, (3) oracle staleness and bounds checking gaps, (4) read-only reentrancy vectors in ERC4626 wrappers. The stale accounting/permissionless processAccounting pattern remains the highest-impact cross-repo concern. |

### Strengths Observed Across Repos
- Consistent use of OpenZeppelin's `ReentrancyGuardUpgradeable` on state-modifying functions
- Proper `SafeERC20` usage for token transfers (with minor exceptions noted above)
- Comprehensive role-based access control with granular roles
- ERC-7201 namespaced storage pattern for upgrade safety
- Virtual inflation attack mitigation via `+1` offset in share conversions
- Proper `_disableInitializers()` in all upgradeable contract constructors
- Vault starts paused by default, requiring explicit configuration before operation

### Areas Requiring Attention
1. **Withdrawal fee bypass** (NEW — High) — yieldnest-vault's direct `withdraw()` path bypasses fee logic; must be patched before mainnet.
2. **Non-standard token handling** (ESCALATED — High) — USDT `approve()` incompatibility in erc4626-wrapper-strategy and inconsistent `forceApprove` usage across repos.
3. **Permissionless accounting updates** — The most impactful cross-repo concern. `processAccounting()` and `processRewards()` should be access-controlled or time-gated.
4. **Oracle staleness** (NEW — Medium) — LSD rate providers and APR oracles lack staleness detection, bounds validation, and circuit breakers.
5. **Off-chain trust dependencies** — yieldnest-eigenlayer-lrt's `rewardsAmount` in withdrawal processing relies entirely on off-chain calculation integrity.
6. **Guard bypass** (NEW — High) — safeguard's guard can be disabled without a timelock, allowing single-tx multisig operations to bypass all protections.
7. **Unbounded iteration** — Multiple contracts iterate unbounded arrays (async withdrawals, staking nodes) that could cause DoS at scale.
8. **Storage slot management** — The MaxVaultViewer/VaultLib collision is a latent risk that should be fixed proactively.

---

## Methodology Coverage Matrix

| Vulnerability Class | Pipeline(s) | Repos Where Found |
|---------------------|-------------|-------------------|
| Access Control | A, B, D, G | eigenlayer-lrt, vault, safeguard, airdrop |
| Reentrancy | A, D, E, G, H | flex-strategy, erc4626-wrapper, eigenlayer-lrt |
| Arithmetic/Precision | B, C, D, G, H | vault, flex-strategy, eigenlayer-lrt, erc4626-wrapper |
| DoS/Griefing | A, E, G, H | vault, vault-periphery, eigenlayer-lrt, flex-strategy |
| Business Logic | B, C, G | vault, flex-strategy, eigenlayer-lrt, erc4626-wrapper |
| Token Integration | F, G | vault, flex-strategy, erc4626-wrapper, wrapped-token |
| Storage Layout | A, C, G | vault, wrapped-token |
| CEI Pattern Violations | A, B, G | eigenlayer-lrt |
| Naming/Convention | A, B, D | vault, vault-periphery, erc4626-wrapper |
| Centralization Risk | B, G | airdrop, eigenlayer-lrt, safeguard |
| Input Validation | A, B, D, G | vault-periphery, safeguard, airdrop |
| Oracle/Price Feed | G, H | eigenlayer-lrt, flex-strategy |
| Fee/Withdrawal Logic | G | vault, eigenlayer-lrt |
| Proxy/Upgrade Safety | E, G | safeguard, wrapped-token |

---

## Pipeline Contribution Analysis

| Pipeline | Total Findings Contributed | Unique Findings (sole source) | Cross-confirmed |
|----------|---------------------------|-------------------------------|-----------------|
| A (SCV Scan) | 35 | 4 | 31 |
| B (Feynman) | 42 | 6 | 36 |
| C (State Inconsistency) | 28 | 3 | 25 |
| D (Pashov) | 38 | 5 | 33 |
| E (QuillAI) | 22 | 2 | 20 |
| F (Token Integration) | 18 | 1 | 17 |
| G (Forefy + Archethect) | 89 | 38 | 51 |
| H (Auditmos) | 34 | 8 | 26 |

Pipeline G (Forefy + Archethect) was the most productive pipeline, contributing 89 findings across all 8 repos, of which 38 were unique discoveries not found by any other pipeline. This demonstrates the value of the OpenAudit multi-methodology approach — the additional pipelines increased total findings from 86 to 148 (+72%) and discovered 5 new High-severity issues.

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

### Raw Pipeline Outputs

| Pipeline | Files |
|----------|-------|
| OpenAudit (Forefy + Archethect) | `audits/openaudit-*-findings.md` (8 files) |
| Auditmos DeFi Checklists | `audits/auditmos-*-findings.md` (4 files) |
| OpenAudit Skills | `audits/.skills/openaudit/`, `audits/.skills/forefy/`, `audits/.skills/archethect/`, `audits/.skills/auditmos/` |
