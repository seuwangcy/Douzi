# AI 辅助整理配置指南

## 概述

Douzi 的 AI 整理功能使用 **Gemini CLI 工具** 自动分析 Inbox 中的任务内容，并将其分类到对应的 GTD 目录中（next_actions、waiting_for、projects、done、reference 等），同时自动设置优先级和标签。

## 前置条件

1. **安装 Gemini CLI**

   确保系统 PATH 中有 `gemini` 命令。可以通过 `npm install -g @google/gemini-cli` 或 Google Cloud SDK 安装。

2. **配置 Gemini 认证**

   根据 Gemini CLI 的指引完成 API Key 配置。

## 使用方式

### 方式一：Web 看板一键整理（推荐）

打开 http://localhost:5000，点击看板右上角的 **「✨ 一键整理」** 按钮。

前端发送 POST 请求到 `/api/organize`，服务器动态调用 `ai-process.mjs` 中的 `organizeInbox` 函数，AI 自动整理后弹窗显示结果并刷新页面。

### 方式二：命令行直接运行

```bash
# 整理 inbox 中所有未处理文件
node ai-process.mjs

# 只整理指定文件
node ai-process.mjs --file 2026-04-29-新想法.md

# 试运行（预览整理结果，不实际移动文件）
node ai-process.mjs --dry-run
```

### 方式三：模块导入使用

`ai-process.mjs` 导出了 `organizeInbox` 函数，支持在其它 Node.js 脚本中调用：

```javascript
import { organizeInbox } from './ai-process.mjs';

// 整理所有 inbox 文件
const { result, summary } = await organizeInbox();
console.log(result);

// 试运行（只预览，不移动文件）
const { result } = await organizeInbox({ dryRun: true });

// 指定自定义 baseDir
const { result } = await organizeInbox({ baseDir: '/path/to/knowledge-base/gtd' });

// 只处理单个文件
const { result } = await organizeInbox({ targetFile: '2026-04-29-新想法.md' });
```

### 方式四：定时自动整理

```bash
# 加入 crontab，每天 20:00 自动整理
crontab -e
# 添加行：
0 20 * * * cd /path/to/douzi && node ai-process.mjs
```

## AI 分类逻辑

Gemini AI 会分析任务内容的语义，自动判断：

1. **紧急/高优先级任务** → `next_actions/`（带 P0 或 P1 优先级）
2. **需要等待他人** → `waiting_for/`
3. **多步骤项目** → `projects/`
4. **纯资料/笔记** → `reference/`
5. **已完成/无需行动** → `done/`
6. **不确定** → 留在 `inbox/` 并附整理理由

## 输出结构

整理完成后返回的结构包含：

```json
{
  "result": "🤖 Gemini 已整理 5 项：\n✅ 文件1.md → next_actions [P1] 需要尽快执行\n✅ 文件2.md → waiting_for [P2] 等待设计回复\n⏭ 文件3.md: 已规范，跳过",
  "summary": {
    "total": 5,
    "moved": 2,
    "updated": 0,
    "skipped": 1,
    "details": ["..."]
  }
}
```

## 常见问题

**Q: AI 整理失败怎么办？**

A: 确保 `gemini` 命令在系统 PATH 中，并检查网络连接。也可添加 `--dry-run` 先测试。

**Q: 可以更换 AI 提供商吗？**

A: 当前版本统一使用 Gemini CLI 工具。如需接入其它 AI（OpenAI、Claude 等），可修改 `ai-process.mjs` 中的 `callGemini` 函数。

**Q: 整理结果不满意可以撤销吗？**

A: 建议先用 `--dry-run` 预览，确认后再执行正式整理。所有 Markdown 文件纳入 Git，整理前 commit 可随时回滚。
