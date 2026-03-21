#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/JY1003/Codex-core/main/codex-core"
SCRIPT_NAME="codex-core"
ALIAS_NAME="cx"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

have_sudo() {
  need_cmd sudo
}

run_root() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

collect_missing_deps() {
  local missing=""
  local cmd
  for cmd in bash curl jq python3; do
    if ! need_cmd "$cmd"; then
      missing="${missing}${cmd}\n"
    fi
  done
  printf "%b" "$missing"
}

install_deps_linux() {
  local pkgs=("$@")
  if need_cmd apt-get; then
    run_root apt-get update -y && run_root apt-get install -y "${pkgs[@]}"
    return $?
  fi
  if need_cmd dnf; then
    run_root dnf install -y "${pkgs[@]}"
    return $?
  fi
  if need_cmd yum; then
    run_root yum install -y "${pkgs[@]}"
    return $?
  fi
  if need_cmd pacman; then
    run_root pacman -Sy --noconfirm "${pkgs[@]}"
    return $?
  fi
  if need_cmd zypper; then
    run_root zypper install -y "${pkgs[@]}"
    return $?
  fi
  if need_cmd apk; then
    run_root apk add --no-cache "${pkgs[@]}"
    return $?
  fi
  return 1
}

install_deps_macos() {
  local pkgs=("$@")
  if need_cmd brew; then
    brew install "${pkgs[@]}"
    return $?
  fi
  return 1
}

try_install_missing_deps() {
  local missing_list="$1"
  if [ -z "$missing_list" ]; then
    return 0
  fi
  if ! is_root && ! have_sudo; then
    return 1
  fi
  local os
  os="$(uname -s 2>/dev/null || echo "")"
  case "$os" in
    Darwin)
      if is_root; then
        return 1
      fi
      # shellcheck disable=SC2086
      install_deps_macos $missing_list
      return $?
      ;;
    Linux)
      # shellcheck disable=SC2086
      install_deps_linux $missing_list
      return $?
      ;;
  esac
  return 1
}

warn_missing_deps() {
  local missing_list="$1"
  if [ -n "$missing_list" ]; then
    printf "警告：缺少依赖：%s\n" "$missing_list" >&2
    printf "脚本仍可安装，但运行功能可能受限。\n" >&2
  fi
}

pick_install_dir() {
  if [ -n "${INSTALL_DIR:-}" ]; then
    echo "$INSTALL_DIR"
    return
  fi
  if [ -w "/usr/local/bin" ]; then
    echo "/usr/local/bin"
    return
  fi
  if [ -n "${HOME:-}" ]; then
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"
    return
  fi
  echo "/tmp"
}

ask_install_dir() {
  local current_dir recommended choice custom_dir
  current_dir="$(pwd)"
  recommended="$(pick_install_dir)"
  echo "请选择安装路径（回车默认当前路径）："
  echo "  1) 当前路径：$current_dir"
  echo "  2) 自定义路径"
  echo "  3) 推荐路径：$recommended"
  if ! read -r -p "选择 [1-3，默认 1]: " choice </dev/tty; then
    choice=""
  fi
  case "$choice" in
    ""|1)
      echo "$current_dir"
      return 0
      ;;
    2)
      if ! read -r -p "请输入自定义安装路径（留空取消，回退当前路径）: " custom_dir </dev/tty; then
        custom_dir=""
      fi
      if [ -n "$custom_dir" ]; then
        echo "$custom_dir"
      else
        echo "$current_dir"
      fi
      return 0
      ;;
    3)
      echo "$recommended"
      return 0
      ;;
    *)
      echo "无效选择，默认使用当前路径：$current_dir"
      echo "$current_dir"
      return 0
      ;;
  esac
}

script_source="${BASH_SOURCE[0]-$0}"
script_dir="$(cd "$(dirname "$script_source")" && pwd)"
install_dir="$(ask_install_dir)"
if [ -n "$install_dir" ]; then
  mkdir -p "$install_dir" 2>/dev/null || true
fi
if [ ! -w "$install_dir" ]; then
  echo "警告：安装路径不可写：$install_dir"
  echo "将回退为推荐路径。"
  install_dir="$(pick_install_dir)"
  mkdir -p "$install_dir" 2>/dev/null || true
fi

missing_deps="$(collect_missing_deps)"
missing_deps="$(printf "%s" "$missing_deps" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
if [ -n "$missing_deps" ]; then
  if try_install_missing_deps "$missing_deps"; then
    missing_deps="$(collect_missing_deps)"
    missing_deps="$(printf "%s" "$missing_deps" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
  fi
  warn_missing_deps "$missing_deps"
fi

src_path=""
force_remote="${FORCE_REMOTE:-0}"
if [ "$force_remote" = "1" ]; then
  src_path=""
else
  if [ -f "$script_dir/$SCRIPT_NAME" ]; then
    src_path="$script_dir/$SCRIPT_NAME"
  fi
fi

if [ -z "$src_path" ]; then
  if ! need_cmd curl; then
    echo "未检测到 curl，无法下载脚本。" >&2
    exit 1
  fi
  tmp="$(mktemp)"
  curl -fsSL "$REPO_RAW_URL" -o "$tmp"
  src_path="$tmp"
fi

install_path="$install_dir/$SCRIPT_NAME"
cp "$src_path" "$install_path"
chmod +x "$install_path"
ln -sf "$install_path" "$install_dir/$ALIAS_NAME"

if [ "${src_path:-}" = "${tmp:-}" ]; then
  rm -f "$tmp"
fi

echo "已安装：$install_path"
echo "已创建命令：$install_dir/$ALIAS_NAME"

if ! echo "$PATH" | tr ':' '\n' | grep -Fx "$install_dir" >/dev/null 2>&1; then
  echo "注意：$install_dir 不在 PATH 中。请将其加入 PATH 或使用全路径运行。"
fi
