#!/bin/bash
#
# mac-inputmethod —— 卸载脚本
#
# 停止并删除两个 LaunchAgent，以及安装目录下的所有文件。
# 如果安装时改过「简体拼音 → 使用半角标点符号」，会还原成安装前的值。
#
# 用法：./uninstall.sh         （会询问确认）
#       ./uninstall.sh --yes   （不询问）
#
set -euo pipefail

INSTALL_DIR="$HOME/Library/Application Support/ABCInputSource"
AGENT_DIR="$HOME/Library/LaunchAgents"
GUARD_LABEL="com.local.abc-inputsource-guard"
LOGIN_LABEL="com.local.abc-default-inputsource"
UID_NUM="$(id -u)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

if [ "${1:-}" != "--yes" ]; then
    printf '将删除：\n'
    printf '  %s\n' "$AGENT_DIR/$GUARD_LABEL.plist"
    printf '  %s\n' "$AGENT_DIR/$LOGIN_LABEL.plist"
    printf '  %s\n' "$INSTALL_DIR"
    printf '继续？[y/N] '
    read -r ans
    case "$ans" in
        [yY]|[yY][eE][sS]) ;;
        *) printf '已取消。\n'; exit 0 ;;
    esac
fi

info "停止服务……"
launchctl bootout "gui/$UID_NUM/$GUARD_LABEL" 2>/dev/null || true
launchctl bootout "gui/$UID_NUM/$LOGIN_LABEL" 2>/dev/null || true
ok "服务已停止"

info "删除文件……"
PUNCT_DOMAIN="com.apple.inputmethod.CoreChineseEngineFramework"
PUNCT_KEY="usesHalfwidthPunctuation"
PUNCT_STATE="$INSTALL_DIR/state.punctuation"

if [ -f "$PUNCT_STATE" ]; then
    prev="$(cat "$PUNCT_STATE")"
    if [ -z "$prev" ] || [ "$prev" = "unset" ]; then
        defaults delete "$PUNCT_DOMAIN" "$PUNCT_KEY" 2>/dev/null || true
        ok "已清除「使用半角标点符号」设置"
    elif [ "$prev" = "1" ]; then
        defaults write "$PUNCT_DOMAIN" "$PUNCT_KEY" -bool true
        ok "已还原「使用半角标点符号」为开启"
    else
        defaults write "$PUNCT_DOMAIN" "$PUNCT_KEY" -bool false
        ok "已还原「使用半角标点符号」为关闭"
    fi
    if pgrep -qx SCIM_Extension; then
        pkill -x SCIM_Extension 2>/dev/null || true
        sleep 1
    fi
else
    ok "没有需要还原的输入法偏好"
fi

rm -f "$AGENT_DIR/$GUARD_LABEL.plist"
rm -f "$AGENT_DIR/$LOGIN_LABEL.plist"
rm -rf "$INSTALL_DIR"
ok "已删除"

cat <<'DONE'

─────────────────────────────────────────────
卸载完成。

注意：脚本会还原安装时改过的「使用半角标点符号」，
      但不会恢复「按 App 记忆输入法」。如需恢复后者，打开：
      系统设置 → 键盘 → 输入法 → 编辑… → 勾选「自动切换到文稿的输入法」
─────────────────────────────────────────────
DONE
