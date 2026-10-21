#!/bin/bash
# ulab image finalize step; runs inside the runtime stage after the payload
# merge and the system_files copy.
#
# 1. Housekeeping: dnf caches and transaction leftovers must not ship in a
#    bootc layer.
# 2. Build stamp: support diagnostics need to answer "what did I run on
#    top of what".
# 3. First-boot directories: sysext staging and Kubernetes config trees
#    are persistent state on bootc (not part of /usr), so the image only
#    provides the paths and tmpfiles.d creates them at boot.
set -euo pipefail

# --- 1. Housekeeping -------------------------------------------------------
rm -rf /var/cache/dnf /var/cache/rpm /var/lib/dnf
find /var/log -type f -size +0 -exec truncate -s 0 {} \; 2>/dev/null || true

# --- 2. Build stamp ---------------------------------------------------------
tee /usr/share/ulab/build-info > /dev/null <<EOF
image: ulab
version: ${ULAB_VERSION:-0.0.1}
commit: ${GIT_COMMIT:-unknown}
base: quay.io/hummingbird-community/os-minimal
EOF

echo "ulab finalize: filesystem ready"
