# AML Monitoring Pipeline — Plan

## Overview

Anti-money laundering pipeline that continuously screens transactions for laundering typologies (structuring, layering, integration, trade-based ML), performs enhanced customer due diligence on flagged accounts, investigates suspicious activity with evidence compilation, prepares and validates SAR filings, manages cases through resolution, and maintains regulatory audit trails compliant with BSA/AML requirements.

- **Agents:** 5 (transaction-screener, pattern-analyst, aml-investigator, compliance-officer, filing-specialist)
- **Phases:** 12
- **Models:** claude-haiku-4-5 (high-volume screening), claude-sonnet-4-6 (pattern analysis/investigation), claude-opus-4-6 (compliance decisions)
- **Workflows:** 3 (full-investigation, transaction-screening, periodic-review)
- **MCP Servers:** filesystem, sequential-thinking

---

## Agents

| Agent | Model | Role |
|---|---|---|
| **transaction-screener** | claude-haiku-4-5 | High-volume transaction screening — applies BSA thresholds, checks CTR triggers ($10K+), flags structuring patterns (multiple sub-$10K deposits), identifies unusual activity relative to customer profile |
| **pattern-analyst** | claude-sonnet-4-6 | Analyzes flagged transactions for AML typologies — structuring/smurfing, layering (rapid movement between accounts/jurisdictions), integration (legitimate-appearing business transactions), trade-based ML (over/under-invoicing) |
| **aml-investigator** | claude-sonnet-4-6 | Deep investigation — builds customer activity timeline, traces fund flows, identifies beneficial ownership chains, correlates with known ML schemes, compiles evidence packages with confidence assessments |
| **compliance-officer** | claude-opus-4-6 | BSA compliance authority — reviews investigation findings, makes filing decisions (file SAR / escalate / close), evaluates regulatory risk, ensures evidence meets FinCEN evidentiary standards |
| **filing-specialist** | claude-sonnet-4-6 | Prepares FinCEN SAR filings (BSA E-Filing format), writes SAR narratives, generates CTRs, compiles case packages, produces management reporting and trend analysis |

---

## Phase Pipeline

### Phase 1: `ingest-transactions` (command)
- **Script:** `scripts/ingest-transactions.sh`
- **Action:** Reads transaction batch from `data/transactions/incoming/`, normalizes format (amount, currency, parties, timestamps, channel, geographic data), enriches with customer profile data from `data/customers/`, writes to `data/transactions/normalized/batch.json`
- **Timeout:** 60s

### Phase 2: `screen-transactions` (agent: transaction-screener)
- **Action:** Screen normalized transactions against BSA/AML rules:
  - CTR threshold check ($10,000+ cash transactions)
  - Structuring detection (multiple deposits just below $10K within rolling window)
  - Velocity anomalies (sudden spikes in volume/value vs customer baseline)
  - Geographic risk (high-risk jurisdictions per FATF grey/black lists)
  - PEP (Politically Exposed Person) and sanctions list matches
  - Channel anomaly (unusual mix of cash/wire/ACH for account type)
- **Output:** Flagged transactions in `data/flagged/screening-alerts.json` with alert codes
- **Capabilities:** mutates_state, writes_files

### Phase 3: `analyze-patterns` (agent: pattern-analyst)
- **Action:** For each flagged transaction cluster, identify AML typology:
  - **Structuring/Smurfing:** Multiple deposits below CTR threshold across branches/days
  - **Layering:** Rapid fund transfers between multiple accounts, shell companies, jurisdictions
  - **Integration:** Funds re-entering legitimate economy via real estate, business revenue, investments
  - **Trade-based ML:** Mis-invoicing, phantom shipments, over/under-valuation of goods
  - **Round-tripping:** Funds sent offshore then returned as "foreign investment"
  - **Funnel accounts:** Multiple individuals depositing into single account
- Compute composite risk score (0-100) with typology-specific weighting
- **Output:** `data/analysis/pattern-report.json` with risk scores and typology classifications
- **Decision Contract:**
  - Required fields: `verdict`, `reasoning`, `high_risk_count`, `typologies_detected`
  - Verdicts:
    - `critical` — patterns strongly indicative of ML, immediate investigation
    - `elevated` — suspicious patterns warrant investigation
    - `routine` — CTR-only or low-risk alerts, file CTR and close
- **Routing:**
  - `critical` / `elevated` → proceed to `enhanced-due-diligence`
  - `routine` → skip to `file-ctrs`

### Phase 4: `enhanced-due-diligence` (agent: aml-investigator)
- **Action:** Perform EDD on flagged customers:
  - Review full account history from `data/customers/` (account opening docs, KYC records)
  - Analyze transaction patterns over 90-day window
  - Check beneficial ownership structure from `data/ownership/`
  - Identify source of funds and source of wealth
  - Cross-reference with adverse media and PEP databases in `config/watchlists.json`
  - Document risk factors and CDD/EDD findings
- **Output:** `data/edd/customer-profile.json` with enhanced due diligence report
- **Capabilities:** mutates_state, writes_files

### Phase 5: `investigate-activity` (agent: aml-investigator)
- **Action:** Deep investigation of suspicious activity:
  1. Build transaction timeline with fund flow visualization data
  2. Trace funds through account chains (follow-the-money)
  3. Identify counterparties and their risk profiles
  4. Map relationships between subjects (shared addresses, phone numbers, employers)
  5. Correlate with known ML typologies in `config/ml-typologies.json`
  6. Assess whether activity has legitimate business purpose
  7. Compile evidence package with confidence levels per finding
- **Output:** Investigation report in `data/investigations/case-report.json`
- **Decision Contract:**
  - Required fields: `verdict`, `reasoning`, `evidence_summary`, `confidence_score`, `estimated_suspicious_amount`
  - Verdicts:
    - `suspicious` — evidence supports SAR filing
    - `inconclusive` — need additional information or monitoring period
    - `legitimate` — activity has documented legitimate purpose
    - `escalate` — complex case (e.g., involves PEPs, foreign government officials, or >$1M)
- **Routing:**
  - `suspicious` → proceed to `compliance-review`
  - `inconclusive` → rework to `investigate-activity` (max 2 attempts, then auto-escalate)
  - `legitimate` → skip to `generate-case-summary`
  - `escalate` → proceed to `compliance-review`

### Phase 6: `compliance-review` (agent: compliance-officer)
- **Action:** Senior BSA officer review:
  - Evaluate strength and completeness of evidence
  - Assess regulatory filing obligations (SAR, CTR, 314(a), 314(b))
  - Consider SAR timing requirements (30 days from detection, 60 if no subject identified)
  - Review for potential violations: structuring (31 USC 5324), money laundering (18 USC 1956/1957)
  - Determine if law enforcement referral warranted (via 314(a) or direct LEA notification)
  - Evaluate if account continuation is appropriate or if exit is required
- **Output:** Compliance decision in `data/decisions/compliance-decision.json`
- **Decision Contract:**
  - Required fields: `verdict`, `reasoning`, `filing_required`, `law_enforcement_referral`, `account_action`
  - Verdicts:
    - `file-sar` — sufficient basis for SAR, proceed with filing
    - `monitor` — insufficient for SAR now but continue monitoring (90-day review)
    - `close` — no filing required, document rationale
    - `rework` — investigation incomplete, need specific additional evidence
- **Routing:**
  - `file-sar` → proceed to `prepare-sar`
  - `monitor` → proceed to `generate-case-summary`
  - `close` → proceed to `generate-case-summary`
  - `rework` → back to `investigate-activity` (max 3 attempts)

### Phase 7: `prepare-sar` (agent: filing-specialist)
- **Action:** Prepare FinCEN SAR filing:
  - Complete all required fields per BSA E-Filing specifications
  - Subject information (name, SSN/TIN, DOB, address, account numbers)
  - Suspicious activity characterization (money laundering, structuring, terrorist financing, etc.)
  - Date range of suspicious activity
  - Amount involved (cumulative, not individual transactions)
  - Write SAR narrative (factual, 300-1000 words, no conclusions of law)
  - Narrative must include: who, what, when, where, why, how
  - Cross-reference related SARs if continuation filing
- **Output:** SAR draft in `data/sars/draft-sar.json`, narrative in `data/sars/narrative.md`
- **Capabilities:** mutates_state, writes_files

### Phase 8: `validate-sar` (agent: compliance-officer)
- **Action:** Quality review of SAR before filing:
  - Verify all required fields populated correctly
  - Review narrative for completeness, accuracy, and prohibited content (no legal conclusions, no speculation)
  - Confirm amount calculations match investigation findings
  - Verify subject identification is complete or appropriately marked unknown
  - Check for consistency between characterization checkboxes and narrative
  - Validate against FinCEN common rejection reasons
- **Decision Contract:**
  - Required fields: `verdict`, `reasoning`, `issues_if_any`
  - Verdicts:
    - `approved` — SAR ready for filing
    - `revise` — specific issues need correction before filing
- **Routing:**
  - `approved` → proceed to `file-reports`
  - `revise` → back to `prepare-sar` (max 2 attempts)

### Phase 9: `file-reports` (command)
- **Script:** `scripts/file-reports.sh`
- **Action:** Simulate BSA E-Filing submission:
  - Generate filing confirmation with BSA ID and timestamp
  - File SAR (if applicable) to `output/sars/SAR-<case-id>.json`
  - File CTRs (if applicable) to `output/ctrs/CTR-<batch-id>.json`
  - Log filing event to `data/audit/filing-log.json`
- **Timeout:** 60s

### Phase 10: `file-ctrs` (agent: filing-specialist)
- **Action:** For transactions triggering CTR requirements ($10K+ cash):
  - Prepare FinCEN CTR (Currency Transaction Report)
  - Document: person conducting transaction, person on whose behalf it is conducted, financial institution info
  - Handle multiple transactions aggregation (same person, same day)
  - Write CTR to `output/ctrs/`
- **Output:** CTR filings in `output/ctrs/`
- **Capabilities:** writes_files

### Phase 11: `generate-case-summary` (agent: filing-specialist)
- **Action:** Generate comprehensive case summary:
  - Case timeline (detection → investigation → resolution)
  - Evidence inventory with confidence ratings
  - Filing decisions and rationale
  - Account actions taken (continue monitoring, restrict, exit)
  - Recommended follow-up actions and monitoring triggers
  - Regulatory examination readiness notes
- **Output:** Case summary in `output/reports/case-summary.md`
- **Capabilities:** writes_files

### Phase 12: `update-monitoring-rules` (agent: pattern-analyst)
- **Action:** Based on investigation findings, update monitoring rules:
  - Add newly identified ML patterns to `config/ml-typologies.json`
  - Tune screening thresholds if false-positive rate exceeds target
  - Update geographic risk ratings based on FATF changes
  - Add new structuring patterns observed
  - Document rule changes with case references and justification
- **Output:** Updated configs and change log in `data/audit/rule-updates.json`
- **Capabilities:** mutates_state, writes_files, requires_commit

---

## Workflows

### 1. `full-investigation` (default)
Complete AML investigation pipeline — from transaction screening through pattern analysis, EDD, investigation, compliance review, SAR/CTR filing, and rule updates.

**Phases:**
1. `ingest-transactions`
2. `screen-transactions`
3. `analyze-patterns` → on `routine`: skip to `file-ctrs`
4. `enhanced-due-diligence`
5. `investigate-activity` → on `legitimate`: skip to `generate-case-summary` / on `inconclusive`: rework to self (max 2)
6. `compliance-review` → on `rework`: back to `investigate-activity` (max 3) / on `monitor` or `close`: skip to `generate-case-summary`
7. `prepare-sar`
8. `validate-sar` → on `revise`: back to `prepare-sar` (max 2)
9. `file-reports`
10. `file-ctrs`
11. `generate-case-summary`
12. `update-monitoring-rules`

### 2. `transaction-screening`
Lightweight screening workflow — ingest, screen, and analyze patterns only. No deep investigation.

**Phases:**
1. `ingest-transactions`
2. `screen-transactions`
3. `analyze-patterns`

### 3. `periodic-review`
Scheduled review of existing cases and customers for ongoing monitoring compliance (90-day SAR continuation reviews, periodic EDD refresh).

**Phases:**
1. `enhanced-due-diligence`
2. `investigate-activity`
3. `compliance-review`
4. `generate-case-summary`

---

## Schedules

| Schedule | Cron | Workflow | Purpose |
|---|---|---|---|
| `continuous-screening` | `*/30 * * * *` | transaction-screening | Screen incoming transactions every 30 minutes |
| `daily-investigation` | `0 7 * * *` | full-investigation | Full investigation run each morning at 7 AM |
| `quarterly-review` | `0 9 1 */3 *` | periodic-review | Quarterly customer review (1st day of quarter) |

---

## MCP Servers

| Server | Purpose |
|---|---|
| `filesystem` | Read/write transaction data, customer profiles, investigation reports, SAR/CTR filings, audit trail |
| `sequential-thinking` | Structured reasoning for pattern analysis, fund flow tracing, evidence evaluation, compliance decisions |

---

## Directory Structure

```
workflows/aml-monitor/
├── .ao/workflows/
│   ├── agents.yaml
│   ├── phases.yaml
│   ├── workflows.yaml
│   ├── mcp-servers.yaml
│   └── schedules.yaml
├── config/
│   ├── screening-rules.json        # BSA thresholds, velocity rules, geographic risk ratings
│   ├── ml-typologies.json          # Known money laundering patterns and indicators
│   ├── watchlists.json             # PEP lists, sanctions, adverse media flags (sample)
│   ├── risk-weights.json           # Composite risk scoring model weights
│   ├── sar-template.json           # FinCEN SAR field requirements and format
│   └── ctr-template.json           # FinCEN CTR field requirements and format
├── data/
│   ├── transactions/
│   │   ├── incoming/               # Raw transaction batches (drop files here)
│   │   └── normalized/             # Post-ingest standardized format
│   ├── customers/                  # Customer profiles, KYC records, account history
│   ├── ownership/                  # Beneficial ownership structures
│   ├── flagged/                    # Screening alerts
│   ├── analysis/                   # Pattern analysis results with typology classifications
│   ├── edd/                        # Enhanced due diligence reports
│   ├── investigations/             # Investigation case reports
│   ├── decisions/                  # Compliance officer decisions
│   ├── sars/                       # SAR drafts and narratives
│   └── audit/                      # Immutable audit trail (filing log, rule changes)
├── output/
│   ├── sars/                       # Filed SAR documents
│   ├── ctrs/                       # Filed CTR documents
│   └── reports/                    # Case summaries, management reports
├── scripts/
│   ├── ingest-transactions.sh      # Transaction ingestion and normalization
│   └── file-reports.sh             # BSA E-Filing submission simulation
├── templates/
│   ├── sar-narrative.md            # SAR narrative template (who/what/when/where/why/how)
│   ├── investigation-report.md     # Investigation report template
│   └── case-summary.md            # Case summary template
├── PLAN.md
├── CLAUDE.md
└── README.md
```

---

## Key Features Demonstrated

| AO Feature | Where Used |
|---|---|
| **Scheduled workflows** | 30-min screening, daily full investigation, quarterly periodic review |
| **Decision contracts** | `analyze-patterns` (critical/elevated/routine), `investigate-activity` (suspicious/inconclusive/legitimate/escalate), `compliance-review` (file-sar/monitor/close/rework), `validate-sar` (approved/revise) |
| **Multi-agent pipeline** | 5 agents across 3 models with clear BSA role separation |
| **Command phases** | Transaction ingestion, BSA E-Filing submission |
| **Phase routing** | Skip-ahead on routine/legitimate, rework loops for insufficient evidence |
| **Rework loops** | Investigation ↔ compliance-review (max 3), SAR preparation ↔ validation (max 2), investigation self-rework on inconclusive (max 2) |
| **Output contracts** | Structured investigation reports, SAR/CTR filings, case summaries |
| **Model variety** | Haiku (high-volume screening), Sonnet (analysis/investigation/filing), Opus (compliance decisions) |
| **Regulatory compliance** | FinCEN SAR/CTR generation, BSA audit trail, evidence chain documentation |

---

## Domain Notes — AML/BSA Reference

- **BSA:** Bank Secrecy Act — primary US AML statute. Requires financial institutions to maintain AML programs, file SARs and CTRs.
- **SAR:** Suspicious Activity Report — must be filed within 30 days of detection (60 if no subject identified). Filed via FinCEN BSA E-Filing. Confidential — cannot be disclosed to subject.
- **CTR:** Currency Transaction Report — mandatory for cash transactions >$10,000. Must be filed within 15 days.
- **Structuring (31 USC 5324):** Deliberately breaking transactions to evade CTR reporting. Federal crime — up to 5 years imprisonment.
- **Money Laundering (18 USC 1956):** Conducting financial transactions with proceeds of specified unlawful activity. Up to 20 years.
- **314(a):** FinCEN program allowing law enforcement to request account searches across financial institutions.
- **314(b):** Voluntary information sharing between financial institutions for AML purposes.
- **CDD/EDD:** Customer Due Diligence / Enhanced Due Diligence. CDD required for all customers; EDD triggered by high-risk indicators.
- **FATF Grey/Black Lists:** Financial Action Task Force jurisdictions with strategic AML deficiencies.
- **PEP:** Politically Exposed Person — foreign government officials and their associates. Require enhanced scrutiny.
- **Beneficial Ownership:** Identifying natural persons who ultimately own/control an entity (>25% ownership or significant control).
- **SAR Narrative Requirements:** Must be factual. Include: who (subjects), what (activity), when (dates), where (accounts/branches), why (suspicious indicators), how (methods used). No legal conclusions. 300-1000 words recommended.

## Differentiation from Fraud Detection

This AML pipeline is distinct from fraud detection:
- **Fraud detection** protects the institution/customer from financial loss (unauthorized transactions, identity theft)
- **AML monitoring** detects customers using the institution to launder illicit proceeds — the customer IS the bad actor
- AML has specific regulatory filing obligations (SAR/CTR) with strict deadlines
- AML investigations trace fund flows across accounts and institutions, not just individual transactions
- AML requires ongoing monitoring (90-day SAR continuation reviews) vs fraud's incident-based response
