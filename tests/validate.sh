#!/bin/bash
# Repo invariants, run locally and by the Validate workflow.
# Fails loudly; prints what failed.

set -euo pipefail

pass() { echo "ok: $*"; }

# --- shell scripts ---------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    # -x follows local source files; warnings-and-up gate on real defects,
    # info notes (SC1090 on dynamic payload sources) do not fail the gate.
    while IFS= read -r -d '' sh; do
        shellcheck -x --severity=warning "$sh"
        pass "shellcheck $sh"
    done < <(find . -name '*.sh' -type f -not -path './.git/*' -print0)
    for recipe in system_files/usr/share/ulab/recipes/*.just system_files/usr/share/ulab/justfile; do
        pass "$recipe exists" && grep -q . "$recipe"
    done
else
    echo "shellcheck missing -- install it (tests gate on it)" >&2
    exit 2
fi

# --- manifest shape --------------------------------------------------------
python3 - <<'EOF'
import tomllib, sys
from pathlib import Path

sections = ["core", "tooling", "networking", "hardware", "excluded"]
seen = set()
for path in [Path("config/packages.toml")]:
    data = tomllib.load(path.open("rb"))
    for section in sections:
        names = data.get(section, {}).get("packages", [])
        assert all(" " not in n for n in names), f"whitespace in {section}"
        seen.update(names)
    for name in data.get("excluded", {}).get("packages", []):
        pass  # exclusion of never-installed names is tolerated by design
print("ok: packages.toml parses; %d unique package names" % len(seen))

updex = tomllib.load(Path("config/updex.toml").open("rb"))["updex"]
assert len(updex["rpm_sha256"]) == 64, "updex sha256 not a full digest"
print("ok: updex.toml pins", updex["version"])
EOF

# --- catalog / builder naming agrees ---------------------------------------
for sysext in sysext/k3s sysext/k0s sysext/kubestellar; do
    name="$(basename "$sysext")"
    grep -q "ULAB_SYSEXT_NAME=$name" "$sysext/sysext.env" \
        || { echo "$sysext/sysext.env: missing/bogus ULAB_SYSEXT_NAME" >&2; exit 1; }
    test -s "$sysext/payload.sh" || { echo "$sysext: payload.sh missing" >&2; exit 1; }
    test -s "$sysext/required-paths.txt" || { echo "$sysext: required-paths.txt missing" >&2; exit 1; }
    pass "$sysext shape"
done

# --- containerfile references resolve --------------------------------------
for ref in packages/fedora-44.repo packages/hummingbird.repo packages/RPM-GPG-KEY-fedora-44-primary packages/RPM-GPG-KEY-redhat-release-2 config/packages.toml config/updex.toml keys/ulab-sysext-public-key.asc; do
    test -s "$ref" || { echo "Containerfile input missing: $ref" >&2; exit 1; }
done
pass "all Containerfile inputs present"

# The key is the trust root of the whole catalog; its format is checked,
# not its contents.
{ head -1 keys/ulab-sysext-public-key.asc | grep -q -- "-----BEGIN PGP PUBLIC KEY BLOCK-----"; } \
    || { echo "keys/ulab-sysext-public-key.asc is not armored OpenPGP" >&2; exit 1; }
pass "sysext public key is armored OpenPGP"

echo "all invariants hold"
