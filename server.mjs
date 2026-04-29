#!/usr/bin/env node

/**
 * GTD 看板服务器 - 零依赖，使用 Node.js 内置模块
 * 使用方式: node server.mjs
 * 然后浏览器打开 http://localhost:5000
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BASE_DIR = path.join(__dirname, 'knowledge-base', 'gtd');

const COLUMNS = {
  inbox: { title: '📥 收件箱', dir: 'inbox' },
  next_actions: { title: '🎯 下一步行动', dir: 'next_actions' },
  waiting_for: { title: '⏳ 等待他人', dir: 'waiting_for' },
  projects: { title: '📋 项目', dir: 'projects' },
  done: { title: '✅ 已完成', dir: 'done' },
  archived: { title: '📦 已归档', dir: 'archived' },
};

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function parseMD(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const meta = { title: path.basename(filePath, '.md'), status: 'inbox', priority: 'P3', tags: [], created: '', updated: '' };
    const fm = content.match(/^---\n([\s\S]*?)\n---\n?/);
    if (fm) {
      for (const line of fm[1].split('\n')) {
        const m = line.match(/^(\w+)\s*:\s*(.+)$/);
        if (m) {
          let key = m[1], val = m[2].trim();
          if (key === 'tags') {
            try { meta.tags = JSON.parse(val.replace(/'/g, '"')); } catch { meta.tags = val.replace(/[\[\]]/g, '').split(',').map(t => t.trim()).filter(Boolean); }
          } else {
            meta[key] = val.replace(/^"(.*)"$/, '$1');
          }
        }
      }
    }
    let body = fm ? content.slice(fm[0].length) : content;
    body = body.replace(/^#+\s*/gm, '').trim();
    const summary = body.replace(/\n+/g, ' ').slice(0, 200);
    const relPath = path.relative(BASE_DIR, filePath);
    return { meta, summary, filename: path.basename(filePath), relpath: relPath, content };
  } catch { return null; }
}

function getAllTasks() {
  const tasks = {};
  for (const key of Object.keys(COLUMNS)) tasks[key] = [];
  for (const [key, col] of Object.entries(COLUMNS)) {
    const dir = path.join(BASE_DIR, col.dir);
    if (fs.existsSync(dir)) {
      const files = fs.readdirSync(dir).filter(f => f.endsWith('.md')).sort().reverse();
      for (const f of files) {
        const task = parseMD(path.join(dir, f));
        if (task) {
          const st = task.meta.status;
          let target = key;
          for (const k of Object.keys(COLUMNS)) {
            if (st === k || st === COLUMNS[k].dir) { target = k; break; }
          }
          if (!tasks[target]) tasks[target] = [];
          tasks[target].push(task);
        }
      }
    }
  }
  return tasks;
}

function getReferenceFiles() {
  const dir = path.join(BASE_DIR, 'reference');
  const files = [];
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.md')).sort().reverse()) {
      const task = parseMD(path.join(dir, f));
      if (task) files.push(task);
    }
  }
  return files;
}

function getDailyReviews() {
  const dir = path.join(BASE_DIR, 'daily_review');
  const files = [];
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.md')).sort().reverse().slice(0, 30)) {
      const task = parseMD(path.join(dir, f));
      if (task) files.push(task);
    }
  }
  return files;
}

function mdToHtml(content) {
  let html = content
    .replace(/^---[\s\S]*?---\n?/, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
  html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');
  html = html.replace(/`(.+?)`/g, '<code>$1</code>');
  html = html.replace(/\[(.+?)\]\((.+?)\)/g, '<a href="$2" target="_blank">$1</a>');
  html = html.replace(/- \[( |x)\] (.+)/g, (m, c, t) => `<li><input type="checkbox" ${c === 'x' ? 'checked' : ''} disabled> ${t}</li>`);
  html = html.replace(/- (.+)/g, '<li>$1</li>');
  html = html.replace(/((?:<li>.*?<\/li>\s*)+)/g, '<ul>$1</ul>');
  html = html.replace(/\n\n/g, '</p><p>');
  return '<p>' + html + '</p>';
}

function renderHTML() {
  const tasks = getAllTasks();
  const refs = getReferenceFiles();
  const reviews = getDailyReviews();

  const visibleColumns = Object.entries(COLUMNS).filter(([key]) => key !== 'archived');
  const colHTML = visibleColumns.map(([key, col]) => {
    const items = (tasks[key] || []).map(t => {
      const pcls = (t.meta.priority || 'P3').toLowerCase();
      const tags = (t.meta.tags || []).map(tag => `<span class="tag">${tag}</span>`).join('');
      return `<div class="card" onclick="openModal('${t.relpath}')">
        <div class="card-title">${t.meta.title}</div>
        <div class="card-meta"><span class="priority-badge ${pcls}">${t.meta.priority || 'P3'}</span>${t.meta.created ? ' <span>' + t.meta.created.slice(0,10) + '</span>' : ''}</div>
        ${t.summary ? `<div class="card-summary">${t.summary}</div>` : ''}
        ${tags ? `<div>${tags}</div>` : ''}
      </div>`;
    }).join('');

    return `<div class="column col-${key}"><div class="column-header">${col.title} <span class="count">(${(tasks[key]||[]).length})</span></div>
      <div class="column-body">
        <div class="add-form" id="add-form-${key}" style="display:none;">
          <form onsubmit="addTask('${key}', event)">
            <input name="title" placeholder="任务标题" required>
            <textarea name="description" placeholder="描述（可选）"></textarea>
            <select name="priority"><option value="P0">P0 - 紧急</option><option value="P1">P1 - 高优</option><option value="P2" selected>P2 - 普通</option><option value="P3">P3 - 低优</option></select>
            <input name="tags" placeholder="标签（逗号分隔）">
            <button type="submit">添加</button>
          </form>
        </div>
        <span class="add-toggle" onclick="toggleAddForm('${key}')">+ 新增</span>
        ${items}
      </div></div>`;
  }).join('\n');

  const refItems = refs.map(r => `<div class="card" onclick="openModal('${r.relpath}')">
    <div class="card-title">${r.meta.title}</div>${r.summary ? `<div class="card-summary">${r.summary}</div>` : ''}
    ${(r.meta.tags||[]).length ? `<div>${r.meta.tags.map(t => `<span class="tag">${t}</span>`).join('')}</div>` : ''}
  </div>`).join('') || '<p style="color:var(--text-light);">暂无知识参考文件</p>';

  const reviewItems = reviews.map(r => `<div class="card" onclick="openModal('${r.relpath}')">
    <div class="card-title">${r.meta.title}</div>${r.summary ? `<div class="card-summary">${r.summary}</div>` : ''}
  </div>`).join('') || '<p style="color:var(--text-light);">暂无回顾记录</p>';

  return `<!DOCTYPE html><html lang="zh-CN"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>GTD 看板</title>
<style>
:root{--bg:#f0f2f5;--card-bg:#fff;--border:#e0e0e0;--text:#333;--text-light:#888;--accent:#4a6cf7;--accent-light:#eef1ff;--inbox:#ff9800;--next:#4a6cf7;--waiting:#9c27b0;--project:#00bcd4;--done:#4caf50;--p0:#e53935;--p1:#fb8c00;--p2:#43a047;--p3:#757575}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--text);line-height:1.5}
.header{background:linear-gradient(135deg,#4a6cf7,#6c63ff);color:#fff;padding:16px 24px;box-shadow:0 2px 8px rgba(0,0,0,.15);position:sticky;top:0;z-index:100}
.header-row{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:16px}
.header h1{font-size:20px;font-weight:700}
.header nav a{color:rgba(255,255,255,.85);text-decoration:none;margin-left:16px;font-size:14px;cursor:pointer;display:inline-block;padding:4px 8px;border-radius:4px}
.header nav a:hover{color:#fff}
.quick-add{display:flex;align-items:center;gap:8px}
.quick-add input{padding:8px 12px;border:none;border-radius:8px;font-size:14px;outline:none;background:rgba(255,255,255,.92);color:#333;width:280px}
.quick-add input::placeholder{color:#999}
.quick-add button{padding:8px 16px;border:none;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer;background:#fff;color:#4a6cf7;transition:all .15s;white-space:nowrap}
.quick-add button:hover{background:rgba(255,255,255,.8)}
.organize-btn{padding:6px 12px;border:1px solid rgba(255,255,255,.4);border-radius:8px;font-size:12px;font-weight:600;cursor:pointer;background:rgba(255,255,255,.15);color:#fff;transition:all .15s;white-space:nowrap}
.organize-btn:hover{background:rgba(255,255,255,.3)}
.quick-add{display:flex;align-items:center;gap:8px;margin-top:8px}
.quick-add input{flex:1;padding:8px 12px;border:none;border-radius:8px;font-size:14px;outline:none;background:rgba(255,255,255,.92);color:#333}
.quick-add input::placeholder{color:#999}
.quick-add button{padding:8px 16px;border:none;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer;background:#fff;color:#4a6cf7;transition:all .15s}
.quick-add button:hover{background:rgba(255,255,255,.8)}
.organize-btn{padding:6px 12px;border:1px solid rgba(255,255,255,.4);border-radius:8px;font-size:12px;font-weight:600;cursor:pointer;background:rgba(255,255,255,.15);color:#fff;transition:all .15s;white-space:nowrap}
.organize-btn:hover{background:rgba(255,255,255,.3)}
.container{max-width:100%;padding:16px;overflow-x:auto}
.board{display:flex;gap:12px;min-height:70vh}
.column{flex:1;min-width:250px;max-width:320px}
.column-header{padding:10px 12px;border-radius:8px 8px 0 0;font-weight:600;font-size:14px;display:flex;justify-content:space-between}
.column-body{background:var(--card-bg);border-radius:0 0 8px 8px;min-height:100px;padding:8px}
.card{background:var(--card-bg);border:1px solid var(--border);border-radius:8px;padding:10px 12px;margin-bottom:8px;cursor:pointer;transition:all .15s}
.card:hover{box-shadow:0 2px 8px rgba(0,0,0,.1);transform:translateY(-1px)}
.card-title{font-size:13px;font-weight:600;margin-bottom:4px}
.card-meta{font-size:11px;color:var(--text-light)}
.card-summary{font-size:12px;color:var(--text-light);margin-top:4px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.priority-badge{font-size:10px;padding:1px 6px;border-radius:10px;font-weight:600;color:#fff;display:inline-block}
.tag{display:inline-block;background:var(--accent-light);color:var(--accent);font-size:10px;padding:1px 6px;border-radius:4px;margin:2px 2px 0 0}
.p0{background:var(--p0)}.p1{background:var(--p1)}.p2{background:var(--p2)}.p3{background:var(--p3)}
.col-inbox .column-header{background:var(--inbox);color:#fff}
.col-next_actions .column-header{background:var(--next);color:#fff}
.col-waiting_for .column-header{background:var(--waiting);color:#fff}
.col-projects .column-header{background:var(--project);color:#fff}
.col-done .column-header{background:var(--done);color:#fff}
.col-done .card{opacity:.75}
.count{font-weight:400;font-size:12px}
.modal-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.4);z-index:200;justify-content:center;align-items:center}
.modal-overlay.active{display:flex}
.modal{background:#fff;border-radius:12px;width:90%;max-width:640px;max-height:85vh;overflow-y:auto;padding:24px;position:relative}
.modal-close{position:absolute;top:12px;right:16px;font-size:24px;cursor:pointer;background:none;border:none;color:var(--text-light)}
.modal h2{font-size:18px;margin-bottom:12px}
.modal .meta-line{font-size:13px;color:var(--text-light);margin-bottom:4px}
.modal .body-content{margin-top:16px;line-height:1.7;font-size:14px}
.modal .body-content h1,.modal .body-content h2,.modal .body-content h3{margin-top:16px;margin-bottom:8px}
.modal .body-content ul,.modal .body-content ol{padding-left:20px}
.modal .body-content li{margin-bottom:4px}
.modal .body-content a{color:var(--accent)}
.modal .body-content code{background:#f5f5f5;padding:1px 4px;border-radius:3px;font-size:13px}
.modal .body-content input[type="checkbox"]{margin-right:6px}
.add-form{background:var(--card-bg);border:1px dashed var(--border);border-radius:8px;padding:10px 12px;margin-bottom:8px}
.add-form input,.add-form select,.add-form textarea{width:100%;margin-bottom:6px;border:1px solid var(--border);border-radius:4px;padding:6px 8px;font-size:12px}
.add-form textarea{min-height:60px;resize:vertical}
.add-form button{background:var(--accent);color:#fff;border:none;padding:6px 16px;border-radius:4px;cursor:pointer;font-size:12px}
.add-form button:hover{opacity:.9}
.add-toggle{font-size:12px;color:var(--accent);cursor:pointer;display:inline-block;margin-bottom:8px;user-select:none}
.btn{display:inline-block;padding:6px 14px;border-radius:6px;font-size:12px;font-weight:500;cursor:pointer;border:none;background:var(--accent);color:#fff}
.btn-sm{padding:4px 10px;font-size:11px}
.btn-outline{background:transparent;border:1px solid var(--border);color:var(--text);margin-right:4px;margin-bottom:4px}
.tab-content{display:none}.tab-content.active{display:block}
.search-bar{margin-bottom:16px}
.search-bar input{width:100%;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:14px}
@media(max-width:1200px){.board{overflow-x:auto}.column{min-width:260px}}
</style></head><body>
<div class="header"><div class="header-row"><div><h1>📋 GTD 看板</h1><nav><a href="javascript:void(0)" onclick="switchTab('board')">看板</a><a href="javascript:void(0)" onclick="switchTab('reference')">知识参考</a><a href="javascript:void(0)" onclick="switchTab('review')">每日回顾</a></nav></div><div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><button class="organize-btn" onclick="organizeInbox()" type="button">✨ 一键整理</button><div class="quick-add"><input type="text" id="quickInput" placeholder="⚡ 快速录入一句话待办" onkeydown="if(event.key==='Enter')quickAdd()"><button onclick="quickAdd()" type="button">添加</button></div></div></div></div>
<div class="container">
<div class="search-bar"><input type="text" id="searchInput" placeholder="🔍 搜索任务..." oninput="searchTasks(this.value)"></div>
<div id="tab-board" class="tab-content active"><div class="board">${colHTML}</div></div>
<div id="tab-reference" class="tab-content"><h2 style="font-size:18px;margin-bottom:12px;">📚 知识参考</h2><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px;">${refItems}</div></div>
<div id="tab-review" class="tab-content"><h2 style="font-size:18px;margin-bottom:12px;">📝 每日回顾</h2><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;">${reviewItems}</div></div>
</div>
<div class="modal-overlay" id="modalOverlay" onclick="if(event.target===this)closeModal()"><div class="modal" id="modalContent"><button class="modal-close" onclick="closeModal()">&times;</button><div id="modalBody">加载中...</div><div style="margin-top:16px;display:flex;gap:8px;flex-wrap:wrap" id="modalActions"></div></div></div>
<script>
let currentFile=null;
function quickAdd(){const i=document.getElementById('quickInput');const v=i.value.trim();if(!v)return;fetch('/api/quick-add',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text:v})}).then(r=>r.json()).then(d=>{if(d.ok){i.value='';if(d.reload)location.reload();else i.placeholder='✅ 已录入，继续输入或按Tab我帮你整理'}})}
function toggleAddForm(k){const f=document.getElementById('add-form-'+k);f.style.display=f.style.display==='none'?'block':'none'}
async function addTask(col,ev){ev.preventDefault();const f=ev.target;const r=await fetch('/api/add',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title:f.title.value,description:f.description.value,priority:f.priority.value,tags:f.tags.value?f.tags.value.split(',').map(t=>t.trim()):[],column:col})});if(r.ok)location.reload();else alert('添加失败')}
async function openModal(p){currentFile=p;const r=await fetch('/api/file?path='+encodeURIComponent(p));if(!r.ok){alert('无法读取');return}
const d=await r.json();let h='<h2>'+d.meta.title+'</h2><div class="meta-line"><span class="priority-badge '+(d.meta.priority||'p3')+'">'+(d.meta.priority||'')+'</span>'+(d.meta.status?' 状态: '+d.meta.status:'')+(d.meta.created?' 创建: '+d.meta.created.slice(0,10):'')+((d.meta.tags||[]).length?' 标签: '+d.meta.tags.join(', '):'')+'</div><div class="body-content">'+d.html+'</div>';document.getElementById('modalBody').innerHTML=h
const a=document.getElementById('modalActions');a.innerHTML=''
const sts=['inbox','next_actions','waiting_for','projects','done'];for(const s of sts){if(s!==d.meta.status&&s!==(d.meta.status||'').replace('_','')){const b=document.createElement('button');b.className='btn btn-sm btn-outline';b.textContent='移至 '+s;b.onclick=()=>moveTask(p,s);a.appendChild(b)}}{const b=document.createElement('button');b.className='btn btn-sm btn-outline';b.textContent='📦 归档';b.onclick=()=>archiveTask(p);a.appendChild(b)}{const db=document.createElement('button');db.className='btn btn-sm';db.style.color='#e53935';db.style.borderColor='#e53935';db.textContent='🗑 删除';db.onclick=()=>deleteTask(p);a.appendChild(db)}
const eb=document.createElement('button');eb.className='btn btn-sm';eb.textContent='✏️ 编辑文件';eb.onclick=()=>window.open('/edit?path='+encodeURIComponent(p),'_blank');a.appendChild(eb)
document.getElementById('modalOverlay').classList.add('active')}
async function organizeInbox(){const btn=document.querySelector('.organize-btn');if(!btn)return;const orig=btn.textContent;btn.textContent='整理中...';btn.disabled=true;fetch('/api/organize',{method:'POST'}).then(r=>r.json()).then(d=>{btn.textContent=orig;btn.disabled=false;if(d.result)alert(d.result);location.reload()}).catch(()=>{btn.textContent=orig;btn.disabled=false;alert('整理失败')})}
async function moveTask(p,s){const r=await fetch('/api/move',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({path:p,status:s})});if(r.ok)location.reload();else alert('移动失败')}
async function deleteTask(p) { if (!confirm('确认删除此任务？此操作不可恢复')) return; const r = await fetch('/api/delete', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({path:p})}); if (r.ok) location.reload(); else alert('删除失败')}
async function archiveTask(p){if(!confirm('确认归档此任务？'))return;const r=await fetch('/api/move',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({path:p,status:'archived'})});if(r.ok)location.reload();else alert('归档失败')}
function closeModal(){document.getElementById('modalOverlay').classList.remove('active')}
function switchTab(n){document.querySelectorAll('.tab-content').forEach(t=>t.classList.remove('active'));document.getElementById('tab-'+n).classList.add('active')}
function searchTasks(q){q=q.toLowerCase();document.querySelectorAll('.card').forEach(c=>{c.style.display=c.textContent.toLowerCase().includes(q)?'':'none'})}
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeModal()});
switchTab('board');
</script></body></html>`;
}

function serveHTML(req, res) {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(renderHTML());
}

function serveJSON(url, req, res) {
  const u = new URL(url, 'http://localhost');
  const p = u.pathname;

  if (p === '/api/add' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const d = JSON.parse(body);
        const today = new Date().toISOString().slice(0, 10);
        const safe = d.title.replace(/[^\w\u4e00-\u9fff\- ]/g, '').slice(0, 40) || 'untitled';
        const fn = today + '-' + safe + '.md';
        const dir = (COLUMNS[d.column] || COLUMNS.inbox).dir;
        const fp = path.join(BASE_DIR, dir, fn);
        ensureDir(path.dirname(fp));
        const tagStr = (d.tags || []).length ? '[' + d.tags.map(t => '"' + t + '"').join(', ') + ']' : '[]';
        const content = `---\ntitle: "${d.title}"\nstatus: "${dir}"\npriority: "${d.priority || 'P2'}"\ncreated: ${today}\ntags: ${tagStr}\n---\n\n# ${d.title}\n\n${d.description || ''}\n`;
        fs.writeFileSync(fp, content, 'utf-8');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }


  if (p === '/api/quick-add' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const d = JSON.parse(body);
        const text = (d.text || '').trim();
        if (!text) { res.writeHead(400); res.end(JSON.stringify({ error: 'empty' })); return; }
        const now = new Date();
        const dateStr = now.toISOString().slice(0, 10);
        const timeStr = now.toTimeString().slice(0, 5).replace(/:/g, '');
        const safe = text.replace(/[^\w\u4e00-\u9fff\- ]/g, '').slice(0, 40) || 'task';
        const fn = dateStr + '-' + timeStr + '-' + safe + '.md';
        const fp = path.join(BASE_DIR, 'inbox', fn);
        ensureDir(path.dirname(fp));
        const content = `---\ntitle: "${text}"\nstatus: "inbox"\npriority: "P3"\ncreated: ${dateStr}\ntags: []\n---\n\n# ${text}\n`;
        fs.writeFileSync(fp, content, 'utf-8');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, path: fn }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }
  if (p === '/api/file') {
    const rel = u.searchParams.get('path') || '';
    const fp = path.join(BASE_DIR, rel);
    if (!fs.existsSync(fp)) { res.writeHead(404); res.end('{}'); return; }
    const task = parseMD(fp);
    if (!task) { res.writeHead(500); res.end('{}'); return; }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ meta: task.meta, html: mdToHtml(task.content), content: task.content, path: rel }));
    return;
  }

  if (p === '/api/move' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const d = JSON.parse(body);
        const fp = path.join(BASE_DIR, d.path);
        if (!fs.existsSync(fp)) { res.writeHead(404); res.end(JSON.stringify({ error: 'not found' })); return; }
        let content = fs.readFileSync(fp, 'utf-8');
        const targetDir = (COLUMNS[d.status] || { dir: d.status }).dir;
        const today = new Date().toISOString().slice(0, 10);
        content = content.replace(/^status:\s*.+/m, `status: "${targetDir}"`);
        if (content.includes('updated:')) content = content.replace(/^updated:\s*.+/m, `updated: ${today}`);
        else content = content.replace(/^created:\s*.+/m, m => m + `\nupdated: ${today}`);
        const newPath = path.join(BASE_DIR, targetDir, path.basename(fp));
        ensureDir(path.dirname(newPath));
        fs.writeFileSync(newPath, content, 'utf-8');
        if (newPath !== fp) fs.unlinkSync(fp);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }



  if (p === '/api/organize' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      execOrganizeWithGemini().then(result => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      }).catch(e => {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      });
    });
    return;
  }

async function execOrganizeWithGemini() {
  const { spawnSync } = await import('node:child_process');

  const inboxDir = path.join(BASE_DIR, 'inbox');
  if (!fs.existsSync(inboxDir)) return { result: '📭 收件箱为空，无需整理' };
  const files = fs.readdirSync(inboxDir).filter(f => f.endsWith('.md'));
  if (files.length === 0) return { result: '📭 收件箱为空，无需整理' };

  // 读取 SKILL.md
  const skillPath = path.join(__dirname, '.agents', 'skills', 'organize-inbox', 'SKILL.md');
  let skill = '';
  try { skill = fs.readFileSync(skillPath, 'utf-8'); } catch {}

  // 读取所有任务内容
  const tasksText = files.map(f => {
    const content = fs.readFileSync(path.join(inboxDir, f), 'utf-8');
    return `\n=== 文件: ${f} ===\n${content}`;
  }).join('\n');

  const instructions = skill
    ? `请严格按照以下 SKILL.md 规则整理任务：\n${skill}\n\n`
    : '';

  const prompt = `${instructions}待整理的任务内容：\n\n${tasksText}\n\n请分析每个任务，输出整理结果。\n\n**严格只输出一个 JSON 数组，不要任何其他文字。** 格式：
[
  {"file":"原文件名.md","action":"moved|updated|skipped","target_dir":"目标列目录名","priority":"P0|P1|P2|P3","title":"精炼标题","tags":["标签1"],"reason":"整理理由"},
  ...
]`;

  console.log('🤖 调用 Gemini AI 整理中...');

  const result = spawnSync('gemini', [
    '-p', prompt,
    '--yolo',
    '--output-format=json'
  ], {
    encoding: 'utf-8',
    timeout: 180000,
    maxBuffer: 50 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  const rawOutput = (result.stdout || '').trim();
  if (!rawOutput) {
    if (result.error) throw new Error('Gemini 执行失败: ' + result.error.message);
    throw new Error('Gemini 返回空输出');
  }

  // Gemini --output-format=json 返回的是一个 JSON 对象，其中 response 字段包含 AI 回复
  let parsed;
  try {
    parsed = JSON.parse(rawOutput);
  } catch {
    return { result: '⚠️ Gemini 返回格式异常:\n' + rawOutput.slice(0, 300) };
  }

  // 提取 AI 回复内容
  const aiReply = parsed.response || '';
  if (!aiReply.trim()) {
    return { result: '⚠️ Gemini 未返回内容' };
  }

  // 从 AI 回复中提取 JSON 数组（可能包裹在 markdown 代码块中）
  let cleanReply = aiReply.replace(/```(?:json)?\s*\n/g, '').replace(/\n```\s*$/g, '');
  cleanReply = cleanReply.trim();

  // 找第一个 [ 和匹配的 ] （处理嵌套括号）
  let actions = null;
  const startIdx2 = cleanReply.indexOf('[');
  if (startIdx2 !== -1) {
    let depth = 0;
    let endIdx2 = -1;
    let inStr = false;
    let escape = false;
    for (let i = startIdx2; i < cleanReply.length; i++) {
      const ch = cleanReply[i];
      if (escape) { escape = false; continue; }
      if (ch === '\\') { escape = true; continue; }
      if (ch === '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (ch === '[') depth++;
      else if (ch === ']') depth--;
      if (depth === 0) { endIdx2 = i; break; }
    }
    if (endIdx2 !== -1) {
      try { actions = JSON.parse(cleanReply.slice(startIdx2, endIdx2 + 1)); }
      catch { actions = null; }
    }
  }

  if (!actions || !Array.isArray(actions)) {
    return { result: '⚠️ AI 回复中未找到有效 JSON 数组:\n' + aiReply.slice(0, 300) };
  }


  // 执行整理
  const summary = { total: files.length, moved: 0, updated: 0, skipped: 0, details: [] };

  for (const action of actions) {
    if (!action.file || action.file === 'summary') continue;

    if (action.action === 'skipped') {
      summary.skipped++;
      summary.details.push(`⏭ ${action.file}: 已规范，跳过`);
      continue;
    }

    const fp = path.join(inboxDir, action.file);
    if (!fs.existsSync(fp)) continue;

    let content = fs.readFileSync(fp, 'utf-8');
    const today = new Date().toISOString().slice(0, 10);
    const targetDir = action.target_dir || 'inbox';
    const priority = action.priority || 'P3';
    const title = action.title || '';
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
      const tagStr = '[' + tags.map(t => `"${t}"`).join(', ') + ']';
      if (content.match(/^tags:\s/m)) {
        content = content.replace(/^tags:\s*.+/m, `tags: ${tagStr}`);
      } else {
        content = content.replace(/^created:\s*.+/m, m => m + `\ntags: ${tagStr}`);
      }
    }

    const newFp = path.join(BASE_DIR, targetDir, action.file);
    ensureDir(path.dirname(newFp));
    fs.writeFileSync(newFp, content, 'utf-8');
    if (newFp !== fp) fs.unlinkSync(fp);

    if (targetDir !== 'inbox') summary.moved++;
    else summary.updated++;
    summary.details.push(`✅ ${action.file} → ${targetDir} [${priority}] ${action.reason || ''}`);
  }

  return {
    result: `🤖 Gemini 已整理 ${summary.total} 项：\n` + summary.details.join('\n')
  };
}


  if (p === '/api/delete' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const d = JSON.parse(body);
        const fp = path.join(BASE_DIR, d.path);
        if (!fs.existsSync(fp)) { res.writeHead(404); res.end(JSON.stringify({ error: 'not found' })); return; }
        fs.unlinkSync(fp);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }
  // fallback: not found
  res.writeHead(404);
  res.end('Not Found');
}

function serveEdit(url, req, res) {
  const u = new URL(url, 'http://localhost');
  const rel = u.searchParams.get('path') || '';
  const fp = path.join(BASE_DIR, rel);
  if (!fs.existsSync(fp)) { res.writeHead(404); res.end('File not found'); return; }
  const content = fs.readFileSync(fp, 'utf-8');
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>编辑</title><style>body{font-family:sans-serif;max-width:800px;margin:0 auto;padding:20px}textarea{width:100%;min-height:400px;font-family:monospace;font-size:14px}</style></head><body><h2>编辑: ${rel}</h2><form method="POST" action="/api/save"><input type="hidden" name="path" value="${rel}"><textarea name="content">${content.replace(/</g,'&lt;').replace(/>/g,'&gt;')}</textarea><br><button type="submit">保存</button></form><a href="/">← 返回看板</a></body></html>`);
}

function serveSave(req, res) {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => {
    const params = new URLSearchParams(body);
    const rel = params.get('path') || '';
    const content = params.get('content') || '';
    const fp = path.join(BASE_DIR, rel);
    ensureDir(path.dirname(fp));
    fs.writeFileSync(fp, content, 'utf-8');
    res.writeHead(302, { 'Location': '/' });
    res.end();
  });
}

function serveStatic(url, req, res) {
  const u = new URL(url, 'http://localhost');
  let f = u.pathname === '/' ? '' : u.pathname.replace(/^\//, '');
  if (!f) { serveHTML(req, res); return; }
  if (f.startsWith('api/') || f.startsWith('api')) { serveJSON(url, req, res); return; }
  if (f === 'edit') { serveEdit(url, req, res); return; }
  if (f === 'api/save' && req.method === 'POST') { serveSave(req, res); return; }
  res.writeHead(404);
  res.end('Not Found');
}

const server = http.createServer((req, res) => {
  if (req.url.startsWith('/api/') || req.url === '/') {
    if (req.url === '/api/save' && req.method === 'POST') { serveSave(req, res); return; }
    if (req.url.startsWith('/api/')) { serveJSON(req.url, req, res); return; }
    serveHTML(req, res);
  } else if (req.url.startsWith('/edit')) {
    serveEdit(req.url, req, res);
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

ensureDir(BASE_DIR);
for (const col of Object.values(COLUMNS)) ensureDir(path.join(BASE_DIR, col.dir));
ensureDir(path.join(BASE_DIR, 'reference'));
ensureDir(path.join(BASE_DIR, 'daily_review'));
ensureDir(path.join(BASE_DIR, 'archived'));

const PORT = 5000;
server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n🚀 GTD 看板已启动!`);
  console.log(`📂 数据目录: ${BASE_DIR}`);
  console.log(`🌐 打开浏览器: http://localhost:${PORT}`);
  console.log(`⌨️  按 Ctrl+C 停止服务器\n`);
});
