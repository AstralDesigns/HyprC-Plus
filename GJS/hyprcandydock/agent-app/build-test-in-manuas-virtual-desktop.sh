#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

# This desktop is Ubuntu-based and does not provide paru/yay. Force the
# portable source-build branch while retaining the same build.sh workflow
# that Arch users will run with paru/yay and AUR enabled.
export HYPRCANDY_LLAMA_SKIP_AUR=1
export HYPRCANDY_LLAMA_FORCE_SOURCE=1

exec ./build.sh "$@"
