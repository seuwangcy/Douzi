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

## macOS Launchpad 图标优化

将自定义图片转换为符合 macOS Launchpad 风格的图标（squircle 圆角矩形 + 透明边距），需要遵循以下方法论。

### 设计规范（来源：Apple HIG + 系统图标实测）

| 参数 | 规范值 | 说明 |
|------|--------|------|
| 画布尺寸 | 1024x1024 px | macOS 标准图标尺寸 |
| 透明边距 | 每边约 10%（~100px） | 实测系统图标（Calculator、Chess 等）一致为 ~9.8% |
| 内容区域 | 824x824 px | 画布减去两侧边距 |
| 圆角半径 | 内容宽度的 22.37%（~184px） | macOS squircle（超椭圆）风格 |

### 制作流程

整体思路：**裁剪定位 → 圆角蒙版 → 透明边距 → 生成 icns**

#### 第一步：裁剪原图以调整主体位置和大小

原始图片中主体可能不居中、周围留白不均匀。通过四边独立裁剪来：
- **控制主体大小**：裁掉越多，缩放到固定内容区域后主体越大
- **控制主体位置**：上下裁剪量不同可纵向移动主体（下边裁更多 → 主体视觉下移），左右同理

这一步的参数需要根据原图内容**反复调试**——先粗调大方向，再微调至满意。关键原则：
- 保持左右裁剪量相等以维持水平居中
- 下边比上边多裁约 50-100px 可补偿人眼视觉重心偏上的错觉
- 每次调整后生成预览对比，逐步收敛

```bash
# 示例：原图 2048x2048，裁剪上250/左375/右375/下500
# 裁剪后宽度 = 2048-375-375 = 1298，高度 = 2048-250-500 = 1298
magick AppIcon.png -crop 1298x1298+375+250 +repage /tmp/icon_cropped.png
```

#### 第二步：缩放 + 圆角蒙版

将裁剪后的图像缩放到 824x824（内容区域），然后用圆角矩形蒙版裁剪。

```bash
# 缩放到内容区域尺寸
magick /tmp/icon_cropped.png -resize 824x824! /tmp/icon_resized.png

# 创建圆角蒙版（半径 184px）
magick -size 824x824 xc:none \
  -draw "roundrectangle 0,0 823,823 184,184" /tmp/mask_824.png

# 应用蒙版
magick /tmp/icon_resized.png /tmp/mask_824.png \
  -compose DstIn -composite /tmp/icon_masked.png
```

#### 第三步：添加透明边距

将圆角内容居中放置在 1024x1024 透明画布上，自动形成 100px 透明边距。

```bash
magick -size 1024x1024 xc:none /tmp/icon_masked.png \
  -gravity center -composite AppIcon_final.png
```

#### 第四步：生成 .icns 并部署

使用项目自带的构建脚本生成 icns：

```bash
# 从 AppIcon_final.png 生成 icns
./macos-tray/scripts/build-icon.sh
```

生成后将 `AppIcon_final.png` 和 `AppIcon.icns` 提交到 GitHub，用户通过 `douzi update` 自动获取更新。

### 构建工具 (build-icon.sh)

`macos-tray/scripts/build-icon.sh` 是图标资源的构建工具，封装了上述全部流程：

```bash
# 仅从已有的 AppIcon_final.png 生成 icns
./macos-tray/scripts/build-icon.sh

# 从原图走完全流程（裁剪+圆角+边距+icns）
./macos-tray/scripts/build-icon.sh --from-source

# 自定义裁剪参数（调试主体位置时使用）
CROP_TOP=250 CROP_LEFT=375 CROP_RIGHT=375 CROP_BOTTOM=500 \
  ./macos-tray/scripts/build-icon.sh --from-source
```

### 一条命令快速生成（手动方式）

如果不使用构建脚本，前三步也可以合并为一条管道命令：

```bash
# 参数说明：-crop 宽x高+左偏移+上偏移
# 宽 = 原图宽 - 左裁剪 - 右裁剪，高 = 原图高 - 上裁剪 - 下裁剪
# 以下示例对应裁剪参数：上250/左375/右375/下500
magick AppIcon.png \
  -crop 1298x1298+375+250 +repage \
  -resize 824x824! \
  \( -size 824x824 xc:none -draw "roundrectangle 0,0 823,823 184,184" \) \
  -compose DstIn -composite \
  -gravity center -extent 1024x1024 \
  AppIcon_final.png
```

需要调整时只需修改 `-crop` 参数，其余保持不变。

### Release 流程中的图标更新

当更新了 `macos-tray/Assets/` 中的原始设计稿后：

1. **调试裁剪参数** — 反复运行 `--from-source` 并调整 `CROP_*` 直到主体大小和位置满意
2. **生成资源文件** — `./macos-tray/scripts/build-icon.sh --from-source`
3. **提交产物** — 将以下文件一起提交到 GitHub：
   - `Assets/AppIcon_final.png` + `Resources/AppIcon.icns`（Launchpad 图标）
   - `Sources/DouziMenuBar/Resources/AppIcon_menubar{,@2x}.png`（Menu bar template 图标）
4. **用户侧生效** — 用户执行 `douzi update` 时自动获取

### 验证方法

```bash
# 检查 Launchpad 图标透明边距是否符合标准
magick AppIcon_final.png -channel Alpha -threshold 50% -trim \
  -format "margin_left=%[fx:page.x] margin_top=%[fx:page.y]" info:
# 期望：margin_left=100, margin_top=100
```

### 工具依赖

- **ImageMagick**（`brew install imagemagick`）：图像裁剪、缩放、蒙版（仅开发者构建时需要）
- **iconutil**（macOS 自带）：生成 .icns 文件

## macOS Menu Bar 图标

### 设计规范

| 参数 | 规范值 | 说明 |
|------|--------|------|
| 图标尺寸 | 18x18 pt | macOS menu bar 高度 22pt，图标留 2pt 上下内边距 |
| @1x 像素 | 18x18 px | 非 Retina 屏幕 |
| @2x 像素 | 36x36 px | Retina 屏幕 |
| 颜色 | 纯黑 + alpha 通道 | Template image，系统自动着色 |
| 格式 | PNG，带 alpha 通道 | 背景必须透明 |

### Template Image 机制

macOS 推荐使用 template image（`isTemplate = true`）来实现 menu bar 图标。其原理：

- 图像仅包含 **黑色 + alpha 通道**（黑色区域为图案，alpha 控制不透明度）
- macOS 系统根据当前外观模式自动着色：浅色主题渲染为深色、深色主题渲染为白色
- 点击高亮等交互状态也由系统自动处理
- **无需手动提供深色模式变体**，一张图即可适配所有场景

### 处理方法论

原始设计稿（`Assets/AppIcon_menubar.png`）通常是白色背景上的黑色图案。处理步骤：

1. **裁剪**：与 Launchpad 图标使用相同的裁剪参数，确保主体位置一致
2. **去白底透明化**：将图像转为灰度后反转，用亮度值作为 alpha 通道（白色→全透明，黑色→完全不透明），RGB 填充纯黑
3. **缩放**：分别缩放到 18x18（@1x）和 36x36（@2x）

关键命令：

```bash
# 去白底：灰度→反转→作为alpha，RGB填黑（生成 template image）
magick input.png -colorspace Gray -negate -alpha copy \
  -channel RGB -evaluate set 0 +channel output_template.png
```

### 资源文件

| 文件 | 用途 |
|------|------|
| `AppIcon_menubar.png` | Template image @1x (18x18) |
| `AppIcon_menubar@2x.png` | Template image @2x (36x36) |

代码中通过 `img.isTemplate = true` 标记后，macOS 自动处理浅色/深色/高亮等所有外观状态。

## Git 自动备份

```bash
# 添加到 crontab，每天自动提交
0 23 * * * cd /path/to/douzi && git add -A && git commit -m "Auto backup $(date +%Y-%m-%d)" && git push
```
