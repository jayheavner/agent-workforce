# Plan snippet — silent checks

- [ ] AC-1 (mechanical): default key present in loader. Check: `grep -q DEFAULT config.py` → expects a match.
- [ ] AC-2 (mechanical): output matches the golden file. Check: `diff -q out.txt golden.txt` → expects no difference.
- [ ] AC-3 (mechanical): release artifact produced. Check: `test -f dist/app.tgz` → expects the file present.
