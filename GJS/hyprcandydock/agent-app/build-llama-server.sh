#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

LLAMA_VERSION="${HYPRCANDY_LLAMA_VERSION:-v0.4.0}"
LLAMA_REPO="${HYPRCANDY_LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"
SRC_DIR="${HYPRCANDY_LLAMA_SRC_DIR:-$(pwd)/../native/llama.cpp}"
BUILD_DIR="${HYPRCANDY_LLAMA_BUILD_DIR:-$SRC_DIR/build}"
BIN="$BUILD_DIR/bin/llama-server"

find_system_server() {
  local candidate
  candidate="$(command -v llama-server 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in /usr/bin/llama-server /usr/local/bin/llama-server /opt/llama.cpp-vulkan-bin/llama-server; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  candidate="$(find /opt -type f -name llama-server -perm -111 -print -quit 2>/dev/null || true)"
  [[ -n "$candidate" ]] && printf '%s\n' "$candidate"
}

find_package_server() {
  local package="$1" candidate
  if command -v pacman >/dev/null 2>&1; then
    candidate="$(pacman -Ql "$package" 2>/dev/null | awk '$2 ~ /\/llama-server$/ { print $2; exit }')"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  return 1
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

link_system_server() {
  local system_bin="$1"
  mkdir -p "$(dirname "$BIN")"
  rm -f "$BIN"
  ln -s "$system_bin" "$BIN"
  echo "llama-server ready from system/AUR package: $system_bin"
  "$system_bin" --version || true
}

try_aur() {
  local helper="$1" package system_bin
  # Never pass the virtual provider name `llama.cpp` to paru/yay: that opens
  # an interactive provider menu and can silently select a huge ROCm package.
  case "${HYPRCANDY_LLAMA_BACKEND:-vulkan}" in
    vulkan) package="llama.cpp-vulkan-bin" ;;
    hip|rocm) package="llama.cpp-hip" ;;
    cuda) package="llama.cpp-cuda" ;;
    git|cpu) package="llama.cpp-git" ;;
    *) package="llama.cpp-vulkan-bin" ;;
  esac
  package="${HYPRCANDY_LLAMA_AUR_PACKAGE:-$package}"
  echo "Trying explicit $helper AUR package: $package"
  sanitize_path_for_arch_tools
  if env PATH="$PATH" "$helper" -S --needed --noconfirm "$package"; then
    system_bin="$(find_system_server || find_package_server "$package" || true)"
    if [[ -n "$system_bin" ]]; then
      link_system_server "$system_bin"
      return 0
    fi
    echo "$package installed but its package file list did not expose llama-server." >&2
  fi
  return 1
}

if [[ "${HYPRCANDY_LLAMA_FORCE_SOURCE:-0}" != "1" && "${HYPRCANDY_LLAMA_SKIP_AUR:-0}" != "1" ]]; then
  if command -v paru >/dev/null 2>&1; then
    if try_aur paru; then exit 0; fi
    echo "paru could not provide llama-server; falling back to source build." >&2
  elif command -v yay >/dev/null 2>&1; then
    if try_aur yay; then exit 0; fi
    echo "yay could not provide llama-server; falling back to source build." >&2
  else
    echo "No paru/yay detected; using the portable source-build fallback."
  fi
fi

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

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required for the source build." >&2
  exit 1
fi

mkdir -p "$(dirname "$SRC_DIR")"
if [[ ! -d "$SRC_DIR/.git" ]]; then
  git clone --depth 1 --branch "$LLAMA_VERSION" "$LLAMA_REPO" "$SRC_DIR"
else
  git -C "$SRC_DIR" fetch --depth 1 origin "refs/tags/$LLAMA_VERSION" || true
  git -C "$SRC_DIR" checkout --force "$LLAMA_VERSION"
fi

cmake_args=(
  -S "$SRC_DIR"
  -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DGGML_NATIVE=ON
  -DGGML_CCACHE=OFF
  -DLLAMA_CURL=OFF
  -DLLAMA_BUILD_SERVER=ON
  -DLLAMA_BUILD_UI=OFF
  -DLLAMA_USE_PREBUILT_UI=OFF
)
if [[ -n "${HYPRCANDY_LLAMA_CMAKE_ARGS:-}" ]]; then
  read -r -a extra_args <<< "$HYPRCANDY_LLAMA_CMAKE_ARGS"
  cmake_args+=("${extra_args[@]}")
fi
cmake "${cmake_args[@]}"
cmake --build "$BUILD_DIR" --target llama-server --parallel "${HYPRCANDY_LLAMA_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
if [[ ! -x "$BIN" ]]; then
  echo "ERROR: llama-server was not produced at $BIN" >&2
  exit 1
fi
"$BIN" --version || true
echo "llama-server ready from source build: $BIN"
