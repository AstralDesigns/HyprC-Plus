#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

# Installs the correct pre-built llama.cpp package for this machine's GPU.
# llama.cpp's own package already provides the `llama-server` binary — there
# is nothing to build and nothing to search the system for separately, so
# the AUR path below only has one job: pick the right package and install
# it.
#
#   Intel / AMD / anything else with Vulkan  ->  llama.cpp-vulkan-bin
#   NVIDIA                                    ->  llama.cpp-cuda-bin
#
# Override auto-detection with HYPRCANDY_LLAMA_PACKAGE if you need a specific
# package (e.g. llama.cpp-hip for ROCm, or llama.cpp-vulkan-bin on a machine
# that also has an NVIDIA card you don't want to build CUDA for).
#
# If llama-server is already installed, this script is a no-op by default —
# set HYPRCANDY_LLAMA_REINSTALL=1 to force it to reinstall/rebuild anyway
# (e.g. to switch backends or pick up a newer version).

find_existing_llama_server() {
  local candidate
  candidate="$(command -v llama-server 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in "$HOME/.local/bin/llama-server" /usr/local/bin/llama-server /usr/bin/llama-server; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

detect_llama_package() {
  if [[ -n "${HYPRCANDY_LLAMA_PACKAGE:-}" ]]; then
    printf '%s\n' "$HYPRCANDY_LLAMA_PACKAGE"
    return 0
  fi

  case "${HYPRCANDY_LLAMA_BACKEND:-}" in
    vulkan) printf '%s\n' "llama.cpp-vulkan-bin"; return 0 ;;
    cuda)   printf '%s\n' "llama.cpp-cuda-bin";   return 0 ;;
  esac

  # Auto-detect: any NVIDIA VGA/3D/Display controller present -> CUDA build.
  # Everything else (Intel, AMD, hybrid laptops with no working detection,
  # or no lspci at all) gets the Vulkan build, which covers Intel/AMD/most
  # other GPUs through a single portable backend.
  if command -v lspci >/dev/null 2>&1 && \
     lspci -nn 2>/dev/null | grep -Eqi '(VGA|3D|Display)[^:]*:.*NVIDIA'; then
    printf '%s\n' "llama.cpp-cuda-bin"
  else
    printf '%s\n' "llama.cpp-vulkan-bin"
  fi
}

sanitize_path_for_arch_tools() {
  local entry
  local -a entries cleaned=()
  IFS=: read -r -a entries <<< "${PATH:-}"
  for entry in "${entries[@]}"; do
    # paru's PKGBUILD sandbox rejects literal "$PATH" entries when find
    # uses -execdir. Remove accidental shell-placeholder segments.
    [[ "$entry" == '\$PATH' || "$entry" == '$PATH' || -z "$entry" ]] && continue
    cleaned+=("$entry")
  done
  PATH="$(IFS=:; echo "${cleaned[*]}")"
  export PATH
}

install_from_aur() {
  local package="$1" helper
  sanitize_path_for_arch_tools
  if command -v paru >/dev/null 2>&1; then
    helper=paru
  elif command -v yay >/dev/null 2>&1; then
    helper=yay
  else
    echo "No paru or yay found on PATH."
    return 1
  fi

  # "could not find all required packages: X (target)" on a package that
  # genuinely exists in the AUR almost always means the helper's local sync
  # databases are stale (very common right after a fresh install, or if
  # paru/yay has never been run before). Refresh them before giving up.
  echo "Syncing $helper's package databases..."
  env PATH="$PATH" "$helper" -Sy --noconfirm >/dev/null 2>&1 || true

  echo "Installing $package via $helper..."
  if env PATH="$PATH" "$helper" -S --needed --noconfirm "$package"; then
    return 0
  fi

  echo "$helper could not resolve/install $package." >&2
  echo "This is usually a stale AUR cache or a network/AUR-RPC hiccup, not a missing helper." >&2
  echo "Try manually: $helper -Sy && $helper -S $package" >&2
  return 1
}

# ── Source-build fallback (non-Arch machines with no AUR helper, e.g. CI/test
# containers) ────────────────────────────────────────────────────────────────
build_from_source() {
  local version="${HYPRCANDY_LLAMA_VERSION:-v0.4.0}"
  local repo="${HYPRCANDY_LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"
  local src_dir="${HYPRCANDY_LLAMA_SRC_DIR:-$(pwd)/../native/llama.cpp}"
  local build_dir="${HYPRCANDY_LLAMA_BUILD_DIR:-$src_dir/build}"
  local bin="$build_dir/bin/llama-server"

  if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is required for the source build; installing build dependencies..."
    if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cmake build-essential git
    elif command -v pacman >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
      sudo pacman -Sy --needed --noconfirm cmake base-devel git
    else
      echo "ERROR: cmake is missing and no supported package installer is available." >&2
      exit 1
    fi
  fi
  command -v git >/dev/null 2>&1 || { echo "ERROR: git is required for the source build." >&2; exit 1; }

  mkdir -p "$(dirname "$src_dir")"
  if [[ ! -d "$src_dir/.git" ]]; then
    git clone --depth 1 --branch "$version" "$repo" "$src_dir"
  else
    git -C "$src_dir" fetch --depth 1 origin "refs/tags/$version" || true
    git -C "$src_dir" checkout --force "$version"
  fi

  local cmake_args=(
    -S "$src_dir" -B "$build_dir"
    -DCMAKE_BUILD_TYPE=Release
    -DGGML_NATIVE=ON
    -DGGML_CCACHE=OFF
    -DLLAMA_CURL=OFF
    -DLLAMA_BUILD_SERVER=ON
    -DLLAMA_BUILD_UI=OFF
    -DLLAMA_USE_PREBUILT_UI=OFF
  )
  if [[ -n "${HYPRCANDY_LLAMA_CMAKE_ARGS:-}" ]]; then
    local extra_args
    read -r -a extra_args <<< "$HYPRCANDY_LLAMA_CMAKE_ARGS"
    cmake_args+=("${extra_args[@]}")
  fi
  cmake "${cmake_args[@]}"
  cmake --build "$build_dir" --target llama-server \
    --parallel "${HYPRCANDY_LLAMA_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

  if [[ ! -x "$bin" ]]; then
    echo "ERROR: llama-server was not produced at $bin" >&2
    exit 1
  fi

  # Drop it somewhere the Python runtime already looks (no sudo needed).
  mkdir -p "$HOME/.local/bin"
  ln -sf "$bin" "$HOME/.local/bin/llama-server"
  echo "llama-server built from source and linked to $HOME/.local/bin/llama-server"
}

EXISTING_BIN="$(find_existing_llama_server || true)"
if [[ -n "$EXISTING_BIN" && "${HYPRCANDY_LLAMA_REINSTALL:-0}" != "1" ]]; then
  echo "llama-server is already installed at $EXISTING_BIN — skipping install."
  "$EXISTING_BIN" --version 2>/dev/null || true
  echo "(Set HYPRCANDY_LLAMA_REINSTALL=1 to force a reinstall/rebuild instead.)"
  exit 0
fi

PACKAGE="$(detect_llama_package)"
echo "Selected llama.cpp package for this GPU: $PACKAGE"

if [[ "${HYPRCANDY_LLAMA_FORCE_SOURCE:-0}" == "1" || "${HYPRCANDY_LLAMA_SKIP_AUR:-0}" == "1" ]]; then
  echo "Source build requested explicitly; skipping AUR."
  build_from_source
elif install_from_aur "$PACKAGE"; then
  :
else
  echo "AUR install of $PACKAGE did not succeed; falling back to a source build." >&2
  build_from_source
fi

hash -r
if ! command -v llama-server >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/llama-server" ]]; then
  echo "ERROR: llama-server is still not on PATH (or in ~/.local/bin) after installation." >&2
  exit 1
fi

llama-server --version 2>/dev/null || "$HOME/.local/bin/llama-server" --version 2>/dev/null || true
echo "llama-server ready. (The Python runtime looks in ~/.local/bin, /usr/local/bin, /usr/bin, and PATH.)"
