"""Check staged blobs for common credentials/private artifacts without printing values."""

import os
from pathlib import Path
import re
import subprocess
import sys

PATTERNS = {
    "credential-like value": rb"(?:xai-|sk-|ghp_|github_pat_)[A-Za-z0-9_\-]{20,}|AKIA[0-9A-Z]{16}",
    "private key": rb"-----BEGIN (?:(?:RSA|OPENSSH|EC|DSA|ENCRYPTED) )?PRIVATE KEY-----\r?\n|-----BEGIN PGP PRIVATE KEY BLOCK-----\r?\n|\bxprv[1-9A-HJ-NP-Za-km-z]{100,}",
    "absolute personal path": rb"/(?:Users|home|Volumes)/[^\x00\s\"<>]{3,}",
}
PRIVATE = {".db", ".jsonl", ".log", ".pem", ".key", ".p12", ".pfx", ".tpz"}
PRIVATE_NAMES = {
    "id_rsa",
    "id_ecdsa",
    "id_ed25519",
    "wallet.dat",
    "credentials.json",
    "mnemonic.txt",
    "mnemonics.txt",
    "seed.txt",
    "seed_phrase.txt",
    "recovery_phrase.txt",
}


def main():
    paths = subprocess.check_output(["git", "ls-files", "-z"]).split(b"\0")
    secrets = [
        value.encode()
        for key, value in os.environ.items()
        if re.search(r"(?:API_KEY|TOKEN|SECRET|PASSWORD)$", key) and len(value) >= 16
    ]
    failures = 0
    count = 0
    total = 0
    for encoded in filter(None, paths):
        name = os.fsdecode(encoded)
        path = Path(name)
        blob = subprocess.check_output(["git", "show", f":{name}"])
        count += 1
        total += len(blob)
        findings = []
        if (
            path.suffix in PRIVATE
            or path.name.lower() in PRIVATE_NAMES
            or path.name.startswith(".env")
            or any(
                part in {"dist", "build", "target", ".godot", ".codex", ".agents"}
                for part in path.parts
            )
        ):
            findings.append("private or generated artifact")
        if len(blob) >= 100 * 1024 * 1024:
            findings.append("exceeds GitHub file-size limit")
        for label, pattern in PATTERNS.items():
            if re.search(pattern, blob):
                findings.append(label)
        if any(secret in blob for secret in secrets):
            findings.append("matches an environment credential")
        if findings:
            failures += 1
            print(f"REVIEW {name}: {', '.join(findings)}")
    print(
        f"Checked {count} staged files ({total / 1024 / 1024:.1f} MiB); {failures} findings."
    )
    print("Pattern checks do not replace manual review or a full security audit.")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
