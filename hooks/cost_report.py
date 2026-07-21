#!/usr/bin/env python3
"""cost_report.py — price an entire session, exactly, from its transcripts.

Reads the main-session transcript AND every subagent transcript beside it,
dedups usage snapshots by message id, prices every logical request at list
rates from model-rates.json (standard or intro, by request date), and prints
one markdown cost report covering the WHOLE session — the orchestrator's own
usage included. There is no estimate path: a model with no rate is reported
as exact unpriced token counts, never multiplied by a guess.

Usage:
  cost_report.py --transcript <session.jsonl> [--rates <model-rates.json>]
                 [--format markdown|json] [--telemetry-dir <dir>]

Exit 0 with a report on stdout, even when nothing is priceable (the report
says so plainly). Exit 2 only on operator error (bad arguments, unreadable
rates file).
"""
import argparse
import datetime
import glob
import json
import os
import shlex
import sys
from collections import defaultdict

TOKEN_FIELDS = ("input", "output", "cw5m", "cw1h", "cread")
INTERPRETERS = {"python", "python3", "bash", "sh", "zsh", "node"}


def load_rates(path):
    with open(path) as f:
        doc = json.load(f)
    doc["models"]  # missing key -> KeyError -> operator error at the call site
    return doc


def rates_staleness_note(as_of, max_age_days=60):
    """A visible nudge when the rates file has not been re-verified lately."""
    try:
        age = (datetime.date.today() - datetime.date.fromisoformat(as_of)).days
    except (TypeError, ValueError):
        return None
    if age > max_age_days:
        return (f"NOTE: model-rates.json as_of {as_of} is {age} days old — "
                "re-verify list prices before trusting the dollar figures.")
    return None


def workforce_build():
    """Installed-build identity from the install manifest beside the hooks dir.

    Every debug log that carries a cost report then names the exact workforce
    version that produced it (the 2026-07-20 innovation-awards log could not
    be dated). Returns {"commit", "installed_at"} or None when no manifest —
    a repo-checkout run is not an install and gets no line."""
    manifest = os.environ.get(
        "AGENT_TEAM_MANIFEST",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                     "agent-team-manifest.json"))
    try:
        with open(manifest) as f:
            doc = json.load(f)
    except (OSError, ValueError):
        return None
    commit = doc.get("commit")
    if not isinstance(commit, str) or not commit:
        return None
    return {"commit": commit, "installed_at": doc.get("installed_at") or "unknown"}


def _hook_command_target(command):
    """(path, needs_exec_bit) for the script a hook command runs, or None.

    PATH-resolved commands (jq, git) and commands still carrying unexpanded
    variables are skipped — only a concrete path can be health-checked. A
    script run through an interpreter needs to exist but not be executable."""
    try:
        argv = shlex.split(os.path.expandvars(command))
    except ValueError:
        return None
    if not argv:
        return None
    head = os.path.expanduser(argv[0])
    if os.path.basename(head) in INTERPRETERS:
        for arg in argv[1:]:
            arg = os.path.expanduser(arg)
            if not arg.startswith("-") and "/" in arg:
                return (arg, False)
        return None
    if "/" in head:
        return (head, True)
    return None


def hook_health(profile_dir=None):
    """Warnings for hook infrastructure that exists but cannot run.

    The 2026-07-20 innovation-awards run spammed 'Permission denied' on every
    command from two hook scripts missing their exec bit, and neither human
    nor model was ever told the fix. Checks the active profile's settings
    hook commands plus every .sh in its hooks dir. Returns [] when healthy.
    Repair stays human on purpose: an agent must not modify its own gates."""
    profile_dir = profile_dir or os.environ.get(
        "AGENT_TEAM_PROFILE",
        os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
    warnings, seen = [], set()

    def check(path, needs_exec, origin):
        if "$" in path:
            return
        real = os.path.realpath(path)
        if real in seen:
            return
        seen.add(real)
        if not os.path.exists(path):
            warnings.append(
                f"WARNING: hook target missing: {path} ({origin}) — "
                "repair by hand; agents must not modify hook infrastructure.")
        elif needs_exec and not os.access(path, os.X_OK):
            warnings.append(
                f"WARNING: hook not executable: {path} ({origin}) — fix by "
                f"hand: chmod +x {path} — agents must not modify hook "
                "infrastructure.")

    for name in ("settings.json", "settings.local.json"):
        try:
            with open(os.path.join(profile_dir, name)) as f:
                doc = json.load(f)
        except (OSError, ValueError):
            continue
        events = doc.get("hooks") if isinstance(doc, dict) else None
        if not isinstance(events, dict):
            continue
        for event, entries in events.items():
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                for h in entry.get("hooks") or []:
                    cmd = h.get("command") if isinstance(h, dict) else None
                    if isinstance(cmd, str):
                        target = _hook_command_target(cmd)
                        if target:
                            check(target[0], target[1], f"{name}:{event}")

    hooks_dir = os.path.join(profile_dir, "hooks")
    try:
        entries = sorted(os.listdir(hooks_dir))
    except OSError:
        entries = []
    for fn in entries:
        path = os.path.join(hooks_dir, fn)
        if fn.endswith(".sh") and os.path.isfile(path):
            check(path, True, "hooks dir")
    return warnings


def canon_model(model_id, rate_keys):
    """Resolve a model id to its rates family: exact key or longest 'key-' prefix."""
    model_id = model_id.removesuffix("[1m]")
    best = None
    for k in rate_keys:
        if model_id == k or model_id.startswith(k + "-"):
            if best is None or len(k) > len(best):
                best = k
    return best or model_id


def parse_transcript(path, rate_keys):
    """Return list of logical requests: {model, ts, input, output, cw5m, cw1h, cread}.

    Dedup rule (same as the cost hook): group usage snapshots by message.id;
    input/cache are constant within a group, output takes the max.
    Unparseable lines are skipped — this reader is for reporting, and a torn
    tail line must not zero out an otherwise-priceable session.
    """
    groups = {}
    order = []
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return []
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except (ValueError, UnicodeDecodeError):
                continue
            if not isinstance(rec, dict) or rec.get("type") != "assistant":
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage")
            mid = msg.get("id")
            model = msg.get("model")
            if not usage or not isinstance(mid, str) or not isinstance(model, str):
                continue
            if model == "<synthetic>":
                continue
            cc = usage.get("cache_creation") or {}
            entry = {
                "model": canon_model(model, rate_keys),
                "ts": rec.get("timestamp") or "",
                "input": usage.get("input_tokens") or 0,
                "output": usage.get("output_tokens") or 0,
                "cw5m": cc.get("ephemeral_5m_input_tokens",
                               usage.get("cache_creation_input_tokens") or 0),
                "cw1h": cc.get("ephemeral_1h_input_tokens", 0),
                "cread": usage.get("cache_read_input_tokens") or 0,
                "web_search": (usage.get("server_tool_use") or {}).get("web_search_requests", 0) or 0,
                "web_fetch": (usage.get("server_tool_use") or {}).get("web_fetch_requests", 0) or 0,
            }
            if mid in groups:
                groups[mid]["output"] = max(groups[mid]["output"], entry["output"])
                groups[mid]["web_search"] = max(groups[mid]["web_search"], entry["web_search"])
                groups[mid]["web_fetch"] = max(groups[mid]["web_fetch"], entry["web_fetch"])
            else:
                groups[mid] = entry
                order.append(mid)
    return [groups[m] for m in order]


def price_request(req, rates):
    fam = rates.get(req["model"])
    if fam is None:
        return None
    r = fam
    intro = fam.get("intro")
    # An undated request cannot claim intro pricing; standard rates apply.
    if intro and req["ts"] and req["ts"][:10] <= intro["ends"]:
        r = intro
    return (req["input"] * r["input"] + req["output"] * r["output"]
            + req["cw5m"] * r["cache_write_5m"] + req["cw1h"] * r["cache_write_1h"]
            + req["cread"] * r["cache_read"]) / 1_000_000


def aggregate(requests, rates):
    """Return (per_model_priced, per_model_unpriced, total_cost, ws, wf)."""
    priced = defaultdict(lambda: dict.fromkeys(TOKEN_FIELDS, 0) | {"cost": 0.0})
    unpriced = defaultdict(lambda: dict.fromkeys(TOKEN_FIELDS, 0))
    total = 0.0
    ws = wf = 0
    for req in requests:
        cost = price_request(req, rates)
        bucket = priced[req["model"]] if cost is not None else unpriced[req["model"]]
        for f in TOKEN_FIELDS:
            bucket[f] += req[f]
        if cost is not None:
            bucket["cost"] += cost
            total += cost
        ws += req["web_search"]
        wf += req["web_fetch"]
    return dict(priced), dict(unpriced), total, ws, wf


def load_agent_types(cost_file):
    """Map subagent id -> agent_type from the session cost file, when present."""
    try:
        with open(cost_file) as f:
            doc = json.load(f)
        return {aid: d.get("agent_type", "unknown")
                for aid, d in (doc.get("dispatches") or {}).items()}
    except (OSError, ValueError):
        return {}


def count_dispatches(transcript):
    """Agent tool_use blocks in the main transcript — the ground truth for how
    many subagent transcripts SHOULD exist beside it."""
    n = 0
    try:
        f = open(transcript, encoding="utf-8", errors="replace")
    except OSError:
        return 0
    with f:
        for line in f:
            if '"Agent"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            content = ((rec or {}).get("message") or {}).get("content")
            if isinstance(content, list):
                n += sum(1 for b in content
                         if isinstance(b, dict) and b.get("type") == "tool_use"
                         and b.get("name") == "Agent")
    return n


def collect(transcript, rates):
    """Parse main + subagent transcripts. Returns (main_reqs, {agent_id: reqs})."""
    main_reqs = parse_transcript(transcript, rates.keys())
    sub_dir = transcript[:-len(".jsonl")] + "/subagents" if transcript.endswith(".jsonl") else None
    subs = {}
    if sub_dir and os.path.isdir(sub_dir):
        for f in sorted(glob.glob(os.path.join(sub_dir, "agent-*.jsonl"))):
            aid = os.path.basename(f)[len("agent-"):-len(".jsonl")]
            subs[aid] = parse_transcript(f, rates.keys())
    return main_reqs, subs


def fmt_tokens(n):
    return f"{n:,}"


def markdown_report(main_reqs, subs, rates, agent_types, dispatches=0):
    all_reqs = list(main_reqs)
    for reqs in subs.values():
        all_reqs.extend(reqs)
    priced, unpriced, total, ws, wf = aggregate(all_reqs, rates)

    lines = ["## Cost report", ""]
    if not all_reqs:
        lines.append("No usage records found — nothing to price for this session.")
        return "\n".join(lines), total
    lines.append("| Model | Input | Output | Cache write | Cache read | Cost |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for model in sorted(priced):
        b = priced[model]
        lines.append(
            f"| {model} | {fmt_tokens(b['input'])} | {fmt_tokens(b['output'])} "
            f"| {fmt_tokens(b['cw5m'] + b['cw1h'])} | {fmt_tokens(b['cread'])} "
            f"| ${b['cost']:.2f} |")
    lines.append(f"| **Total** | | | | | **${total:.2f}** |")
    lines.append("")

    # Attribution: orchestrator session + each dispatch.
    _, _, main_cost, _, _ = aggregate(main_reqs, rates)
    lines.append("Per-agent attribution:")
    lines.append("")
    lines.append("| Agent | Requests | Cost |")
    lines.append("|---|---:|---:|")
    lines.append(f"| orchestrator (main session) | {len(main_reqs)} | ${main_cost:.2f} |")
    for aid, reqs in subs.items():
        _, _, c, _, _ = aggregate(reqs, rates)
        atype = agent_types.get(aid, "subagent")
        lines.append(f"| {atype} ({aid}) | {len(reqs)} | ${c:.2f} |")
    lines.append("")

    if unpriced:
        lines.append("Unpriced (exact token volumes, no rate in model-rates.json — "
                     "add the model there and re-run; never estimated):")
        for model in sorted(unpriced):
            b = unpriced[model]
            lines.append(f"- {model}: in {fmt_tokens(b['input'])}, out {fmt_tokens(b['output'])}, "
                         f"cache-write {fmt_tokens(b['cw5m'] + b['cw1h'])}, cache-read {fmt_tokens(b['cread'])}")
        lines.append("")
    if ws or wf:
        lines.append(f"Server tools (billed per use, counted not priced): "
                     f"web_search x{ws}, web_fetch x{wf}.")
        lines.append("")
    if dispatches > 0 and not subs:
        lines.append(
            f"WARNING: the transcript records {dispatches} Agent dispatch(es) "
            "but no subagent transcripts were found beside it — subagent usage "
            "is MISSING from this table (the transcript layout may have "
            "changed; totals above are an undercount).")
        lines.append("")
    lines.append("Exact per-request figures from session transcripts at list rates "
                 "(model-rates.json), main session included.")
    build = workforce_build()
    if build:
        lines.append("")
        lines.append(f"Workforce build {build['commit']} "
                     f"(installed {build['installed_at']}).")
    # Hook health rides in EVERY report so a broken gate cannot scroll away:
    # the Stop hook re-demands the report at each closeout, putting these
    # warnings at the bottom of the final message every time.
    try:
        health = hook_health()
    except Exception:
        health = []
    if health:
        lines.append("")
        lines.extend(health)
    return "\n".join(lines), total


def write_telemetry(tdir, session_id, cwd, subs, rates, agent_types):
    """One JSONL record per dispatch — mechanical facts only."""
    os.makedirs(tdir, exist_ok=True)
    slug = cwd.replace("/", "-")
    path = os.path.join(tdir, f"{slug}--{session_id}.jsonl")
    with open(path, "w") as f:
        for aid, reqs in subs.items():
            _, _, cost, _, _ = aggregate(reqs, rates)
            models = sorted({r["model"] for r in reqs})
            tokens = {tf: sum(r[tf] for r in reqs) for tf in TOKEN_FIELDS}
            f.write(json.dumps({
                "agent_id": aid,
                "role": agent_types.get(aid, "unknown"),
                "resolved_models": models,
                "requests": len(reqs),
                "tokens": tokens,
                "cost_usd": round(cost, 6),
                "session_id": session_id,
            }) + "\n")
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcript", default=None)
    ap.add_argument("--hook-health", action="store_true",
                    help="print hook health warnings for the active profile "
                         "and exit (silent when healthy)")
    ap.add_argument("--rates", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                    "model-rates.json"))
    ap.add_argument("--cost-file", default=None,
                    help="session cost file for agent-type attribution (optional)")
    ap.add_argument("--format", choices=("markdown", "json"), default="markdown")
    ap.add_argument("--telemetry-dir", default=None)
    ap.add_argument("--session-id", default="")
    ap.add_argument("--cwd", default="")
    args = ap.parse_args()

    if args.hook_health:
        for warning in hook_health():
            print(warning)
        return 0
    if not args.transcript:
        ap.error("--transcript is required unless --hook-health is given")

    rates_path = os.environ.get("AGENT_TEAM_RATES", args.rates)
    try:
        rates_doc = load_rates(rates_path)
    except (OSError, ValueError, KeyError) as e:
        print(f"cost_report: cannot read rates file {rates_path}: {e}", file=sys.stderr)
        return 2
    rates = rates_doc["models"]
    stale_note = rates_staleness_note(rates_doc.get("as_of"))

    main_reqs, subs = collect(args.transcript, rates)
    agent_types = load_agent_types(args.cost_file) if args.cost_file else {}
    dispatches = count_dispatches(args.transcript)

    if args.format == "json":
        all_reqs = list(main_reqs) + [r for reqs in subs.values() for r in reqs]
        priced, unpriced, total, ws, wf = aggregate(all_reqs, rates)
        print(json.dumps({"total_cost_usd": round(total, 6), "models": priced,
                          "unpriced_models": unpriced,
                          "web_search_requests": ws, "web_fetch_requests": wf,
                          "dispatches": dispatches,
                          "subagent_transcripts_found": len(subs),
                          "rates_as_of": rates_doc.get("as_of"),
                          "workforce_build": workforce_build(),
                          "hook_health": hook_health()}, default=int))
    else:
        report, _ = markdown_report(main_reqs, subs, rates, agent_types, dispatches)
        print(report)
        if stale_note:
            print("\n" + stale_note)

    if args.telemetry_dir and args.session_id:
        write_telemetry(args.telemetry_dir, args.session_id, args.cwd or os.getcwd(),
                        subs, rates, agent_types)
    return 0


if __name__ == "__main__":
    sys.exit(main())
