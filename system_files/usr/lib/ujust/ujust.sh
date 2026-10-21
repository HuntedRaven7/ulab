#!/bin/bash
# ulab ujust helpers -- sourced by /usr/bin/ulab and by the script bodies
# inside just recipes.
#
# Helpers never sudo anything themselves: recipes prefix whole steps with
# sudo, matching ujust convention. Path names used by recipes resolve here
# so behavior stays the same whether a recipe or `ulab` CLI calls them.

_ulab() { echo -en "\033[0;34m[ulab]\033[0m "; }

ulab_info() {
    _ulab; echo "sysext features:"; updex features list || true
}

feature_is_shipped() {
    # 0 when the named feature exists among the sysupdate components
    # shipped by the image.
    local name="$1"
    test -f "/usr/lib/sysupdate.${name}.d/${name}.transfer" \
        && test -f "/usr/lib/sysupdate.${name}.d/${name}.feature"
}

kubeconfig_path() {
    # Print the first kubeconfig a ulab node plausibly has, mirroring the
    # places k3s and k0s write them and $KUBECONFIG. Prints nothing and
    # exits 1 when no cluster config exists.
    local candidate
    if [[ -n "${KUBECONFIG:-}" && -s "$KUBECONFIG" ]]; then
        "$KUBECONFIG"
        return 0
    fi
    for candidate in \
        "$HOME/.kube/config" \
        /etc/rancher/k3s/k3s.yaml \
        /var/lib/k0s/pki/admin.conf; do
        if [[ -s "$candidate" ]]; then
            "$candidate"
            return 0
        fi
    done
    return 1
}

cluster_ready() {
    # Verify a local cluster answers from its kubeconfig. Sets the
    # variable KUBECONFIG itself when only a component path exists.
    local path
    if ! path="$(kubeconfig_path)"; then
        return 1
    fi
    export KUBECONFIG="$path"
    kubectl --kubeconfig "$path" get nodes >/dev/null 2>&1
}
