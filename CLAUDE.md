# AML Monitoring Pipeline — Project Context

## What This Project Does

This is an anti-money laundering (AML) monitoring system for a US financial institution.
It screens transactions for Bank Secrecy Act (BSA) violations and money laundering activity,
investigates suspicious patterns, and prepares regulatory filings (SAR/CTR) for FinCEN.

## Regulatory Framework

This system operates under the Bank Secrecy Act (BSA) and FinCEN regulations:

- **SAR (Suspicious Activity Report)**: Must be filed within 30 days of detection when the institution
  has "reason to suspect" funds involve illegal activity. Filed via FinCEN BSA E-Filing.
  SAR filings are CONFIDENTIAL — never disclose to the subject or third parties.
- **CTR (Currency Transaction Report)**: Filed for cash transactions >= $10,000.
  Must be filed within 15 calendar days. Aggregation rules apply.
- **SAR Safe Harbor**: Financial institutions and their employees are immune from civil liability
  for filing SARs in good faith (31 USC 5318(g)(3)). When in doubt, file.
- **Tipping Off Prohibition**: It is illegal to notify a subject that a SAR has been or may be filed.

## Data Layout

- `data/transactions/incoming/` — raw transaction batches arrive here (CSV or JSON)
- `data/transactions/normalized/batch.json` — post-ingest standardized format
- `data/customers/<customer_id>/` — KYC records, account history, prior SAR activity
- `data/ownership/<customer_id>/` — beneficial ownership corporate structures
- `data/flagged/screening-alerts.json` — output from screening phase
- `data/analysis/pattern-report.json` — typology analysis output
- `data/edd/<customer_id>-edd.json` — enhanced due diligence reports
- `data/investigations/<case_id>-case-report.json` — investigation findings
- `data/decisions/<case_id>-compliance-decision.json` — BSA officer decisions
- `data/sars/<case_id>-draft-sar.json` and `data/sars/<case_id>-narrative.md` — SAR drafts
- `data/audit/` — immutable audit trail (never modify existing entries)
- `output/sars/` — finalized SAR filings
- `output/ctrs/` — finalized CTR filings
- `output/reports/` — case summaries, management reports

## Configuration Files

- `config/screening-rules.json` — BSA thresholds, velocity baselines, FATF country risk ratings
- `config/ml-typologies.json` — known money laundering patterns (indicators, risk weights)
- `config/watchlists.json` — PEP lists, sanctions, adverse media, known associates
- `config/risk-weights.json` — composite risk score model (typology match, velocity, geo, PEP)
- `config/sar-template.json` — FinCEN SAR field specification and valid values
- `config/ctr-template.json` — FinCEN CTR field specification

## Agent Responsibilities

- **transaction-screener** (haiku): Volume screening only — applies rules mechanically, flags exceptions
- **pattern-analyst** (sonnet): Typology identification — thinks about behavioral patterns across transactions
- **aml-investigator** (sonnet): Evidence gathering and analysis — builds the case file
- **compliance-officer** (opus): Decision authority — makes filing and account action decisions
- **filing-specialist** (sonnet): Documentation — produces the actual regulatory submissions

## Case ID Convention

Case IDs follow the format: `CASE-YYYYMMDD-NNNN`
Example: `CASE-20260330-0001`

Generate these when a new investigation case is opened in the `investigate-activity` phase.

## Audit Trail Rules

The `data/audit/` directory contains the immutable audit trail. Rules:
1. Never modify or delete existing entries in `data/audit/filing-log.json`
2. Always append (never overwrite) to audit log files
3. Every filing event must be logged with timestamp and agent identity
4. Rule changes in `data/audit/rule-updates.json` require case_reference

## Output Quality Standards

For SAR narratives:
- Must be factual — only state what the transaction records show
- Must include WHO/WHAT/WHEN/WHERE/WHY/HOW structure
- 300-1,000 words
- No legal conclusions ("the subject is laundering money")
- No officer names, no attorney-client material
- Cumulative suspicious amount, not per-transaction amounts

## Workflows

- `full-investigation`: Complete pipeline, run daily at 7am
- `transaction-screening`: Screening only, runs every 30 minutes
- `periodic-review`: Ongoing monitoring for existing cases, quarterly
