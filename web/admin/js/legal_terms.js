/**
 * Syarat & Ketentuan (SK) — manajemen versi, PDF, dan maker-checker (internal/legaldoc).
 * Isi dikelola sebagai JSON terstruktur; PDF dibuat backend. Versi terbit tidak dapat
 * diubah; persetujuan nasabah tercatat di backend.
 */
let termsVersions = [];
let termsEditingId = null;

const TERMS_STATUS_LABEL = {
  DRAFT: ['Draf', 'bg-amber-50 text-amber-700 border-amber-200'],
  PENDING_APPROVAL: ['Menunggu Persetujuan', 'bg-blue-50 text-blue-700 border-blue-200'],
  PUBLISHED: ['Terbit', 'bg-emerald-50 text-emerald-700 border-emerald-200'],
  ARCHIVED: ['Arsip', 'bg-slate-100 text-slate-500 border-slate-200']
};

function termsDate(v) {
  if (!v) return '-';
  try { return new Date(v).toLocaleString('id-ID'); } catch (_) { return String(v); }
}

async function loadTermsVersions() {
  const list = document.getElementById('termsVersionList');
  const info = document.getElementById('termsActiveInfo');
  if (!list) return;
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
  const newBtn = document.getElementById('termsNewDraftBtn');
  if (newBtn) newBtn.disabled = hasOpen;

  list.innerHTML = termsVersions.map(v => {
    const [label, cls] = TERMS_STATUS_LABEL[v.status] || [v.status, 'bg-slate-50'];
    const id = jsArg(v.id);
    const actions = [];
    if (v.status === 'DRAFT') {
      actions.push(`<button type="button" onclick="openTermsEditor(${id})" class="text-slate-700 font-bold hover:underline">Ubah</button>`);
      actions.push(`<button type="button" onclick="generateTermsPdf(${id})" class="text-slate-700 font-bold hover:underline">Buat PDF Draf</button>`);
      if (v.draft_pdf_sha256) {
        actions.push(`<button type="button" onclick="openTermsPdf(${id}, 'draft')" class="text-[#00897B] font-bold hover:underline">Unduh PDF Draf</button>`);
        actions.push(`<button type="button" onclick="submitTerms(${id})" class="text-blue-700 font-bold hover:underline">Ajukan Persetujuan</button>`);
      }
    }
    if (v.status === 'PENDING_APPROVAL') {
      actions.push(`<button type="button" onclick="openTermsPdf(${id}, 'draft')" class="text-[#00897B] font-bold hover:underline">Unduh PDF Draf</button>`);
      actions.push(`<button type="button" onclick="approveTerms(${id}, ${jsArg(v.version_number)})" class="text-emerald-700 font-bold hover:underline">Setujui &amp; Terbitkan</button>`);
      actions.push(`<button type="button" onclick="rejectTerms(${id})" class="text-rose-600 font-bold hover:underline">Kembalikan ke Draf</button>`);
    }
    if (v.status === 'PUBLISHED' || v.status === 'ARCHIVED') {
      actions.push(`<button type="button" onclick="openTermsPdf(${id}, 'final')" class="text-[#00897B] font-bold hover:underline">Unduh PDF</button>`);
    }
    if (v.status === 'PUBLISHED' && !v.is_active) {
      actions.push(`<button type="button" onclick="archiveTerms(${id}, ${jsArg(v.version_number)})" class="text-slate-500 font-bold hover:underline">Arsipkan</button>`);
    }
    return `<div class="p-3 rounded-xl border border-slate-200 bg-slate-50/60 space-y-1">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs font-black text-slate-800">Versi ${esc(v.version_number)}</span>
        <span class="px-2 py-0.5 rounded-full border text-[10px] font-bold ${cls}">${esc(label)}</span>
        ${v.is_active ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-600 text-white">AKTIF</span>' : ''}
        ${v.document_number ? `<span class="text-[11px] text-slate-500">No. ${esc(v.document_number)}</span>` : ''}
      </div>
      <p class="text-[11px] text-slate-500">${esc(v.change_summary || '')}</p>
      <p class="text-[11px] text-slate-400">Dibuat ${esc(termsDate(v.created_at))} oleh ${esc(v.created_by_name || v.created_by)}
        ${v.published_at ? ' · terbit ' + esc(termsDate(v.published_at)) + ' oleh ' + esc(v.approved_by_name || '-') + ' · berlaku ' + esc(termsDate(v.effective_from)) : ''}
        ${v.pdf_sha256 ? ' · SHA-256 PDF ' + esc(v.pdf_sha256.substring(0, 16)) + '…' : ''}</p>
      <div class="flex flex-wrap gap-3 text-[11px] pt-1">${actions.join('')}</div>
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
  const latest = termsVersions[0];
  if (!latest) return;
  await termsAction('/admin/terms/versions', { base_version_id: latest.id, change_summary: `Revisi dari versi ${latest.version_number}` },
    'Draf versi baru dibuat dari versi terakhir.');
}

async function openTermsEditor(id) {
  const { ok, json } = await safeFetch(`/admin/terms/versions/${encodeURIComponent(id)}`, { headers: getAuthHeaders() });
  if (!ok || !json.data) {
    showToast(json.message || 'Draf tidak dapat dimuat', 'error');
    return;
  }
  termsEditingId = id;
  document.getElementById('termsEditorTitle').textContent = `Ubah Draf Versi ${json.data.version_number}`;
  document.getElementById('termsDocNumber').value = json.data.document_number || '';
  document.getElementById('termsChangeSummary').value = json.data.change_summary || '';
  document.getElementById('termsContentJson').value = JSON.stringify(json.data.content, null, 2);
  document.getElementById('termsEditorCard').classList.remove('hidden');
}

function closeTermsEditor() {
  termsEditingId = null;
  document.getElementById('termsEditorCard').classList.add('hidden');
}

async function saveTermsDraft() {
  if (!termsEditingId) return;
  let content;
  try {
    content = JSON.parse(document.getElementById('termsContentJson').value);
  } catch (err) {
    showToast('Format JSON tidak valid: ' + err.message, 'error');
    return;
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
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/pdf`, null, 'PDF draf dibuat. Periksa sebelum diajukan.');
}

/**
 * Downloads a PDF fetched with the officer token (the token is never put in a URL).
 * The file is saved by the browser and opened in the officer's PDF reader for review.
 */
async function openTermsPdf(id, type) {
  try {
    const kind = type === 'draft' ? 'draft' : 'final';
    const res = await fetch(`${API_BASE}/admin/terms/versions/${encodeURIComponent(id)}/pdf?type=${kind}`, {
      headers: { 'Authorization': `Bearer ${localStorage.getItem('dmb_admin_token')}` }
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

function submitTerms(id) {
  const raw = prompt('Tanggal & jam mulai berlaku (format 2026-12-01 00:00, WIB). Kosongkan = berlaku saat disetujui.', '');
  if (raw === null) return;
  let effective = '';
  if (raw.trim() !== '') {
    const m = raw.trim().match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?$/);
    if (!m) {
      showToast('Format tanggal tidak valid', 'error');
      return;
    }
    effective = `${m[1]}-${m[2]}-${m[3]}T${m[4] || '00'}:${m[5] || '00'}:00+07:00`;
  }
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/submit`, { effective_from: effective },
    'Diajukan. Persetujuan harus dilakukan petugas lain (maker-checker).');
}

function approveTerms(id, version) {
  if (!confirm(`Setujui dan terbitkan SK versi ${version}? Versi terbit tidak dapat diubah, dan nasabah wajib menyetujuinya setelah berlaku.`)) return;
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/approve`, null, `SK versi ${version} diterbitkan.`);
}

function rejectTerms(id) {
  const reason = prompt('Alasan dikembalikan ke draf:', '');
  if (!reason) return;
  termsAction(`/admin/terms/versions/${encodeURIComponent(id)}/reject`, { reason }, 'Dikembalikan ke draf.');
}

function archiveTerms(id, version) {
  if (!confirm(`Arsipkan SK versi ${version}? Dokumen tetap tersimpan sebagai bukti.`)) return;
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
      <th class="py-1">Waktu (server)</th><th>Versi</th><th>Kanal</th><th>Nasabah</th><th>PDF</th></tr></thead><tbody>` +
    json.data.map(a => `<tr class="border-t border-slate-100">
      <td class="py-1">${esc(termsDate(a.accepted_at))}</td><td>${esc(a.version_number)}</td><td>${esc(a.channel)}</td>
      <td>${esc(a.user_id || '(perangkat, sebelum login)')}</td><td>${esc((a.pdf_sha256 || '').substring(0, 12))}…</td></tr>`).join('') +
    '</tbody></table>';
}
