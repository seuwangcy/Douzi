#!/usr/bin/env node

/**
 * AI 辅助整理脚本 — 自动将 Inbox 中的内容分类到对应 GTD 目录
 *
 * 用法:
 *   node ai-process.mjs              整理所有未处理的 inbox
 *   node ai-process.mjs --dry-run    试运行，不实际移动文件
 *   node ai-process.mjs --file X.md  只处理指定文件
 *
 * 也可以从其它模块导入使用:
 *   import { organizeInbox } from "./ai-process.mjs";
 *   const result = await organizeInbox({ dryRun: false, baseDir });
 */

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_BASE_DIR = process.env.DOUZI_KNOWLEDGE_BASE_DIR || path.join(os.homedir(), ".douzi", "knowledge-base", "gtd");
const CONFIG_PATH = path.join(os.homedir(), ".douzi", "config.json");

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function getAIProvider() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const config = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8"));
      if (config.aiProvider) return config.aiProvider;
    }
  } catch {}
  return "gemini";
}

async function callGemini(tasksText, skill = "") {
  const { spawnSync } = await import("node:child_process");

  const instructions = skill
    ? `请严格按照以下 SKILL.md 规则整理任务：\n\n${skill}\n\n`
    : "";

  const prompt = `${instructions}待整理的任务内容：\n\n${tasksText}\n\n请分析每个任务，输出整理结果。\n\n**严格只输出一个 JSON 数组，不要任何其他文字。** 格式：\n[
  {"file":"原文件名.md","action":"moved|updated|skipped","target_dir":"目标列目录名","priority":"P0|P1|P2|P3","title":"精炼标题","tags":["标签1"],"reason":"整理理由"},
  ...
]`;

  console.log("🤖 调用 Gemini AI 整理中...");

  const result = spawnSync("gemini", [
    "-p", prompt,
    "--yolo",
    "--output-format=json"
  ], {
    encoding: "utf-8",
    timeout: 180000,
    maxBuffer: 50 * 1024 * 1024,
    stdio: ["pipe", "pipe", "pipe"]
  });

  const rawOutput = (result.stdout || "").trim();
  if (!rawOutput) {
    if (result.error) throw new Error("Gemini 执行失败: " + result.error.message);
    throw new Error("Gemini 返回空输出");
  }

  let parsed;
  try {
    parsed = JSON.parse(rawOutput);
  } catch {
    return { rawOutput, actions: null, error: "Gemini 返回格式异常" };
  }

  const aiReply = parsed.response || "";
  if (!aiReply.trim()) {
    return { rawOutput, actions: null, error: "Gemini 未返回内容" };
  }

  let cleanReply = aiReply.replace(/```(?:json)?\s*\n/g, "").replace(/\n```\s*$/g, "");
  cleanReply = cleanReply.trim();

  let actions = null;
  const startIdx = cleanReply.indexOf("[");
  if (startIdx !== -1) {
    let depth = 0;
    let endIdx = -1;
    let inStr = false;
    let escape = false;
    for (let i = startIdx; i < cleanReply.length; i++) {
      const ch = cleanReply[i];
      if (escape) { escape = false; continue; }
      if (ch === "\\") { escape = true; continue; }
      if (ch === '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (ch === "[") depth++;
      else if (ch === "]") depth--;
      if (depth === 0) { endIdx = i; break; }
    }
    if (endIdx !== -1) {
      try { actions = JSON.parse(cleanReply.slice(startIdx, endIdx + 1)); }
      catch { actions = null; }
    }
  }

  if (!actions || !Array.isArray(actions)) {
    return { rawOutput, actions: null, error: "AI 回复中未找到有效 JSON 数组" };
  }

  return { rawOutput, actions, error: null };
}

async function callClaude(tasksText, skill = "") {
  const { spawnSync } = await import("node:child_process");

  const instructions = skill
    ? `请严格按照以下 SKILL.md 规则整理任务：\n\n${skill}\n\n`
    : "";

  const prompt = `${instructions}待整理的任务内容：\n\n${tasksText}\n\n请分析每个任务，输出整理结果。\n\n**严格只输出一个 JSON 数组，不要任何其他文字。** 格式：\n[\n  {"file":"原文件名.md","action":"moved|updated|skipped","target_dir":"目标列目录名","priority":"P0|P1|P2|P3","title":"精炼标题","tags":["标签1"],"reason":"整理理由"},\n  ...\n]`;

  console.log("🤖 调用 Claude AI 整理中...");

  const result = spawnSync("claude", [
    "-p", prompt,
    "--output-format=json"
  ], {
    encoding: "utf-8",
    timeout: 180000,
    maxBuffer: 50 * 1024 * 1024,
    stdio: ["pipe", "pipe", "pipe"]
  });

  const rawOutput = (result.stdout || "").trim();
  if (!rawOutput) {
    if (result.error) throw new Error("Claude 执行失败: " + result.error.message);
    throw new Error("Claude 返回空输出");
  }

  let parsed;
  try {
    parsed = JSON.parse(rawOutput);
  } catch {
    return { rawOutput, actions: null, error: "Claude 返回格式异常" };
  }

  const aiReply = parsed.response || "";
  if (!aiReply.trim()) {
    return { rawOutput, actions: null, error: "Claude 未返回内容" };
  }

  let cleanReply = aiReply.replace(/```(?:json)?\s*\n/g, "").replace(/\n```\s*$/g, "");
  cleanReply = cleanReply.trim();

  let actions = null;
  const startIdx = cleanReply.indexOf("[");
  if (startIdx !== -1) {
    let depth = 0;
    let endIdx = -1;
    let inStr = false;
    let escape = false;
    for (let i = startIdx; i < cleanReply.length; i++) {
      const ch = cleanReply[i];
      if (escape) { escape = false; continue; }
      if (ch === "\\") { escape = true; continue; }
      if (ch === '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (ch === "[") depth++;
      else if (ch === "]") depth--;
      if (depth === 0) { endIdx = i; break; }
    }
    if (endIdx !== -1) {
      try { actions = JSON.parse(cleanReply.slice(startIdx, endIdx + 1)); }
      catch { actions = null; }
    }
  }

  if (!actions || !Array.isArray(actions)) {
    return { rawOutput, actions: null, error: "AI 回复中未找到有效 JSON 数组" };
  }

  return { rawOutput, actions, error: null };
}

async function callAI(tasksText, skill = "") {
  const provider = getAIProvider();
  if (provider === "claude") {
    return callClaude(tasksText, skill);
  }
  return callGemini(tasksText, skill);
}

function applyActions(actions, inboxDir, baseDir, dryRun = false) {
  const summary = { total: actions.length, moved: 0, updated: 0, skipped: 0, details: [] };

  for (const action of actions) {
    if (!action.file || action.file === "summary") continue;

    if (action.action === "skipped") {
      summary.skipped++;
      summary.details.push(`⏭ ${action.file}: 已规范，跳过`);
      continue;
    }

    const fp = path.join(inboxDir, action.file);
    if (!fs.existsSync(fp)) {
      summary.details.push(`❌ ${action.file}: 文件不存在`);
      continue;
    }

    let content = fs.readFileSync(fp, "utf-8");
    const today = new Date().toISOString().slice(0, 10);
    const targetDir = action.target_dir || "inbox";
    const priority = action.priority || "P3";
    const title = action.title || "";
    const tags = action.tags || [];

    if (title) content = content.replace(/^title:\s*.+/m, `title: "${title}"`);
    content = content.replace(/^status:\s*.+/m, `status: "${targetDir}"`);
    content = content.replace(/^priority:\s*.+/m, `priority: "${priority}"`);
    if (content.match(/^updated:\s/m)) {
      content = content.replace(/^updated:\s*.+/m, `updated: ${today}`);
    } else {
      content = content.replace(/^created:\s*.+/m, m => m + `\nupdated: ${today}`);
    }
    if (tags.length > 0) {
      const tagStr = "[" + tags.map(t => `"${t}"`).join(", ") + "]";
      if (content.match(/^tags:\s/m)) {
        content = content.replace(/^tags:\s*.+/m, `tags: ${tagStr}`);
      } else {
        content = content.replace(/^created:\s*.+/m, m => m + `\ntags: ${tagStr}`);
      }
    }

    const newFp = path.join(baseDir, targetDir, action.file);
    ensureDir(path.dirname(newFp));
    if (!dryRun) {
      fs.writeFileSync(newFp, content, "utf-8");
      if (newFp !== fp) fs.unlinkSync(fp);
    }

    if (targetDir !== "inbox") summary.moved++;
    else summary.updated++;
    const dryTag = dryRun ? " [DRY RUN]" : "";
    summary.details.push(`✅${dryTag} ${action.file} → ${targetDir} [${priority}] ${action.reason || ""}`);
  }

  return summary;
}

/**
 * 组织（整理）收件箱中的任务
 *
 * @param {Object} options
 * @param {boolean} options.dryRun      是否仅试运行，不实际移动文件
 * @param {string|null} options.targetFile  只处理该文件（相对于 inbox）
 * @param {string} options.baseDir      GTD 根目录，默认 knowledge-base/gtd
 * @returns {{result: string, summary: Object}}
 */
export async function organizeInbox({ dryRun = false, targetFile = null, baseDir = DEFAULT_BASE_DIR } = {}) {
  const inboxDir = path.join(baseDir, "inbox");
  if (!fs.existsSync(inboxDir)) {
    return { result: "📭 收件箱为空，无需整理", summary: { total: 0, moved: 0, updated: 0, skipped: 0, details: [] } };
  }

  let files = fs.readdirSync(inboxDir).filter(f => f.endsWith(".md"));
  if (files.length === 0) {
    return { result: "📭 收件箱为空，无需整理", summary: { total: 0, moved: 0, updated: 0, skipped: 0, details: [] } };
  }

  if (targetFile) {
    if (!files.includes(targetFile)) {
      throw new Error(`文件 ${targetFile} 不存在于 inbox`);
    }
    files = [targetFile];
  }

  const skillPath = path.join(__dirname, ".agents", "skills", "organize-inbox", "SKILL.md");
  let skill = "";
  try { skill = fs.readFileSync(skillPath, "utf-8"); } catch {}

  const tasksText = files.map(f => {
    const content = fs.readFileSync(path.join(inboxDir, f), "utf-8");
    return `\n=== 文件: ${f} ===\n${content}`;
  }).join("\n");

  const { actions, error } = await callAI(tasksText, skill);

  if (error) {
    throw new Error(`${error}`);
  }

  const summary = applyActions(actions, inboxDir, baseDir, dryRun);
  const modeLabel = dryRun ? "[DRY RUN] " : "";
  const provider = getAIProvider();
  return {
    result: `🤖 ${modeLabel}${provider === "claude" ? "Claude" : "Gemini"} 已整理 ${summary.moved + summary.updated + summary.skipped} 项：\n` + summary.details.join("\n"),
    summary
  };
}


// ---- CLI 入口 --------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const fileIdx = args.indexOf("--file");
  const targetFile = fileIdx !== -1 ? args[fileIdx + 1] : null;

  try {
    const { result } = await organizeInbox({ dryRun, targetFile });
    console.log(result);
  } catch (e) {
    console.error("❌ 整理失败:", e.message);
    process.exit(1);
  }
}

main();
