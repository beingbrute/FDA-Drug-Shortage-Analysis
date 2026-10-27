"""
AI extraction check: ask a local LLM (Qwen3 4B via Ollama) to extract two fields
from FDA drug-shortage notes, using the same written rules as the rule-based labels.

Input : data/ai_sample_rules.csv   (exported from the ai_sample tab; needs columns ID and Text)
Output: data/ai_sample_qwen3.csv   (ID, Text, AI: expected recovery, AI: reason, Valid output, Raw output)

Run from the project folder:
    python scripts/ai_extract.py
Ollama must be running, with the model pulled (ollama pull qwen3:4b).
"""

import csv
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

MODEL = "qwen3:4b"
OLLAMA_URL = "http://localhost:11434/api/chat"
INPUT_CSV = Path("data/ai_sample_rules.csv")
OUTPUT_CSV = Path("data/ai_sample_qwen3.csv")

MONTHS = ("January|February|March|April|May|June|July|August|"
          "September|October|November|December")
RECOVERY_OK = re.compile(rf"^(?:(?:{MONTHS}) \d{{4}}|TBD|Not stated)$")
REASONS = ["Manufacturing delay", "Discontinuation", "Demand increase", "Other", "Not stated"]

RULES = """You extract two fields from a short note about a US drug shortage.

FIELD 1 "expected_recovery": when supply is expected to come back.
Answer with a month and year written as "Month YYYY" (full month name, e.g. "March 2027"), or "TBD", or "Not stated".
Rules:
1. A single month and year for recovery, availability, replenishment, next release, or when more lots will be available: use it.
2. Ignore words like early, mid, late, end.
3. A range or two months: use the later month.
4. A quarter: use the last month of that quarter (Q1 = March, Q2 = June, Q3 = September, Q4 = December).
5. Both a next-delivery date and an estimated-recovery date: use the estimated-recovery date.
6. Recovery or release is to be decided, or not available yet: "TBD".
7. Dates about expiry, dating or shelf life are not recovery dates.
8. No recovery information at all (distributor names, phone numbers, NDC codes, "check wholesalers"): "Not stated".

FIELD 2 "reason": why the drug is short, only if the note says so.
Answer with exactly one of: "Manufacturing delay", "Discontinuation", "Demand increase", "Other", "Not stated".
Rules:
1. The note says there is a manufacturing delay: "Manufacturing delay".
2. The note says the product is no longer, or not currently, manufactured, or is discontinued: "Discontinuation".
3. The note says demand has increased: "Demand increase".
4. The note gives another cause (ingredient shortage, shipping delay, regulatory issue): "Other".
5. No cause is given. Status words (backorder, allocation, limited supply, check wholesalers) and plans ("lots scheduled to meet demand") are not causes: "Not stated".

Reply with JSON only."""

SCHEMA = {
    "type": "object",
    "properties": {
        "expected_recovery": {"type": "string"},
        "reason": {"type": "string", "enum": REASONS},
    },
    "required": ["expected_recovery", "reason"],
}


def ask_model(text):
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": RULES},
            {"role": "user", "content": f"Note: {text}\n/no_think"},
        ],
        "format": SCHEMA,
        "stream": False,
        "think": False,
        "options": {"temperature": 0, "seed": 42},
    }
    req = urllib.request.Request(
        OLLAMA_URL, data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        reply = json.loads(resp.read().decode("utf-8"))
    content = reply["message"]["content"]
    # Remove any <think>...</think> block, in case the model still reasons out loud.
    content = re.sub(r"(?s)<think>.*?</think>", "", content).strip()
    return content


def parse(content):
    try:
        data = json.loads(content)
        recovery = str(data.get("expected_recovery", "")).strip()
        reason = str(data.get("reason", "")).strip()
    except (json.JSONDecodeError, AttributeError):
        return "", "", False
    valid = bool(RECOVERY_OK.match(recovery)) and reason in REASONS
    return recovery, reason, valid


def main():
    if not INPUT_CSV.exists():
        sys.exit(f"Input file not found: {INPUT_CSV}. Run this from the project folder.")

    with INPUT_CSV.open(encoding="utf-8-sig", newline="") as f:
        rows = [r for r in csv.DictReader(f) if r.get("Text", "").strip()]
    print(f"{len(rows)} notes to process with {MODEL}")

    results = []
    for r in rows:
        start = time.time()
        content = ask_model(r["Text"])
        recovery, reason, valid = parse(content)
        if not valid:  # one retry, then keep whatever came back and flag it
            content = ask_model(r["Text"])
            recovery, reason, valid = parse(content)
        results.append({
            "ID": r["ID"],
            "Text": r["Text"],
            "AI: expected recovery": recovery,
            "AI: reason": reason,
            "Valid output": "Yes" if valid else "No",
            "Raw output": content,
        })
        print(f"ID {r['ID']:>2}: {recovery or '?':<15} | {reason or '?':<20} "
              f"| valid={valid} | {time.time() - start:.1f}s")

    with OUTPUT_CSV.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(results[0].keys()))
        writer.writeheader()
        writer.writerows(results)

    invalid = sum(1 for x in results if x["Valid output"] == "No")
    print(f"\nSaved {len(results)} rows to {OUTPUT_CSV} ({invalid} invalid outputs)")


if __name__ == "__main__":
    main()
