#!/bin/bash
# Verified download helper for ulab sysext payloads, adapted from snosi's
# shared/download/verified-download.sh (simplified: GitHub upstreams only).
#
# Purpose of a sysext build is to ship byte-exact upstream artifacts the
# project already published and hash-verified; this helper refuses to write
# an unhashed artifact into a commit range.
#
# Interface:
#   verified_download <dest> <url> <sha256> [<retry-attempts=4>]
#
# Refuses https-less URLs outright.

verified_download() {
    local dest="$1" url="$2" sha="$3" attempts="${4:-4}"

    [ -n "$dest" ] || { echo "verified_download: dest required" >&2; return 2; }
    [ -n "$url" ] || { echo "verified_download: url required" >&2; return 2; }
    [ -n "$sha" ] || { echo "verified_download: sha256 required (nothing without a hash)" >&2; return 2; }
    case "$url" in
        https://*) : ;;
        *) echo "verified_download: refusing non-https url: $url" >&2; return 2 ;;
    esac

    mkdir -p "$(dirname "$dest")"
    if curl -fL --retry "$attempts" --silent --show-error -o "$dest" "$url"; then
        local got
        got="$(sha256sum "$dest" | awk '{print $1}')"
        if [ "$got" != "$sha" ]; then
            echo "verified_download: digest mismatch for $url: got $got want $sha" >&2
            rm -f "$dest"
            return 1
        fi
        return 0
    fi
    echo "verified_download: download failed: $url" >&2
    return 1
}

# github_release_asset <repo> <tag> <asset-name> <sha256> <dest>
github_release_asset() {
    local repo="$1" tag="$2" asset="$3" sha="$4" dest="$5"
    local encoded
    encoded="$(printf '%s' "$tag" | sed 's/+/%2B/g')"
    verified_download "$dest" \
        "https://github.com/$repo/releases/download/$encoded/$asset" "$sha"
}

# checksum_from_file <file> <token>
# Scans a sha256 checksums file (GNU style, name in any column) for the
# token and prints the hex digest. Fails when the token matches nothing or
# more than one line.
checksum_from_file() {
    local file="$1" token="$2"
    [ -s "$file" ] || { echo "checksum_from_file: file missing: $file" >&2; return 2; }
    [ -n "$token" ] || { echo "checksum_from_file: token required" >&2; return 2; }
    local hits
    # sha256sum --binary lines carry the name as '*name'; strip a leading
    # asterisk before comparing.
    hits="$(awk -v t="$token" '{
        for (i = 2; i <= NF; i++) {
            name = $i; sub(/^\*/, "", name);
            if (name == t) { print $1; exit }
        }
    }' "$file")"
    [ -n "$hits" ] || { echo "checksum_from_file: token not found: $token" >&2; return 1; }
    printf '%s\n' "$hits"
}

# download_checksum_file <url> <dest>:
# Fetches the checksum companion of a payload. The digest of the digest
# file is not pinned separately: it is fetched over the same TLS channel
# as the release listing, which is the standard bootstrap k3s/k0s installer
# scripts themselves use. Use pinned (sysext.env) digests instead of this
# helper where pre-release tampering concerns matter.
download_checksum_file() {
    local url="$1" dest="$2"
    curl -fsSL --retry 4 -o "$dest" "$url"
}

# upstream_latest_version <repo>  -> prints the newest release tag
upstream_latest_version() {
    curl -fsSL --retry 3 "https://api.github.com/repos/$1/releases/latest" |
        grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}
