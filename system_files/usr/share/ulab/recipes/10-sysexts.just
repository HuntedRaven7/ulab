# sysext management recipes. Heavy payloads never ship in the image:
# updex stages them into /var/lib/extensions.d and a symlink into
# /var/lib/extensions feeds systemd-sysext's merge.

sysext-list:
    #!/bin/bash
    updex features list

sysext-status:
    #!/bin/bash
    echo "== updex =="
    updex features list
    echo
    echo "== merged extensions =="
    systemd-sysext status

sysext-enable feature="" check="--now":
    #!/bin/bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh
    if ! feature_is_shipped "$feature"; then
        echo "feature '$feature' is not shipped by ulab (k3s, k0s, kubestellar)" >&2
        exit 64
    fi
    echo "downloading + merging '$feature' via updex ($check)..."
    if [ "$check" = "--now" ]; then
        sudo updex features enable "$feature" --now
    else
        sudo updex features enable "$feature"
        echo "enabled; download later with 'ujust sysext-update'"
    fi

sysext-disable feature="" force="":
    #!/bin/bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh
    if ! feature_is_shipped "$feature"; then
        echo "feature '$feature' is not shipped by ulab (k3s, k0s, kubestellar)" >&2
        exit 64
    fi
    if [ -n "$force" ]; then
        sudo updex features disable "$feature" --now --force
    else
        sudo updex features disable "$feature" --now
    fi
    echo "'$feature' disabled (merged extensions are gone until refresh or reboot)"

sysext-update check="":
    #!/bin/bash
    set -euo pipefail
    if [ -n "$check" ]; then
        updex features check
    else
        sudo updex features update
    fi

# Toggle the updex auto-update timer: staged automatic updates of every
# enabled sysext feature.
sysext-auto-update toggle="enable":
    #!/bin/bash
    set -euo pipefail
    case "$toggle" in
    enable) sudo updex daemon enable; updex daemon status ;;
    disable) sudo updex daemon disable; updex daemon status ;;
    *) echo "toggle must be 'enable' or 'disable'" >&2; exit 64 ;;
    esac
