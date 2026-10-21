# ulab

A **ucore-style server image built on Fedora Hummingbird**, with
Kubernetes available as on-demand system extensions:

> `ujust k3s` · `ujust k0s` · `ujust kubestellar`

Like [utah](https://github.com/projectbluefin/utah) (from which the
Hummingbird handling here borrows heavily), the base is
`quay.io/hummingbird-community/os-minimal`, digest-pinned:

```
quay.io/hummingbird-community/os-minimal:latest@sha256:5ae51afb8a120e7e7c32a774be23b300dad3dd58ef51086de917e5eb66a91030
```

The base ships essentially nothing; ulab adds the pieces a server node
needs (SSH, tooling, the Hummingbird-networking firmware set from utah's
`[hardware]` list) and nothing else. The heavy payloads never touch the
image: they're **system extensions (`/usr`-only sysexts) downloaded at
runtime with [updex](https://github.com/frostyard/updex)** from this
repository's own catalog, and follow the schema published by
[frostyard/snosi](https://github.com/frostyard/snosi) (their k3s sysext
units are the design template for ulab's, adapted to a Fedora host).

## Design

```
   container image                    runtime
  ┌──────────────────────┐    ┌──────────────────────────────────┐
  │ hummingbird base     │    │ updex --enable k3s               │
  │ + server packages    │ ─► │  download → /var/lib/extensions.d│
  │ + updex CLI+t        │    │  link k3s.raw → staging artifact │
  │ + sysupdate.<n>.d/   │    │  systemd-sysext refresh (merged) │
  │   transfer + feature │    │  preset-driven unit activation   │
  │ + catalog keyring    │    └──────────────────────────────────┘
  └──────────────────────┘
```

* `.transfer` / `.feature` files for k3s, k0s, kubestellar ship inside
  the image in `usr/lib/sysupdate.<name>.d/` (Enabled=false by default;
  registry-verified by the baked keyring `import-pubring.gpg`).
* The catalog lives on GitHub Pages:
  `https://huntedraven7.github.io/ulab/ext/<name>/`, published by
  `.github/workflows/publish-sysexts.yml` with per-sysext
  `SHA256SUMS(.gpg)`.

## Recipes

| ujust | Effect |
| --- | --- |
| `ujust sysext-list` | updex feature table |
| `ujust sysext-status` | updex features + current merge state |
| `ujust sysext-enable <k3s\|k0s\|kubestellar>` | download + merge + activate |
| `ujust sysext-disable <feature>` [force] | unmerge + remove |
| `ujust sysext-update` [check] | newest version of every enabled feature |
| `ujust sysext-auto-update` enable\|disable | updex daemon timer toggle |
| `ujust k3s` | enable k3s as a standalone server |
| `ujust k3s <url>` / `ujust k3s-agent <url> <token>` | join an upstream server |
| `ujust k0s` | enable k0s as a controller |
| `ujust k0s-worker <url> <token>` | enable k0s as a worker node |
| `ujust kubestellar` | deploy the KubeStellar core chart onto a local cluster |
| `ujust kubestellar-off` | uninstall the chart |
| `ulab info` | fast status of everything |

## Build / publish (first time)

1. **Generate the catalog signing keypair** (this is the trust root of
   every sysext download):
   ```sh
   just keygen               # writes keys/ulab-sysext-public-key.asc
   git add keys/ulab-sysext-public-key.asc
   git commit -m "initial sysext verification key"
   ```
   Keep `ulab-gpg-private-key.asc` (written to the repo root) out of git:
   import it locally and store the armored text as the
   `ULAB_GPG_PRIVATE_KEY` **secret** in this repository.
2. **Turn on GitHub Pages** (Settings ▸ Pages ▸ Build and deployment ▸
   Source: GitHub Actions). The `publish-sysexts` workflow deploys the
   catalog on every change under `sysext/`.
3. **Build image** happens automatically on push to `main` and goes to
   `ghcr.io/huntedraven7/ulab:{latest,<version>}`.

### locally

```sh
just build-sysexts          # all three sysexts into sysext/dist/
just build-image            # podman build; needs the committed public key
./tests/validate.sh          # repo invariants
```

## How it works (details worth knowing)

### Packages and the builder-only rule

Everything appends to `config/packages.toml` (core/tooling/networking/
hardware/excluded) and resolves in **one dnf transaction** against:

* `packages/hummingbird.repo` — Red Hat's public Hummingbird buildroot
  (priority=10, `gpgcheck=1`, Red Hat release key 2 committed here) which
  **ships in the runtime image**;
* `packages/fedora-44.repo` — Fedora 44 Everything + updates, used only
  for the transaction (utah's `builder-only: true` policy; GPG: Fedora 44
  primary, also committed). It is deleted from the final image along
  with its key: the runtime keeps only the Hummingbird repo + Red Hat
  key, exactly what the Containerfile copies out of the builder stage.

The `[hardware]` list mirrors utah's thinking on firmware: the Hummingbird
base omits the linux-firmware blob entirely — a server image with Wi-Fi
hardware pulls the radio's firmware from `linux-firmware` and the four
iwlwifi slices (`dvm`, `mvm`, `mld`) that linux-firmware's own weak-deps
do not cover.

### Sysext schema

* `/usr`-only payload, `extension-release.d/extension-release.<name>`
  with `ID=_any`/`VERSION_ID=_any` + the strict=0 xattr escape, so one
  artifact merges regardless of the hummingbird base version.
* The image name inside the store is `<name>_<version>_<arch>.raw`
  (version in the `@v` slot of the `.transfer` MatchPattern); updex
  symlinks the newest into `/var/lib/extensions/<name>.raw`, the stable
  name systemd-sysext merges.
* systemd preset files in the *sysext* payload (`40-k3s.preset` and
  `40-k0s.preset`, `enable` both role units, whose `ConditionPathExists`
  decide which one runs: **controller/server by default, agent/worker as
  soon as `/etc/default/k3s-agent` or `/etc/default/k0s-worker` exists**
  — the snosi design lifted for the units themselves).
* updex is pinned by digest in `config/updex.toml` and installed at build
  with all repos disabled (its deps resolve from the base).

### KubeStellar shape

The `kubestellar` sysext ships **helm + control-plane binaries
(relocated into `/usr/lib/kubestellar/bin`, prefixed symlinks in
`/usr/bin`)** — not a running control plane. `ujust kubestellar` runs:

```
helm upgrade --install ks-core oci://ghcr.io/kubestellar/kubestellar/core-chart \
    --version 0.30.0  --set-json ITSes='[{"name":"its1"}]' \
                      --set-json WDSes='[{"name":"wds1"}]'
```

against a local k3s or k0s hosting cluster (`ujust k3s`/`ujust k0s`
first). Chart URI/version and ITS/WDS defaults live in
`/usr/share/ulab/kubestellar.env`, site-overridable via
`/etc/kubestellar/env`. See kubestellar.io's core-helm-chart docs for the
ingress (SSL passthrough, host port 9443) and dns domain knobs when
clusters grow beyond one machine.

## Known gaps (v0 scaffold)

* **No hardware validation** — like utah, everything here boots to
  build-verified state only; hosting-cluster layout and Wi-Fi members
  need real machines before this image is useful on hardware you keep.
* **No ISO installer** yet: rebase into an existing bootc-compatible
  system or `bootc bootc-image install` manually; an Anaconda-tracking
  bootc install flow is on the roadmap.
* **SELinux on merged sysexts** unverified: squashfs content carries no
  SELinux labels; on enforcing hosts, either run lab tests or set
  `--mutable=`; extending `mksquashfs` to label files is on the roadmap.
* **updex auto-update daemon** is opt-in (`ujust sysext-auto-update
  enable`), matching snosi's "natural reboot window" philosophy; bootc OS
  updates are left untouched (hummingbird's native machinery runs).
* Only x86-64; aarch64 is a CI-matrix extension away (all three payload
  binaries exist for arm64).

## License

Apache-2.0, like utah.
