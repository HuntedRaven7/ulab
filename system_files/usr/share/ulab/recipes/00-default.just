# Default recipe: show available commands, ublue-style.

ulab-default:
    @echo "$(tput setaf 4)ulab$(tput sgr0): Fedora Hummingbird server image with updex-managed Kubernetes sysexts"
    @echo "Available commands:"
    @ujust --list --list-heading '' --list-prefix ' - '

ulab-info:
    #!/bin/bash
    source /usr/lib/ujust/ujust.sh
    ulab_info
