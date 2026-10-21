#!/bin/bash
# kubestellar sysext payload.
#
# Ships:
#   /usr/bin/helm                              (helmv4 static binary)
#   /usr/lib/kubestellar/bin/*                 upstream release binaries,
#                                              relocated the way snosi
#                                              relocates /opt payloads
#   /usr/bin/kubestellar-<short>               symlinks with prefixed
#                                              names -- "controller-manager"
#                                              is far too generic a name
#                                              to own in /usr/bin
#
# The binaries come from the release tarball, verified against
# kubestellar_<version>_checksums.txt.

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

    # ---- helm -------------------------------------------------------------
    # get.helm.sh is the canonical helm CDN (the GitHub release only
    # carries .asc signatures); the digest is pinned in sysext.env and
    # verified with the same verified_download gate as every other
    # artifact, which is the stronger posture when a pin exists.
    mkdir -p "$tree/usr/bin"
    verified_download "$work/helm.tar.gz" \
        "https://get.helm.sh/helm-v$ULAB_HELM_VERSION-linux-$upstream_arch.tar.gz" \
        "$ULAB_HELM_SHA256"
    tar -xzf "$work/helm.tar.gz" -C "$work"
    install -m 0755 "$work/linux-$upstream_arch/helm" "$tree/usr/bin/helm"

    # ---- KubeStellar release binaries -------------------------------------
    mkdir -p "$work/kubestellar" "$tree/usr/lib/kubestellar/bin"
    download_checksum_file \
        "https://github.com/$ULAB_SYSEXT_REPO/releases/download/v$version/kubestellar_${version}_checksums.txt" \
        "$work/kubestellar-checksums.txt"
    local tarball
    tarball="kubestellar_${version}_linux_${upstream_arch}.tar.gz"
    local tar_digest
    tar_digest="$(checksum_from_file "$work/kubestellar-checksums.txt" "$tarball")"
    github_release_asset "$ULAB_SYSEXT_REPO" "v$version" "$tarball" "$tar_digest" \
        "$work/kubestellar/$tarball"
    tar -xzf "$work/kubestellar/$tarball" -C "$work/kubestellar"

    # Relocate from the tar's bin/ layout into a namespaced directory;
    # every name that lands in /usr/bin is prefixed so no generic name
    # ("controller-manager") is claimed in the merged /usr namespace.
    for bin in controller-manager ocm-transport-controller kflex-get-kubeconfig; do
        if [ ! -f "$work/kubestellar/bin/$bin" ]; then
            echo "FATAL: upstream tarball has no bin/$bin; SYSEXT CONTRACTS HAVE DRIFTED" >&2
            exit 1
        fi
        install -m 0755 "$work/kubestellar/bin/$bin" "$tree/usr/lib/kubestellar/bin/$bin"
        ln -sf ../lib/kubestellar/bin/$bin "$tree/usr/bin/kubestellar-$bin"
    done
}
