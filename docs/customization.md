# 自定义与扩展指南

## 修改看板界面

### 改变颜色主题

编辑 `server.mjs` 中的 CSS 变量：

```css
:root {
  --bg: #f5f5f5;
  --col-bg: #e8e8e8;
  --card-bg: #ffffff;
  --primary: #4a90d9;
  --accent: #e74c3c;
}
```

### 隐藏特定列

在 `COLUMNS` 对象中注释掉不需要的列：

```javascript
const COLUMNS = {
  inbox: { title: '📥 收件箱', dir: 'inbox' },
  next_actions: { title: '🎯 下一步行动', dir: 'next_actions' },
  // waiting_for: { title: '⏳ 等待他人', dir: 'waiting_for' },
  // ...
};
```

## 扩展目录结构

### 添加新列

```javascript
const COLUMNS = {
  // ... existing columns ...
  learnings: { title: '📖 学习中', dir: 'learnings' },
};
```

然后在 `knowledge-base/gtd/` 下创建 `learnings/` 文件夹，并确保 `ai-process.mjs` 中的目标目录映射也包含该目录。

## 配置端口

```bash
# 默认是 5000
# 如需修改，编辑 server.mjs 底部:
const PORT = 5000;
```

或直接指定环境变量启动：
```bash
PORT=8080 node server.mjs
```

## 添加自定义模板

在 `docs/templates/` 中创建新的 `.md` 模板：

```yaml
---
title: "模板名称"
status: "next_actions"
priority: "P3"
created: 2026-04-29
tags: []
---

# 模板名称

## 描述

## 行动清单
- [ ]

## 参考
-
```

## Git 自动备份

```bash
# 添加到 crontab，每天自动提交
0 23 * * * cd /path/to/douzi && git add -A && git commit -m "Auto backup $(date +%Y-%m-%d)" && git push
```
