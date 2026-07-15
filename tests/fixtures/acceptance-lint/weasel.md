# Plan snippet — unfalsifiable phrasing (advisory)

- [ ] AC-1 (mechanical): the parser handles malformed rows gracefully. Check: `python3 parse.py bad.csv; echo "exit=$?"` → expects exit=0 and a per-row error line.
