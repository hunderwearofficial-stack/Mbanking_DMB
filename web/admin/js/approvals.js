/**
 * Maker-Checker Approval Queue (C-04)
 */
async function loadApprovals() {
  const container = document.getElementById('approvalsList');
  if (!container) return;
  const statusEl = document.getElementById('approvalsFilterStatus');
  const status = statusEl ? statusEl.value : 'PENDING';
  container.innerHTML = '<p class="text-xs text-slate-400">Memuat daftar persetujuan...</p>';
  try {
    const qs = status ? `?status=${encodeURIComponent(status)}&limit=50` : '?limit=50';
    const { ok, json } = await safeFetch(`/admin/approvals${qs}`, { headers: getAuthHeaders() });
    if (!ok || !Array.isArray(json.data)) {
      container.innerHTML = `<p class="text-xs text-rose-600">${esc(json.message || 'Gagal memuat persetujuan')}</p>`;
      return;
    }
    if (json.data.length === 0) {
      container.innerHTML = '<div class="p-6 text-center text-xs text-slate-400 bg-slate-50 rounded-xl border border-slate-200">Tidak ada permintaan persetujuan.</div>';
      return;
    }
    const me = typeof getCurrentUser === 'function' ? getCurrentUser() : {};
    container.innerHTML = json.data.map(item => {
      const pending = item.status === 'PENDING';
      const isSameOfficer = me.id && item.requested_by === me.id;
      const badgeCls = item.status === 'APPROVED'
        ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
        : item.status === 'REJECTED'
          ? 'bg-rose-50 text-rose-700 border-rose-200'
          : 'bg-amber-50 text-amber-700 border-amber-200';
      return `
        <div class="p-4 rounded-xl border border-slate-200 bg-white space-y-2">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="px-2 py-0.5 rounded-md bg-slate-100 text-slate-700 text-[10px] font-bold">${esc(item.kind)}</span>
              <span class="px-2 py-0.5 rounded-full border text-[10px] font-bold ${badgeCls}">${esc(item.status)}</span>
            </div>
            <span class="text-[11px] text-slate-400">${esc(new Date(item.requested_at).toLocaleString('id-ID'))}</span>
          </div>
          <p class="text-xs font-bold text-slate-800">${esc(item.summary)}</p>
          <p class="text-[11px] text-slate-500">Diajukan oleh: <b>${esc(item.requested_by_name)}</b> (${esc(item.requested_by_role)})</p>
          ${item.decided_by_name ? `<p class="text-[11px] text-slate-500">Diputuskan oleh: <b>${esc(item.decided_by_name)}</b>${item.decision_note ? ' — ' + esc(item.decision_note) : ''}</p>` : ''}
          ${pending ? `
            <div class="pt-2 flex flex-wrap items-center gap-2">
              ${isSameOfficer
                ? '<span class="text-[11px] text-amber-700 font-semibold">Menunggu petugas lain (maker tidak bisa menyetujui sendiri)</span>'
                : `<button type="button" onclick="decideApproval(${jsArg(item.id)}, true)" class="px-3 py-1.5 rounded-lg bg-emerald-600 text-white text-xs font-bold hover:bg-emerald-700">Setujui &amp; Jalankan</button>
                   <button type="button" onclick="decideApproval(${jsArg(item.id)}, false)" class="px-3 py-1.5 rounded-lg bg-rose-50 border border-rose-200 text-rose-700 text-xs font-bold hover:bg-rose-100">Tolak</button>`}
            </div>` : ''}
        </div>`;
    }).join('');
  } catch (err) {
    container.innerHTML = `<p class="text-xs text-rose-600">${esc(err.message)}</p>`;
  }
}

async function decideApproval(id, approve) {
  const note = prompt(approve ? 'Catatan persetujuan (opsional):' : 'Alasan penolakan:') ?? '';
  if (!approve && !note.trim()) {
    showToast('Alasan penolakan wajib diisi', 'warning');
    return;
  }
  try {
    const ep = approve ? `/admin/approvals/${encodeURIComponent(id)}/approve` : `/admin/approvals/${encodeURIComponent(id)}/reject`;
    const { ok, json } = await safeFetch(ep, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ note: note.trim() })
    });
    if (!ok || !json.success) {
      showToast(json.message || 'Gagal memproses persetujuan', 'error');
      return;
    }
    if (approve && json.data && json.data.issued_password) {
      showIssuedPassword(json.data.issued_password, json.message);
    } else {
      showToast(json.message || 'Berhasil diproses', 'success');
    }
    loadApprovals();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

/**
 * One-time display of a system-issued officer password (audit MA-03). The console never
 * stores it; closing the dialog removes it from the page.
 */
function showIssuedPassword(password, message) {
  const modal = document.createElement('div');
  modal.className = 'fixed inset-0 z-50 bg-slate-900/60 flex items-center justify-center p-4';
  modal.innerHTML = `
    <div class="bg-white rounded-2xl shadow-2xl border border-slate-200 max-w-md w-full p-6 space-y-4">
      <h3 class="text-base font-extrabold text-slate-900">Kata Sandi Sementara Petugas</h3>
      <p class="text-xs text-slate-600">${esc(message || '')}</p>
      <div class="p-3 rounded-xl bg-slate-50 border border-slate-200 text-center">
        <span class="issued-pw text-base font-mono font-bold tracking-wider text-slate-900 select-all"></span>
      </div>
      <p class="text-[11px] text-rose-700 font-semibold">Kata sandi ini tidak dapat ditampilkan lagi. Jangan kirim melalui chat atau email.</p>
      <div class="flex justify-end gap-2">
        <button type="button" class="copy-pw px-4 py-2 rounded-xl text-xs font-bold text-slate-700 bg-slate-100 hover:bg-slate-200">Salin</button>
        <button type="button" class="close-pw px-4 py-2 rounded-xl text-xs font-bold text-white bg-[#00897B] hover:bg-[#00796B]">Sudah Diserahkan</button>
      </div>
    </div>`;
  modal.querySelector('.issued-pw').textContent = password;
  modal.querySelector('.copy-pw').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(password);
      showToast('Kata sandi disalin', 'info');
    } catch (_) {
      showToast('Salin manual dari kotak di atas', 'warning');
    }
  });
  modal.querySelector('.close-pw').addEventListener('click', () => modal.remove());
  document.body.appendChild(modal);
}
