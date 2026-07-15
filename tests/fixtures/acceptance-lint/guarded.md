# Plan snippet — the same checks with failure-output branches (must NOT be flagged)

- [ ] AC-1 (mechanical): default key present in loader. Check: `grep -q DEFAULT config.py || echo "why: DEFAULT missing from config.py"` → expects silence on pass, the reason on fail.
- [ ] AC-2 (mechanical): output matches the golden file. Check: `diff -q out.txt golden.txt || echo "why: output diverges from golden"` → expects silence on pass, the reason on fail.
- [ ] AC-3 (mechanical): release artifact produced. Check: `test -f dist/app.tgz || echo "why: dist/app.tgz was not built"` → expects silence on pass, the reason on fail.
