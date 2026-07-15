# Plan snippet — well-formed criteria (zero findings expected)

- [ ] AC-1 (mechanical): the converter emits a JSON array. Check: `python3 csv2json.py in.csv | head -c 1` → expects the first byte to be "[".
- [ ] AC-2 (judgment): the README quickstart is followable by a newcomer. Judge: human. Bar: any step that depends on unstated context is a fail.
