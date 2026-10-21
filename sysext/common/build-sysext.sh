#!/bin/bash
# ulab sysext assembler.
#
# Every sysext directory (sysext/<name>/) provides:
#   sysext.env       static metadata: ULAB_SYSEXT_NAME (must equal the
#                    directory name), ULAB_SYSEXT_REPO, pinned version key
#   payload.sh       payload_resolve_version <work-dir> and
#                    payload_install <tree-dir> <work-dir> <version>:
#                    download (verified) and stage the /usr payload
#   required-paths.txt   absolute paths that MUST exist in the finished
#                    payload, one per line ('#' comments allowed); the
#                    build fails loudly if any is missing, guarding
#                    against publishing structurally broken images (the
#                    guard snosi added after the incus incident)
#   tree/            static overlay copied into the tree verbatim (systemd
#                    units, presets, tmpfiles). Sysexts are /usr-only:
#                    nothing outside /usr is packaged.
#
# Usage: build-sysext.sh <name> [<name>...]
#
# Output (per name) under sysext/dist/<name>/:
#   <name>_<version>_<arch>.raw        squashfs sysext image
#   <name>_<version>_<arch>.raw.zst    compressed, what the catalog ships
#   SHA256SUMS.new / SHA256SUMS.new.gpg   new-artifact-only manifest lines,
#                    appended to the published catalog by the CI
#                    publisher; a detached signature over the appended
#                    lines is produced when ULAB_GPG_KEY_ID is set.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SYSEXT_DIR="$REPO_ROOT/sysext"
DIST_ROOT="${ULAB_DIST_DIR:-$SYSEXT_DIR/dist}"

case "$(uname -m)" in
    x86_64) SYS_ARCH="x86-64" ;;
    aarch64) SYS_ARCH="arm64" ;;
    *) SYS_ARCH="$(uname -m)" ;;
esac

# shellcheck source=source/download.sh
source "$(dirname "$0")/source/download.sh"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "FATAL: '$1' is required but not installed" >&2
        exit 2
    }
}

build_sysext() {
    local name="$1"
    local base="$SYSEXT_DIR/$name"

    # ----- metadata ----------------------------------------------------------
    set -a
    # shellcheck disable=SC1091
    source "$base/sysext.env"
    set +a
    : "${ULAB_SYSEXT_NAME:?ULAB_SYSEXT_NAME missing in sysext.env}"
    : "${ULAB_SYSEXT_REPO:?ULAB_SYSEXT_REPO missing in sysext.env}"
    [ "$name" = "$ULAB_SYSEXT_NAME" ] || {
        echo "FATAL: sysext dir '$name' disagrees with ULAB_SYSEXT_NAME=$ULAB_SYSEXT_NAME" >&2
        exit 2
    }

    # ----- payload ------------------------------------------------------------
    local work tree
    work="$(mktemp -d)"
    tree="$work/payload"
    mkdir -p "$tree/usr"

    # Static overlay first; payload-installed files may not shadow it.
    if [ -d "$base/tree" ]; then
        cp -a "$base/tree/." "$tree/"
    fi

    # shellcheck disable=SC1090
    source "$base/payload.sh"
    # shellcheck disable=SC2154
    version="$(payload_resolve_version "$work")"
    payload_install "$tree" "$work" "$version"

    # ----- extension-release metadata ----------------------------------------
    mkdir -p "$tree/usr/lib/extension-release.d"
    cat > "$tree/usr/lib/extension-release.d/extension-release.$name" <<-EOF
	ID=_any
	VERSION_ID=_any
	ARCHITECTURE=$SYS_ARCH
	SYSEXT_ID=$name
	SYSEXT_VERSION_ID=$version
	SYSEXT_SCOPE=system
	EOF
    # Relax the strict filename check: the deployed image filename carries
    # a version suffix (k3s_1.36.5+k3s1_x86-64.raw) while the updex symlink
    # presents it as k3s.raw. With exactly one extension-release.* file
    # tagged strict=0, systemd accepts either name (os-release(5) escape
    # hatch).
    setfattr -n user.extension-release.strict -v 0 \
        "$tree/usr/lib/extension-release.d/extension-release.$name"

    # ----- required paths ------------------------------------------------------
    while IFS= read -r req; do
        # Strip trailing comments and ignore blank lines.
        req="${req%%#*}"
        req="${req//[$'\t\r ']/}"
        [ -n "$req" ] || continue
        if [ ! -e "$tree$req" ]; then
            echo "FATAL: $name payload missing required path: $req" >&2
            exit 1
        fi
    done < "$base/required-paths.txt"

    # ----- package -------------------------------------------------------------
    local dist artifact
    dist="$DIST_ROOT/$name"
    mkdir -p "$dist"
    artifact="${ULAB_SYSEXT_NAME}_${version}_${SYS_ARCH}.raw"

    echo "packaging $artifact"
    mksquashfs "$tree" "$dist/$artifact" \
        -comp zstd -Xcompression-level 19 \
        -noappend -quiet -no-progress
    zstd -q -f -k -19 "$dist/$artifact" -o "$dist/$artifact.zst"

    # ----- manifest contribution ------------------------------------------------
    (cd "$dist" && sha256sum --binary "$artifact" "$artifact.zst" > "SHA256SUMS.new")
    if [ -n "${ULAB_GPG_KEY_ID:-}" ]; then
        gpg --batch --yes --local-user "$ULAB_GPG_KEY_ID" \
            --detach-sign --output "$dist/SHA256SUMS.new.gpg" \
            "$dist/SHA256SUMS.new"
    fi

    rm -rf "$work"
    echo "built $name $version (${SYS_ARCH}):"
    ls -la "$dist/$artifact" "$dist/$artifact.zst"
}

need mksquashfs
need zstd
need gpg
need setfattr

for name in "$@"; do
    build_sysext "$name"
done
