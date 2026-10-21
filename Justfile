# ulab repository build recipes (CI and local builds agree on these).
#
# Local prerequisites: podman, just, git. Building the image locally also
# requires the sysext public key committed at
# keys/ulab-sysext-public-key.asc (see `just keygen`).

default:
    @just --list --list-heading 'Available recipes:\n' --list-prefix ' - '

# Validate the repo invariants locally (what the CI Validate job runs).
validate:
    ./tests/validate.sh

# Build the bootc image locally with podman; outputs ulab:latest.
build-image version="$(date -u '+%Y.%m.%d')":
    #!/bin/bash
    set -euo pipefail
    commit=$(git rev-parse HEAD)
    podman build \
        --build-arg BASE_IMAGE=quay.io/hummingbird-community/os-minimal:latest@sha256:5ae51afb8a120e7e7c32a774be23b300dad3dd58ef51086de917e5eb66a91030 \
        --build-arg ULAB_VERSION="$version" \
        --build-arg GIT_COMMIT="$commit" \
        --tag ulab:"$version" \
        --tag ulab:latest .
    echo "built ulab:$version"

# Build one sysext locally. Signing is skipped unless ULAB_GPG_KEY_ID set.
build-sysext name:
    #!/bin/bash
    set -euo pipefail
    sudo apt-get install -qq -y squashfs-tools zstd attr >/dev/null 2>&1 || \
        { echo 'install squashfs-tools zstd attr' >&2; }
    ./sysext/common/build-sysext.sh {{ name }}

# Build every sysext locally.
build-sysexts:
    #!/bin/bash
    set -euo pipefail
    for name in k3s k0s kubestellar; do just build-sysext "$name"; done

# One-time: create the sysext catalog signing keypair. The private half
# goes to ~/.gnupg (and CI secret ULAB_GPG_PRIVATE_KEY); the public half
# is written to keys/ulab-sysext-public-key.asc for commit.
keygen:
    #!/bin/bash
    set -euo pipefail
    homedir=$(mktemp -d)
    # gpg batch parameter files must not carry leading whitespace; printf
    # one line at a time so the recipe's tab indentation stays out.
    {
        printf '%%no-protection\n'
        printf 'Key-Type: eddsa\n'
        printf 'Key-Curve: Ed25519\n'
        printf 'Key-Usage: sign\n'
        printf 'Name-Real: ulab sysext catalog\n'
        printf 'Name-Email: sysupdate@ulab.invalid\n'
        printf 'Expire-Date: 0\n'
        printf '%%commit\n'
    } > "$homedir/params"
    gpg --batch --homedir "$homedir" --gen-key "$homedir/params"
    keyid=$(gpg --homedir "$homedir" --list-secret-keys --with-colons | awk -F: '/^sec/ {print $5; exit}')
    gpg --homedir "$homedir" --export --armor --output keys/ulab-sysext-public-key.asc "$keyid"
    gpg --homedir "$homedir" --export-secret-keys --armor --output ulab-gpg-private-key.asc "$keyid"
    chmod 600 ulab-gpg-private-key.asc
    echo "committed public key: keys/ulab-sysext-public-key.asc"
    echo "private key: ulab-gpg-private-key.asc (NEVER commit; import into"
    echo "gpg and save the armored form as the ULAB_GPG_PRIVATE_KEY secret)"
    gpg --homedir "$homedir" --fingerprint "$keyid"
