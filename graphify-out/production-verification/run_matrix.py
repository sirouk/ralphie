#!/usr/bin/env python3
"""Run frozen candidate tests; Python is a proof tool, not a product dependency."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
lane = sys.argv[1]
source = ROOT / "final-candidate"
assert source.is_dir(), "freeze the final candidate first"
hashes = {name: hashlib.sha256((source / name).read_bytes()).hexdigest()
          for name in ("ralphie.sh", "test.sh")}
images = {
    "linux-tools": "sha256:d2c411a8c5530718ad1031eb76b244c86a641175deda06ac266c25f7f9063531",
    "linux-minimal": "sha256:ae84710b1265e61ebc9e486a5266f95b884c16cd2f26e0650234b2cc1e107d4a",
}
env = os.environ.copy()
if lane == "macos-bash32":
    work = ROOT / lane
    work.mkdir()
    for name in hashes:
        shutil.copy2(source / name, work / name)
    command = ["/bin/bash", "./test.sh"]
    env["PATH"] = "/bin:/usr/bin:" + env["PATH"]
else:
    script = '''set -eu
proof_dir=$(mktemp -d)
cp /source/ralphie.sh /source/test.sh "$proof_dir/"
cd "$proof_dir"
/bin/bash --version | head -1
id
for tool in python3 node jq curl wget timeout; do
    command -v "$tool" || :
done
sha256sum ralphie.sh test.sh
set +e
PATH="/bin:/usr/bin:$PATH" /bin/bash ./test.sh
result=$?
sha256sum ralphie.sh test.sh
exit "$result"
'''
    command = ["docker", "run", "--rm", "--network", "none", "--user", "65534:65534",
               "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
               "--mount", f"type=bind,source={source},target=/source,readonly",
               "--entrypoint", "/bin/bash", images[lane], "-c", script]
    work = ROOT
receipt = ROOT / "receipts" / f"{lane}.log"
start = time.time()
with receipt.open("w") as output:
    output.write(json.dumps({"lane": lane, "input_sha256": hashes}) + "\n")
    output.flush()
    result = subprocess.run(command, cwd=work, env=env, stdout=output,
                            stderr=subprocess.STDOUT, timeout=2400)
elapsed = round(time.time() - start, 3)
after = {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in hashes}
assert after == hashes, "frozen candidate changed during validation"
if lane == "macos-bash32":
    assert {name: hashlib.sha256((work / name).read_bytes()).hexdigest() for name in hashes} == hashes
summary = {"lane": lane, "exit": result.returncode, "elapsed_seconds": elapsed,
           "sha256": hashes, "log": str(receipt)}
(ROOT / "receipts" / f"{lane}.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary))
print("\n".join(receipt.read_text(errors="replace").splitlines()[-6:]))
raise SystemExit(result.returncode)
