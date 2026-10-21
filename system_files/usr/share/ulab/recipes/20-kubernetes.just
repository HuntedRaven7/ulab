# Kubernetes cluster recipes. k3s and k0s ship as sysexts enabled with
# updex; their units decide controller/server vs worker/agent via
# condition files in /etc that ujust writes for you.

# Enable the k3s sysext. mode="server" (default) runs a standalone server
# (optionally joining an existing one when join_url is given);
# mode="agent" is handled by the k3s-agent recipe below.
k3s mode="server" join_url="" join_token="":
    #!/bin/bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh
    case "$mode" in
    server)
        if [ -f /etc/default/k3s-agent ]; then
            echo "a k3s agent is configured (/etc/default/k3s-agent exists)." >&2
            echo "Remove it first (sudo rm /etc/default/k3s-agent) to switch this node to server" >&2
            exit 1
        fi
        sudo install -d -m 0700 /etc/rancher /etc/default
        if [ -n "$join_url" ]; then
            echo "K3S_URL=$join_url" | sudo tee -a /etc/default/k3s >/dev/null
            [ -n "$join_token" ] && echo "K3S_TOKEN=$join_token" | sudo tee -a /etc/default/k3s >/dev/null
            echo "joining $join_url via /etc/default/k3s"
        fi
        ;;
    agent)
        echo "agent mode uses the dedicated recipe:" >&2
        echo "  ujust k3s-agent <k3s-server-url> <token>" >&2
        exit 64
        ;;
    *) echo "mode must be 'server' or 'agent'" >&2; exit 64 ;;
    esac
    ujust sysext-enable k3s
    echo
    echo "k3s: server on this node, kubectl at $(command -v kubectl)"
    echo "$ sudo kubectl get nodes"
    echo "config: /etc/rancher/k3s/config.yaml   state: /var/lib/rancher"

# Flip this node to a k3s agent joining an existing server: writes
# /etc/default/k3s-agent (the file that stops k3s.service and starts
# k3s-agent.service), then merges the sysext in place.
k3s-agent join_server_url="" join_token="":
    #!/bin/bash
    set -euo pipefail
    : "${join_server_url:?join_server_url required: ujust k3s-agent <k3s-server-url> <token>}"
    printf 'K3S_URL=%s\n' "$join_server_url" | sudo tee /etc/default/k3s-agent >/dev/null
    if [ -n "$join_token" ]; then
        printf 'K3S_TOKEN=%s\n' "$join_token" | sudo tee -a /etc/default/k3s-agent >/dev/null
    else
        echo "add the join token to /etc/default/k3s-agent before enabling:"
        echo "  $ sudo tee -a /etc/default/k3s-agent <<< 'K3S_TOKEN=<token-from-server>'"
    fi
    ujust sysext-enable k3s

# ---- k0s ------------------------------------------------------------------

# Enable the k0s sysext as a controller node (the default role).
k0s:
    #!/bin/bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh
    if [ -f /etc/default/k0s-worker ]; then
        echo "a k0s worker is configured (/etc/default/k0s-worker exists)." >&2
        echo "Remove it first to switch back to controller." >&2
        exit 1
    fi
    sudo install -d -m 0700 /etc/k0s /etc/default
    ujust sysext-enable k0s
    echo
    echo "k0s: controller on this node"
    echo "kubeconfig:" && echo "  $ sudo k0s kubeconfig create localhost"
    echo "config: /etc/k0s/k0s.yaml   state: /var/lib/k0s"

# Enable k0s as a worker joining an existing controller.
k0s-worker controller_url token="":
    #!/bin/bash
    set -euo pipefail
    : "${controller_url:?controller_url required: ujust k0s-worker <https://controller:6443> <token>}"
    printf 'K0S_WORKER_FLAGS=--token-file=/etc/k0s/worker-token\n' | sudo tee /etc/default/k0s-worker >/dev/null
    if [ -n "$token" ]; then
        printf '%s' "$token" | sudo tee /etc/k0s/worker-token >/dev/null
    else
        echo "write the join token: sudo tee /etc/k0s/worker-token <<< '<token>'"
    fi
    echo "worker flags written; run 'ujust sysext-enable k0s' to merge and start"

# ---- KubeStellar ----------------------------------------------------------

# Deploy KubeStellar Core into an existing local cluster (k3s or k0s):
# enables the kubestellar sysext (helm + kbundle binaries) and runs the
# upstream core chart onto the hosting cluster.
#
#   ujust kubestellar                      # ITSes/WDSes from kubestellar.env
#   ujust kubestellar itses='[{"name":"its1"}]' wdses='[{"name":"wds1"}]'
kubestellar itses="" wdses="" release="ks-core":
    #!/bin/bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh
    test -x /usr/bin/helm || ujust sysext-enable kubestellar
    test -x /usr/bin/helm || { echo "helm missing; kubestellar sysext did not merge" >&2; exit 1; }
    test -x /usr/bin/kubectl || { echo "kubectl missing; enable the k3s or k0s sysext first" >&2; exit 1; }
    if ! cluster_ready; then
        echo "no running local cluster: run 'ujust k3s' or 'ujust k0s' first," >&2
        echo "or import a kubeconfig through KUBECONFIG." >&2
        exit 1
    fi
    . /usr/share/ulab/kubestellar.env
    # Site policy may override the defaults wholesale.
    if [ -f /etc/kubestellar/env ]; then
        . /etc/kubestellar/env
    fi
    : "${KUBESTELLAR_CHART:?KUBESTELLAR_CHART missing from kubestellar.env}"
    : "${KUBESTELLAR_VERSION:?KUBESTELLAR_VERSION missing from kubestellar.env}"
    itses="${itses:-$KUBESTELLAR_ITSES}"
    wdses="${wdses:-$KUBESTELLAR_WDSES}"
    sudo --preserve-env=KUBECONFIG helm upgrade --install "$release" \
        "$KUBESTELLAR_CHART" --version "$KUBESTELLAR_VERSION" \
        --kubeconfig "$KUBECONFIG" \
        --set-json "ITSes=$itses" --set-json "WDSes=$wdses"
    echo "KubeStellar deployed. Next:"
    echo "  $ kubectl --kubeconfig $KUBECONFIG get pods -n kubestellar"
    echo "add control-plane contexts with kflex or import-cp-contexts.sh (see kubestellar.io docs)."

kubestellar-off:
    #!/bin/bash
    set -euo pipefail
    . /usr/share/ulab/kubestellar.env
    if ! path="$(source /usr/lib/ujust/ujust.sh; kubeconfig_path)"; then
        echo "no kubeconfig found; nothing to uninstall" >&2
        exit 1
    fi
    sudo --preserve-env=KUBECONFIG env KUBECONFIG="$path" \
        helm uninstall ks-core || true
    echo "KubeStellar core chart removed. The sysext stays merged until 'ujust sysext-disable kubestellar'."
