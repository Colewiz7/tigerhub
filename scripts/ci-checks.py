#!/usr/bin/env python3
"""Repo hygiene checks that need no Flutter and no Mac.

Run as `python3 -I scripts/ci-checks.py` from the repo root. Exits non-zero
with a list of problems. Prints paths only, never file contents, so a leaked
secret is not echoed into a CI log.
"""
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
problems = []


def tracked():
    out = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True
    ).stdout.decode()
    return [p for p in out.split("\0") if p]


files = tracked()

# 1. Signing material and credential files must never be tracked.
SECRET_NAME = re.compile(
    r"(\.(p8|p12|pem|cer|mobileprovision|keystore|jks)$|(^|/)key\.properties$"
    r"|(^|/)\.env(\..*)?$|codemagic_api)"
)
for f in files:
    if SECRET_NAME.search(f):
        problems.append(f"secret-looking file is tracked: {f}")

# 2. Secret-looking content in tracked text files (paths only in the report).
SECRET_BODY = re.compile(
    rb"(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
    rb"|AKIA[0-9A-Z]{16}"
    rb"|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"
)
for f in files:
    p = ROOT / f
    if p.suffix in {".png", ".ttf", ".otf", ".ico", ".jpg", ".jpeg", ".svg"}:
        continue
    try:
        data = p.read_bytes()
    except OSError:
        continue
    if SECRET_BODY.search(data):
        problems.append(f"secret-looking content in: {f}")

# 3. Info.plist and privacy manifest parse, and carry what App Review needs.
plist_path = ROOT / "client/ios/Runner/Info.plist"
manifest_path = ROOT / "client/ios/Runner/PrivacyInfo.xcprivacy"
try:
    info = plistlib.loads(plist_path.read_bytes())
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        problems.append("Info.plist: ITSAppUsesNonExemptEncryption must be false")
    if info.get("CFBundleDisplayName") != "TigerHub":
        problems.append("Info.plist: CFBundleDisplayName must be TigerHub")
    orient = info.get("UISupportedInterfaceOrientations", [])
    if orient != ["UIInterfaceOrientationPortrait"]:
        problems.append("Info.plist: iPhone must be portrait only")
    for key in ("NSAppTransportSecurity",):
        if key in info:
            problems.append(f"Info.plist: {key} present; no plain HTTP is allowed")
except Exception as exc:  # noqa: BLE001
    problems.append(f"Info.plist does not parse: {type(exc).__name__}")
try:
    manifest = plistlib.loads(manifest_path.read_bytes())
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("PrivacyInfo.xcprivacy: NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyCollectedDataTypes"):
        problems.append(
            "PrivacyInfo.xcprivacy: collected data types declared; the label is "
            "Data Not Collected"
        )
except Exception as exc:  # noqa: BLE001
    problems.append(f"PrivacyInfo.xcprivacy does not parse: {type(exc).__name__}")

# 4. No plain-HTTP endpoints in app code or config (ATS would block them).
HTTP = re.compile(r"""['"]http://(?!127\.0\.0\.1|localhost)""")
for f in files:
    if f.startswith("client/lib/") and f.endswith(".dart") or f.startswith(
        "client/assets/config/"
    ):
        text = (ROOT / f).read_text(errors="ignore")
        if HTTP.search(text):
            problems.append(f"plain http:// endpoint in: {f}")

# 5. Every bundled config keeps its last_verified date.
for f in files:
    if f.startswith("client/assets/config/") and f.endswith(".json"):
        if "last_verified" not in (ROOT / f).read_text():
            problems.append(f"missing last_verified: {f}")

# 6. Codemagic yaml must not inline secrets.
cm = (ROOT / "codemagic.yaml").read_text()
if re.search(r"(?im)^\s*[A-Z_]*(TOKEN|SECRET|PASSWORD|PRIVATE_KEY)[A-Z_]*\s*:\s*\S", cm):
    problems.append("codemagic.yaml: a secret-named variable has an inline value")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print("repo checks passed")
