/**
 * Konten Aplikasi — elemen konten layar Flutter yang dikelola dari server
 * (internal/mobilecontent registry). Alur: Simpan Draf → Ajukan Persetujuan →
 * Setujui & Publikasikan (petugas lain) → aplikasi mengambil versi baru (GET /api/v1/content).
 */
const contentState = {
  schema: null,      // { pages, fields }
  current: null,     // { live, live_version, published_at, published, open }
  values: {},        // values being edited
  page: null,
  dirty: false,
  history: []
};

const CONTENT_STATUS = {
  DRAFT: ['Draf', 'bg-amber-50 text-amber-700 border-amber-200'],
  PENDING_APPROVAL: ['Menunggu Persetujuan', 'bg-blue-50 text-blue-700 border-blue-200'],
  PUBLISHED: ['Dipublikasikan', 'bg-emerald-50 text-emerald-700 border-emerald-200'],
  ARCHIVED: ['Arsip', 'bg-slate-100 text-slate-500 border-slate-200']
};

function currentAdmin() {
  try { return JSON.parse(localStorage.getItem('dmb_admin_user') || '{}'); } catch (_) { return {}; }
}
function canEditContent() { return ['SUPER_ADMIN', 'MARKETING'].includes(currentAdmin().role); }
function canApproveContent() { return ['SUPER_ADMIN', 'MARKETING', 'COMPLIANCE'].includes(currentAdmin().role); }
function contentDate(v) {
  if (!v) return '-';
  try { return new Date(v).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }); } catch (_) { return String(v); }
}
function statusPill(status) {
  const [label, cls] = CONTENT_STATUS[status] || [status, 'bg-slate-50 text-slate-600 border-slate-200'];
  return `<span class="inline-flex px-2 py-0.5 rounded-full border text-[10px] font-bold ${cls}">${esc(label)}</span>`;
}

async function loadContent() {
  const form = document.getElementById('contentForm');
  if (!form) return;
  if (contentState.dirty && !confirm('Perubahan yang belum disimpan akan hilang. Muat ulang?')) return;
  try {
    if (!contentState.schema) {
      const s = await safeFetch('/admin/content/schema', { headers: getAuthHeaders() });
      if (!s.ok) throw new Error(s.json.message || 'Struktur konten tidak dapat dimuat');
      contentState.schema = s.json.data;
    }
    const c = await safeFetch('/admin/content', { headers: getAuthHeaders() });
    if (!c.ok) throw new Error(c.json.message || 'Konten tidak dapat dimuat');
    contentState.current = c.json.data;
    const open = c.json.data.open;
    contentState.values = Object.assign({}, c.json.data.live, open ? open.values : {});
    contentState.dirty = false;
    if (!contentState.page) contentState.page = contentState.schema.pages[0].id;
    renderContentStatus();
    renderContentPages();
    renderContentPage();
  } catch (err) {
    document.getElementById('contentLiveInfo').textContent = err.message;
    form.innerHTML = '';
  }
}

function renderContentStatus() {
  const cur = contentState.current;
  const pub = cur.published;
  document.getElementById('contentLiveInfo').innerHTML = cur.live_version > 0
    ? `<b>Versi ${esc(cur.live_version)}</b> &middot; dipublikasikan ${esc(contentDate(cur.published_at))} oleh ${esc(pub && pub.published_by_name || '-')}`
    : '<b>Versi 0</b> &middot; konten bawaan aplikasi (belum ada perubahan yang dipublikasikan)';
  const open = cur.open;
  const me = currentAdmin();
  let openTxt = 'Tidak ada. Ubah nilai pada formulir lalu klik <b>Simpan Draf</b>.';
  if (open) {
    openTxt = `${statusPill(open.status)} <b>Versi ${esc(open.version_number)}</b> &middot; dibuat ${esc(open.created_by_name)}`;
    if (open.status === 'PENDING_APPROVAL') openTxt += ` &middot; diajukan ${esc(open.submitted_by_name || '-')} (${esc(contentDate(open.submitted_at))})`;
    const changed = changedFromLive(open.values).length;
    openTxt += ` &middot; ${changed} elemen berbeda dari yang tampil`;
  }
  if (contentState.dirty) openTxt += ' <span class="ml-1 px-2 py-0.5 rounded-full bg-rose-50 text-rose-700 border border-rose-200 text-[10px] font-bold">Belum disimpan</span>';
  document.getElementById('contentOpenInfo').innerHTML = openTxt;

  const pending = open && open.status === 'PENDING_APPROVAL';
  const draft = open && open.status === 'DRAFT';
  const isMaker = open && (open.created_by === me.id || open.submitted_by === me.id);
  const set = (id, enabled, title) => {
    const b = document.getElementById(id);
    if (!b) return;
    b.disabled = !enabled;
    b.title = title || '';
  };
  set('contentSaveBtn', canEditContent() && !pending && contentState.dirty, pending ? 'Revisi sedang menunggu persetujuan' : '');
  set('contentSubmitBtn', canEditContent() && draft && !contentState.dirty, contentState.dirty ? 'Simpan draf terlebih dahulu' : '');
  set('contentApproveBtn', canApproveContent() && pending && !isMaker, isMaker ? 'Maker-checker: harus disetujui petugas lain' : '');
  set('contentRejectBtn', canApproveContent() && pending, '');
  set('contentDiscardBtn', canEditContent() && draft, '');
}

function changedFromLive(values) {
  const live = contentState.current.live;
  return contentState.schema.fields.filter(f => (values[f.key] || '') !== (live[f.key] || '')).map(f => f.key);
}

function renderContentPages() {
  const nav = document.getElementById('contentPageList');
  const changed = new Set(changedFromLive(contentState.values));
  nav.innerHTML = contentState.schema.pages.map(p => {
    const fields = contentState.schema.fields.filter(f => f.page === p.id);
    const n = fields.filter(f => changed.has(f.key)).length;
    const active = p.id === contentState.page;
    return `<button type="button" onclick="selectContentPage(${jsArg(p.id)})"
      class="w-full text-left px-3 py-2.5 rounded-xl text-xs transition flex items-center justify-between gap-2 ${active ? 'bg-teal-50 text-[#00897B] font-bold border border-teal-200' : 'text-slate-700 hover:bg-slate-50 font-semibold border border-transparent'}">
      <span>${esc(p.name)}<span class="block text-[10px] font-medium text-slate-400">${fields.length} elemen</span></span>
      ${n ? `<span class="px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-800 text-[10px] font-bold">${n} diubah</span>` : ''}
    </button>`;
  }).join('');
}

function selectContentPage(id) {
  contentState.page = id;
  renderContentPages();
  renderContentPage();
}

function renderContentPage() {
  const page = contentState.schema.pages.find(p => p.id === contentState.page);
  const fields = contentState.schema.fields.filter(f => f.page === page.id);
  document.getElementById('contentPageHeader').innerHTML = `
    <div class="flex flex-col sm:flex-row sm:items-start justify-between gap-2">
      <div>
        <h4 class="text-sm font-black text-slate-900">${esc(page.name)}</h4>
        <p class="text-xs text-slate-500 mt-1">${esc(page.description)}</p>
      </div>
      <code class="text-[10px] text-slate-400">${esc(page.screen)}</code>
    </div>
    ${page.static && page.static.length ? `<details class="mt-3 text-xs text-slate-600">
      <summary class="cursor-pointer font-bold text-slate-500">Elemen layar ini yang tetap di kode aplikasi (${page.static.length})</summary>
      <ul class="list-disc pl-5 mt-2 space-y-1">${page.static.map(s => `<li>${esc(s)}</li>`).join('')}</ul>
    </details>` : ''}`;

  const pending = contentState.current.open && contentState.current.open.status === 'PENDING_APPROVAL';
  const readOnly = pending || !canEditContent();
  const groups = [];
  fields.forEach(f => {
    let g = groups.find(x => x.name === f.group);
    if (!g) groups.push(g = { name: f.group, fields: [] });
    g.fields.push(f);
  });
  document.getElementById('contentForm').innerHTML = (readOnly ? `<div class="p-3 rounded-xl bg-blue-50 border border-blue-200 text-xs text-blue-800">${pending
      ? 'Revisi sedang menunggu persetujuan; formulir hanya dapat dibaca. Setujui atau kembalikan ke draf untuk mengubah.'
      : 'Peran Anda hanya dapat melihat konten.'}</div>` : '') +
    groups.map(g => `
    <fieldset class="bg-white rounded-2xl border border-slate-200/80 shadow-xs p-5 space-y-4">
      <legend class="px-2 text-[11px] font-extrabold text-slate-500 uppercase tracking-wider">${esc(g.name)}</legend>
      ${g.fields.map(f => renderContentField(f, readOnly)).join('')}
    </fieldset>`).join('');
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function renderContentField(f, readOnly) {
  const v = contentState.values[f.key] || '';
  const live = contentState.current.live[f.key] || '';
  const id = 'cf_' + f.key.replace(/[^a-z0-9]/gi, '_');
  const dis = readOnly ? 'disabled' : '';
  const base = 'w-full px-3.5 py-2.5 text-xs rounded-xl border border-slate-200 focus:outline-none focus:border-[#00897B] disabled:bg-slate-50 disabled:text-slate-500';
  const onInput = `oninput="setContentValue(${jsArg(f.key)}, this.value)"`;
  let input;
  switch (f.type) {
    case 'multiline':
      input = `<textarea id="${id}" rows="3" maxlength="${f.max}" class="${base}" ${onInput} ${dis}>${esc(v)}</textarea>`;
      break;
    case 'bool':
      input = `<label class="inline-flex items-center gap-2 text-xs font-semibold text-slate-700">
        <input id="${id}" type="checkbox" class="w-4 h-4 accent-[#00897B]" ${v === 'true' ? 'checked' : ''}
          onchange="setContentValue(${jsArg(f.key)}, this.checked ? 'true' : 'false')" ${dis}> Tampilkan di aplikasi</label>`;
      break;
    case 'enum':
      input = `<select id="${id}" class="${base}" onchange="setContentValue(${jsArg(f.key)}, this.value)" ${dis}>
        ${(f.options || []).map(o => `<option value="${esc(o.value)}" ${o.value === v ? 'selected' : ''}>${esc(o.label)}</option>`).join('')}</select>`;
      break;
    case 'image': {
      const preview = v && v.startsWith('/admin/')
        ? `<img src="${esc(v)}" alt="" class="h-16 w-28 object-cover rounded-lg border border-slate-200 bg-slate-50">`
        : `<div class="h-16 w-28 rounded-lg border border-dashed border-slate-300 bg-slate-50 flex items-center justify-center text-[10px] text-slate-400 text-center px-1">${v ? 'URL eksternal' : 'Gambar bawaan aplikasi'}</div>`;
      input = `<div class="flex flex-col sm:flex-row gap-3 sm:items-center">
        ${preview}
        <div class="flex-1 space-y-2">
          <input id="${id}" type="text" maxlength="${f.max}" placeholder="Kosong = gambar bawaan aplikasi" value="${esc(v)}" class="${base}" ${onInput} ${dis}>
          ${readOnly ? '' : `<div class="flex flex-wrap gap-2 items-center">
            <label class="px-3 py-1.5 rounded-lg text-[11px] font-bold text-white bg-slate-700 hover:bg-slate-800 cursor-pointer">Unggah gambar
              <input type="file" accept="image/png,image/jpeg,image/webp" class="hidden" onchange="uploadContentImage(${jsArg(f.key)}, this)"></label>
            <button type="button" onclick="setContentValue(${jsArg(f.key)}, ''); renderContentPage();" class="px-3 py-1.5 rounded-lg text-[11px] font-bold text-slate-600 bg-slate-100 hover:bg-slate-200">Pakai gambar bawaan</button>
            <span id="${id}_status" class="text-[11px] text-slate-500"></span>
          </div>`}
        </div>
      </div>`;
      break;
    }
    default:
      input = `<input id="${id}" type="${f.type === 'email' ? 'email' : f.type === 'phone' ? 'tel' : 'text'}" maxlength="${f.max}" value="${esc(v)}" class="${base}" ${onInput} ${dis}>`;
  }
  const changed = v !== live;
  return `<div class="space-y-1.5">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <label for="${id}" class="text-xs font-bold text-slate-800">${esc(f.label)}${f.required ? ' <span class="text-rose-500">*</span>' : ''}</label>
      <span class="text-[10px] text-slate-400">Dipakai di: ${esc(f.used)}</span>
    </div>
    ${input}
    <div class="flex flex-wrap items-center justify-between gap-2 text-[10.5px]">
      <span class="text-slate-400">${esc(f.help || '')}${f.type === 'text' || f.type === 'multiline' ? ` (maks. ${f.max} karakter)` : ''}</span>
      ${changed ? `<span class="text-amber-700 font-semibold">Diubah &middot; tampil sekarang: ${esc(live || '(kosong)').slice(0, 80)}</span>` : ''}
    </div>
  </div>`;
}

function setContentValue(key, value) {
  contentState.values[key] = value;
  contentState.dirty = true;
  renderContentStatus();
  renderContentPages();
}

async function uploadContentImage(key, input) {
  const file = input.files && input.files[0];
  if (!file) return;
  const status = document.getElementById('cf_' + key.replace(/[^a-z0-9]/gi, '_') + '_status');
  if (status) status.textContent = 'Mengunggah...';
  const fd = new FormData();
  fd.append('file', file);
  const category = key.includes('logo') ? 'logo' : key.includes('banner') ? 'banner' : 'bg';
  fd.append('category', category);
  try {
    const res = await fetch(`${API_BASE}/admin/upload?category=${category}`, {
      method: 'POST', headers: { 'Authorization': `Bearer ${localStorage.getItem('dmb_admin_token')}` }, body: fd
    });
    const json = await res.json();
    if (!res.ok || !json.success) throw new Error(json.message || 'Gagal mengunggah');
    setContentValue(key, json.data.url);
    renderContentPage();
    showToast('Gambar diunggah. Simpan draf lalu ajukan persetujuan.', 'success');
  } catch (err) {
    if (status) status.textContent = err.message;
    showToast(err.message, 'error');
  }
}

async function contentRequest(path, method, body, okMsg) {
  const { ok, json } = await safeFetch(path, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined });
  showToast(ok && json.success ? okMsg : (json.message || 'Tindakan gagal'), ok && json.success ? 'success' : 'error');
  if (ok && json.success) {
    contentState.dirty = false;
    await loadContent();
    if (!document.getElementById('contentHistoryView').classList.contains('hidden')) loadContentHistory();
  }
  return ok && json.success;
}

function saveContentDraft() {
  if (!contentState.dirty || !contentState.current) return;
  contentRequest('/admin/content/draft', 'PUT', { values: contentState.values }, 'Draf disimpan. Belum tampil di aplikasi sampai disetujui.');
}
function openRevision() {
  return contentState.current ? contentState.current.open : null;
}
function submitContent() {
  const o = openRevision();
  if (!o) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}/submit`, 'POST', null, 'Diajukan. Persetujuan dilakukan petugas lain.');
}
function approveContent() {
  const o = openRevision();
  if (!o || !confirm(`Setujui dan publikasikan versi ${o.version_number}? Konten akan tampil di aplikasi nasabah.`)) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}/approve`, 'POST', null, `Versi ${o.version_number} dipublikasikan.`);
}
function rejectContent() {
  const o = openRevision();
  if (!o) return;
  const reason = prompt('Alasan dikembalikan ke draf:', '');
  if (!reason) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}/reject`, 'POST', { reason }, 'Dikembalikan ke draf.');
}
function discardContent() {
  const o = openRevision();
  if (!o || !confirm('Buang draf ini? Versi yang tampil di aplikasi tidak berubah.')) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}`, 'DELETE', null, 'Draf dibuang.');
}

function switchContentView(view) {
  document.getElementById('contentEditorView').classList.toggle('hidden', view === 'history');
  document.getElementById('contentHistoryView').classList.toggle('hidden', view !== 'history');
  if (view === 'history') loadContentHistory();
}

async function loadContentHistory() {
  const body = document.getElementById('contentHistoryBody');
  body.innerHTML = '<tr><td colspan="7" class="py-6 text-center text-slate-400">Memuat...</td></tr>';
  const { ok, json } = await safeFetch('/admin/content/revisions?limit=100', { headers: getAuthHeaders() });
  if (!ok || !Array.isArray(json.data)) {
    body.innerHTML = `<tr><td colspan="7" class="py-6 text-center text-rose-600">${esc(json.message || 'Riwayat tidak dapat dimuat')}</td></tr>`;
    return;
  }
  contentState.history = json.data;
  if (!json.data.length) {
    body.innerHTML = '<tr><td colspan="7" class="py-6 text-center text-slate-400">Belum ada revisi. Versi 0 = konten bawaan aplikasi.</td></tr>';
    return;
  }
  body.innerHTML = json.data.map(r => `<tr class="hover:bg-slate-50 align-top">
    <td class="py-3 px-4 font-black">v${esc(r.version_number)}</td>
    <td class="py-3 px-4">${statusPill(r.status)}</td>
    <td class="py-3 px-4">${esc(r.created_by_name)}<div class="text-[10px] text-slate-400">${esc(contentDate(r.created_at))}</div></td>
    <td class="py-3 px-4">${esc(r.submitted_by_name || '-')}<div class="text-[10px] text-slate-400">${r.submitted_at ? esc(contentDate(r.submitted_at)) : ''}</div></td>
    <td class="py-3 px-4">${esc(r.published_by_name || '-')}<div class="text-[10px] text-slate-400">${r.published_at ? esc(contentDate(r.published_at)) : ''}</div></td>
    <td class="py-3 px-4 text-slate-500">${esc(r.note || '')}</td>
    <td class="py-3 px-4 text-right whitespace-nowrap space-x-2">
      <button type="button" onclick="showContentDiff(${jsArg(r.id)})" class="text-[#00897B] font-bold hover:underline">Lihat perubahan</button>
      ${(r.status === 'PUBLISHED' || r.status === 'ARCHIVED') && canEditContent() ? `<button type="button" onclick="rollbackContent(${jsArg(r.id)}, ${jsArg(r.version_number)})" class="text-slate-600 font-bold hover:underline">Pulihkan ke draf</button>` : ''}
    </td></tr>`).join('');
}

function showContentDiff(id) {
  const list = contentState.history;
  const i = list.findIndex(r => r.id === id);
  if (i < 0) return;
  const r = list[i];
  // previous published/archived revision with a lower version, else the app's built-in values
  const prev = list.slice(i + 1).find(x => x.status === 'PUBLISHED' || x.status === 'ARCHIVED');
  const fields = contentState.schema.fields;
  const base = prev ? prev.values : Object.fromEntries(fields.map(f => [f.key, f.default]));
  const rows = fields.filter(f => (r.values[f.key] ?? '') !== (base[f.key] ?? '')).map(f => `<tr class="align-top">
      <td class="py-2 px-3 font-semibold">${esc(f.label)}<div class="text-[10px] text-slate-400">${esc(f.key)}</div></td>
      <td class="py-2 px-3 text-rose-700 line-through decoration-rose-300">${esc(base[f.key] ?? '')}</td>
      <td class="py-2 px-3 text-emerald-700">${esc(r.values[f.key] ?? '')}</td></tr>`).join('');
  const panel = document.getElementById('contentDiffPanel');
  panel.classList.remove('hidden');
  panel.innerHTML = `<h5 class="text-xs font-bold text-slate-800 mb-2">Perubahan versi ${esc(r.version_number)} dibanding ${prev ? 'versi ' + esc(prev.version_number) : 'nilai bawaan di kode aplikasi'}</h5>
    ${rows ? `<table class="w-full text-xs"><thead class="text-slate-500"><tr><th class="text-left py-1 px-3">Elemen</th><th class="text-left py-1 px-3">Sebelumnya</th><th class="text-left py-1 px-3">Versi ini</th></tr></thead><tbody class="divide-y divide-slate-100">${rows}</tbody></table>`
      : '<p class="text-xs text-slate-500">Tidak ada perubahan nilai.</p>'}`;
}

function rollbackContent(id, version) {
  if (!confirm(`Salin isi versi ${version} ke draf? Draf perlu diajukan dan disetujui sebelum tampil.`)) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(id)}/rollback`, 'POST', null, `Isi versi ${version} disalin ke draf.`);
}

/** Dashboard card: content version shown in the app and pending approvals. */
async function loadContentSummary() {
  const v = document.getElementById('statContentVersion');
  const p = document.getElementById('statContentPending');
  if (!v) return;
  const { ok, json } = await safeFetch('/admin/content', { headers: getAuthHeaders() });
  if (!ok || !json.data) {
    v.textContent = '-';
    if (p) p.textContent = 'Tidak tersedia untuk peran Anda';
    return;
  }
  v.textContent = 'v' + json.data.live_version;
  const o = json.data.open;
  if (p) p.textContent = o ? (o.status === 'PENDING_APPROVAL' ? `v${o.version_number} menunggu persetujuan` : `Draf v${o.version_number} belum diajukan`) : 'Tidak ada perubahan berjalan';
}
