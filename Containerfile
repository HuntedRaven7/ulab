ARG BASE_IMAGE=quay.io/hummingbird-community/os-minimal:latest@sha256:5ae51afb8a120e7e7c32a774be23b300dad3dd58ef51086de917e5eb66a91030

# ---------------------------------------------------------------------------
# Builder-only repository + package transaction stage.
#
# Packages that the Hummingbird buildroot does not publish (just,
# linux-firmware, the iwlwifi firmware family, microcode) resolve from the
# Fedora 44 Everything/updates repos here, whose repo file is committed
# with `builder-only: true` (packages/fedora-44.repo). The pinned updex RPM
# installs into the same transaction with all repositories disabled: it
# satisfies its dependencies from the base image alone.
#
# The runtime image copies this stage's installed payload, never its
# fedora-44.repo entries or the Fedora GPG key.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS packages-builder
COPY packages/fedora-44.repo packages/hummingbird.repo /etc/yum.repos.d/
COPY packages/RPM-GPG-KEY-fedora-44-primary packages/RPM-GPG-KEY-redhat-release-2 /etc/pki/rpm-gpg/
COPY config/packages.toml config/updex.toml /tmp/ulab-config/
COPY scripts/install-packages.py /tmp/ulab-scripts/
RUN /tmp/ulab-scripts/install-packages.py /tmp/ulab-config/packages.toml /tmp/ulab-config/updex.toml

# ---------------------------------------------------------------------------
# Import the sysext verification keyring from the ASCII-armor public key.
# systemd 257+ reads /usr/lib/systemd/import-pubring.gpg, systemd 261+
# reads /usr/lib/systemd/import-pubring.pgp. Ship both, matching snosi's
# import-pubring convention (snosi shared/sysext/keys/README.md).
# The build fails loudly if keys/ulab-sysext-public-key.asc is absent:
# a sysext catalog without a pinned verification key never ships.
# ---------------------------------------------------------------------------
FROM packages-builder AS keyring
COPY keys/ulab-sysext-public-key.asc /tmp/ulab-key/
RUN test -f /tmp/ulab-key/ulab-sysext-public-key.asc || { echo "FATAL: keys/ulab-sysext-public-key.asc is missing; run 'just keygen' and commit the public key (README#signing)" >&2; false; }
RUN mkdir -p /out && \
    gpg --batch --yes --dearmor --output /out/import-pubring.gpg /tmp/ulab-key/ulab-sysext-public-key.asc && \
    rm -rf /tmp/ulab-key

# ---------------------------------------------------------------------------
# Runtime image.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS base

# Stage sources without committing their COPY mtimes to the runtime image.
FROM scratch AS inputs
COPY system_files/ /tmp/ulab-assets/
COPY scripts/finalize.sh /tmp/ulab-scripts/

FROM base AS ulab

# Build stamp inputs, readable by finalize.sh below and consumed again by
# the LABEL block afterwards.
ARG ULAB_VERSION=0.0.1
ARG GIT_COMMIT=unknown

# One RUN keeps the layer small and atomic:
#   1. Package payload merge from the builder stage (both /usr and the
#      hummingbird repo file, whose runtime copy keeps gpgcheck=1).
#   2. Import-pubring keyring under both paths systemd wants it.
#   3. ulab system files: sysupdate.<name>.d transfer/feature definitions,
#      /usr/share/ulab material (justfile, recipes, helpers), ujust CLI.
#   4. finalize.sh: fix timestamps for reproducibility, strip builder-only
#      leftovers, clean dnf state.
#   5. ulab-verify: fail the layer loudly when anything structural is
#      missing (transfer files, keyring, ujust wiring, updex CLI).
RUN --mount=type=bind,from=packages-builder,source=/,target=/tmp/ulab-packages,ro \
    --mount=type=bind,from=keyring,source=/out,target=/tmp/ulab-keyring,ro \
    --mount=type=bind,from=inputs,source=/,target=/tmp/ulab-inputs,ro \
    cp -a /tmp/ulab-packages/usr/. /usr/ && \
    cp -a /tmp/ulab-packages/etc/. /etc/ && \
    rm -f /etc/yum.repos.d/fedora-44.repo /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-primary && \
    install -D -m 0644 /tmp/ulab-keyring/import-pubring.gpg /usr/lib/systemd/import-pubring.gpg && \
    install -D -m 0644 /tmp/ulab-keyring/import-pubring.gpg /usr/lib/systemd/import-pubring.pgp && \
    cp -a /tmp/ulab-inputs/tmp/ulab-assets/usr/. /usr/ && \
    /tmp/ulab-inputs/tmp/ulab-scripts/finalize.sh && \
    /usr/local/libexec/ulab-verify && \
    rm -rf /tmp/ulab-packages /tmp/ulab-keyring /tmp/ulab-inputs

LABEL org.opencontainers.image.title="ulab" \
      org.opencontainers.image.description="A ucore-style Fedora Hummingbird server image with updex-managed Kubernetes sysexts (k3s, k0s, KubeStellar)." \
      org.opencontainers.image.version="${ULAB_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.source="https://github.com/HuntedRaven7/ulab" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.readme-url="https://raw.githubusercontent.com/HuntedRaven7/ulab/main/README.md"
