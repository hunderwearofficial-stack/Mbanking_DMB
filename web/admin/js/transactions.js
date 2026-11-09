/**
 * Audit & Transaction Monitoring Module (Financial + OJK Security Audit Trail)
 */

let cachedAuditLogs = [];

async function loadTransactions() {
  loadAuditLogs();

  const tbody = document.getElementById('transactionsTableBody');
  if (!tbody) return;

  tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Memuat log transaksi...</td></tr>`;

  try {
    const { ok, json } = await safeFetch('/admin/transactions?limit=50', { headers: getAuthHeaders() });

    if (ok && json.data && json.data.length > 0) {
      tbody.innerHTML = json.data.map(tx => `
        <tr class="hover:bg-slate-50 transition">
          <td class="py-3 px-4 text-slate-500">${formatDateTime(tx.created_at)}</td>
          <td class="py-3 px-4 font-bold text-slate-800">${tx.transaction_type}</td>
          <td class="py-3 px-4 font-mono text-slate-700">${tx.from_account}</td>
          <td class="py-3 px-4 font-mono text-slate-700">${tx.to_account}</td>
          <td class="py-3 px-4 font-bold text-slate-900">Rp ${Number(tx.amount).toLocaleString('id-ID')}</td>
          <td class="py-3 px-4 font-mono text-[11px] text-slate-500">${tx.cbs_ref_no || '-'}</td>
          <td class="py-3 px-4">
            <span class="inline-flex px-2 py-0.5 rounded-full text-[10px] font-bold ${tx.status === 'SUCCESS' ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-800'}">
              ${tx.status}
            </span>
          </td>
        </tr>
      `).join('');
    } else {
      tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Belum ada catatan transaksi</td></tr>`;
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-rose-500">Error: ${e.message}</td></tr>`;
  }
}

async function loadAuditLogs() {
  const tbody = document.getElementById('auditLogsTableBody');
  if (!tbody) return;

  const filterEl = document.getElementById('auditActorFilter');
  const actorType = filterEl ? filterEl.value : 'ALL';

  tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Memuat data audit trail keamanan...</td></tr>`;

  try {
    const { ok, json } = await safeFetch(`/admin/audit-logs?actor_type=${encodeURIComponent(actorType)}&limit=100`, {
      headers: getAuthHeaders()
    });

    if (ok && json.data && json.data.length > 0) {
      cachedAuditLogs = json.data;
      tbody.innerHTML = json.data.map(log => {
        let statusClass = 'bg-emerald-100 text-emerald-800';
        if (log.status === 'WARNING') statusClass = 'bg-amber-100 text-amber-800';
        if (log.status === 'DANGER') statusClass = 'bg-rose-100 text-rose-800';

        const actorBadge = log.actor_type === 'ADMIN'
          ? '<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-purple-100 text-purple-800">ADMIN</span>'
          : '<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-blue-100 text-blue-800">NASABAH</span>';

        return `
          <tr class="hover:bg-slate-50 transition">
            <td class="py-3 px-4 text-slate-500 whitespace-nowrap">${formatDateTime(log.created_at)}</td>
            <td class="py-3 px-4">
              <div class="flex items-center gap-1.5">
                ${actorBadge}
                <span class="font-bold text-slate-800">${log.actor_name || '-'}</span>
              </div>
            </td>
            <td class="py-3 px-4 font-mono font-bold text-slate-800">${log.action}</td>
            <td class="py-3 px-4 font-mono text-slate-600">${log.target || '-'}</td>
            <td class="py-3 px-4 font-mono text-[11px] text-slate-600">${log.device_id || '-'}</td>
            <td class="py-3 px-4 text-slate-600 max-w-xs">${log.details || '-'}</td>
            <td class="py-3 px-4">
              <span class="inline-flex px-2 py-0.5 rounded-full text-[10px] font-bold ${statusClass}">
                ${log.status}
              </span>
            </td>
          </tr>
        `;
      }).join('');
    } else {
      cachedAuditLogs = [];
      tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Belum ada rekam jejak audit keamanan</td></tr>`;
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-rose-500">Error: ${e.message}</td></tr>`;
  }
}

function exportAuditLogsCSV() {
  if (!cachedAuditLogs || cachedAuditLogs.length === 0) {
    showToast('Belum ada data audit log untuk di-export', 'info');
    return;
  }
  const headers = ['Waktu', 'Tipe Aktor', 'Nama Aktor', 'Aksi', 'Target', 'Device ID', 'Status', 'Detail'];
  const rows = cachedAuditLogs.map(l => [
    l.created_at,
    l.actor_type,
    `"${(l.actor_name || '').replace(/"/g, '""')}"`,
    l.action,
    `"${(l.target || '').replace(/"/g, '""')}"`,
    `"${(l.device_id || '').replace(/"/g, '""')}"`,
    l.status,
    `"${(l.details || '').replace(/"/g, '""')}"`
  ]);
  const csvContent = 'data:text/csv;charset=utf-8,' + [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
  const encodedUri = encodeURI(csvContent);
  const link = document.createElement('a');
  link.setAttribute('href', encodedUri);
  link.setAttribute('download', `Audit_Trail_Mbanking_DMB_${new Date().toISOString().slice(0, 10)}.csv`);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  showToast('File CSV Audit Trail berhasil diunduh', 'success');
}

function formatDateTime(isoString) {
  if (!isoString) return '-';
  const d = new Date(isoString);
  return d.toLocaleDateString('id-ID', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

