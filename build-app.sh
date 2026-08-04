#!/usr/bin/env bash
# 把 swift build 的 release 二进制组装成可双击的 .app（ad-hoc 签名，本地用）。
set -euo pipefail
cd "$(dirname "$0")"

BIN=SystemMonitor
APP="${BIN}.app"
BUNDLE_ID="com.personal.systemmonitor"

echo "==> swift build -c release"
swift build -c release

REL_BIN=".build/release/${BIN}"
if [[ ! -x "${REL_BIN}" ]]; then
  echo "release 二进制未找到: ${REL_BIN}" >&2
  exit 1
fi

echo "==> 组装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${REL_BIN}" "${APP}/Contents/MacOS/${BIN}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"

echo "==> ad-hoc 签名"
codesign --force --sign - "${APP}" 2>/dev/null \
  || codesign --force --deep --sign - "${APP}" 2>/dev/null \
  || echo "  (codesign 跳过 — 可能未勾选命令行工具权限)"

echo
echo "完成: ${APP}"
echo "运行:  open ${APP}"
echo "开机自启: 打开后在「系统设置 > 通用 > 登录项」确认 SystemMonitor 已启用"
