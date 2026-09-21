# 自动化配方（Cookbook）

LidKeep 的 CLI 是普通命令行工具，因此可以被任何能跑 shell 的自动化接入：
快捷指令、SSH 远程脚本、LaunchAgent、Home Assistant、CI 等。下面是一组可直接套用的配方。

> 前提：CLI 已安装（一行安装脚本或 `brew install --cask hoodas101/tap/lidkeep`）。
> 大多数命令无副作用；涉及「黑屏」的命令在远程场景尤其有用。

---

## 1. 快捷指令（iPhone / Mac 一键黑屏）

用「运行 Shell 脚本」动作包一条命令：

- **熄屏（机器继续跑）：** `lidkeep off`
- **恢复屏幕：** `lidkeep on`
- **切换：** `lidkeep toggle`

把这两个做成一个「熄屏 / 亮屏」的切换快捷指令，放在主屏幕或 Apple Watch 上，
离开座位前点一下即可。

---

## 2. 远程 SSH：黑掉无人值守的 Mac 屏幕

在办公室/家里的 Mac 上保持远程可达，又不想屏幕一直亮着：

```bash
# 离开时（或放进一个「下班」脚本）：
ssh mac@home "lidkeep off"

# 回来时：
ssh mac@home "lidkeep on"
```

`lidkeep on` 在 SSH 上也能恢复菜单栏 App 熄掉的屏幕（两者共享状态）。
配合 `lidkeep status` 可检查远端电源与电量：

```bash
ssh mac@home "lidkeep status"
```

---

## 3. 合盖当作家用服务器 / 下载机

希望笔记本合盖后继续跑（下载、构建、远程访问），且内屏熄灭省电：

```bash
# 接电时：合盖保持唤醒
lidkeep plan --ac --lid nothing
# 想要更稳（电池+合盖也覆盖）需要先装特权 helper：
#   sudo lidkeep nosleep install-helper
#   lidkeep nosleep on --system
```

注意：合盖 + 电池 + 不睡是耗电最快的组合，已受电量下限保护（低于下限自动放手）。
长期合盖建议**接电源**。

---

## 4. Home Assistant / 监控面板

`lidkeep status` 输出可被解析。举例（HA 的 `command_line` 传感器，取是否黑屏）：

```yaml
sensor:
  - platform: command_line
    name: Study Mac Blackout
    command: "ssh mac@home 'lidkeep status' | grep -qi blacked && echo 1 || echo 0"
    scan_interval: 30
```

更稳妥的做法是让 HA 通过 `lidkeep doctor` 的 JSON 字段取值；`doctor` 会列出
显示控制、进程、残留等自检项，适合做成「这台 Mac 还正常吗」的看板。

---

## 5. LaunchAgent：开机即进入某种状态

若想开机后自动用某套电源方案（而不是等手动设置），写一个简单的 LaunchAgent
在登录后执行 `lidkeep plan ...`。注意 LidKeep 自身已经是一个登录项，
这里只是补充「登录后应用一次偏好」：

```xml
<!-- ~/Library/LaunchAgents/com.example.lidkeep-prefs.plist -->
<key>ProgramArguments</key>
<array>
  <string>/opt/homebrew/bin/lidkeep</string>
  <string>plan</string>
  <string>--ac</string>
  <string>--lid</string>
  <string>nothing</string>
</array>
<key>RunAtLoad</key><true/>
```

---

## 6. 与 `caffeinate` 的边界（演示/长任务）

LidKeep 的「保持屏幕常亮」(`keepDisplayOn`，`caffeinate -d`) 适合「屏幕必须整夜亮着」
的场景（如投屏演示）。若你只是想阻止系统睡眠而屏幕可以熄，`lidkeep off` + 方案里的
`keepAwake` 更省电。两种都可以和 `caffeinate` 叠加，不会冲突——LidKeep 持有的是
自己名下的断言，并带 owner accounting，不会误关别人的断言。

---

## 7. 排错配方

```bash
lidkeep doctor     # 一键自检：显示控制 / 进程 / 残留 / 远程软件占用
lidkeep status     # 当前状态、电源来源、电量、各断言持有情况
LIDKEEP_LANG=zh lidkeep doctor   # 强制中文输出（调试时方便对照）
```

如果 `disablesleep` 被某远程控制软件（ToDesk / UURemote / TeamViewer）占用，
`doctor` 会明确说「被远程软件持有」，而不是把它当残留让你去修——这种情况是正常的。
