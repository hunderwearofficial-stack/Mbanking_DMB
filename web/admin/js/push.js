/**
 * Notifikasi Push — integrasi Firebase (FCM HTTP v1), pembuatan notifikasi dengan
 * maker-checker, riwayat dan hasil pengiriman (internal/push).
 */
const pushState = { settings: null, campaigns: [] };

const PUSH_STATUS = {
  DRAFT: ['Draf', 'bg-amber-50 text-amber-700 border-amber-200'],
  PENDING_APPROVAL: ['Menunggu Persetujuan', 'bg-blue-50 text-blue-700 border-blue-200'],
  REJECTED: ['Ditolak', 'bg-rose-50 text-rose-700 border-rose-200'],
  SENDING: ['Sedang Dikirim', 'bg-indigo-50 text-indigo-700 border-indigo-200'],
  SENT: ['Diterima FCM', 'bg-emerald-50 text-emerald-700 border-emerald-200'],
  PARTIAL: ['Sebagian Gagal', 'bg-amber-50 text-amber-800 border-amber-300'],
  FAILED: ['Gagal', 'bg-rose-50 text-rose-700 border-rose-200'],
  NO_RECIPIENT: ['Tidak Ada Perangkat', 'bg-slate-100 text-slate-600 border-slate-200']
};
const DELIVERY_STATUS = {
  QUEUED: 'Antre', ACCEPTED: 'Diterima FCM', FAILED: 'Gagal', INVALID_TOKEN: 'Token tidak valid (perangkat dilepas)'
};

function pushRole() {
  try { return JSON.parse(localStorage.getItem('dmb_admin_user') || '{}'); } catch (_) { return {}; }
}
function pushDate(v) {
  if (!v) return '-';
  try { return new Date(v).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }); } catch (_) { return String(v); }
}
function pushPill(status) {
  const [label, cls] = PUSH_STATUS[status] || [status, 'bg-slate-50 text-slate-600 border-slate-200'];
  return `<span class="inline-flex px-2 py-0.5 rounded-full border text-[10px] font-bold ${cls}">${esc(label)}</span>`;
}

async function loadPush() {
  const me = pushRole();
  document.getElementById('pushAdminActions').classList.toggle('hidden', me.role !== 'SUPER_ADMIN');
  document.getElementById('pushComposeCard').classList.toggle('hidden', !['SUPER_ADMIN', 'MARKETING'].includes(me.role));
  const s = await safeFetch('/admin/push/settings', { headers: getAuthHeaders() });
  if (!s.ok || !s.json.data) {
    document.getElementById('pushStatusBadge').textContent = s.json.message || 'Tidak tersedia untuk peran Anda';
    return;
  }
  pushState.settings = s.json.data;
  renderPushSettings();
  await loadPushCampaigns();
}

function renderPushSettings() {
  const v = pushState.settings;
  const badge = document.getElementById('pushStatusBadge');
  const state = !v.credential_configured ? ['Belum dikonfigurasi', 'bg-slate-100 text-slate-600 border-slate-200']
    : v.enabled ? ['Aktif', 'bg-emerald-50 text-emerald-700 border-emerald-200']
      : ['Nonaktif', 'bg-amber-50 text-amber-700 border-amber-200'];
  badge.textContent = state[0];
  badge.className = `px-2.5 py-1 rounded-full border text-[11px] font-bold ${state[1]}`;
  const item = (label, value) => `<div><dt class="text-[10px] font-extrabold text-slate-400 uppercase tracking-wider">${esc(label)}</dt><dd class="mt-1 text-slate-800 break-all">${value}</dd></div>`;
  const test = v.last_test_at
    ? `${v.last_test_ok ? '<span class="text-emerald-700 font-bold">Berhasil</span>' : '<span class="text-rose-700 font-bold">Gagal</span>'} &middot; ${esc(pushDate(v.last_test_at))}`
    : 'Belum pernah diuji';
  document.getElementById('pushSettingsGrid').innerHTML =
    item('Firebase Project ID', esc(v.project_id || '-')) +
    item('Akun layanan (Admin SDK)', esc(v.client_email || '-')) +
    item('Credential', v.credential_configured
      ? `Tersimpan terenkripsi &middot; sidik ${esc(v.credential_fingerprint)}…<br><span class="text-slate-500">diganti ${esc(pushDate(v.credential_updated_at))} oleh ${esc(v.credential_updated_by || '-')}</span>`
      : 'Belum diunggah') +
    item('Uji koneksi terakhir', test) +
    item('Perangkat terdaftar aktif', esc(v.active_devices)) +
    item('24 jam terakhir', `Diterima FCM ${esc(v.last_24h.accepted)} &middot; gagal ${esc(v.last_24h.failed)} &middot; token tidak valid ${esc(v.last_24h.invalid_token)}`);
  const err = document.getElementById('pushErrorBox');
  err.classList.toggle('hidden', !v.last_test_error);
  err.textContent = v.last_test_error ? 'Kesalahan uji koneksi terakhir: ' + v.last_test_error : '';
  const enableBtn = document.getElementById('pushEnableBtn');
  enableBtn.textContent = v.enabled ? 'Nonaktifkan' : 'Aktifkan';
  enableBtn.disabled = !v.enabled && !(v.credential_configured && v.tested_current_credential);
  enableBtn.title = enableBtn.disabled ? 'Unggah credential dan lakukan Uji Koneksi sampai berhasil' : '';
  document.getElementById('pushTestBtn').disabled = !v.credential_configured;
}

async function uploadPushCredential(input) {
  const file = input.files && input.files[0];
  input.value = '';
  if (!file) return;
  if (file.size > 32 * 1024) {
    showToast('Berkas terlalu besar untuk service account', 'error');
    return;
  }
  const confirmed = await showConfirmModal({
    title: 'Unggah Credential Firebase Admin SDK',
    message: 'Unggah berkas service account JSON baru? Credential lama akan diganti dan integrasi pengiriman dinonaktifkan sementara hingga Anda melakukan Uji Koneksi & mengaktifkannya kembali.',
    confirmText: 'Ya, Unggah Credential',
    cancelText: 'Batal',
    variant: 'warning'
  });
  if (!confirmed) return;
  const fd = new FormData();
  fd.append('file', file);
  try {
    const res = await fetch(`${API_BASE}/admin/push/credential`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: getAuthHeaders(false),
      body: fd
    });
    const json = await res.json();
    showToast(json.message || (res.ok ? 'Credential disimpan' : 'Credential ditolak'), res.ok && json.success ? 'success' : 'error');
  } catch (err) {
    showToast('Gagal mengunggah: ' + err.message, 'error');
  }
  loadPush();
}

async function pushPost(path, method, body, okMsg) {
  const { ok, json } = await safeFetch(path, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined });
  showToast(ok && json.success ? (okMsg || json.message) : (json.message || 'Tindakan gagal'), ok && json.success ? 'success' : 'error');
  return { ok: ok && json.success, json };
}

async function testPushConnection() {
  const btn = document.getElementById('pushTestBtn');
  btn.disabled = true;
  await pushPost('/admin/push/test', 'POST', null);
  loadPush();
}

async function togglePushEnabled() {
  const enable = !pushState.settings.enabled;
  const confirmed = await showConfirmModal({
    title: enable ? 'Aktifkan Pengiriman Notifikasi Push' : 'Nonaktifkan Pengiriman Notifikasi Push',
    message: enable
      ? 'Aktifkan pengiriman notifikasi push ke perangkat HP nasabah melalui Firebase Cloud Messaging?'
      : 'Nonaktifkan pengiriman notifikasi push Firebase? Notifikasi tetap tersimpan di kotak masuk aplikasi nasabah.',
    confirmText: enable ? 'Ya, Aktifkan' : 'Ya, Nonaktifkan',
    cancelText: 'Batal',
    variant: enable ? 'primary' : 'warning'
  });
  if (!confirmed) return;
  await pushPost('/admin/push/settings', 'PUT', { enabled: enable });
  loadPush();
}

async function createPushCampaign(e) {
  e.preventDefault();
  const target = document.getElementById('pushTarget').value;
  const created = await pushPost('/admin/push/campaigns', 'POST', {
    title: document.getElementById('pushTitle').value,
    body: document.getElementById('pushBody').value,
    category: document.getElementById('pushCategory').value,
    target_type: target,
    target_user_id: target === 'USER' ? document.getElementById('pushTargetUser').value.trim() : ''
  }, 'Draf dibuat');
  if (!created.ok) return;
  await pushPost(`/admin/push/campaigns/${encodeURIComponent(created.json.data.id)}/submit`, 'POST', null, 'Diajukan. Persetujuan dilakukan petugas lain.');
  document.getElementById('pushComposeForm').reset();
  document.getElementById('pushTargetUserWrap').classList.add('hidden');
  loadPushCampaigns();
}

async function loadPushCampaigns() {
  const body = document.getElementById('pushCampaignBody');
  const { ok, json } = await safeFetch('/admin/push/campaigns?limit=100', { headers: getAuthHeaders() });
  if (!ok || !Array.isArray(json.data)) {
    body.innerHTML = `<tr><td colspan="6" class="py-6 text-center text-rose-600">${esc(json.message || 'Riwayat tidak dapat dimuat')}</td></tr>`;
    return;
  }
  pushState.campaigns = json.data;
  const me = pushRole();
  const canApprove = ['SUPER_ADMIN', 'MARKETING', 'COMPLIANCE'].includes(me.role);
  const canEdit = ['SUPER_ADMIN', 'MARKETING'].includes(me.role);
  body.innerHTML = json.data.map(c => {
    const id = jsArg(c.id);
    const actions = [];
    if (c.status === 'PENDING_APPROVAL' && canApprove) {
      if (c.created_by !== me.id) actions.push(`<button type="button" onclick="approvePushCampaign(${id})" class="text-emerald-700 font-bold hover:underline">Setujui &amp; Kirim</button>`);
      else actions.push('<span class="text-slate-400" title="Maker-checker">Menunggu petugas lain</span>');
      actions.push(`<button type="button" onclick="rejectPushCampaign(${id})" class="text-rose-600 font-bold hover:underline">Tolak</button>`);
    }
    if ((c.status === 'DRAFT' || c.status === 'REJECTED') && canEdit) {
      actions.push(`<button type="button" onclick="submitPushCampaign(${id})" class="text-blue-700 font-bold hover:underline">Ajukan</button>`);
    }
    if (['SENT', 'PARTIAL', 'FAILED', 'SENDING'].includes(c.status)) {
      actions.push(`<button type="button" onclick="showPushDeliveries(${id})" class="text-[#00897B] font-bold hover:underline">Detail</button>`);
    }
    const result = c.send_started_at
      ? `${esc(c.target_devices)} perangkat &middot; diterima FCM ${esc(c.accepted_count)} &middot; gagal ${esc(c.failed_count)} &middot; token tidak valid ${esc(c.invalid_token_count)}${c.last_error ? `<div class="text-rose-600">${esc(c.last_error)}</div>` : ''}`
      : (c.reject_reason ? `<span class="text-rose-600">Alasan: ${esc(c.reject_reason)}</span>` : '-');
    return `<tr class="hover:bg-slate-50 align-top">
      <td class="py-3 px-4 max-w-xs"><div class="font-bold text-slate-900">${esc(c.title)}</div><div class="text-slate-500 whitespace-pre-line">${esc(c.body)}</div><div class="text-[10px] text-slate-400 mt-1">${esc(c.category)}</div></td>
      <td class="py-3 px-4">${c.target_type === 'ALL' ? 'Semua nasabah' : 'Satu nasabah<div class="text-[10px] font-mono text-slate-400">' + esc(c.target_user_id) + '</div>'}</td>
      <td class="py-3 px-4">${pushPill(c.status)}</td>
      <td class="py-3 px-4">${esc(c.created_by_name)}<div class="text-[10px] text-slate-400">${esc(pushDate(c.created_at))}</div>${c.approved_by_name ? `<div class="mt-1">${esc(c.approved_by_name)}</div><div class="text-[10px] text-slate-400">${esc(pushDate(c.approved_at))}</div>` : ''}</td>
      <td class="py-3 px-4">${result}</td>
      <td class="py-3 px-4 text-right whitespace-nowrap space-x-2">${actions.join('')}</td></tr>`;
  }).join('') || '<tr><td colspan="6" class="py-6 text-center text-slate-400">Belum ada notifikasi.</td></tr>';
  if (json.data.some(c => c.status === 'SENDING') && currentTab === 'push') {
    clearTimeout(pushState.timer);
    pushState.timer = setTimeout(loadPushCampaigns, 4000);
  }
}

async function submitPushCampaign(id) {
  await pushPost(`/admin/push/campaigns/${encodeURIComponent(id)}/submit`, 'POST', null);
  loadPushCampaigns();
}

async function approvePushCampaign(id) {
  const c = pushState.campaigns.find(x => x.id === id);
  if (!c) return;
  const confirmed = await showConfirmModal({
    title: 'Setujui & Kirim Notifikasi Push',
    message: `Setujui dan kirim notifikasi "${c.title}" ke ${c.target_type === 'ALL' ? 'SEMUA nasabah aktif' : 'satu nasabah'}? Notifikasi yang telah dikirim ke perangkat tidak dapat ditarik kembali.`,
    confirmText: 'Ya, Setujui & Kirim',
    cancelText: 'Batal',
    variant: 'primary'
  });
  if (!confirmed) return;
  await pushPost(`/admin/push/campaigns/${encodeURIComponent(id)}/approve`, 'POST', null);
  loadPush();
}

async function rejectPushCampaign(id) {
  const reason = await showConfirmModal({
    title: 'Tolak Pengajuan Notifikasi Push',
    message: 'Tuliskan alasan penolakan notifikasi push ini:',
    confirmText: 'Tolak Notifikasi',
    cancelText: 'Batal',
    variant: 'danger',
    requireInput: true,
    inputType: 'textarea',
    inputLabel: 'Alasan Penolakan',
    inputPlaceholder: 'Contoh: Redaksi pesan terlalu panjang atau kurang jelas...'
  });
  if (!reason) return;
  await pushPost(`/admin/push/campaigns/${encodeURIComponent(id)}/reject`, 'POST', { reason: reason.trim() });
  loadPushCampaigns();
}

async function showPushDeliveries(id) {
  const panel = document.getElementById('pushDeliveryPanel');
  panel.classList.remove('hidden');
  panel.textContent = 'Memuat detail pengiriman...';
  const { ok, json } = await safeFetch(`/admin/push/campaigns/${encodeURIComponent(id)}/deliveries`, { headers: getAuthHeaders() });
  if (!ok || !Array.isArray(json.data)) {
    panel.textContent = json.message || 'Detail tidak dapat dimuat.';
    return;
  }
  const c = pushState.campaigns.find(x => x.id === id) || {};
  panel.innerHTML = `<h5 class="text-xs font-bold text-slate-800 mb-2">Detail pengiriman: ${esc(c.title || '')} (${json.data.length} perangkat${json.data.length >= 200 ? ', 200 pertama' : ''})</h5>` +
    (json.data.length ? `<table class="w-full text-xs"><thead class="text-slate-500"><tr>
        <th class="text-left py-1 px-2">Nasabah</th><th class="text-left py-1 px-2">Platform</th><th class="text-left py-1 px-2">Status</th>
        <th class="text-left py-1 px-2">Percobaan</th><th class="text-left py-1 px-2">Dibuka di HP</th><th class="text-left py-1 px-2">Keterangan</th></tr></thead>
      <tbody class="divide-y divide-slate-100">${json.data.map(d => `<tr>
        <td class="py-1.5 px-2 font-mono text-[10px]">${esc(d.user_id)}</td><td class="py-1.5 px-2">${esc(d.platform)}</td>
        <td class="py-1.5 px-2">${esc(DELIVERY_STATUS[d.status] || d.status)}</td><td class="py-1.5 px-2">${esc(d.attempts)}</td>
        <td class="py-1.5 px-2">${d.opened_at ? esc(pushDate(d.opened_at)) : 'Belum ada laporan'}</td>
        <td class="py-1.5 px-2 text-rose-700">${esc(d.error_code ? d.error_code + ': ' + (d.error_message || '') : '')}</td></tr>`).join('')}</tbody></table>`
      : '<p class="text-xs text-slate-500">Tidak ada perangkat penerima.</p>');
}
