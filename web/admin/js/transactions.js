/**
 * Audit & Transaction Monitoring Module
 */

async function loadTransactions() {
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

