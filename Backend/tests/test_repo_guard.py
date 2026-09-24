"""Block 3 -- the repository security guard passes on this repo and demonstrably FAILS on violations."""

import importlib.util
import pathlib
import subprocess

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("repo_guard", REPO / "tools/security/repo_guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def test_repository_is_clean():
    assert guard.check(REPO) == []


def make_repo(tmp_path, files):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    for name, content in files.items():
        p = tmp_path / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    subprocess.run(["git", "add", "-A"], cwd=tmp_path, check=True)
    return tmp_path


GOOD_MANIFEST = '<application android:allowBackup="false" android:usesCleartextTraffic="false"><activity android:name=".MainActivity" android:exported="true"/></application>'
GRADLE_OK = '// SETU RELEASE BUILD REFUSED\nsigningConfig = signingConfigs.findByName("release")\n'


@pytest.mark.parametrize("name,content,rule", [
    ("Backend/.env", "X=1", "R1-forbidden-file"),
    ("android/app/release.jks", "x", "R1-forbidden-file"),
    ("keys/server.pem", "x", "R1-forbidden-file"),
    ("Backend/app/x.py", 'API_KEY = "abcdefghijklmnopqrstuvwx"', "R2-secret-literal"),
    ("Backend/app/y.py", "k = '" + "AKIA" + "ABCDEFGHIJKLMNOP" + "'", "R2-secret-literal"),
    ("Backend/app/z.py", "-----BEGIN " + "PRIVATE KEY-----", "R2-secret-literal"),
    ("setu_dashboard/src/a.js", "const k = import.meta.env.VITE_API_KEY;", "R3-dashboard-secret-var"),
    ("Backend/app/main.py", 'app.add_middleware(CORSMiddleware, allow_origins=["*"])', "R6-permissive-cors"),
    ("Backend/app/main.py", "allow_credentials=True", "R6-permissive-cors"),
    ("setu_app/lib/x.dart", "developer.log('sent to $phoneNumber');", "R7-sensitive-log"),
    ("setu_app/lib/x.dart", "print('body: ${sos.message}');\n", "R7-sensitive-log"),
    ("setu_app/lib/x.dart", "debugPrint('seed=$seed');", "R7-sensitive-log"),
])
def test_guard_detects_violation(tmp_path, name, content, rule):
    repo = make_repo(tmp_path, {name: content})
    findings = guard.check(repo)
    assert any(f.startswith(rule) for f in findings), findings
    assert not any(content[:12] in f for f in findings)  # findings never echo the matched text


def test_guard_detects_manifest_and_signing_regressions(tmp_path):
    base = "setu_app/android/app/src/main/AndroidManifest.xml"
    gradle = "setu_app/android/app/build.gradle.kts"
    (tmp_path / "ok").mkdir()
    ok = make_repo(tmp_path / "ok", {base: GOOD_MANIFEST, gradle: GRADLE_OK})
    assert guard.check(ok) == []
    bad_dir = tmp_path / "bad"
    bad_dir.mkdir()
    bad = make_repo(bad_dir, {
        base: '<application android:allowBackup="true"><service android:name=".Evil" android:exported="true"/></application>',
        gradle: 'signingConfig = signingConfigs.getByName("debug")\n',
    })
    rules = {f.split()[0].split("(")[0] for f in guard.check(bad)}
    assert {"R4-allowBackup-not-false", "R4-cleartext-not-disabled", "R4-unexpected-exported-component",
            "R5-debug-signing-reference", "R5-release-guard-missing"} <= rules


def test_examples_and_docs_may_contain_placeholders(tmp_path):
    repo = make_repo(tmp_path, {"Backend/.env.example": "API_KEY=", "docs/x.md": 'password = "not-a-real-secret-12345"'})
    assert guard.check(repo) == []
