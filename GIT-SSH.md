# GIT-SSH.md — Deterministic GitHub identity routing (work machine)

**Audience:** a Claude Code session running on Jay's **work machine**.
**Goal:** git on this machine always authenticates as the right GitHub account
based on **which folder the repo lives in** — never on `gh auth switch`, which
is machine-wide mutable state that concurrent sessions race over (this broke a
live session on 2026-07-22: pull failed, push failed, account flipped between
commands).

**The rule being installed:**

| Repo location | GitHub identity | SSH key (lives in 1Password) |
|---|---|---|
| `~/Code/corporate/**` | `jheavner` (CTA) | new key in the **CTA** account's vault |
| everywhere else | `jayheavner` (personal) | existing **GitHub-Personal** key, "heavners" account, Private vault |
| exception: the AI-EA repo (personal repo in a corporate path) | `jayheavner` | pinned repo-locally (repo config outranks the folder rule) |

Private keys never touch disk — the 1Password SSH agent signs everything. Only
**public** keys are written to `~/.ssh/`.

Execute the phases in order. Every phase is idempotent — safe to re-run. If a
check fails, stop and report; do not improvise around it.

---

## Phase 0 — Preconditions

1. `op account list` must show **both** accounts: the personal "heavners"
   account and the CTA account. If either is missing, STOP — Jay must sign it
   in to the 1Password app first.
2. The 1Password SSH agent must be enabled (1Password app → Settings →
   Developer → "Use the SSH agent"). Verify the socket exists:

   ```bash
   ls "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
   ```

   If missing, STOP and ask Jay to enable the agent in the app.
3. Confirm the personal key is served by the agent:

   ```bash
   SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ssh-add -l
   ```

   Expect a line ending `i/Cwa6wqMHtSCF6wiKaFeOjQSUYgKESkP8IUIt6ON8M` (the
   GitHub-Personal key). If absent, STOP — the Private vault isn't being
   served on this machine.

## Phase 1 — Create + register the CTA work key (currently missing)

Verified 2026-07-22: `https://github.com/jheavner.keys` is **empty** — the
work account has no SSH key. Create it in the **CTA** 1Password account so
both machines that sign into CTA get it automatically.

1. Find the CTA account shorthand and its default vault:

   ```bash
   op account list
   op vault list --account <cta-shorthand>
   ```

   Use the account's own default vault (usually `Employee` or `Private`) —
   the agent serves default vaults without extra config.
2. Generate the key inside 1Password (no private key on disk). Check
   `op item create --help` for the SSH key generation flag on the installed
   CLI version; current syntax:

   ```bash
   op item create --account <cta-shorthand> --vault <vault> \
     --category "SSH Key" --title "GitHub-CTA" \
     --ssh-generate-key ed25519
   ```

   If the installed `op` doesn't support key generation, STOP and ask Jay to
   create it in the 1Password app (New Item → SSH Key → Generate), then
   continue.
3. Export the **public** key to disk:

   ```bash
   op item get "GitHub-CTA" --account <cta-shorthand> --fields label="public key" \
     | tr -d '"' > ~/.ssh/jheavner-cta.pub
   chmod 644 ~/.ssh/jheavner-cta.pub
   ```
4. Register it with the `jheavner` GitHub account:

   ```bash
   gh auth switch --user jheavner
   gh auth refresh -h github.com -s admin:public_key   # only if the next step fails on scopes
   gh ssh-key add ~/.ssh/jheavner-cta.pub --title "1Password CTA (work machine)"
   ```
5. **Human step — surface this to Jay, do not skip:** if the CTA org enforces
   SAML SSO, the new key must be authorized: GitHub → Settings → SSH and GPG
   keys → the new key → **Configure SSO → Authorize** for the CTA org. Until
   then, org repos will refuse the key even though it's registered.

## Phase 2 — Write the personal public key to disk

Already registered with GitHub and already in the agent; it just needs its
public half on disk for pinning (verified against both 1Password and
`github.com/jayheavner.keys` on 2026-07-22):

```bash
cat > ~/.ssh/jayheavner.pub <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEVdiVAki5J0+yOGee/O2eRFAVyFoNrwHXCaeo+5Y1C+
EOF
chmod 644 ~/.ssh/jayheavner.pub
```

## Phase 3 — Point SSH at the 1Password agent

Append a **marked managed block** to `~/.ssh/config` (create the file if
absent; if the block already exists, replace its contents; never touch
anything outside the markers):

```
# BEGIN agent-workforce GIT-SSH (managed — do not hand-edit inside markers)
Host github.com
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
# END agent-workforce GIT-SSH
```

Note: no `IdentityFile`/`IdentitiesOnly` here — key *selection* is done
per-directory by git (Phase 4), so it can differ by folder. This block only
routes github.com SSH through the 1Password agent.

## Phase 4 — Directory-based identity in git config

1. Write `~/.gitconfig-cta` (whole file, workforce-owned):

   ```ini
   # agent-workforce GIT-SSH: identity for repos under ~/Code/corporate/
   [core]
     sshCommand = ssh -i ~/.ssh/jheavner-cta.pub -o IdentitiesOnly=yes
   ```
2. In the **global** git config, set the personal identity as the default and
   the corporate override (idempotent `git config` writes, no file editing):

   ```bash
   git config --global core.sshCommand "ssh -i ~/.ssh/jayheavner.pub -o IdentitiesOnly=yes"
   git config --global includeIf."gitdir:~/Code/corporate/".path "~/.gitconfig-cta"
   ```

   (`gitdir:~/Code/corporate/` matches every repo anywhere under that tree.)
3. Before setting the global `core.sshCommand`, check whether one already
   exists (`git config --global core.sshCommand`). If a different value is
   present, STOP and show Jay both values — do not overwrite silently.

## Phase 5 — Convert remotes from HTTPS to SSH

SSH identity routing only applies to SSH remotes. Convert:

1. **The AI-EA repo** (`~/Code/corporate/python/Lambda/email_webhook_handler`)
   — personal repo in a corporate path, so it also gets the repo-local pin
   that outranks the folder rule:

   ```bash
   cd ~/Code/corporate/python/Lambda/email_webhook_handler
   git remote set-url origin git@github.com:jayheavner/AI-EA.git
   git config core.sshCommand "ssh -i ~/.ssh/jayheavner.pub -o IdentitiesOnly=yes"
   ```
2. **Every other GitHub repo on the machine:** enumerate and convert any
   `https://github.com/...` remotes:

   ```bash
   find ~/Code -maxdepth 4 -name .git -type d 2>/dev/null | while read -r g; do
     r=$(git -C "${g%/.git}" remote get-url origin 2>/dev/null)
     case "$r" in https://github.com/*) echo "${g%/.git}  $r";; esac
   done
   ```

   For each hit, `git remote set-url origin git@github.com:<owner>/<repo>.git`.
   List what was converted in the final report. Repos outside `~/Code` are out
   of scope — mention any you know of, don't hunt.

## Phase 6 — Verify (all four must pass)

```bash
AGENT_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# 1. Personal identity answers as jayheavner:
SSH_AUTH_SOCK="$AGENT_SOCK" ssh -T -i ~/.ssh/jayheavner.pub -o IdentitiesOnly=yes git@github.com
# expect: "Hi jayheavner! You've successfully authenticated..."

# 2. Work identity answers as jheavner:
SSH_AUTH_SOCK="$AGENT_SOCK" ssh -T -i ~/.ssh/jheavner-cta.pub -o IdentitiesOnly=yes git@github.com
# expect: "Hi jheavner! ..."

# 3. The AI-EA repo reaches its remote with NO gh involvement:
git -C ~/Code/corporate/python/Lambda/email_webhook_handler ls-remote origin HEAD

# 4. The race is actually dead — flip gh to the WRONG account and repeat:
gh auth switch --user jheavner
git -C ~/Code/corporate/python/Lambda/email_webhook_handler ls-remote origin HEAD
# must still succeed; then switch gh back to whatever it was.
```

Check 4 is the point of the whole exercise: git must no longer care what gh's
active account is. If any check fails, report exactly which and stop.

## Final report

State plainly: keys created/registered (and whether the SSO authorization
human step is still pending), files written (`~/.ssh/*.pub`, ssh config block,
gitconfig entries), remotes converted, and the four verification results.
`gh` remains installed and useful for API work (PRs, issues) — it is simply no
longer in the git transport path.
