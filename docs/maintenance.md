# 🔄 维护管理指南

## 更新 Douzi

### 方式一：运行更新脚本（推荐）

安装后，随时通过更新脚本拉取最新版本：

```bash
bash ~/.douzi/update.sh
```

更新脚本自动完成以下步骤：

| 步骤 | 说明 |
|------|------|
| 📥 拉取最新代码 | `git pull`，自动暂存本地修改 |
| 🔨 重新编译菜单栏应用 | `cd macos-tray && swift build` |
| 🖥️ 更新命令行启动器 | 更新 `~/.local/bin/douzi` |
| 📱 更新 Launchpad 入口 | 更新 `~/Applications/Douzi.app` |
| 🔄 重启服务 | 自动重启菜单栏应用和 Node.js 看板服务 |

若更新后遇到问题，可尝试手动重编：

```bash
cd ~/.douzi/macos-tray && swift build
```

### 方式二：手动更新

```bash
cd ~/.douzi
git pull
cd macos-tray
swift build
```

## 卸载 Douzi

```bash
bash ~/.douzi/uninstall.sh
```

卸载脚本会执行以下清理：

### 1. 停止运行中的进程

- `DouziMenuBar` — macOS 菜单栏应用进程
- Node.js 服务进程（`node server.mjs` from `~/.douzi/`）

### 2. 删除安装文件

| 路径 | 内容 |
|------|------|
| `~/.douzi/` | 整个安装目录（代码 + 构建产物） |
| `~/.local/bin/douzi` | CLI 命令行启动器 |
| `~/Applications/Douzi.app` | Launchpad 启动入口 |

### 3. 清理系统配置

- **Shell PATH** — 移除 `~/.local/bin` 的 PATH 添加（从 `.zshrc`/`.bashrc` 中删除）
- **Crontab** — 移除与 Douzi 相关的定时任务

### 4. 数据保留提示

交互模式下（直接运行脚本而非 `curl | bash`），脚本会询问是否保留 `knowledge-base/` 下的 GTD 数据：
- 选择 **y** — 保留目录下的所有笔记和任务
- 选择 **N**（默认）— 全部删除

> ⚠️ 通过 `curl -fsSL .../uninstall.sh | bash` 管道方式运行时，所有数据将被直接删除。

### 5. 重装

卸载后如需重新安装：

```bash
curl -fsSL https://raw.githubusercontent.com/seuwangcy/Douzi/main/install.sh | bash
```

## 查看安装与运行状态

```bash
# 查看安装位置
ls -la ~/.douzi

# 查看当前 Git 版本
cd ~/.douzi && git log --oneline -1

# 检查菜单栏应用是否运行
pgrep -x "DouziMenuBar" && echo "✅ 菜单栏应用运行中" || echo "❌ 菜单栏应用已停止"

# 检查看板服务是否运行
lsof -i :5000 -P -n 2>/dev/null | grep LISTEN && echo "✅ 看板服务运行中" || echo "❌ 看板服务未启动"
```
