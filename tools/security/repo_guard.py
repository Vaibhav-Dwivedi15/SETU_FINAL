#!/usr/bin/env python3
"""
Repository security guard (Block 3). Run in CI and by tests; exits non-zero on any finding.
Findings print FILE:LINE and a rule id only -- never the matched text, so a real secret is not
copied into CI logs.

Rules
  R1  forbidden files tracked (.env, keystores, private keys, key.properties, google-services.json)
  R2  secret-shaped literals in tracked text files
  R3  dashboard: no secret-looking VITE_ variable read in src/ or set in .env.example
  R4  Android manifest: allowBackup=false, cleartext off, only MainActivity exported
  R5  Android release signing has no debug-key fallback
  R6  backend: no wildcard CORS / credentialed wildcard
  R7  mobile logging: no phone numbers, SMS/message bodies, medical data, keys or signatures in logs
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

FORBIDDEN_NAME = re.compile(
    r"(^|/)(\.env|\.env\.[^/]*(?<!\.example)|key\.properties|google-services\.json|id_rsa|id_ed25519)$"
    r"|\.(jks|keystore|pem|p12|pfx)$"
)
SECRET_PATTERNS = [
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("google-api-key", re.compile(r"AIza[0-9A-Za-z_\-]{30,}")),
    ("github-token", re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}")),
    ("slack-token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("openai-style-key", re.compile(r"\bsk-[A-Za-z0-9]{32,}")),
    ("private-key-block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_\-]{15,}\.eyJ[A-Za-z0-9_\-]{15,}\.[A-Za-z0-9_\-]{10,}")),
    ("assigned-secret", re.compile(r"""(?i)\b(password|passwd|secret|api[_-]?key|access[_-]?token)\b\s*[:=]\s*["'][^"'\s]{12,}["']""")),
]
TEXT_SUFFIXES = {".py", ".dart", ".kt", ".kts", ".java", ".js", ".jsx", ".mjs", ".json", ".yml", ".yaml", ".xml",
                 ".properties", ".gradle", ".sh", ".env", ".toml", ".cfg", ".ini", ".txt", ".html"}
# tests, fixtures and docs may contain obviously-fake sample credentials
SECRET_SCAN_SKIP = re.compile(r"(^|/)(tests?|test|docs|node_modules|dist|build|\.dart_tool)/|package-lock\.json$|pubspec\.lock$|\.md$")
LOG_CALL = re.compile(r"(developer\.log|debugPrint|\bprint|\bLog\.[diwev]|\bprintln)\s*\(")
# Only INTERPOLATED sensitive values count (the word "signature" inside a message is fine; logging a
# signature VALUE, a phone number, a message body, medical data, a key/seed or a location is not).
SENSITIVE_INTERP = re.compile(
    r"(?i)\$\{?[\w.!?\[\]]*?\b(phone\w*|normalizedNumber|number|message|body|text|contacts?|emergencyContacts|medical\w*|"
    r"bloodGroup|privateKey|private_?key|seed|signature|signaturePayload|payload|jsonPayload|latitude|longitude|lat|lng)\b"
    r"|\.toJson\(\)|\.signature\b"
)


def tracked_files(root: Path):
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout
    return [f for f in out.splitlines() if (root / f).is_file()]


def lines(path: Path):
    try:
        return path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return []


def check(root: Path = ROOT, files=None):
    findings = []
    files = files if files is not None else tracked_files(root)
    add = lambda rule, f, n=0: findings.append(f"{rule} {f}:{n}")

    for f in files:
        if FORBIDDEN_NAME.search(f):
            add("R1-forbidden-file", f)
        p = root / f
        if p.suffix.lower() in TEXT_SUFFIXES and not SECRET_SCAN_SKIP.search(f) and not f.endswith(".example"):
            for n, line in enumerate(lines(p), 1):
                for name, rx in SECRET_PATTERNS:
                    if rx.search(line):
                        add(f"R2-secret-literal({name})", f, n)

    # R3 dashboard
    for f in (x for x in files if x.startswith("setu_dashboard/src/") and x.endswith((".js", ".jsx"))):
        for n, line in enumerate(lines(root / f), 1):
            if re.search(r"VITE_[A-Z_]*(API_KEY|SECRET|TOKEN|PASSWORD)", line):
                add("R3-dashboard-secret-var", f, n)
    ex = root / "setu_dashboard/.env.example"
    if ex.exists():
        for n, line in enumerate(lines(ex), 1):
            if not line.lstrip().startswith("#") and re.search(r"VITE_[A-Z_]*(API_KEY|SECRET|TOKEN|PASSWORD)\s*=", line):
                add("R3-dashboard-secret-var", "setu_dashboard/.env.example", n)

    # R4 manifest
    manifest = root / "setu_app/android/app/src/main/AndroidManifest.xml"
    if manifest.exists():
        text = manifest.read_text(encoding="utf-8")
        if 'android:allowBackup="false"' not in text:
            add("R4-allowBackup-not-false", "setu_app/android/app/src/main/AndroidManifest.xml")
        if 'android:usesCleartextTraffic="false"' not in text:
            add("R4-cleartext-not-disabled", "setu_app/android/app/src/main/AndroidManifest.xml")
        for m in re.finditer(r"<(activity|service|receiver|provider)\b[^>]*>", text):
            tag = m.group(0)
            if 'android:exported="true"' in tag and ".MainActivity" not in tag:
                add("R4-unexpected-exported-component", "setu_app/android/app/src/main/AndroidManifest.xml", text[:m.start()].count("\n") + 1)

    # R5 release signing
    gradle = root / "setu_app/android/app/build.gradle.kts"
    if gradle.exists():
        for n, line in enumerate(lines(gradle), 1):
            if re.search(r'signingConfigs\.getByName\("debug"\)|signingConfigs\["debug"\]', line) and not line.strip().startswith("//"):
                add("R5-debug-signing-reference", "setu_app/android/app/build.gradle.kts", n)
        if "SETU RELEASE BUILD REFUSED" not in gradle.read_text(encoding="utf-8"):
            add("R5-release-guard-missing", "setu_app/android/app/build.gradle.kts")

    # R6 backend CORS
    for f in (x for x in files if x.startswith("Backend/app/") and x.endswith(".py")):
        for n, line in enumerate(lines(root / f), 1):
            if line.strip().startswith("#"):
                continue
            if re.search(r"allow_origins\s*=\s*\[\s*[\"']\*[\"']\s*\]", line) or re.search(r"allow_credentials\s*=\s*True", line):
                add("R6-permissive-cors", f, n)

    # R7 mobile logging
    for f in (x for x in files if (x.startswith("setu_app/lib/") and x.endswith(".dart"))
              or (x.startswith("setu_app/android/app/src/main/") and x.endswith((".kt", ".java")))):
        src = lines(root / f)
        for n, line in enumerate(src, 1):
            if line.strip().startswith(("//", "*", "/*")) or not LOG_CALL.search(line):
                continue
            # a log call may span lines: look at it plus the next 3 lines up to its terminating ');'
            window = " ".join(src[n - 1:n + 3]).split(");")[0]
            window = re.sub(r"\$\{?(e|ex|err|error)\.message\}?", "", window)  # exception text, not user data
            if SENSITIVE_INTERP.search(window):
                add("R7-sensitive-log", f, n)
    return findings


def main() -> int:
    findings = check()
    for f in findings:
        print(f)
    print(f"repo_guard: {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
