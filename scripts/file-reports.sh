#!/usr/bin/env bash
# file-reports.sh
# Simulates BSA E-Filing submission — generates filing confirmations with BSA IDs,
# copies approved SARs and CTRs to output directories, and logs to audit trail.

set -euo pipefail

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date -u +%Y%m%d)
AUDIT_LOG="data/audit/filing-log.json"
SAR_DRAFT_DIR="data/sars"
CTR_STAGING_DIR="output/ctrs"
SAR_OUTPUT_DIR="output/sars"

echo "[${TIMESTAMP}] Starting BSA E-Filing simulation"
mkdir -p "${SAR_OUTPUT_DIR}" "${CTR_STAGING_DIR}" "data/audit"

# Initialize audit log if it doesn't exist
if [ ! -f "${AUDIT_LOG}" ]; then
  echo '{"filings": []}' > "${AUDIT_LOG}"
fi

filing_count=0

# Process approved SAR drafts
for draft in ${SAR_DRAFT_DIR}/*-draft-sar.json 2>/dev/null; do
  [ -f "${draft}" ] || continue

  case_id=$(basename "${draft}" "-draft-sar.json")
  bsa_id="BSA$(date -u +%Y%m%d%H%M%S)$(shuf -i 1000-9999 -n 1)"

  echo "[${TIMESTAMP}] Filing SAR for case ${case_id} — BSA ID: ${bsa_id}"

  # Generate filed SAR with confirmation
  python3 << PYTHON
import json, os
from datetime import datetime, timezone

draft_file = "${draft}"
output_file = "${SAR_OUTPUT_DIR}/${case_id}-filed-sar.json"
bsa_id = "${bsa_id}"
timestamp = "${TIMESTAMP}"

try:
    with open(draft_file) as f:
        sar_data = json.load(f)
except Exception:
    sar_data = {}

filed_sar = {
    **sar_data,
    "filing_confirmation": {
        "bsa_id": bsa_id,
        "filing_timestamp": timestamp,
        "filing_method": "BSA E-Filing (Simulated)",
        "status": "ACCEPTED",
        "confirmation_number": f"CONF-{bsa_id}",
        "_note": "This is a simulated filing. In production, connect to FinCEN BSA E-Filing system."
    }
}

os.makedirs(os.path.dirname(output_file), exist_ok=True)
with open(output_file, "w") as f:
    json.dump(filed_sar, f, indent=2)

print(f"Filed SAR: {output_file} (BSA ID: {bsa_id})")
PYTHON

  # Append to audit log
  python3 << PYTHON
import json, os

audit_log = "${AUDIT_LOG}"
entry = {
    "filing_type": "SAR",
    "case_id": "${case_id}",
    "bsa_id": "${bsa_id}",
    "filing_timestamp": "${TIMESTAMP}",
    "status": "ACCEPTED",
    "filed_by": "file-reports-script"
}

with open(audit_log) as f:
    log = json.load(f)

log["filings"].append(entry)

with open(audit_log, "w") as f:
    json.dump(log, f, indent=2)
PYTHON

  filing_count=$((filing_count + 1))
done

# Process CTR drafts
for ctr in ${CTR_STAGING_DIR}/CTR-*.json 2>/dev/null; do
  [ -f "${ctr}" ] || continue

  # Only process if not already filed (no filing_confirmation field)
  if python3 -c "import json; d=json.load(open('${ctr}')); exit(0 if 'filing_confirmation' not in d else 1)" 2>/dev/null; then
    ctr_id=$(basename "${ctr}" .json)
    bsa_ctr_id="CTR$(date -u +%Y%m%d%H%M%S)$(shuf -i 1000-9999 -n 1)"

    echo "[${TIMESTAMP}] Filing CTR: ${ctr_id} — BSA ID: ${bsa_ctr_id}"

    python3 << PYTHON
import json, os

ctr_file = "${ctr}"
bsa_id = "${bsa_ctr_id}"
timestamp = "${TIMESTAMP}"

with open(ctr_file) as f:
    ctr_data = json.load(f)

ctr_data["filing_confirmation"] = {
    "bsa_id": bsa_id,
    "filing_timestamp": timestamp,
    "filing_method": "BSA E-Filing (Simulated)",
    "status": "ACCEPTED",
    "_note": "Simulated filing. CTRs must be filed within 15 days of transaction date."
}

with open(ctr_file, "w") as f:
    json.dump(ctr_data, f, indent=2)

print(f"Filed CTR: {ctr_file} (BSA ID: {bsa_id})")
PYTHON

    # Append to audit log
    python3 << PYTHON
import json

audit_log = "${AUDIT_LOG}"
entry = {
    "filing_type": "CTR",
    "ctr_id": "${ctr_id}",
    "bsa_id": "${bsa_ctr_id}",
    "filing_timestamp": "${TIMESTAMP}",
    "status": "ACCEPTED",
    "filed_by": "file-reports-script"
}

with open(audit_log) as f:
    log = json.load(f)

log["filings"].append(entry)

with open(audit_log, "w") as f:
    json.dump(log, f, indent=2)
PYTHON

    filing_count=$((filing_count + 1))
  fi
done

echo "[${TIMESTAMP}] BSA E-Filing complete — ${filing_count} reports filed"
echo "[${TIMESTAMP}] Audit log: ${AUDIT_LOG}"
