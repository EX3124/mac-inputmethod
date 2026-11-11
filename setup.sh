#!/bin/bash
#
# mac-inputmethod —— 安装脚本
#
# 做三件事：
#   1. 把 src/ 里的源码编译成三个小工具，装到
#      ~/Library/Application Support/ABCInputSource/
#   2. 生成并加载两个 LaunchAgent：
#        com.local.abc-inputsource-guard  常驻，按 App 粘滞地管理输入法
#        com.local.abc-default-inputsource 登录时跑一次，设定默认输入法
#   3. 校验并打印当前状态
#
# 用法：
#   ./setup.sh
#   TARGET_ID=com.apple.keylayout.ABC ./setup.sh    # 自定义"默认输入法"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/ABCInputSource"
AGENT_DIR="$HOME/Library/LaunchAgents"
GUARD_LABEL="com.local.abc-inputsource-guard"
LOGIN_LABEL="com.local.abc-default-inputsource"
GUARD_PLIST="$AGENT_DIR/$GUARD_LABEL.plist"
LOGIN_PLIST="$AGENT_DIR/$LOGIN_LABEL.plist"
TARGET_ID="${TARGET_ID:-com.apple.keylayout.ABC}"
UID_NUM="$(id -u)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 环境检查 ----------
[ "$(uname -s)" = "Darwin" ] || die "本脚本只能在 macOS 上运行。"

if ! command -v clang >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
    die "缺少编译工具链。请先执行：xcode-select --install"
fi

info "默认输入法目标：$TARGET_ID"

# ---------- 编译 ----------
info "编译小工具……"
mkdir -p "$INSTALL_DIR" "$AGENT_DIR"

clang -O2 -Wall -framework Carbon \
      -o "$INSTALL_DIR/abc-select" "$SCRIPT_DIR/src/abc-select.c"
clang -O2 -Wall -framework Carbon \
      -o "$INSTALL_DIR/abc-current" "$SCRIPT_DIR/src/abc-current.c"
clang -fobjc-arc -O2 -Wall -framework Cocoa -framework Carbon \
      -o "$INSTALL_DIR/abc-guard" "$SCRIPT_DIR/src/abc-guard.m"
ok "已安装到 $INSTALL_DIR"

# ---------- 目标输入源是否存在 ----------
if ! "$INSTALL_DIR/abc-current" --list | grep -qx "$TARGET_ID"; then
    warn "系统里当前没有启用 $TARGET_ID"
    warn "请先到「系统设置 → 键盘 → 输入法」添加它，否则切换不会生效。"
fi

# ---------- 简体拼音：使用半角标点符号 ----------
# Apple 内部键：com.apple.inputmethod.CoreChineseEngineFramework / usesHalfwidthPunctuation
# 对应菜单栏「简体拼音 → 使用半角标点符号」。
# 用 HALFWIDTH_PUNCTUATION=0 ./setup.sh 可跳过。
PUNCT_DOMAIN="com.apple.inputmethod.CoreChineseEngineFramework"
PUNCT_KEY="usesHalfwidthPunctuation"
PUNCT_STATE="$INSTALL_DIR/state.punctuation"

if [ "${HALFWIDTH_PUNCTUATION:-1}" = "1" ]; then
    if "$INSTALL_DIR/abc-current" --list | grep -qx "com.apple.inputmethod.SCIM.ITABC"; then
        prev="$(defaults read "$PUNCT_DOMAIN" "$PUNCT_KEY" 2>/dev/null || echo unset)"
        if [ "$prev" = "1" ]; then
            ok "简体拼音「使用半角标点符号」已是开启状态"
        else
            # 记录原值，方便 uninstall.sh 还原
            printf '%s\n' "$prev" > "$PUNCT_STATE"
            defaults write "$PUNCT_DOMAIN" "$PUNCT_KEY" -bool true
            # 让输入法引擎重读偏好
            if pgrep -qx SCIM_Extension; then
                pkill -x SCIM_Extension 2>/dev/null || true
                sleep 1
            fi
            ok "已开启简体拼音「使用半角标点符号」（原值：${prev}，卸载时会还原）"
        fi
    else
        warn "系统里没有启用简体拼音（com.apple.inputmethod.SCIM.ITABC），跳过半角标点设置"
    fi
fi

# ---------- 生成 LaunchAgent ----------
info "写入 LaunchAgent……"

cat > "$GUARD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$GUARD_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$INSTALL_DIR/abc-guard</string>
		<string>$TARGET_ID</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>10</integer>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardErrorPath</key>
	<string>$INSTALL_DIR/guard.err.log</string>
</dict>
</plist>
PLIST

cat > "$LOGIN_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LOGIN_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$INSTALL_DIR/abc-select</string>
		<string>$TARGET_ID</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
PLIST

plutil -lint "$GUARD_PLIST" >/dev/null || die "生成的 plist 格式有误"
plutil -lint "$LOGIN_PLIST" >/dev/null || die "生成的 plist 格式有误"
ok "已写入 $AGENT_DIR"

# ---------- 加载 ----------
info "加载服务……"
launchctl bootout "gui/$UID_NUM/$GUARD_LABEL" 2>/dev/null || true
launchctl bootout "gui/$UID_NUM/$LOGIN_LABEL" 2>/dev/null || true

launchctl bootstrap "gui/$UID_NUM" "$GUARD_PLIST"
launchctl bootstrap "gui/$UID_NUM" "$LOGIN_PLIST"

sleep 1
launchctl list | grep -q "$GUARD_LABEL" || die "守护进程没有启动成功，看日志：$INSTALL_DIR/guard.err.log"
ok "服务已启动"

# ---------- 完成 ----------
CURRENT="$("$INSTALL_DIR/abc-current" 2>/dev/null || echo '读取失败')"
if [ "$(defaults read "$PUNCT_DOMAIN" "$PUNCT_KEY" 2>/dev/null || echo 0)" = "1" ]; then
    PUNCT_STATUS="已开启（半角 , . ? !）"
else
    PUNCT_STATUS="未开启（全角 ，。？！）"
fi

cat <<DONE

─────────────────────────────────────────────
安装完成。

  当前输入源   $CURRENT
  简体拼音标点 $PUNCT_STATUS
  守护日志     $INSTALL_DIR/guard.log
  实时查看     tail -f "$INSTALL_DIR/guard.log"

行为规则：
  · 切到一个没记录过的 App → 用 $TARGET_ID
  · 在某 App 里手动换成中文输入法 → 该 App 保持，直到它被退出
  · App 退出后重新打开 → 回到 $TARGET_ID

卸载：$SCRIPT_DIR/uninstall.sh
─────────────────────────────────────────────
DONE
