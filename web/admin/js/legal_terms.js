/**
 * Syarat & Ketentuan (SK) — manajemen versi, PDF, maker-checker (internal/legaldoc)
 * Dilengkapi Structured Visual Section & Block Builder + Mode JSON Lanjutan,
 * RBAC read-only untuk CS, dan pemilih tanggal berlaku (datetime-local -> RFC3339 +07:00).
 */
let termsVersions = [];
let termsEditingId = null;
let termsEditorMode = 'visual'; // 'visual' | 'json'
let termsVisualData = null;

const TERMS_STATUS_LABEL = {
  DRAFT: ['Draf', 'bg-amber-50 text-amber-700 border-amber-200'],
  PENDING_APPROVAL: ['Menunggu Persetujuan', 'bg-blue-50 text-blue-700 border-blue-200'],
  PUBLISHED: ['Terbit', 'bg-emerald-50 text-emerald-700 border-emerald-200'],
  ARCHIVED: ['Arsip', 'bg-slate-100 text-slate-500 border-slate-200']
};

function getTermsAdminRole() {
  try {
    return (JSON.parse(localStorage.getItem('dmb_admin_user') || '{}').role || 'SUPER_ADMIN').toUpperCase();
  } catch (_) {
    return 'SUPER_ADMIN';
  }
}

function canMutateTerms() {
  const role = getTermsAdminRole();
  return role === 'SUPER_ADMIN' || role === 'COMPLIANCE';
}

function termsDate(v) {
  if (!v) return '-';
  try { return new Date(v).toLocaleString('id-ID'); } catch (_) { return String(v); }
}

function getLocalDatetimeDefault() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
}

function localDatetimeToRFC3339WIB(val) {
  if (!val || !val.trim()) return '';
  const m = val.trim().match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (!m) return null;
  return `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6] || '00'}+07:00`;
}

async function loadTermsVersions() {
  const list = document.getElementById('termsVersionList');
  const info = document.getElementById('termsActiveInfo');
  if (!list) return;

  const canMutate = canMutateTerms();
  const newBtn = document.getElementById('termsNewDraftBtn');
  if (newBtn) {
    newBtn.classList.toggle('hidden', !canMutate);
  }
  const acceptCard = document.getElementById('termsAcceptancesCard');
  if (acceptCard) {
    acceptCard.classList.toggle('hidden', !canMutate);
  }

  list.innerHTML = '<p class="text-xs text-slate-400">Memuat versi...</p>';
  const { ok, json } = await safeFetch('/admin/terms/versions', { headers: getAuthHeaders() });
  if (!ok || !Array.isArray(json.data)) {
    list.innerHTML = '';
    if (info) info.textContent = json.message || 'Daftar versi tidak dapat dimuat (hanya SUPER_ADMIN, COMPLIANCE, CS).';
    return;
  }
  termsVersions = json.data;
  const active = termsVersions.find(v => v.is_active);
  if (info) {
    info.innerHTML = active
      ? `<span class="font-bold text-emerald-700">Berlaku: versi ${esc(active.version_number)}</span> sejak ${esc(termsDate(active.effective_from))} · diterbitkan oleh ${esc(active.approved_by_name || '-')}`
      : '<span class="font-bold text-rose-700">Belum ada SK yang berlaku.</span> Nasabah tidak dapat login/aktivasi sampai satu versi diterbitkan.';
  }

  const hasOpen = termsVersions.some(v => v.status === 'DRAFT' || v.status === 'PENDING_APPROVAL');
  if (newBtn) newBtn.disabled = hasOpen || !canMutate;

  list.innerHTML = termsVersions.map(v => {
    const [label, cls] = TERMS_STATUS_LABEL[v.status] || [v.status, 'bg-slate-50'];
    const id = jsArg(v.id);
    const actions = [];
    if (v.status === 'DRAFT') {
      if (canMutate) {
        actions.push(`<label class="px-2.5 py-1 rounded-lg bg-[#0A2A66] text-white font-bold hover:bg-[#0D3882] cursor-pointer inline-flex items-center gap-1">Unggah PDF Draf<input type="file" accept="application/pdf,.pdf" class="hidden" onchange="uploadTermsPdf(${id}, this)"></label>`);
        actions.push(`<button type="button" onclick="openTermsEditor(${id})" class="px-2.5 py-1 rounded-lg bg-white border border-slate-200 text-slate-700 font-bold hover:bg-slate-50">Ubah Persetujuan / Isi</button>`);
        actions.push(`<button type="button" onclick="generateTermsPdf(${id})" class="px-2.5 py-1 rounded-lg bg-white border border-slate-200 text-slate-700 font-bold hover:bg-slate-50">Buat PDF Otomatis</button>`);
      }
      if (v.draft_pdf_sha256) {
        actions.push(`<button type="button" onclick="openTermsPdf(${id}, 'draft')" class="px-2.5 py-1 rounded-lg bg-[#EFF6FF] border border-blue-200 text-[#033172] font-bold hover:bg-blue-100">Unduh PDF Draf</button>`);
        if (canMutate) {
          actions.push(`<button type="button" onclick="submitTerms(${id}, ${jsArg(v.version_number)})" class="px-2.5 py-1 rounded-lg bg-blue-50 border border-blue-200 text-blue-700 font-bold hover:bg-blue-100">Ajukan Persetujuan</button>`);
        }
      }
    }
    if (v.status === 'PENDING_APPROVAL') {
      actions.push(`<button type="button" onclick="openTermsPdf(${id}, 'draft')" class="px-2.5 py-1 rounded-lg bg-[#EFF6FF] border border-blue-200 text-[#033172] font-bold hover:bg-blue-100">Unduh PDF Draf</button>`);
      if (canMutate) {
        actions.push(`<button type="button" onclick="approveTerms(${id}, ${jsArg(v.version_number)})" class="px-2.5 py-1 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-700 font-bold hover:bg-emerald-100">Setujui &amp; Terbitkan</button>`);
        actions.push(`<button type="button" onclick="rejectTerms(${id})" class="px-2.5 py-1 rounded-lg bg-rose-50 border border-rose-200 text-rose-600 font-bold hover:bg-rose-100">Kembalikan ke Draf</button>`);
      }
    }
    if (v.status === 'PUBLISHED' || v.status === 'ARCHIVED') {
      actions.push(`<button type="button" onclick="openTermsPdf(${id}, 'final')" class="px-2.5 py-1 rounded-lg bg-[#EFF6FF] border border-blue-200 text-[#033172] font-bold hover:bg-blue-100">Unduh PDF Resmi</button>`);
    }
    if (v.status === 'PUBLISHED' && !v.is_active && canMutate) {
      actions.push(`<button type="button" onclick="archiveTerms(${id}, ${jsArg(v.version_number)})" class="px-2.5 py-1 rounded-lg bg-slate-100 border border-slate-200 text-slate-600 font-bold hover:bg-slate-200">Arsipkan</button>`);
    }
    return `<div class="p-4 rounded-xl border border-slate-200 bg-slate-50/60 space-y-1.5">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs font-black text-slate-800">Versi ${esc(v.version_number)}</span>
        <span class="px-2 py-0.5 rounded-full border text-[10px] font-bold ${cls}">${esc(label)}</span>
        ${v.is_active ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-600 text-white">AKTIF BERLAKU</span>' : ''}
        ${v.document_number ? `<span class="text-[11px] font-mono text-slate-500">No. ${esc(v.document_number)}</span>` : ''}
      </div>
      <p class="text-[11px] text-slate-600 font-medium">${esc(v.change_summary || '')}</p>
      <p class="text-[11px] text-slate-400">Dibuat ${esc(termsDate(v.created_at))} oleh ${esc(v.created_by_name || v.created_by)}
        ${v.published_at ? ' · terbit ' + esc(termsDate(v.published_at)) + ' oleh ' + esc(v.approved_by_name || '-') + ' · berlaku ' + esc(termsDate(v.effective_from)) : ''}
        ${v.pdf_sha256 ? ' · SHA-256 PDF ' + esc(v.pdf_sha256.substring(0, 16)) + '…' : ''}</p>
      <div class="flex flex-wrap gap-2 text-[11px] pt-1">${actions.join('')}</div>
    </div>`;
  }).join('') || '<p class="text-xs text-slate-400">Belum ada versi.</p>';
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

async function termsAction(path, body, okMsg) {
  const { ok, json } = await safeFetch(path, { method: 'POST', headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined });
  showToast(ok && json.success ? okMsg : (json.message || 'Tindakan gagal'), ok && json.success ? 'success' : 'error');
  loadTermsVersions();
  return ok && json.success;
}

async function createTermsDraft() {
  if (!canMutateTerms()) return;
  const latest = termsVersions[0];
  if (!latest) return;
  await termsAction('/admin/terms/versions', { base_version_id: latest.id, change_summary: `Revisi dari versi ${latest.version_number}` },
    'Draf versi baru dibuat dari versi terakhir.');
}

/**
 * Normalize Content JSON into a rich Visual Builder state and back to canonical legaldoc.Content
 */
function inferBlockType(block) {
  const items = Array.isArray(block.items) ? block.items : [];
  const txt = (block.text || '').trim();
  if (txt.startsWith('PERHATIAN:') || txt.startsWith('PENTING:') || txt.startsWith('CATATAN:')) {
    return 'callout';
  }
  if (items.length > 0) {
    if (items.every(it => it.includes(' : ') || it.includes(': '))) {
      return 'table';
    }
    if (/^\d+[\.\)]/.test(items[0].trim())) {
      return 'numbered';
    }
    return 'bullets';
  }
  return 'paragraph';
}

function normalizeVisualContent(raw) {
  const c = raw || {};
  return {
    title: c.title || 'RINGKASAN INFORMASI PRODUK DAN SYARAT KETENTUAN LAYANAN DMB MOBILE',
    date_note: c.date_note || '',
    intro: c.intro || '',
    consent_heading: c.consent_heading || 'PERNYATAAN PERSETUJUAN NASABAH',
    consent_instruction: c.consent_instruction || '',
    consent_statements: Array.isArray(c.consent_statements) && c.consent_statements.length
      ? [...c.consent_statements]
      : ['Saya telah membaca, memahami, dan menyetujui seluruh Syarat dan Ketentuan Layanan Mobile Banking Bank DMB.'],
    sections: Array.isArray(c.sections) && c.sections.length
      ? c.sections.map(s => ({
          heading: s.heading || '',
          fields: Array.isArray(s.fields) ? s.fields.map(f => ({ label: f.label || '', value: f.value || '' })) : [],
          blocks: Array.isArray(s.blocks) ? s.blocks.map(b => ({
            type: inferBlockType(b),
            text: b.text || '',
            items: Array.isArray(b.items) ? [...b.items] : []
          })) : []
        }))
      : [{
          heading: 'BAGIAN I — KETENTUAN UMUM',
          fields: [],
          blocks: [{ type: 'paragraph', text: 'Ketentuan layanan DMB Mobile berlaku bagi seluruh nasabah.', items: [] }]
        }]
  };
}

function serializeVisualToCanonicalContent(v) {
  const sections = (v.sections || []).map(s => {
    const outSec = {
      heading: (s.heading || '').trim()
    };
    const cleanFields = (s.fields || [])
      .map(f => ({ label: (f.label || '').trim(), value: (f.value || '').trim() }))
      .filter(f => f.label || f.value);
    if (cleanFields.length > 0) {
      outSec.fields = cleanFields;
    }
    const cleanBlocks = (s.blocks || []).map((b, bIdx) => {
      let txt = (b.text || '').trim();
      const rawItems = (b.items || []).map(it => (it || '').trim()).filter(Boolean);
      let finalItems = [];
      if (b.type === 'callout') {
        if (txt && !/^(PERHATIAN|PENTING|CATATAN):/i.test(txt)) {
          txt = 'PENTING: ' + txt;
        }
        finalItems = rawItems;
      } else if (b.type === 'numbered') {
        finalItems = rawItems.map((it, idx) => /^\d+[\.\)]/.test(it) ? it : `${idx + 1}. ${it}`);
      } else if (b.type === 'bullets' || b.type === 'table') {
        finalItems = rawItems;
      }
      const blk = { text: txt };
      if (finalItems.length > 0) {
        blk.items = finalItems;
      }
      return blk;
    }).filter(b => b.text || (b.items && b.items.length > 0));
    if (cleanBlocks.length > 0) {
      outSec.blocks = cleanBlocks;
    }
    return outSec;
  });

  const out = {
    title: (v.title || '').trim(),
    sections: sections,
    consent_heading: (v.consent_heading || '').trim(),
    consent_statements: (v.consent_statements || []).map(st => (st || '').trim()).filter(Boolean)
  };
  if ((v.date_note || '').trim()) out.date_note = v.date_note.trim();
  if ((v.intro || '').trim()) out.intro = v.intro.trim();
  if ((v.consent_instruction || '').trim()) out.consent_instruction = v.consent_instruction.trim();
  return out;
}

async function openTermsEditor(id) {
  if (!canMutateTerms()) return;
  const { ok, json } = await safeFetch(`/admin/terms/versions/${encodeURIComponent(id)}`, { headers: getAuthHeaders() });
  if (!ok || !json.data) {
    showToast(json.message || 'Draf tidak dapat dimuat', 'error');
    return;
  }
  termsEditingId = id;
  document.getElementById('termsEditorTitle').textContent = `Ubah Draf Versi ${json.data.version_number}`;
  document.getElementById('termsDocNumber').value = json.data.document_number || '';
  document.getElementById('termsChangeSummary').value = json.data.change_summary || '';
  termsVisualData = normalizeVisualContent(json.data.content);
  document.getElementById('termsContentJson').value = JSON.stringify(serializeVisualToCanonicalContent(termsVisualData), null, 2);
  termsEditorMode = 'visual';
  updateTermsEditorModeUI();
  renderTermsVisualBuilder();
  document.getElementById('termsEditorCard').classList.remove('hidden');
  document.getElementById('termsEditorCard').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function toggleTermsEditorMode(mode) {
  if (mode === termsEditorMode) return;
  if (mode === 'json') {
    // Sync visual -> JSON textarea
    const canonical = serializeVisualToCanonicalContent(termsVisualData);
    document.getElementById('termsContentJson').value = JSON.stringify(canonical, null, 2);
    termsEditorMode = 'json';
  } else {
    // Sync JSON textarea -> visual
    try {
      const parsed = JSON.parse(document.getElementById('termsContentJson').value);
      termsVisualData = normalizeVisualContent(parsed);
      termsEditorMode = 'visual';
      renderTermsVisualBuilder();
    } catch (err) {
      showToast('Format JSON tidak valid, perbaiki sebelum beralih ke Editor Visual: ' + err.message, 'error');
      return;
    }
  }
  updateTermsEditorModeUI();
}

function updateTermsEditorModeUI() {
  const visWrap = document.getElementById('termsVisualEditorWrap');
  const jsonWrap = document.getElementById('termsJsonEditorWrap');
  const btnVis = document.getElementById('termsModeVisualBtn');
  const btnJson = document.getElementById('termsModeJsonBtn');
  if (visWrap) visWrap.classList.toggle('hidden', termsEditorMode !== 'visual');
  if (jsonWrap) jsonWrap.classList.toggle('hidden', termsEditorMode !== 'json');
  if (btnVis && btnJson) {
    if (termsEditorMode === 'visual') {
      btnVis.className = 'px-3 py-1.5 rounded-lg text-xs font-bold bg-[#033172] text-white shadow-xs';
      btnJson.className = 'px-3 py-1.5 rounded-lg text-xs font-bold bg-slate-100 text-slate-600 hover:bg-slate-200';
    } else {
      btnJson.className = 'px-3 py-1.5 rounded-lg text-xs font-bold bg-[#033172] text-white shadow-xs';
      btnVis.className = 'px-3 py-1.5 rounded-lg text-xs font-bold bg-slate-100 text-slate-600 hover:bg-slate-200';
    }
  }
}

function renderTermsVisualBuilder() {
  const container = document.getElementById('termsVisualEditorWrap');
  if (!container || !termsVisualData) return;

  const v = termsVisualData;

  const sectionsHtml = v.sections.map((sec, sIdx) => {
    const fieldsHtml = (sec.fields || []).map((f, fIdx) => `
      <div class="grid grid-cols-1 sm:grid-cols-12 gap-2 items-start bg-slate-50 p-2.5 rounded-xl border border-slate-200/80">
        <div class="sm:col-span-4">
          <input type="text" value="${esc(f.label)}" placeholder="Label (contoh: Nama Produk)"
            oninput="termsVisualData.sections[${sIdx}].fields[${fIdx}].label = this.value"
            class="w-full px-3 py-1.5 text-xs font-bold rounded-lg border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">
        </div>
        <div class="sm:col-span-7">
          <input type="text" value="${esc(f.value)}" placeholder="Nilai / Keterangan"
            oninput="termsVisualData.sections[${sIdx}].fields[${fIdx}].value = this.value"
            class="w-full px-3 py-1.5 text-xs rounded-lg border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">
        </div>
        <div class="sm:col-span-1 flex justify-end">
          <button type="button" onclick="removeTermsField(${sIdx}, ${fIdx})" title="Hapus Baris"
            class="p-1.5 rounded-lg text-rose-600 hover:bg-rose-50 border border-transparent hover:border-rose-200">
            <i data-lucide="trash-2" class="w-3.5 h-3.5"></i>
          </button>
        </div>
      </div>
    `).join('');

    const blocksHtml = (sec.blocks || []).map((b, bIdx) => {
      const hasItems = ['numbered', 'bullets', 'table'].includes(b.type);
      const itemsText = (b.items || []).join('\n');
      return `
        <div class="p-3.5 rounded-xl border border-slate-200 bg-slate-50/70 space-y-2.5">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="px-2 py-0.5 rounded bg-slate-200 text-slate-700 text-[10px] font-extrabold">Butir #${bIdx + 1}</span>
              <select onchange="changeTermsBlockType(${sIdx}, ${bIdx}, this.value)"
                class="px-2.5 py-1 rounded-lg border border-slate-200 bg-white text-xs font-bold text-slate-700">
                <option value="paragraph" ${b.type === 'paragraph' ? 'selected' : ''}>Paragraf Klausul</option>
                <option value="numbered" ${b.type === 'numbered' ? 'selected' : ''}>Daftar Bernomor (1, 2, 3...)</option>
                <option value="bullets" ${b.type === 'bullets' ? 'selected' : ''}>Daftar Poin (Bullets)</option>
                <option value="callout" ${b.type === 'callout' ? 'selected' : ''}>Kotak Perhatian / Callout Penting</option>
                <option value="table" ${b.type === 'table' ? 'selected' : ''}>Tabel Ringkasan (Label : Nilai per baris)</option>
              </select>
            </div>
            <div class="flex items-center gap-1">
              <button type="button" onclick="moveTermsBlock(${sIdx}, ${bIdx}, -1)" ${bIdx === 0 ? 'disabled' : ''}
                class="px-2 py-1 rounded text-[10px] font-bold bg-white border border-slate-200 text-slate-600 disabled:opacity-40">Naik</button>
              <button type="button" onclick="moveTermsBlock(${sIdx}, ${bIdx}, 1)" ${bIdx === sec.blocks.length - 1 ? 'disabled' : ''}
                class="px-2 py-1 rounded text-[10px] font-bold bg-white border border-slate-200 text-slate-600 disabled:opacity-40">Turun</button>
              <button type="button" onclick="removeTermsBlock(${sIdx}, ${bIdx})"
                class="px-2 py-1 rounded text-[10px] font-bold bg-rose-50 border border-rose-200 text-rose-600 hover:bg-rose-100">Hapus</button>
            </div>
          </div>
          <div>
            <label class="block text-[10.5px] font-bold text-slate-600 mb-1">
              ${b.type === 'callout' ? 'Teks Peringatan / Callout *' : hasItems ? 'Kalimat Pengantar Butir / Judul Tabel *' : 'Isi Paragraf / Klausul *'}
            </label>
            <textarea rows="2" placeholder="Tulis isi klausul atau kalimat pengantar..."
              oninput="termsVisualData.sections[${sIdx}].blocks[${bIdx}].text = this.value"
              class="w-full px-3 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">${esc(b.text)}</textarea>
          </div>
          ${hasItems ? `
            <div>
              <label class="block text-[10.5px] font-bold text-slate-600 mb-1">
                ${b.type === 'table' ? 'Baris Tabel (Tulis 1 baris per item dengan format "Kolom : Nilai")' : 'Sub-Butir / Item Daftar (Tulis 1 baris untuk setiap poin)'}
              </label>
              <textarea rows="4" placeholder="${b.type === 'table' ? 'Biaya Admin : Rp 0\nLimit Harian : Sesuai ketentuan' : 'Tulis satu butir per baris...'}"
                oninput="termsVisualData.sections[${sIdx}].blocks[${bIdx}].items = this.value.split('\\n')"
                class="w-full px-3 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172] font-mono">${esc(itemsText)}</textarea>
            </div>
          ` : ''}
        </div>
      `;
    }).join('');

    return `
      <div class="p-4 rounded-2xl border border-slate-200 bg-white shadow-xs space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-2 pb-2 border-b border-slate-100">
          <div class="flex items-center gap-2 flex-1 min-w-[240px]">
            <span class="px-2.5 py-1 rounded-lg bg-[#EFF6FF] text-[#033172] border border-blue-200 text-xs font-black">Pasal / Bagian ${sIdx + 1}</span>
            <input type="text" value="${esc(sec.heading)}" placeholder="Judul Bagian (contoh: BAGIAN I — KETENTUAN UMUM)"
              oninput="termsVisualData.sections[${sIdx}].heading = this.value"
              class="flex-1 px-3 py-1.5 text-xs font-extrabold rounded-xl border border-slate-200 focus:outline-none focus:border-[#033172]">
          </div>
          <div class="flex items-center gap-1">
            <button type="button" onclick="moveTermsSection(${sIdx}, -1)" ${sIdx === 0 ? 'disabled' : ''}
              class="px-2.5 py-1 rounded-lg text-[11px] font-bold bg-slate-100 text-slate-600 hover:bg-slate-200 disabled:opacity-40">↑ Naik</button>
            <button type="button" onclick="moveTermsSection(${sIdx}, 1)" ${sIdx === v.sections.length - 1 ? 'disabled' : ''}
              class="px-2.5 py-1 rounded-lg text-[11px] font-bold bg-slate-100 text-slate-600 hover:bg-slate-200 disabled:opacity-40">↓ Turun</button>
            <button type="button" onclick="removeTermsSection(${sIdx})"
              class="px-2.5 py-1 rounded-lg text-[11px] font-bold bg-rose-50 text-rose-600 border border-rose-200 hover:bg-rose-100">Hapus Bagian</button>
          </div>
        </div>

        <!-- Ringkasan Key-Value Fields -->
        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-[11px] font-bold text-slate-600">Baris Ringkasan Informasi (Label : Nilai) — Opsional</span>
            <button type="button" onclick="addTermsField(${sIdx})"
              class="px-2.5 py-1 rounded-lg text-[11px] font-bold text-[#033172] bg-[#EFF6FF] border border-blue-200 hover:bg-blue-100">+ Tambah Baris Label:Nilai</button>
          </div>
          ${fieldsHtml || '<p class="text-[11px] text-slate-400 italic">Tidak ada baris label:nilai pada bagian ini.</p>'}
        </div>

        <!-- Klausul / Blocks -->
        <div class="space-y-2 pt-2 border-t border-slate-100">
          <div class="flex items-center justify-between">
            <span class="text-[11px] font-bold text-slate-600">Daftar Butir Klausul &amp; Paragraf</span>
            <button type="button" onclick="addTermsBlock(${sIdx})"
              class="px-2.5 py-1 rounded-lg text-[11px] font-bold text-white bg-slate-800 hover:bg-slate-900">+ Tambah Butir Klausul</button>
          </div>
          ${blocksHtml || '<p class="text-[11px] text-slate-400 italic">Belum ada butir klausul.</p>'}
        </div>
      </div>
    `;
  }).join('');

  const statementsHtml = (v.consent_statements || []).map((st, idx) => `
    <div class="flex items-start gap-2">
      <span class="px-2 py-1.5 rounded-lg bg-emerald-50 text-emerald-700 border border-emerald-200 text-xs font-black">#${idx + 1}</span>
      <textarea rows="2" maxlength="600"
        oninput="termsVisualData.consent_statements[${idx}] = this.value"
        class="flex-1 px-3 py-2 text-xs rounded-xl border border-slate-200 focus:outline-none focus:border-[#033172]">${esc(st)}</textarea>
      <button type="button" onclick="removeTermsConsentStatement(${idx})" ${v.consent_statements.length <= 1 ? 'disabled' : ''}
        class="p-2 rounded-xl text-rose-600 hover:bg-rose-50 disabled:opacity-30">
        <i data-lucide="trash-2" class="w-4 h-4"></i>
      </button>
    </div>
  `).join('');

  container.innerHTML = `
    <!-- Informasi Kepala Dokumen -->
    <div class="p-4 rounded-2xl border border-slate-200 bg-slate-50/60 space-y-3">
      <div class="text-xs font-extrabold text-slate-700 uppercase tracking-wider">1. Kepala Dokumen &amp; Pengantar</div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <label class="block text-xs font-bold text-slate-700 mb-1">Judul Dokumen Utama *</label>
          <input type="text" value="${esc(v.title)}" maxlength="300"
            oninput="termsVisualData.title = this.value"
            class="w-full px-3.5 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">
        </div>
        <div>
          <label class="block text-xs font-bold text-slate-700 mb-1">Catatan Tanggal / Edisi (Opsional)</label>
          <input type="text" value="${esc(v.date_note)}" maxlength="300" placeholder="Contoh: Edisi Pembaruan Regulasi POJK"
            oninput="termsVisualData.date_note = this.value"
            class="w-full px-3.5 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">
        </div>
      </div>
      <div>
        <label class="block text-xs font-bold text-slate-700 mb-1">Paragraf Pengantar (Opsional)</label>
        <textarea rows="2" maxlength="5000"
          oninput="termsVisualData.intro = this.value"
          class="w-full px-3.5 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">${esc(v.intro)}</textarea>
      </div>
    </div>

    <!-- Daftar Pasal / Bagian -->
    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <div class="text-xs font-extrabold text-slate-700 uppercase tracking-wider">2. Struktur Bagian &amp; Pasal (${v.sections.length} Bagian)</div>
        <button type="button" onclick="addTermsSection()"
          class="px-3.5 py-2 rounded-xl text-xs font-bold text-white bg-[#033172] hover:bg-[#022454] transition">+ Tambah Bagian / Pasal Baru</button>
      </div>
      <div class="space-y-3">${sectionsHtml}</div>
    </div>

    <!-- Pernyataan Persetujuan Nasabah -->
    <div class="p-4 rounded-2xl border border-slate-200 bg-slate-50/60 space-y-3">
      <div class="flex items-center justify-between">
        <div class="text-xs font-extrabold text-slate-700 uppercase tracking-wider">3. Kotak Centang Pernyataan Persetujuan Nasabah (1–5 Poin)</div>
        <button type="button" onclick="addTermsConsentStatement()" ${v.consent_statements.length >= 5 ? 'disabled' : ''}
          class="px-3 py-1.5 rounded-xl text-xs font-bold text-[#033172] bg-white border border-blue-200 hover:bg-[#EFF6FF] disabled:opacity-40">+ Tambah Poin Centang</button>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <label class="block text-xs font-bold text-slate-700 mb-1">Judul Bagian Persetujuan *</label>
          <input type="text" value="${esc(v.consent_heading)}" maxlength="300"
            oninput="termsVisualData.consent_heading = this.value"
            class="w-full px-3.5 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">
        </div>
        <div>
          <label class="block text-xs font-bold text-slate-700 mb-1">Instruksi Persetujuan (Opsional)</label>
          <input type="text" value="${esc(v.consent_instruction)}" maxlength="300"
            oninput="termsVisualData.consent_instruction = this.value"
            class="w-full px-3.5 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-none focus:border-[#033172]">
        </div>
      </div>
      <div class="space-y-2">${statementsHtml}</div>
    </div>
  `;

  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function addTermsSection() {
  termsVisualData.sections.push({
    heading: `BAGIAN ${termsVisualData.sections.length + 1} — JUDUL BAGIAN`,
    fields: [],
    blocks: [{ type: 'paragraph', text: 'Tulis klausul bagian ini.', items: [] }]
  });
  renderTermsVisualBuilder();
}

function removeTermsSection(sIdx) {
  if (termsVisualData.sections.length <= 1) {
    showToast('Dokumen minimal harus memiliki 1 bagian.', 'warning');
    return;
  }
  termsVisualData.sections.splice(sIdx, 1);
  renderTermsVisualBuilder();
}

function moveTermsSection(sIdx, dir) {
  const next = sIdx + dir;
  if (next < 0 || next >= termsVisualData.sections.length) return;
  const tmp = termsVisualData.sections[sIdx];
  termsVisualData.sections[sIdx] = termsVisualData.sections[next];
  termsVisualData.sections[next] = tmp;
  renderTermsVisualBuilder();
}

function addTermsField(sIdx) {
  termsVisualData.sections[sIdx].fields.push({ label: '', value: '' });
  renderTermsVisualBuilder();
}

function removeTermsField(sIdx, fIdx) {
  termsVisualData.sections[sIdx].fields.splice(fIdx, 1);
  renderTermsVisualBuilder();
}

function addTermsBlock(sIdx) {
  termsVisualData.sections[sIdx].blocks.push({ type: 'paragraph', text: '', items: [] });
  renderTermsVisualBuilder();
}

function removeTermsBlock(sIdx, bIdx) {
  termsVisualData.sections[sIdx].blocks.splice(bIdx, 1);
  renderTermsVisualBuilder();
}

function moveTermsBlock(sIdx, bIdx, dir) {
  const arr = termsVisualData.sections[sIdx].blocks;
  const next = bIdx + dir;
  if (next < 0 || next >= arr.length) return;
  const tmp = arr[bIdx];
  arr[bIdx] = arr[next];
  arr[next] = tmp;
  renderTermsVisualBuilder();
}

function changeTermsBlockType(sIdx, bIdx, newType) {
  const blk = termsVisualData.sections[sIdx].blocks[bIdx];
  blk.type = newType;
  if (['numbered', 'bullets', 'table'].includes(newType) && (!blk.items || blk.items.length === 0)) {
    blk.items = [''];
  }
  renderTermsVisualBuilder();
}

function addTermsConsentStatement() {
  if (termsVisualData.consent_statements.length >= 5) return;
  termsVisualData.consent_statements.push('Saya menyetujui ketentuan di atas.');
  renderTermsVisualBuilder();
}

function removeTermsConsentStatement(idx) {
  if (termsVisualData.consent_statements.length <= 1) return;
  termsVisualData.consent_statements.splice(idx, 1);
  renderTermsVisualBuilder();
}

function closeTermsEditor() {
  termsEditingId = null;
  document.getElementById('termsEditorCard').classList.add('hidden');
}

async function saveTermsDraft() {
  if (!termsEditingId || !canMutateTerms()) return;
  let content;
  if (termsEditorMode === 'visual') {
    content = serializeVisualToCanonicalContent(termsVisualData);
    document.getElementById('termsContentJson').value = JSON.stringify(content, null, 2);
  } else {
    try {
      content = JSON.parse(document.getElementById('termsContentJson').value);
    } catch (err) {
      showToast('Format JSON tidak valid: ' + err.message, 'error');
      return;
    }
  }
  const { ok, json } = await safeFetch(`/admin/terms/versions/${encodeURIComponent(termsEditingId)}`, {
    method: 'PUT',
    headers: getAuthHeaders(),
    body: JSON.stringify({
      content,
      document_number: document.getElementById('termsDocNumber').value.trim(),
      change_summary: document.getElementById('termsChangeSummary').value.trim()
    })
  });
  showToast(ok && json.success ? 'Draf disimpan. Buat ulang PDF draf sebelum diajukan.' : (json.message || 'Gagal menyimpan draf'), ok && json.success ? 'success' : 'error');
  if (ok && json.success) closeTermsEditor();
  loadTermsVersions();
}

function generateTermsPdf(id) {
  if (!canMutateTerms()) return;
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/pdf`, null, 'PDF draf berhasil dibuat. Unduh dan periksa sebelum diajukan.');
}

async function uploadTermsPdf(id, input) {
  const file = input.files && input.files[0];
  if (!file || !canMutateTerms()) return;
  if (file.type !== 'application/pdf' && !file.name.toLowerCase().endsWith('.pdf')) {
    showToast('File harus berformat PDF.', 'error');
    input.value = '';
    return;
  }
  if (file.size > 10 * 1024 * 1024) {
    showToast('Ukuran file PDF maksimal 10 MB.', 'error');
    input.value = '';
    return;
  }
  const fd = new FormData();
  fd.append('file', file);
  try {
    const res = await fetch(`${API_BASE}/admin/terms/versions/${encodeURIComponent(id)}/pdf/upload`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: getAuthHeaders(false),
      body: fd
    });
    const json = await res.json();
    if (!res.ok || !json.success) throw new Error(json.message || 'Gagal mengunggah PDF');
    showToast('PDF draf berhasil diunggah. Unduh & periksa sebelum diajukan.', 'success');
    await loadTermsVersions();
  } catch (err) {
    showToast(err.message || 'Gagal mengunggah PDF', 'error');
  } finally {
    input.value = '';
  }
}

/**
 * Downloads a PDF fetched with the officer token (the token is never put in a URL).
 */
async function openTermsPdf(id, type) {
  try {
    const kind = type === 'draft' ? 'draft' : 'final';
    const res = await fetch(`${API_BASE}/admin/terms/versions/${encodeURIComponent(id)}/pdf?type=${kind}`, {
      credentials: 'same-origin',
      headers: getAuthHeaders(false)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const blob = await res.blob();
    if (blob.type !== 'application/pdf') throw new Error('respons bukan PDF');
    const version = res.headers.get('X-Document-Version') || '';
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `SK-Mobile-Banking-v${version}${kind === 'draft' ? '-DRAF' : ''}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
    showToast('PDF diunduh. Buka berkasnya untuk memeriksa isi dan tata letak.', 'success');
  } catch (err) {
    showToast('PDF tidak dapat diunduh: ' + err.message, 'error');
  }
}

async function submitTerms(id, versionNum = '') {
  if (!canMutateTerms()) return;
  const raw = await showConfirmModal({
    title: `Ajukan Persetujuan SK ${versionNum ? 'Versi ' + versionNum : ''}`,
    message: 'Tentukan tanggal & jam mulai berlaku (WIB). Setelah diajukan, dokumen harus disetujui oleh petugas lain (Maker-Checker).',
    confirmText: 'Ajukan Persetujuan',
    cancelText: 'Batal',
    variant: 'primary',
    showInput: true,
    requireInput: 'optional',
    inputType: 'datetime-local',
    inputLabel: 'Tanggal & Jam Mulai Berlaku (WIB)',
    inputDefaultValue: getLocalDatetimeDefault(),
    inputHelp: 'Kosongkan bila ingin langsung berlaku pada saat disetujui.'
  });
  if (raw === null || raw === false) return;

  let effective = '';
  if (typeof raw === 'string' && raw.trim() !== '') {
    const rfc = localDatetimeToRFC3339WIB(raw);
    if (!rfc) {
      showToast('Format tanggal mulai berlaku tidak valid', 'error');
      return;
    }
    effective = rfc;
  }
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/submit`, { effective_from: effective },
    'Draf diajukan. Persetujuan harus dilakukan petugas lain (maker-checker).');
}

async function approveTerms(id, version) {
  if (!canMutateTerms()) return;
  const raw = await showConfirmModal({
    title: `Setujui & Terbitkan SK Versi ${version}`,
    message: `Setujui dan terbitkan Syarat & Ketentuan versi ${version}? Versi terbit bersifat mengikat, tidak dapat diubah, dan nasabah wajib menyetujuinya pada saat berlaku.`,
    confirmText: 'Ya, Setujui & Terbitkan',
    cancelText: 'Batal',
    variant: 'primary',
    showInput: true,
    requireInput: 'optional',
    inputType: 'datetime-local',
    inputLabel: 'Tanggal & Jam Mulai Berlaku (WIB)',
    inputDefaultValue: getLocalDatetimeDefault(),
    inputHelp: 'Format waktu akan dikonversi otomatis ke RFC3339 (+07:00).'
  });
  if (raw === null || raw === false) return;

  let body = null;
  if (typeof raw === 'string' && raw.trim() !== '') {
    const rfc = localDatetimeToRFC3339WIB(raw);
    if (rfc) {
      body = { effective_from: rfc };
    }
  }
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/approve`, body, `SK versi ${version} berhasil diterbitkan.`);
}

async function rejectTerms(id) {
  if (!canMutateTerms()) return;
  const reason = await showConfirmModal({
    title: 'Kembalikan SK ke Draf',
    message: 'Masukkan alasan pengembalian dokumen ke status draf:',
    confirmText: 'Kembalikan ke Draf',
    cancelText: 'Batal',
    variant: 'danger',
    requireInput: true,
    inputType: 'textarea',
    inputLabel: 'Alasan Penolakan / Koreksi',
    inputPlaceholder: 'Contoh: Perlu penyesuaian klausul perlindungan data pribadi nasabah...'
  });
  if (!reason) return;
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/reject`, { reason: reason.trim() }, 'Dokumen dikembalikan ke draf.');
}

async function archiveTerms(id, version) {
  if (!canMutateTerms()) return;
  const confirmed = await showConfirmModal({
    title: `Arsipkan SK Versi ${version}`,
    message: `Arsipkan Syarat & Ketentuan versi ${version}? Dokumen PDF tetap tersimpan permanen sebagai bukti audit historis.`,
    confirmText: 'Ya, Arsipkan',
    cancelText: 'Batal',
    variant: 'warning'
  });
  if (!confirmed) return;
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/archive`, null, `SK versi ${version} diarsipkan.`);
}

async function loadTermsAcceptances() {
  const box = document.getElementById('termsAcceptanceList');
  const uid = document.getElementById('termsAcceptUserId').value.trim();
  box.textContent = 'Memuat...';
  const q = uid ? `?user_id=${encodeURIComponent(uid)}` : '';
  const { ok, json } = await safeFetch(`/admin/terms/acceptances${q}`, { headers: getAuthHeaders() });
  if (!ok || !Array.isArray(json.data)) {
    box.textContent = json.message || 'Riwayat tidak dapat dimuat.';
    return;
  }
  if (json.data.length === 0) {
    box.textContent = 'Belum ada catatan persetujuan.';
    return;
  }
  box.innerHTML = `<table class="w-full text-[11px]"><thead><tr class="text-left text-slate-500">
      <th class="py-1">Waktu (server)</th><th>Versi</th><th>Kanal</th><th>Nasabah</th><th>SHA-256 PDF</th></tr></thead><tbody>` +
    json.data.map(a => `<tr class="border-t border-slate-100">
      <td class="py-1.5">${esc(termsDate(a.accepted_at))}</td><td class="font-bold">v${esc(a.version_number)}</td><td>${esc(a.channel)}</td>
      <td class="font-mono">${esc(a.user_id || '(perangkat, sebelum login)')}</td><td class="font-mono text-slate-500" title="${esc(a.pdf_sha256 || '')}">${esc((a.pdf_sha256 || '').substring(0, 12))}…</td></tr>`).join('') +
    '</tbody></table>';
}
