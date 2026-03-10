#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/JY1003/Codex-core/main/codex-core"
SCRIPT_NAME="codex-core"
ALIAS_NAME="cx"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

warn_missing_deps() {
  local missing=()
  for cmd in bash curl jq python3; do
    if ! need_cmd "$cmd"; then
      missing+=( "$cmd" )
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf "警告：缺少依赖：%s\n" "${missing[*]}" >&2
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_dir="$(pick_install_dir)"

warn_missing_deps

src_path=""
if [ -f "$script_dir/$SCRIPT_NAME" ]; then
  src_path="$script_dir/$SCRIPT_NAME"
else
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
