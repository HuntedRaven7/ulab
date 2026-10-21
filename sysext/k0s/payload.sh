#!/bin/bash
# k0s sysext payload.
#
# Downloads the pinned upstream `k0s` binary (checked against the
# release's checksums.txt), stages it at /usr/bin/k0s. All role logic
# lives in the systemd units.

set -euo pipefail

payload_resolve_version() {
    local work="$1"
    if [ -n "${ULAB_PINNED_VERSION:-}" ]; then
        printf '%s\n' "$ULAB_PINNED_VERSION"
        return 0
    fi
    local tag
    tag="$(upstream_latest_version "$ULAB_SYSEXT_REPO")"
    printf '%s\n' "${tag#v}"
}

payload_install() {
    local tree="$1" work="$2" version="$3"

    local upstream_arch="amd64"
    case "$SYS_ARCH" in
    arm64) upstream_arch="arm64" ;;
    esac

    mkdir -p "$work/checksum"
    download_checksum_file \
        "https://github.com/$ULAB_SYSEXT_REPO/releases/download/v$version/sha256sums.txt" \
        "$work/checksum/checksums.txt"
    # k0s lists its binaries as k0s-v<version>-<arch> in checksums.txt.
    local digest asset
    asset="k0s-v$version-$upstream_arch"
    digest="$(checksum_from_file "$work/checksum/checksums.txt" "$asset")"

    mkdir -p "$tree/usr/bin"
    github_release_asset "$ULAB_SYSEXT_REPO" "v$version" "$asset" "$digest" \
        "$tree/usr/bin/k0s"
    chmod 0755 "$tree/usr/bin/k0s"
}
