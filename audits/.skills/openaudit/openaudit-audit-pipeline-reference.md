# Audit Pipeline Reference

This file describes how an AI agent should run each audit skill pipeline.
Each pipeline is a combination of tools (Slither, Aderyn, Semgrep) and/or
AI-driven methodology skills (structured markdown prompts the agent follows).

## Pipeline Categories

### Category A: Static Analysis Tools (automated)

These pipelines run external binaries on the source code. They produce machine-readable output
that the agent parses and includes in the report.

| Pipeline | Tool | Command | Output |
|----------|------|---------|--------|
| Slither | Python static analyzer | `uv run slither {src_dir} --json {output}.json` | JSON with detectors, severity, locations |
| Aderyn | Rust static analyzer | `aderyn {src_dir} --output {output}.md` | Markdown report with H/L findings |
| Semgrep | Pattern matching | `uv run semgrep --metrics=off --config "r/solidity" --json {src_dir}/ > {output}.json` | JSON with rule matches |

**Important**: The source directory must be a git repository for Semgrep to scan files.
Run `git init && git add -A && git commit -m init` in the source dir if needed.

**Solc version**: Match the compiler version used by the contract (check `pragma solidity` lines).
Install with: `uv run solc-select install {version} && uv run solc-select use {version}`

### Category B: AI-Driven Methodology Skills (agent reads and follows)

These are structured markdown prompts. The agent reads the skill file and follows
the methodology step by step against the downloaded source code. **No external tools needed** —
the agent performs the analysis using its own reasoning over the code.

Each skill targets different vulnerability classes and uses different techniques.
Running all of them provides defense-in-depth: what one misses, another catches.

---

## Solidity-Applicable Pipelines (run all of these for EVM audits)

### Pipeline 1: Slither (static analysis)
- **Repo**: Built-in (pyproject.toml dependency)
- **Type**: Category A — automated tool
- **What it finds**: Reentrancy, uninitialized variables, shadowing, unchecked calls, compiler bugs
- **Run**: `uv run slither {src_dir} --json {output_dir}/slither-output.json`
- **Parse**: Group findings by impact (High/Medium/Low/Informational), filter out Informational

### Pipeline 2: Aderyn (static analysis)
- **Repo**: Installed via `cargo install aderyn`
- **Type**: Category A — automated tool
- **What it finds**: Unsafe casting, unprotected initializers, centralization risks, locked ether
- **Run**: `aderyn {src_dir} --output {output_dir}/aderyn-report.md`
- **Note**: May panic on non-standard version strings — the report is still generated before the panic

### Pipeline 3: Semgrep (pattern matching)
- **Repo**: Built-in (pyproject.toml dependency)
- **Type**: Category A — automated tool
- **What it finds**: Gas optimizations, unsafe patterns, coding style issues
- **Run**: `uv run semgrep --metrics=off --config "r/solidity" --json {src_dir}/ > {output_dir}/semgrep-results.json`
- **Important**: Always use `--metrics=off` to prevent telemetry

### Pipeline 4: Pashov Solidity Auditor (AI methodology)
- **Repo**: `deps/pashov-skills/`
- **Type**: Category B — AI-driven methodology
- **What it finds**: Business logic bugs, attack vectors across 4 categories
- **Skill file**: `deps/pashov-skills/solidity-auditor/SKILL.md`
- **How to run**:
  1. Read `deps/pashov-skills/solidity-auditor/SKILL.md` completely
  2. The skill instructs spawning 4 parallel scanning agents, each with different attack vector files
  3. If parallel agents are not available, run sequentially: for each of the 4 attack vector files at
     `deps/pashov-skills/solidity-auditor/references/attack-vectors/attack-vectors-{1,2,3,4}.md`,
     read the attack vectors, then systematically check every in-scope .sol file for those patterns
  4. Use `deps/pashov-skills/solidity-auditor/references/judging.md` for severity classification
  5. Merge and deduplicate findings
- **In-scope files**: All `.sol` files EXCEPT interfaces/, lib/, mocks/, test/ directories
- **Output**: Write to `{output_dir}/pashov-skills.md`

### Pipeline 5: SCV-Scan / kadenzipfel (AI methodology)
- **Repo**: `deps/kadenzipfel-scv-scan/`
- **Type**: Category B — AI-driven methodology
- **What it finds**: 36 specific vulnerability types from a curated database
- **Skill file**: `deps/kadenzipfel-scv-scan/SKILL.md`
- **How to run**:
  1. Read `deps/kadenzipfel-scv-scan/SKILL.md`
  2. **Phase 1**: Read `deps/kadenzipfel-scv-scan/references/CHEATSHEET.md` — memorize all 36 patterns
  3. **Phase 2a**: Grep-scan the source code for trigger patterns from the cheatsheet
  4. **Phase 2b**: Semantic read-through of source code for logic patterns
  5. **Phase 3**: For each candidate, read the full reference file (e.g. `references/reentrancy.md`)
     and walk through Detection Heuristics and False Positive conditions
  6. **Phase 4**: Report confirmed findings only
- **Output**: Write to `{output_dir}/kadenzipfel-scv-scan.md`

### Pipeline 6: Forefy Smart Contract Audit (AI methodology)
- **Repo**: `deps/forefy-context/`
- **Type**: Category B — AI-driven methodology
- **What it finds**: Protocol-specific vulnerabilities, cross-contract issues, economic attacks
- **Skill file**: `deps/forefy-context/skills/smart-contract-audit/SKILL.md`
- **How to run**:
  1. Read `deps/forefy-context/skills/smart-contract-audit/SKILL.md`
  2. Detect protocol type (DEX, lending, pool, governance, etc.)
  3. Read language-specific checks from `deps/forefy-context/prompts/SOLIDITY-CHECKS.md`
  4. Read vulnerability patterns from `deps/forefy-context/skills/smart-contract-audit/reference/solidity/`
  5. Follow the 5 audit layers: protocol → economic → access control → integration → technical
  6. Apply the multi-expert framework from `deps/forefy-context/prompts/MULTI-EXPERT.md`
- **Output**: Write to `{output_dir}/forefy-context.md`

### Pipeline 7: QuillAI Behavioral State Analysis (AI methodology)
- **Repo**: `deps/quillai-qs-skills/`
- **Type**: Category B — AI-driven methodology
- **What it finds**: State invariant violations, economic exploits, access control gaps
- **Skill file**: `deps/quillai-qs-skills/plugins/behavioral-state-analysis/skills/behavioral-state-analysis/SKILL.md`
- **How to run**:
  1. Read the SKILL.md above
  2. Classify the contract type (DEX, lending, vault/pool, utility, governance, etc.)
  3. Select relevant threat engines based on contract type
  4. **Phase 1**: Behavioral decomposition — extract states, invariants, roles, value flows
  5. **Phase 2**: Threat modeling with Economic, Access Control, State Integrity engines
  6. **Phase 3**: Exploit verification — build attack sequences for Critical/High
  7. **Phase 4**: Confidence scoring
- **Additional QuillAI plugins to run** (each has its own SKILL.md in `plugins/{name}/skills/{name}/`):
  - `reentrancy-pattern-analysis` — all reentrancy variants
  - `oracle-flashloan-analysis` — price manipulation, flash loans (if protocol uses oracles)
  - `proxy-upgrade-safety` — storage collisions, function clashing (if proxy pattern detected)
  - `external-call-safety` — unsafe calls, fee-on-transfer tokens
- **Output**: Write to `{output_dir}/quillai-qs-skills.md`

### Pipeline 8: Auditmos DeFi Checklists (AI methodology)
- **Repo**: `deps/auditmos-skills/`
- **Type**: Category B — AI-driven methodology
- **What it finds**: DeFi-specific vulnerabilities across 14 categories
- **How to run**:
  1. Read `deps/auditmos-skills/skills/always-checklist.md` — the master checklist
  2. Based on the protocol type, read the relevant domain-specific skill:
     - Pool/vault → `audit-staking/`, `audit-slippage/`
     - Lending → `audit-lending/`, `audit-liquidation/`, `audit-liquidation-calculation/`
     - Oracle-dependent → `audit-oracle/`
     - Has signatures → `audit-signature/`
     - Math-heavy → `audit-math-precision/`
     - General → `audit-reentrancy/`, `audit-state-validation/`
  3. For each applicable skill, read its checklist.md and systematically verify each item
- **Output**: Write to `{output_dir}/auditmos-skills.md`

### Pipeline 9: Trail of Bits Skills (AI + tools)
- **Repo**: `deps/trailofbits-skills/`
- **Type**: Category A+B — mixed
- **What it finds**: Entry point analysis, specification compliance, architecture review
- **How to run**:
  1. Read `deps/trailofbits-skills/CLAUDE.md` for orientation
  2. **Entry point analysis**: Read `deps/trailofbits-skills/plugins/entry-point-analyzer/skills/entry-point-analyzer/SKILL.md`
     and identify all state-changing entry points in the contract
  3. **Spec-to-code compliance**: Read `deps/trailofbits-skills/plugins/spec-to-code-compliance/skills/spec-to-code-compliance/SKILL.md`
     and check if the implementation matches documented specifications
  4. **Audit context building**: Read `deps/trailofbits-skills/plugins/audit-context-building/skills/audit-context-building/SKILL.md`
     to build architectural context
  5. If CodeQL is installed, run CodeQL queries from the static-analysis plugin
- **Output**: Write to `{output_dir}/trailofbits-skills.md`

### Pipeline 10: Archethect SC Auditor (AI methodology + MCP tools)
- **Repo**: `deps/archethect-sc-auditor/`
- **Type**: Category A+B — mixed
- **Skill file**: `deps/archethect-sc-auditor/skills/security-auditor/SKILL.md`
- **How to run**:
  1. Read the SKILL.md above for the Map-Hunt-Attack methodology
  2. **Setup**: Review scope and codebase structure
  3. **Map**: Build architecture map (contracts, inheritance, external calls, storage)
  4. **Hunt**: Identify vulnerabilities using the methodology
  5. **Attack**: Develop proof-of-concept exploits for critical findings
  6. If MCP tools are configured, use them to run Slither/Aderyn/search Solodit
- **Note**: The MCP tools component requires `npm install` and Node.js setup. The methodology skill
  works standalone without MCP.
- **Output**: Write to `{output_dir}/archethect-sc-auditor.md`

## Non-Solidity Pipelines (skip for EVM audits)

| Pipeline | Language | When to use |
|----------|----------|-------------|
| `frankcastle-safe-solana` | Rust (Solana Anchor) | Solana program audits only |
| `membrane-core` | Rust (CosmWasm) | CosmWasm protocol reference only |

## Important: Library and Extension Coverage

When auditing a contract, do NOT limit analysis to just the main contract file.
The audit MUST cover:

1. **All libraries** imported by the contract (SafeTransferLib, EnumerableSet, etc.)
2. **All inherited contracts** in the mixin/diamond hierarchy
3. **Extension contracts** that are called via delegatecall or staticcall from fallback functions
4. **External contracts** at addresses stored in state (governance, extension registries, routers, hooks, etc.)

For libraries and inherited contracts, include them in the source code scope for all pipelines.
For extension/external contracts, download their source code separately (using Sourcify/Etherscan)
and note in the report which external contracts were and were not analyzed.
