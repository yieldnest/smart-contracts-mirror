# Smart Contract Audit Report Repositories

A curated directory of public smart contract audit report repositories, contest platforms, and aggregators.

## Summary Table: GitHub Repositories

| Organization         | GitHub Repository                                                                                 | Reports | Notes                                   |
| -------------------- | ------------------------------------------------------------------------------------------------- | ------- | --------------------------------------- |
| PeckShield           | [peckshield/publications](https://github.com/peckshield/publications)                             | ~481    | Largest single-firm collection          |
| Trail of Bits        | [trailofbits/publications](https://github.com/trailofbits/publications)                           | ~403    | In `reviews/` subfolder                 |
| Zellic               | [Zellic/publications](https://github.com/Zellic/publications)                                     | ~361    | Flat structure, all PDFs                |
| SlowMist             | [slowmist/Knowledge-Base](https://github.com/slowmist/Knowledge-Base)                             | ~322    | In `open-report/` and `open-report-V2/` |
| Halborn              | [HalbornSecurity/PublicReports](https://github.com/HalbornSecurity/PublicReports)                 | ~282    | Organized by chain type                 |
| Solidified           | [solidified-platform/audits](https://github.com/solidified-platform/audits)                       | ~247    | Reports since 2018                      |
| MixBytes             | [mixbytes/audits_public](https://github.com/mixbytes/audits_public)                               | ~217    | Organized by project                    |
| Cyfrin               | [Cyfrin/cyfrin-audit-reports](https://github.com/Cyfrin/cyfrin-audit-reports)                     | ~143    | Categorized findings                    |
| Sigma Prime          | [sigp/public-audits](https://github.com/sigp/public-audits)                                       | ~139    | In `reports/` subfolder                 |
| Spearbit             | [spearbit/portfolio](https://github.com/spearbit/portfolio)                                       | ~136    | Includes educational materials          |
| Runtime Verification | [runtimeverification/publications](https://github.com/runtimeverification/publications)           | ~103    | Formal verification focus               |
| Ackee Blockchain     | [Ackee-Blockchain/public-audit-reports](https://github.com/Ackee-Blockchain/public-audit-reports) | ~95     | EVM and Solana                          |
| Dedaub               | [Dedaub/audits](https://github.com/Dedaub/audits)                                                 | ~49     | More reports on website                 |
| ChainSecurity        | [ChainSecurity/audits](https://github.com/ChainSecurity/audits)                                   | ~19     | Subset; 1,000+ on website               |

## Contest Platforms

| Platform            | GitHub Org                                                  | Repos | Contests                                               |
| ------------------- | ----------------------------------------------------------- | ----- | ------------------------------------------------------ |
| Code4rena           | [code-423n4](https://github.com/code-423n4)                 | ~873  | 400+ contests                                          |
| Sherlock            | [sherlock-audit](https://github.com/sherlock-audit)         | ~459  | 370+ contests                                          |
| Consensys Diligence | [ConsenSysDiligence](https://github.com/ConsenSysDiligence) | ~97   | One repo per audit                                     |
| CodeHawks (Cyfrin)  | [Cyfrin](https://github.com/Cyfrin)                         | —     | Via codehawks.cyfrin.io                                |
| Cantina             | —                                                           | —     | [cantina.xyz/portfolio](https://cantina.xyz/portfolio) |

## Website-Only Publishers (No Significant GitHub Repo)

| Organization    | Website                                                                                                 | Claimed Audits |
| --------------- | ------------------------------------------------------------------------------------------------------- | -------------- |
| CertiK          | [skynet.certik.com](https://skynet.certik.com/)                                                         | 7,000+         |
| Hacken          | [hacken.io/audits](https://hacken.io/audits/)                                                           | 2,300+         |
| OpenZeppelin    | [openzeppelin.com/security-audits](https://www.openzeppelin.com/security-audits)                        | 900+           |
| Quantstamp      | [certificate.quantstamp.com](https://certificate.quantstamp.com/)                                       | 750+           |
| Least Authority | [leastauthority.com/published-audits](https://leastauthority.com/security-consulting/published-audits/) | 200+           |

## Aggregators & Databases

| Site                | URL                                                             | Description                                             |
| ------------------- | --------------------------------------------------------------- | ------------------------------------------------------- |
| Solodit             | [solodit.cyfrin.io](https://solodit.cyfrin.io/)                 | 50,000+ vulnerability findings from audits and contests |
| AuditBase           | [auditbase.com](https://www.auditbase.com/)                     | AI-powered scanner trained on 14,000+ audit reports     |
| De.Fi Scanner       | [de.fi/scanner](https://de.fi/scanner)                          | DeFi security scanner + REKT exploit database           |
| Rekt News           | [rekt.news](https://rekt.news/)                                 | Exploit post-mortems and hack leaderboard               |
| SmartContractAudits | [smartcontractaudits.com](https://www.smartcontractaudits.com/) | Directory of audit providers and reports                |

---

## How to Find Audit Reports

### 1. Search GitHub Directly

**Search for a specific project's audits:**

```
site:github.com "<project name>" audit report filetype:pdf
```

**GitHub search queries:**

- Go to [github.com/search](https://github.com/search) and use:
  - `"<project name>" audit path:*.pdf` — find PDF audit reports
  - `"<project name>" audit org:trailofbits` — search within a specific firm's org
  - `"<project name>" audit org:code-423n4` — find Code4rena contest repos
  - `"<project name>" audit org:sherlock-audit` — find Sherlock contest repos

**Clone and search a firm's entire repo locally:**

```bash
git clone https://github.com/trailofbits/publications.git
ls publications/reviews/ | grep -i "<project name>"
```

### 2. Search Aggregator Platforms

**Solodit (best single source):**

1. Go to [solodit.cyfrin.io](https://solodit.cyfrin.io/)
2. Search by protocol name, vulnerability type, or keyword
3. Filter by severity (Critical/High/Medium/Low), audit firm, or time period
4. Results link back to original audit reports and findings

**AuditBase:**

1. Go to [auditbase.com](https://www.auditbase.com/)
2. Paste a contract address or search by project name
3. View associated audit reports and automated scan results

### 3. Web Search Techniques

**Google search operators:**

```
"<project name>" "audit report" filetype:pdf
"<project name>" "security review" filetype:pdf
"<project name>" audit site:github.com
"<project name>" audit (site:openzeppelin.com OR site:trailofbits.com OR site:zellic.io)
```

**Search for a protocol across all major firms:**

```
"<project name>" audit (Trail of Bits OR OpenZeppelin OR Cyfrin OR Zellic OR Spearbit OR Halborn)
```

**Find contest results:**

```
"<project name>" site:code4rena.com
"<project name>" site:audits.sherlock.xyz
"<project name>" site:cantina.xyz
```

### 4. Check the Project Itself

Many projects link their audits directly:

- Look for an `audits/` or `security/` folder in the project's GitHub repo
- Check the project's documentation site for a "Security" or "Audits" page
- Check the project's README for audit links
- Search the project's Discord or forum for "audit" announcements

### 5. On-Chain and Registry Sources

- **Etherscan:** Some verified contracts on Etherscan link to their audit reports in the contract metadata

### 6. Bulk Download Tips

To build a local corpus of audit reports:

```bash
# Clone the top repos
git clone https://github.com/peckshield/publications.git
git clone https://github.com/trailofbits/publications.git
git clone https://github.com/Zellic/publications.git
git clone https://github.com/slowmist/Knowledge-Base.git
git clone https://github.com/HalbornSecurity/PublicReports.git
git clone https://github.com/solidified-platform/audits.git
git clone https://github.com/mixbytes/audits_public.git
git clone https://github.com/Cyfrin/cyfrin-audit-reports.git
git clone https://github.com/sigp/public-audits.git
git clone https://github.com/spearbit/portfolio.git
git clone https://github.com/runtimeverification/publications.git
git clone https://github.com/Ackee-Blockchain/public-audit-reports.git
git clone https://github.com/Dedaub/audits.git
git clone https://github.com/ChainSecurity/audits.git

# Find all PDFs across cloned repos
find . -name "*.pdf" -type f | wc -l
```

This gives you ~3,000+ audit report PDFs locally for analysis.

### 7. Banned sources and tools

DO NOT USE THE FOLLOWING BECAUSE OF THE LOW QUALITY:

- **CertiK Skynet:** [skynet.certik.com](https://skynet.certik.com/)
- **De.Fi Scanner:** [de.fi/scanner](https://de.fi/scanner)
