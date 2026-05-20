#!/usr/bin/env python3
# espalier/hooks/parse-drift-blocks.py
# Invoked by the orchestrator at Stage 4:
#   python3 espalier/hooks/parse-drift-blocks.py <review-record.md>
# Emits one tab-separated line per "## Convention Drift" block found:
#   DRIFT\t<rule_file>\t<coupled_with>
#   MALFORMED\t<reason>
# A well-formed block has exactly one "- Rule file:" line; zero or 2+ is
# malformed (the reviewer bundled unrelated drifts into one block).
import sys, re

review_md = open(sys.argv[1]).read()
blocks = re.split(r'^## Convention Drift\s*$', review_md, flags=re.M)[1:]

for raw in blocks:
    body = re.split(r'^## ', raw, flags=re.M)[0]          # stop at next heading
    fields = {}
    for k, v in re.findall(r'^- ([\w ]+?):\s*(.+)$', body, flags=re.M):
        fields[k.strip().lower().replace(' ', '_')] = v.strip()
    rule_files = re.findall(r'^- Rule file:\s*(.+)$', body, flags=re.M)
    if len(rule_files) != 1:
        print(f"MALFORMED\t{len(rule_files)} rule files in one block")
        continue
    print(f"DRIFT\t{rule_files[0].strip()}\t{fields.get('coupled_with', '')}")
