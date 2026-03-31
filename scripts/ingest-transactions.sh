#!/usr/bin/env bash
# ingest-transactions.sh
# Reads raw transaction files from data/transactions/incoming/,
# normalizes format, enriches with customer data, outputs to data/transactions/normalized/batch.json

set -euo pipefail

INCOMING_DIR="data/transactions/incoming"
NORMALIZED_DIR="data/transactions/normalized"
CUSTOMERS_DIR="data/customers"
OUTPUT_FILE="${NORMALIZED_DIR}/batch.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BATCH_ID="BATCH-$(date -u +%Y%m%d-%H%M%S)"

echo "[${TIMESTAMP}] Starting transaction ingestion — batch ${BATCH_ID}"
mkdir -p "${NORMALIZED_DIR}"

# Check for incoming files
incoming_files=$(find "${INCOMING_DIR}" -name "*.json" -o -name "*.csv" 2>/dev/null | sort)

if [ -z "${incoming_files}" ]; then
  echo "[${TIMESTAMP}] No incoming transaction files found in ${INCOMING_DIR}"
  echo "[${TIMESTAMP}] Creating empty batch for downstream phases"
  cat > "${OUTPUT_FILE}" << EOF
{
  "batch_id": "${BATCH_ID}",
  "ingestion_timestamp": "${TIMESTAMP}",
  "transaction_count": 0,
  "transactions": [],
  "_note": "No incoming transaction files found. Place JSON or CSV files in ${INCOMING_DIR}/ to process."
}
EOF
  exit 0
fi

# Initialize output
transaction_count=0
transactions_json="[]"

# Process each incoming file
for file in ${incoming_files}; do
  echo "[${TIMESTAMP}] Processing: ${file}"
  extension="${file##*.}"

  if [ "${extension}" = "json" ]; then
    # JSON format — validate and extract transactions array
    if python3 -c "import json, sys; data=json.load(open('${file}')); print(len(data.get('transactions', data if isinstance(data, list) else [])))" 2>/dev/null; then
      count=$(python3 -c "
import json, sys
data = json.load(open('${file}'))
txns = data.get('transactions', data) if isinstance(data, dict) else data
print(len(txns) if isinstance(txns, list) else 0)
")
      echo "[${TIMESTAMP}]   Found ${count} transactions in ${file}"
      transaction_count=$((transaction_count + count))
    else
      echo "[${TIMESTAMP}]   WARNING: Could not parse ${file} — skipping"
    fi
  elif [ "${extension}" = "csv" ]; then
    count=$(python3 -c "
import csv
with open('${file}') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
print(len(rows))
" 2>/dev/null || echo "0")
    echo "[${TIMESTAMP}]   Found ${count} rows in CSV ${file}"
    transaction_count=$((transaction_count + count))
  fi
done

# Build normalized batch — in production this would do full normalization/enrichment
# For demonstration, merge all incoming files into standardized format
python3 << PYTHON
import json
import os
import glob
from datetime import datetime, timezone

batch_id = "${BATCH_ID}"
timestamp = "${TIMESTAMP}"
incoming_dir = "${INCOMING_DIR}"
customers_dir = "${CUSTOMERS_DIR}"
output_file = "${OUTPUT_FILE}"

all_transactions = []

# Load all incoming JSON files
for filepath in sorted(glob.glob(os.path.join(incoming_dir, "*.json"))):
    try:
        with open(filepath) as f:
            data = json.load(f)
        if isinstance(data, list):
            raw_txns = data
        elif isinstance(data, dict):
            raw_txns = data.get("transactions", [])
        else:
            raw_txns = []

        for txn in raw_txns:
            # Normalize to standard schema
            normalized = {
                "transaction_id": txn.get("transaction_id", txn.get("id", f"TXN-UNKNOWN-{len(all_transactions)}")),
                "customer_id": txn.get("customer_id", txn.get("account_holder_id", "UNKNOWN")),
                "account_number": txn.get("account_number", txn.get("account", "UNKNOWN")),
                "transaction_date": txn.get("date", txn.get("transaction_date", txn.get("timestamp", ""))),
                "amount": float(txn.get("amount", 0)),
                "currency": txn.get("currency", "USD"),
                "transaction_type": txn.get("type", txn.get("transaction_type", "UNKNOWN")),
                "channel": txn.get("channel", "UNKNOWN"),
                "counterparty_name": txn.get("counterparty_name", txn.get("payee", txn.get("payer", ""))),
                "counterparty_account": txn.get("counterparty_account", ""),
                "counterparty_institution": txn.get("counterparty_institution", txn.get("bank", "")),
                "counterparty_country": txn.get("counterparty_country", txn.get("country", "US")),
                "memo": txn.get("memo", txn.get("description", txn.get("narrative", ""))),
                "branch_id": txn.get("branch_id", txn.get("branch", "")),
                "is_cash": txn.get("is_cash", txn.get("cash", txn.get("transaction_type", "").upper() in ["CASH", "CASH_DEPOSIT", "CASH_WITHDRAWAL"])),
                "source_file": os.path.basename(filepath),
                "ingestion_timestamp": timestamp
            }
            all_transactions.append(normalized)
    except Exception as e:
        print(f"Warning: Could not process {filepath}: {e}")

# Build output batch
batch = {
    "batch_id": batch_id,
    "ingestion_timestamp": timestamp,
    "transaction_count": len(all_transactions),
    "unique_customers": len(set(t["customer_id"] for t in all_transactions)),
    "transactions": all_transactions
}

os.makedirs(os.path.dirname(output_file), exist_ok=True)
with open(output_file, "w") as f:
    json.dump(batch, f, indent=2)

print(f"Wrote {len(all_transactions)} normalized transactions to {output_file}")
PYTHON

echo "[${TIMESTAMP}] Ingestion complete — ${transaction_count} transactions in batch ${BATCH_ID}"
echo "[${TIMESTAMP}] Output: ${OUTPUT_FILE}"
