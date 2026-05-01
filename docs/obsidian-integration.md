# Obsidian / Foam 集成指南

## 知识库设计原则

Douzi 的知识库采用标准 Markdown + 双向链接规范，与任何 Markdown 笔记系统兼容。

## 核心规范

### 1. 文件头 — 标准 Front Matter

```yaml
---
title: "页面标题"
status: "project"
priority: "P1"
created: 2026-04-29
updated: 2026-04-29
tags: ["标签1", "标签2"]
---
```

兼容 Obsidian 的 Properties 插件和 Foam 的 YAML 头。

### 2. 双向链接

使用 `[[文件名]]` 语法：

```markdown
详见 [[AI搜项目规划]]
参考 [[2026-04-28-个人知识管理体系]]
```

### 3. 标签

使用 `#标签` 语法：

```markdown
这是一个 #AI 项目，涉及 #技术/#架构 方面的工作。
```

### 4. 任务列表

```markdown
- [ ] 未完成的任务
- [x] 已完成的任务
```

## Obsidian 集成

### 步骤 1：打开知识库作为 Obsidian Vault

```bash
# 在 Obsidian 中打开
# File → Open Folder → 选择 ~/.douzi/knowledge-base/gtd/
```

或者将整个 `douzi/` 作为 vault，Obsidian 会索引所有 Markdown 文件。

### 步骤 2：Obsidian 插件推荐

| 插件 | 用途 |
|------|------|
| **Dataview** | 查询/筛选 Markdown 中的 front matter |
| **Templater** | 使用 Douzi 的 `docs/templates/` 模板 |
| **Tasks** | Markdown 任务管理可视化 |
| **Calendar** | 日历视图，关联每日回顾 |
| **Backlinks** | 反向链接，追踪 [[双向链接]] |

### 步骤 3：Dataview 查询示例

在 Obsidian 中创建一个看板视图 Dashboard：

```markdown
## 🎯 下一步行动

```dataview
TABLE priority AS "优先级", tags AS "标签"
FROM "next_actions"
SORT priority ASC
```

## 📋 进行中的项目

```dataview
TABLE priority, updated
FROM "projects"
WHERE status != "done"
```
```

## Foam (VS Code) 集成

### 步骤 1：在 VS Code 中打开

1. 克隆仓库到本地
2. VS Code 打开 `douzi/` 目录
3. 安装 Foam 扩展

### 步骤 2：配置 .vscode/settings.json

```json
{
  "foam.files.root": "~/.douzi/knowledge-base/gtd",
  "foam.files.ignore": [
    "**/_TEMPLATE.md",
    "**/_README.md"
  ]
}
```

### 步骤 3：利用 Foam 功能

- **Graph Visualization** — 可视化知识图谱
- **Backlinks Panel** — 查看谁链接到了当前页面
- **Daily Notes** — 与 `daily_review/` 目录联动
- **Tag Explorer** — 按标签浏览知识

## 双向链接的最佳实践

### 1. 用日期前缀做唯一文件名

```
2026-04-29-AI搜项目规划.md
```

这样不同日期创建的同名文件不会冲突。

### 2. 跨文件引用

```markdown
## 关联项目
- 详见 [[2026-04-28-2257-AI搜Q2关键落地项和过程指标]]
- 参考 [[2026-04-28-个人知识管理体系]]
```

### 3. 知识地图

创建一个 `MAP_OF_CONTENT.md` 作为知识库入口：

```markdown
---
title: "知识地图"
---

# 🗺️ 知识地图

## 进行中项目
- [[2026-04-28-2257-AI搜Q2关键落地项和过程指标]]
- [[AI搜-项目看板]]

## 参考资料
- [[joyspace-云文档使用指南]]

## 每日回顾
- [[2026-04-28]]
```

## 同步方案

### Git 同步

```bash
git push  # 推送到 GitHub / 私有仓库
```

### 云盘同步

- iCloud Drive / Dropbox / OneDrive 同步整个仓库
- Obsidian 和 Douzi Web 看板共享同一份文件

### 手机同步

- Option A：NAS 部署 Douzi 看板，通过手机浏览器访问
- Option B：手机端用 Obsidian App 打开同步的 vault

## FAQ

**Q: 可以同时用 Obsidian 和 Douzi 看板编辑吗？**

A：完全可以！它们操作的是同一组 Markdown 文件。看板服务器读取的是本地文件系统，Obsidian 也是。任何一方修改，另一方刷新即可看到。

**Q: 双向链接能在 Web 看板中生效吗？**

A：当前看板对 `[[链接]]` 做了基础解析。未来会支持更完整的双向链接可视化。
