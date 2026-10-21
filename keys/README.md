# ulab sysext verification keyring
#
# This directory holds the ASCII-armored OpenPGP key the sysext catalog
# verifies against: keys/ulab-sysext-public-key.asc, imported at image
# build time into /usr/lib/systemd/import-pubring.gpg (and .pgp), which is
# the keyring updex/systemd-sysupdate consult while checking the
# SHA256SUMS.gpg signatures of the catalog at
# https://huntedraven7.github.io/ulab/ext/<name>/.
#
# Generate the pair with `just keygen`:
#   * keys/ulab-sysext-public-key.asc    committed here (public, armored)
#   * ulab-gpg-private-key.asc           LOCAL ONLY; lives in
#                                        ~/.gnupg and as the CI secret
#                                        ULAB_GPG_PRIVATE_KEY
# Never commit a private key. Rotation: publish a new public key in a new
# image, then retire the old key only after the fleet has rebased onto
# that image (the keyring leaves with the image; a live system cannot
# re-read it).
#
# The build fails loudly when the public key is missing: a catalog
# without a pinned verification key never ships (the snosi trust-root
# rule). See shared/sysext/keys/README.md in frostyard/snosi for the
# convention this file structure follows.
