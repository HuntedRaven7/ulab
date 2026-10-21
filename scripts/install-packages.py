#!/usr/bin/env python3
"""Install the ulab package manifest into a buildroot.

Usage: install-packages.py MANIFEST.toml [MANIFEST.toml ...]

Every manifest may carry any of the package sections below; names are
merged in file order and resolved in ONE dnf transaction, the same shape
utah uses (utah-install-packages) so a package can never be broken by a
later transaction. [excluded] is a second transaction, running immediately
after the installs inside the same RUN step the caller provides.

A manifest declaring an `[updex]` table is treated as the pinned
external-artifact manifest: its RPM installs with all repositories
disabled, because its dependencies resolve from the base image alone.

Fedora 44 repos are used during the transaction (utah keeps them
`builder-only: true`, packages/fedora-44.repo) and the repo file plus the
Fedora GPG key are deleted afterwards: the runtime image carries only the
Hummingbird repo.
"""

import hashlib
import subprocess
import sys
import tomllib
from pathlib import Path

# File order governs resolution order per section.
SECTIONS = ["core", "tooling", "networking", "hardware"]


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def load_tables(path: Path) -> dict:
    with path.open("rb") as fh:
        return tomllib.load(fh)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2

    manifests = [Path(a) for a in argv[1:]]
    package_lists: dict[str, list[str]] = {section: [] for section in SECTIONS}
    excluded: list[str] = []
    updex_conf: dict | None = None

    seen: set[str] = set()
    for manifest in manifests:
        tables = load_tables(manifest)
        for section in SECTIONS:
            for name in tables.get(section, {}).get("packages", []):
                if name not in seen:
                    seen.add(name)
                    package_lists[section].append(name)
        for name in tables.get("excluded", {}).get("packages", []):
            if name not in excluded:
                excluded.append(name)
        if "updex" in tables:
            updex_conf = tables["updex"]

    installs = [n for section in SECTIONS for n in package_lists[section]]
    if installs:
        run(["dnf", "-y", "install", *installs])
    if excluded:
        # Only remove what the base actually installed: hummingbird's
        # minimal tree may never have shipped these, and a dnf transaction
        # must not fail on an already-absent name (utah's path had the
        # richer bluefin base where every [excluded] name resolves).
        present = (
            subprocess.run(
                ["rpm", "-q", "--qf", "%{NAME}\n", *excluded],
                capture_output=True,
                text=True,
            )
            .stdout.splitlines()
        )
        to_remove = [name for name in excluded if name in present]
        if to_remove:
            run(["dnf", "-y", "remove", *to_remove])

    if updex_conf is not None:
        version = updex_conf["version"]
        arch = updex_conf["arch"]
        rpm_name = updex_conf["rpm"]
        expected = updex_conf["rpm_sha256"]
        url = (
            "https://github.com/frostyard/updex/releases/download/"
            f"v{version}/{rpm_name}"
        )
        print(f"+ verify pinned updex {version} {arch}", flush=True)
        cache = Path("/tmp/ulab-updex-rpm")
        cache.mkdir(parents=True, exist_ok=True)
        rpm_path = cache / rpm_name
        run(["curl", "-fSL", "--retry", "4", "-o", str(rpm_path), url])
        digest = hashlib.sha256(rpm_path.read_bytes()).hexdigest()
        if digest != expected:
            print(
                f"FATAL: updex RPM digest mismatch: got {digest}, want {expected}",
                file=sys.stderr,
            )
            return 1
        # Dependencies of the updex RPM must resolve inside the image:
        # nothing new is allowed from any repo in this step.
        run(["dnf", "--disablerepo=*", "-y", "install", str(rpm_path)])

    # Builder-only repo hygiene: the runtime image keeps hummingbird.repo
    # and its Red Hat key, and nothing else.
    for stale in [
        "/etc/yum.repos.d/fedora-44.repo",
        "/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary",
    ]:
        print("+ rm", stale, flush=True)
        Path(stale).unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
