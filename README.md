# aml-monitor

Anti-money laundering pipeline — screens transactions for BSA/AML red flags, identifies laundering typologies (structuring, layering, integration, TBML), investigates suspicious activity, prepares FinCEN SAR/CTR filings, and manages cases through regulatory resolution.

## Workflow Diagram

```
                    ┌─────────────────────┐
                    │  ingest-transactions │  (command: normalize + enrich)
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  screen-transactions │  (haiku: CTR, structuring, velocity,
                    └──────────┬──────────┘   geo risk, PEP/sanctions, channel)
                               │
                    ┌──────────▼──────────┐
                    │   analyze-patterns   │  (sonnet: typology detection,
                    └──────────┬──────────┘   risk scoring 0-100)
                               │
              ┌────────────────┼────────────────┐
           routine          elevated          critical
              │                └────────────────┤
              ▼                                 ▼
        ┌──────────┐              ┌─────────────────────────┐
        │ file-ctrs│              │  enhanced-due-diligence  │
        └──────────┘              └────────────┬────────────┘
                                               │
                                  ┌────────────▼────────────┐
                                  │   investigate-activity   │◄─────┐
                                  └────────────┬────────────┘      │ rework
                                               │                   │ (max 2)
                         ┌─────────────────────┼──────────────┐    │
                      legitimate          suspicious        inconclusive
                         │             + escalate                │──┘
                         ▼                   ▼
                 ┌───────────────┐  ┌─────────────────┐
                 │               │  │ compliance-review │◄──┐
                 │               │  └────────┬─────────┘   │ rework
                 │               │           │             │ (max 3)
                 │               │   ┌───────┴──────┐      │
                 │               │monitor/close  file-sar──┘
                 │               │   │              │
                 │               │   │    ┌─────────▼────────┐
                 │               │   │    │   prepare-sar     │◄─┐
                 │               │   │    └─────────┬────────┘  │ revise
                 │               │   │              │           │ (max 2)
                 │               │   │    ┌─────────▼────────┐  │
                 │               │   │    │   validate-sar    │──┘
                 │               │   │    └─────────┬────────┘
                 │               │   │              │
                 │               │   │    ┌─────────▼────────┐
                 │               │   │    │   file-reports    │  (command)
                 │               │   │    └─────────┬────────┘
                 │               │   │              │
                 └───────────────┴───┴──────────────┤
                                                    ▼
                                         ┌─────────────────────┐
                                         │  generate-case-summary│
                                         └──────────┬──────────┘
                                                    │
                                         ┌──────────▼──────────┐
                                         │ update-monitoring-rules│
                                         └─────────────────────┘
```

## Quick Start

```bash
cd workflows/aml-monitor
ao daemon start

# Drop a transaction batch to trigger screening
cp /path/to/transactions.json data/transactions/incoming/

# Run manually
ao workflow run full-investigation

# Or let the schedule run it automatically (every 30min screening, 7am full investigation)
```

## Agents

| Agent | Model | Role |
|---|---|---|
| **transaction-screener** | claude-haiku-4-5 | High-volume screening — CTR thresholds, structuring detection, velocity/geo/PEP/sanctions checks |
| **pattern-analyst** | claude-sonnet-4-6 | Typology identification — structuring, layering, integration, TBML, round-tripping, funnel accounts |
| **aml-investigator** | claude-sonnet-4-6 | Deep investigation — fund flow tracing, beneficial ownership, evidence packages with confidence ratings |
| **compliance-officer** | claude-opus-4-6 | BSA authority — SAR filing decisions, regulatory risk evaluation, evidence sufficiency review |
| **filing-specialist** | claude-sonnet-4-6 | FinCEN filings — SAR narratives, CTR preparation, case summaries, management reporting |

## AO Features Demonstrated

| Feature | Where Used |
|---|---|
| **Scheduled workflows** | 30-min transaction screening, 7am daily full investigation, quarterly periodic review |
| **Decision contracts** | `analyze-patterns` (critical/elevated/routine), `investigate-activity` (suspicious/inconclusive/legitimate/escalate), `compliance-review` (file-sar/monitor/close/rework), `validate-sar` (approved/revise) |
| **Rework loops** | Investigation ↔ compliance review (max 3), SAR validation ↔ preparation (max 2), investigation self-rework on inconclusive (max 2) |
| **Phase routing / skip-ahead** | `routine` skips directly to CTR filing; `legitimate` skips to case summary; `monitor`/`close` bypass SAR pipeline |
| **Multi-agent pipeline** | 5 agents across 3 models with domain-appropriate role separation |
| **Command phases** | Transaction ingestion/normalization, BSA E-Filing simulation |
| **Model variety** | Haiku (high-throughput screening), Sonnet (analysis/investigation/filing), Opus (compliance decisions) |
| **Post-success merge** | Full investigation workflow commits and merges updated rule configurations |
| **Multiple workflows** | full-investigation, transaction-screening, periodic-review for different operational cadences |

## Requirements

### API Keys
None required — all processing is done by Claude agents with filesystem access.

### Tools
- Node.js (for MCP servers via npx)
- `ao` CLI daemon

### MCP Servers (auto-installed via npx)
- `@modelcontextprotocol/server-filesystem` — read/write all case data, configs, reports
- `@modelcontextprotocol/server-sequential-thinking` — structured reasoning for complex fund flow analysis

## Directory Structure

```
workflows/aml-monitor/
├── .ao/workflows/
│   ├── agents.yaml           # 5 agents across 3 models
│   ├── phases.yaml           # 12 phases
│   ├── workflows.yaml        # 3 workflow pipelines
│   ├── mcp-servers.yaml
│   └── schedules.yaml        # 3 cron schedules
├── config/
│   ├── screening-rules.json  # BSA thresholds, velocity rules, geographic risk
│   ├── ml-typologies.json    # Known ML patterns and indicators
│   ├── watchlists.json       # PEP lists, sanctions, adverse media (sample)
│   ├── risk-weights.json     # Composite risk scoring weights
│   ├── sar-template.json     # FinCEN SAR field spec
│   └── ctr-template.json     # FinCEN CTR field spec
├── data/
│   ├── transactions/
│   │   ├── incoming/         # Drop raw transaction batches here
│   │   └── normalized/       # Post-ingest standardized format
│   ├── customers/            # Customer profiles, KYC records
│   ├── ownership/            # Beneficial ownership structures
│   ├── flagged/              # Screening alerts
│   ├── analysis/             # Pattern analysis with typology classifications
│   ├── edd/                  # Enhanced due diligence reports
│   ├── investigations/       # Investigation case reports
│   ├── decisions/            # Compliance officer decisions
│   ├── sars/                 # SAR drafts and narratives
│   └── audit/                # Immutable audit trail
├── output/
│   ├── sars/                 # Filed SAR documents
│   ├── ctrs/                 # Filed CTR documents
│   └── reports/              # Case summaries, management reports
├── scripts/
│   ├── ingest-transactions.sh
│   └── file-reports.sh
└── templates/
    ├── sar-narrative.md
    ├── investigation-report.md
    └── case-summary.md
```
