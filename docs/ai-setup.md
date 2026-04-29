# AI 辅助整理配置指南

## 概述

Douzi 的 AI 辅助功能可以自动将 Inbox 中的原始想法分类、打标、拆分到对应的 GTD 目录中，大幅降低手动整理的工作量。

## 支持的 AI 提供商

- OpenAI (GPT-4 / GPT-4o)
- Google Gemini
- Claude (Anthropic)

## 快速配置

### 方式一：环境变量

```bash
# OpenAI
export AI_PROVIDER=openai
export API_KEY=sk-your-key
export AI_MODEL=gpt-4o

# Google Gemini
export AI_PROVIDER=google
export API_KEY=your-gemini-key
export AI_MODEL=gemini-2.0-flash

# Claude
export AI_PROVIDER=anthropic  
export API_KEY=your-claude-key
export AI_MODEL=claude-sonnet-4-20250514
```

### 方式二：.env 文件

```bash
cp .env.example .env
# 编辑 .env 填入 API Key
```

## 使用方式

### 整理所有未处理的内容

```bash
# AI 分析 inbox/ 中所有文件并自动分类
node ai-process.mjs
```

### 整理指定文件

```bash
node ai-process.mjs --file 2026-04-29-新想法.md
```

### 试运行（不实际移动，只输出建议）

```bash
node ai-process.mjs —dry-run
```

## AI 分类逻辑

AI 会根据内容判断：

1. **P0/P1 紧急任务** → `next_actions/`（带 P0 或 P1 优先级）
2. **需要等待他人** → `waiting_for/`
3. **多步骤项目** → `projects/`
4. **纯资料/笔记** → `reference/`
5. **不确定** → 留在 `inbox/` 并建议下一步

## 输出示例

```
🤖 AI 已处理 5 项:
✅ inbox/2026-04-29-新需求.md → next_actions/ [P1] #AI #技术
✅ inbox/2026-04-29-等设计稿.md → waiting_for/ [P2] #设计 #等待
✅ inbox/2026-04-29-Q2规划.md → projects/ [P0] #项目 #规划
✅ inbox/2026-04-29-React笔记.md → reference/ [P3] #学习 #前端
✅ inbox/2026-04-29-随便记的idea.md → next_actions/ [P2] #想法
```

## 批量自动整理

```bash
# 每天自动运行一次（可加入 cron）
crontab -e
# 每天 20:00 执行 AI 整理
0 20 * * * cd /path/to/douzi && node ai-process.mjs
```
