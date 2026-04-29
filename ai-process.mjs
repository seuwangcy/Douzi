#!/usr/bin/env node

/**
 * AI 辅助整理脚本 — 自动将 Inbox 中的内容分类到对应 GTD 目录
 *
 * 用法:
 *   node ai-process.mjs              整理所有未处理的 inbox
 *   node ai-process.mjs --dry-run    试运行，不实际移动文件
 *   node ai-process.mjs --file X.md  只处理指定文件
 *
 * 需要设置环境变量:
 *   AI_PROVIDER=openai|google|anthropic
 *   API_KEY=your-key
 *   AI_MODEL=your-model (可选)
 *
 * 注意: 本脚本是 AI 整理的接口骨架，需接入具体的 LLM API。
 *       当前版本使用本地启发式分类作为默认 fallback。
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BASE_DIR = path.join(__dirname, 'knowledge-base', 'gtd');
const INBOX_DIR = path.join(BASE_DIR, 'inbox');

// ---- Classification --------------------------------------------------------

const KEYWORDS = {
  waiting_for: ['等', '等待', '催', '同事', 'review', '审批', '回复', '对方', 'design'],
  project: ['项目', '规划', '体系', '搭建', '方案', '重构', '迁移', '升级', 'q2', '季度'],
  reference: ['笔记', '学习', '资料', '整理', '指南', '教程', '研究', '调研'],
  done: ['完成', 'done', '已做'],
};

function classifyByContent(content) {
  const lower = content.toLowerCase();

  for (const [category, kws] of Object.entries(KEYWORDS)) {
    for (const kw of kws) {
      if (lower.includes(kw)) return category;
    }
  }
  return 'next_actions';
}

function assignPriority(content) {
  const lower = content.toLowerCase();
  if (/紧急|urgent|urgent|火烧眉毛|p0|blocker/i.test(lower)) return 'P0';
  if (/重要|important|关键|必须|deadline/i.test(lower)) return 'P1';
  if (/一般|普通|normal|有空/i.test(lower)) return 'P3';
  return 'P2';
}

function extractTags(content) {
  const tags = [];
  const tagMap = {
    'AI': /AI|智能|模型|gpt|gemini/i,
    '技术': /技术|代码|开发|bug|fix|server|api/i,
    '调研': /调研|研究|竞品|方案/i,
    '学习': /学习|笔记|教程|文档/i,
    '项目': /项目|规划|目标|指标/i,
    '设计': /设计|ui|ux|交互|视觉/i,
    '等待': /等|催|审批|回复/i,
  };
  for (const [tag, re] of Object.entries(tagMap)) {
    if (re.test(content)) tags.push(tag);
  }
  return tags;
}

// ---- API Stub (接入真实 LLM) ------------------------------------------------

async function aiClassify(content) {
  const provider = process.env.AI_PROVIDER || 'local';

  if (provider === 'openai') {
    // TODO: OpenAI API 接入
    console.warn('⚠️ OpenAI API 尚未接入，使用本地启发式分类');
  } else if (provider === 'google') {
    // TODO: Google Gemini API 接入
    console.warn('⚠️ Gemini API 尚未接入，使用本地启发式分类');
  } else if (provider === 'anthropic') {
    // TODO: Claude API 接入
    console.warn('⚠️ Claude API 尚未接入，使用本地启发式分类');
  }

  const category = classifyByContent(content);
  const priority = assignPriority(content);
  const tags = extractTags(content);

  const dirMap = {
    waiting_for: 'waiting_for',
    project: 'projects',
    reference: 'reference',
    done: 'done',
    next_actions: 'next_actions',
  };

  return {
    targetDir: dirMap[category] || 'next_actions',
    priority,
    tags,
    reason: `本地分类: ${category}`,
  };
}

// ---- Processing ------------------------------------------------------------

function readFileMeta(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const title = path.basename(filePath, '.md').replace(/^\d{4}-\d{2}-\d{2}[-_]\d{4}-?/, '').replace(/[-_]/g, ' ');
  return { content, title, filepath: filePath };
}

function updateFileMeta(item, result) {
  const { content, title, filepath } = item;
  const today = new Date().toISOString().slice(0, 10);

  let updated = content;
  // Update status field in front matter
  updated = updated.replace(/^(status:\s*).+/m, `$1"${result.targetDir}"`);
  updated = updated.replace(/^(priority:\s*).+/m, `$1"${result.priority}"`);
  updated = updated.replace(/^(updated:\s*).+/m, `$1"${today}"`);

  if (result.tags.length > 0) {
    const tagStr = '[' + result.tags.map(t => `"${t}"`).join(', ') + ']';
    if (updated.match(/^tags:/m)) {
      updated = updated.replace(/^(tags:\s*).+/m, `$1${tagStr}`);
    } else {
      updated = updated.replace(/^(created:\s*).+/m, `$1${today}\ntags: ${tagStr}`);
    }
  }

  fs.writeFileSync(filepath, updated, 'utf-8');
}

function moveFile(filepath, targetDir) {
  const fileName = path.basename(filepath);
  const targetPath = path.join(BASE_DIR, targetDir, fileName);
  fs.renameSync(filepath, targetPath);
  return targetPath;
}

async function processInbox(dryRun, targetFile) {
  if (!fs.existsSync(INBOX_DIR)) {
    console.log('📥 Inbox 目录不存在，跳过');
    return;
  }

  const files = fs.readdirSync(INBOX_DIR).filter(f => f.endsWith('.md'));

  if (targetFile) {
    if (!files.includes(targetFile)) {
      console.log(`❌ 文件 ${targetFile} 不存在于 inbox`);
      process.exit(1);
    }
  }

  const toProcess = targetFile ? files.filter(f => f === targetFile) : files;

  if (toProcess.length === 0) {
    console.log('✨ Inbox 为空，所有任务已整理完毕！');
    return;
  }

  console.log(`🤖 开始处理 ${toProcess.length} 项...\n`);

  for (const f of toProcess) {
    const fp = path.join(INBOX_DIR, f);
    const item = readFileMeta(fp);

    const result = await aiClassify(item.content);

    if (dryRun) {
      console.log(`  [DRY RUN] ${f}`);
      console.log(`    → ${result.targetDir} [${result.priority}] ${result.tags.join(', ')}`);
      console.log(`    原因: ${result.reason}`);
      continue;
    }

    // Update front matter
    updateFileMeta(item, result);

    // Move file to target directory
    const newPath = moveFile(fp, result.targetDir);
    const newName = path.basename(newPath);

    console.log(`  ✅ ${f}`);
    console.log(`    → ${newName} [${result.priority}] ${result.tags.join(', ')}`);
  }

  console.log(`\n🎉 ${dryRun ? '试运行完成' : '整理完成'}！共处理 ${toProcess.length} 项。`);
}

// ---- CLI --------------------------------------------------------------------

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const fileIdx = args.indexOf('--file');
const targetFile = fileIdx !== -1 ? args[fileIdx + 1] : null;

processInbox(dryRun, targetFile);
