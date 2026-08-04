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
# 不再吞掉 stderr，签名失败直接报错退出（--deep 已被 Apple 标记为废弃，不再使用）。
if ! codesign --force --sign - "${APP}"; then
  echo "错误: codesign 失败。请确认已安装『命令行开发者工具』(xcode-select --install) 且终端有签名权限。" >&2
  exit 1
fi

echo
echo "完成: ${APP}"
echo "运行:  open ${APP}"
echo "开机自启: 打开后右键面板 → 勾选「开机自启」即可（注册的是当前这份 .app 的位置）"

# 可选：将 .app 安装到 /Applications，让登录项指向稳定路径（避免源码目录被清理后失效）。
if [[ "${1:-}" == "--install" ]]; then
  echo "==> 安装到 /Applications"
  rm -rf "/Applications/${APP}"
  cp -R "${APP}" "/Applications/"
  echo "已安装: /Applications/${APP}（从该副本启动后再开启开机自启即可）"
fi
