#!/bin/bash
# k3s sysext payload.
#
# Downloads the pinned upstream static binary, verifies it against the
# release's checksum file (the same sha256sum-amd64.txt the k3s installer
# consumes), stages it under /usr/bin/k3s, and adds the multicall entry
# points: kubectl and crictl (not ctr: a docker sysext in another merge
# layer could ship /usr/bin/ctr already, and two merged sysexts claiming
# one path shadow each other -- use `k3s ctr`).

set -euo pipefail

payload_resolve_version() {
    local work="$1"
    if [ -n "${ULAB_PINNED_VERSION:-}" ]; then
        # CI validates pins against upstream in a separate check.
        printf '%s\n' "$ULAB_PINNED_VERSION"
        return 0
    fi
    local tag
    tag="$(upstream_latest_version "$ULAB_SYSEXT_REPO")"
    printf '%s\n' "${tag#v}"
}

payload_install() {
    local tree="$1" work="$2" version="$3"

    # k3s names its checksum files sha256sum-amd64.txt (x86_64);
    # SYS_ARCH uses the systemd spelling, so map back.
    local upstream_arch="amd64"
    case "$SYS_ARCH" in
    arm64) upstream_arch="arm64" ;;
    esac

    mkdir -p "$work/checksum"
    download_checksum_file \
        "https://github.com/$ULAB_SYSEXT_REPO/releases/download/v$version/sha256sum-${upstream_arch}.txt" \
        "$work/checksum/sha256sum.txt"
    local digest
    digest="$(checksum_from_file "$work/checksum/sha256sum.txt" "k3s")"

    mkdir -p "$tree/usr/bin"
    github_release_asset "$ULAB_SYSEXT_REPO" "v$version" "k3s" "$digest" \
        "$tree/usr/bin/k3s"
    chmod 0755 "$tree/usr/bin/k3s"

    # Multicall entry points, minus ctr (see header); relative links so
    # they resolve inside the build tree and the merged overlay alike.
    ln -sf k3s "$tree/usr/bin/kubectl"
    ln -sf k3s "$tree/usr/bin/crictl"
}
