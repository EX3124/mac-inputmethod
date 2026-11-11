# mac-inputmethod

让 **ABC 成为默认输入法**，并且**按 App 粘滞**：每个 App 默认是 ABC，你在某个 App 里换成拼音后，这个 App 会一直保持拼音（切走再切回来也一样），直到你**退出这个 App**。

macOS 自带的「自动切换到文稿的输入法」只能"记住"，做不到"退出即重置"；「Input Source Pro」这类工具在 macOS 26 上又容易引起 `CursorUIViewService` 无响应。这个项目用 200 行 Objective-C 自己实现，无第三方依赖、无常驻 GUI、资源占用可以忽略。

## 行为

| 情况 | 结果 |
|---|---|
| 切到一个没有记录的 App | **ABC** |
| 在某个 App 里手动换成拼音 | 记住，**该 App 保持拼音** |
| 切走再切回同一个 App（App 仍在运行） | 仍是**拼音** |
| 该 App 被退出（Cmd+Q / 崩溃），之后重新打开 | 回到 **ABC** |
| 在该 App 里手动切回 ABC | 清除记录，恢复"默认 ABC" |

记忆以**进程**为单位，只存在内存里：App 一退出记忆就没了。

## 环境要求

- macOS 13 或更高（在 macOS 26.7 上验证）
- Xcode Command Line Tools：`xcode-select --install`

## 安装

```bash
git clone <本仓库地址> mac-inputmethod
cd mac-inputmethod
./setup.sh
```

脚本会编译三个小工具、生成两个 LaunchAgent 并加载，同时把**简体拼音设为使用半角标点符号**（`, . ? !`），全程无需 sudo。

安装后可以实时观察它的判断：

```bash
tail -f ~/Library/Application\ Support/ABCInputSource/guard.log
```

典型输出：

```
11-10 13:43:13  计算器 中手动切到 com.apple.inputmethod.SCIM.ITABC → 记住，直到该 App 退出
11-10 13:43:16  访达 → 默认 com.apple.keylayout.ABC
11-10 13:43:18  计算器 → 恢复你在这个 App 里选的 com.apple.inputmethod.SCIM.ITABC
11-10 13:43:20  计算器 已退出 → 清除记忆，下次启动回到默认
```

## 换一个"默认输入法"

默认目标是 `com.apple.keylayout.ABC`。换成别的（比如你自己的英文输入法）：

```bash
TARGET_ID=com.apple.keylayout.U.S. ./setup.sh
```

查看系统里已启用的输入源 ID：

```bash
~/Library/Application\ Support/ABCInputSource/abc-current --list
```

## 简体拼音使用半角标点符号

安装时默认会把「简体拼音 → 使用半角标点符号」打开，这样打拼音时输出的是 `, . ? ! : ; ( )` 而不是 `，。？！：；（）`，写代码和中英混排时不用反复切换。

对应的系统偏好是：

```
com.apple.inputmethod.CoreChineseEngineFramework / usesHalfwidthPunctuation = true
```

（就是菜单栏输入法图标里那个「使用半角标点符号」勾选项的落点。）

不想要可以跳过：

```bash
HALFWIDTH_PUNCTUATION=0 ./setup.sh
```

安装时脚本会把改动前的值记在 `state.punctuation`，`uninstall.sh` 会自动还原。想手动关掉：

```bash
defaults write com.apple.inputmethod.CoreChineseEngineFramework usesHalfwidthPunctuation -bool false
pkill -x SCIM_Extension     # 让输入法引擎重读配置，会自动重启
```

## 卸载

```bash
./uninstall.sh
```

会停止并删除两个 LaunchAgent 与安装目录，不改动系统其它输入法设置。

## 组成

```
mac-inputmethod/
├── setup.sh              编译 + 安装
├── uninstall.sh          卸载
├── README.md
└── src/
    ├── abc-guard.m       常驻守护：按 App 粘滞地管理输入法
    ├── abc-select.c      切换当前输入源（带回读校验）
    └── abc-current.c     查看当前 / 已启用的输入源
```

安装到 `~/Library/Application Support/ABCInputSource/`，两个服务：

- `com.local.abc-inputsource-guard` —— 常驻（`KeepAlive`），实现粘滞规则
- `com.local.abc-default-inputsource` —— 登录时跑一次，把输入法设为默认

## 实现要点

- **用 Carbon TIS API 切换**（`TISSelectInputSource`）。单纯改 `com.apple.HIToolbox` 偏好再用 `killall TextInputMenuAgent` 是不够的 —— 实测配置文件改了，实际输入源并不会变。
- **以 PID 为记忆键**：这样"App 退出"天然等于"忘记"，重启后必然回到默认，不需要额外逻辑。
- **0.45 秒宽限期**：系统会在 App 激活后的一瞬间恢复它自己按文稿记住的输入法，宽限期内不记录用户选择，避免把系统的恢复误判成用户的手动操作；宽限期结束时再纠正一次。
- **200ms 轮询 + App 激活通知**：通知负责即时响应，轮询负责捕捉"用户在 App 内手动按了切换键"。
- **启动时不纠正**：服务重启（或登录后 guard 启动）只记录现状，不会把正在输入的中文打断。

## 已知边界

- **粒度是 App 级，不是窗口级。** 同一个 App 的多个窗口共享一个输入法状态。做窗口级需要「辅助功能」权限（`AXObserver` 监听 `kAXFocusedWindowChangedNotification`），而且保存对话框、sheet 等临时窗口会被误判，反而更烦人，故不采用。
- **切进 App 后 0.45 秒内换输入法会被吞掉**（宽限期）。正常使用不会碰到。
- 想减少"切换瞬间闪一下中文"的观感，可以关闭 `系统设置 → 键盘 → 输入法 → 编辑…` 里的「自动切换到文稿的输入法」，让系统不再做自己的记忆恢复。

## 排查

| 现象 | 检查 |
|---|---|
| 完全不生效 | `launchctl list \| grep abc-` 看服务在不在；看 `guard.err.log` |
| 切 App 不回到 ABC | `abc-current --list` 确认目标 ID 确实已启用 |
| 记不住拼音 | 确认切换时该 App 是前台，且距切进来已超过 0.45 秒 |
| 想临时关掉 | `launchctl bootout gui/$(id -u)/com.local.abc-inputsource-guard` |

## License

未指定。使用前请自行评估。
