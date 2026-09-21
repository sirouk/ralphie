#!/usr/bin/env python3
"""One paid, bounded adapter smoke test; never runs against the user's project."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent
script = ROOT / "final-candidate" / "ralphie.sh"
product_hash = hashlib.sha256(script.read_bytes()).hexdigest()
project = ROOT / "prime fixture"
project.mkdir()
(project / "calc.sh").write_text('#!/bin/bash\nprintf "%s\\n" "$(($1 - $2))"\n')
(project / "verify.sh").write_text('''#!/bin/bash
set -eu
test "$(bash calc.sh 2 3)" = 5
test "$(bash calc.sh -8 3)" = -5
test "$(bash calc.sh 0 0)" = 0
test "$(bash calc.sh 12345 6789)" = 19134
''')
test_hash = hashlib.sha256((project / "verify.sh").read_bytes()).hexdigest()
def git(*args):
    return subprocess.check_output(["git", "-C", str(project), *args], text=True).strip()
git("init", "-q", "-b", "master")
git("config", "user.name", "Ralphie integration test")
git("config", "user.email", "ralphie-test@example.invalid")
git("add", "calc.sh", "verify.sh")
git("commit", "-qm", "broken arithmetic fixture")
before = git("rev-parse", "HEAD")
assert subprocess.run(["/bin/bash", "verify.sh"], cwd=project).returncode != 0
env = {k: v for k, v in os.environ.items() if not k.startswith("RALPHIE_")}
env.update(ENGINE_RETRIES="1", ENGINE_TIMEOUT="120", ENGINE_MAX_TURNS="12",
           ENGINE_MAX_CONT="2", ENGINE_MAX_TOKENS="65536", GATE_TIMEOUT="10",
           PATH="/bin:/usr/bin:" + env["PATH"])
command = ["/bin/bash", str(script), "--project", str(project), "run", "--once",
           "--no-update", "--gate", "bash verify.sh", "--accept", "bash verify.sh",
           "Fix calc.sh so verify.sh passes for all cases. Change calc.sh only; "
           "keep verify.sh byte-for-byte unchanged. Do not create other files. "
           "Run bash verify.sh to verify the repair."]
started = time.time()
with (ROOT / "receipts" / "prime-live.log").open("w") as log:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                            stderr=subprocess.STDOUT, timeout=210)
status_run = subprocess.run(["/bin/bash", str(script), "--project", str(project), "status", "--json"],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=15)
(ROOT / "receipts" / "prime-status.json").write_text(status_run.stdout)
status = json.loads(status_run.stdout)
checks = {
    "ralphie_exit_zero": result.returncode == 0,
    "prime_selected_by_default": status["engine"] == "prime-agent",
    "independent_health_pass": subprocess.run(["/bin/bash", "verify.sh"], cwd=project).returncode == 0,
    "acceptance_done": status["status"] == "done",
    "check_file_unchanged": hashlib.sha256((project / "verify.sh").read_bytes()).hexdigest() == test_hash,
    "only_calc_changed": git("diff", "--name-only", before, "HEAD") == "calc.sh",
    "commit_saved": before != git("rev-parse", "HEAD"),
    "worktree_clean": not git("status", "--porcelain"),
    "lock_released": not (project / ".ralphie" / "lock").exists(),
    "script_unchanged": hashlib.sha256(script.read_bytes()).hexdigest() == product_hash,
}
receipt = {"exit": result.returncode, "elapsed_seconds": round(time.time() - started, 3),
           "product_sha256": product_hash, "prime_version": subprocess.check_output(
               ["prime-agent", "--version"], env=env, text=True, timeout=20).strip(),
           "fixture": str(project), "before": before, "after": git("rev-parse", "HEAD"),
           "checks": checks, "status": status}
(ROOT / "receipts" / "prime-result.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
raise SystemExit(0 if all(checks.values()) else 1)
