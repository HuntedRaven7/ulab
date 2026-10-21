# AGENTS.md

Rules for agents working in the ulab repository.

## What this repo is

ulab is a ucore-style server image built on Fedora Hummingbird
(`quay.io/hummingbird-community/os-minimal`, digest-pinned in
`Containerfile`). Its defining feature is that the Kubernetes payloads
(k3s, k0s, KubeStellar tooling) do NOT live in the image: they are
system extensions (`/usr`-only sysexts) streamed onto the node at runtime
with `updex` (frostyard/updex) from the repository's own catalog
(GitHub Pages, `https://huntedraven7.github.io/ulab/ext/<name>/`).

## Layout map

| Path | Purpose |
| --- | --- |
| `Containerfile` | The image. Builder stage pulls the package lists; runtime stage merges payloads. |
| `packages/` | Repo files and their GPG keys (fedora 44 is builder-only). |
| `config/packages.toml` | The package manifest (utah-style sections). |
| `config/updex.toml` | Pinned updex RPM + digest. |
| `scripts/install-packages.py` | Single dnf transaction + exclusion pass + pinned updex install. |
| `scripts/finalize.sh` | Runtime-stage housekeeping and build stamp. |
| `system_files/usr/` | Everything the image ships: sysupdate definitions, ujust tree, helpers, verifier. |
| `sysext/<name>/` | One directory per shipped sysext (env, payload, required paths, unit tree). |
| `sysext/common/` | Shared assembler + verified download helpers. |
| `.github/workflows/` | build-image, publish-sysexts, validate. |
| `tests/validate.sh` | Repo invariants (shellcheck, manifest parse, catalog naming). |
| `keys/` | Catalog verification keyring (armored public key only). |

## Invariants (do not break any of these)

1. **Digest-pinned base.** The `BASE_IMAGE` argument cites an exact
   digest. Never relax it to a tag.
2. **Builder-only Fedora.** `packages/fedora-44.repo` is enabled only
   during the package transaction. Runtime images carry only
   `hummingbird.repo` (taken from utah's policy, `builder-only: true`).
   If a package needs Fedora 44 at *runtime*, that is a design smell:
   instead, add the package to a sysext or to `config/packages.toml`.
3. **One dnf transaction.** Package installs resolve at once in
   `install-packages.py`; append to `config/packages.toml` and let the
   transaction stay single.
4. **Sysexts are /usr-only.** Payload touching `/etc`, `/var`, or `/opt`
   is rejected: systemd-sysext does not merge them. `/etc`-needing state
   goes through factory conventions in the *host image* (tmpfiles.d in
   `system_files/usr/lib/tmpfiles.d/`), or the sysext's own units write
   into `/etc`/`/var` only as runtime side effects.
5. **Verification everywhere.** Downloads in `sysext/*/payload.sh` go
   through `sysext/common/source/download.sh` (checksum-from-upstream;
   digest pin where a paid-for pin exists). `required-paths.txt` lists
   the load-bearing paths per sysext; the assembler fails the build on
   absence. The same posture as snosi (the incus regression taught them
   that; keep it).
6. **Trust is a keyring, not a raw manifest.** The catalog publishes
   SHA256SUMS + SHA256SUMS.gpg per sysext, verified against the armored
   key in `keys/ulab-sysext-public-key.asc` baked into
   `/usr/lib/systemd/import-pubring.gpg` at image build. Don't flip
   `Verify=false` in a transfer file except in a branch's test fixture.
7. **Feature names = component names.** One `sysupdate.<name>.d/`
   directory per sysext whose name equals the `ULAB_SYSEXT_NAME` and the
   dir under `sysext/`. Updating a sysext means coordinated files:
   `sysext/<name>/`, `system_files/usr/lib/sysupdate.<name>.d/`,
   and the catalog naming scheme in `.github/workflows/publish-sysexts.yml`.
8. **ext release metadata stays universal.** Every built sysext uses
   `ID=_any`/`VERSION_ID=_any`/`ARCHITECTURE=x86-64` (systemd naming),
   with the one-extension-release escape xattr
   `user.extension-release.strict=0`. Version in the file name sits in
   the `@v` slot of the `.transfer` MatchPattern; the pattern must expand
   exactly the artifact naming
   `<name>_<version>_<arch>.raw(.zst)` the assembler reports.

## Style

* Bash, everywhere, no `set -x` left in shipped scripts; `shellcheck`
  clean (tests/validate.sh enforces).
* Python is `python3`-only stdlib (tomllib), like `scripts/install-packages.py`.
* Comments explain *why* (they mirror utah's packages/*.toml comment
  culture: every non-obvious package or exclusion cites its reason).

## Before opening a PR

`./tests/validate.sh` must pass without shellcheck complaints and tomllib
errors. For sysext changes, build the touched sysext locally
(`just build-sysext k3s` etc.) and, when the payload's unit layouts
changed, mention in the PR body HOW it was exercised (unit verify or the
host merge path).
