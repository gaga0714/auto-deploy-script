#!/usr/bin/env bash
#
# install.sh — 把 setup-site 安装到 /usr/local/bin
#
# 用法:
#   sudo bash scripts/install.sh              # 安装/升级
#   sudo bash scripts/install.sh --uninstall  # 卸载

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/setup-site.sh"
DST=/usr/local/bin/setup-site

[[ $EUID -eq 0 ]] || { echo "must run as root (use sudo)" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -e "$DST" ]]; then
    rm -f "$DST"
    echo "[install] removed $DST"
  else
    echo "[install] $DST not found, nothing to do"
  fi
  exit 0
fi

[[ -f "$SRC" ]] || { echo "source not found: $SRC" >&2; exit 1; }

install -m 0755 "$SRC" "$DST"
echo "[install] installed: $DST"
echo "[install] try: sudo setup-site --help"
