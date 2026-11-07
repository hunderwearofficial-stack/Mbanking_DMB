/**
 * Dashboard & KPI Overview Module
 */

async function loadDashboardStats() {
  try {
    const { ok, json } = await safeFetch('/admin/stats', { headers: getAuthHeaders() });

    if (ok && json.data) {
      const s = json.data;
      document.getElementById('statTotalUsers').innerText = (s.total_users || 0).toLocaleString();
      document.getElementById('statActiveUsers').innerText = (s.active_users || 0).toLocaleString();
      document.getElementById('statBoundDevices').innerText = (s.bound_devices || 0).toLocaleString();
      document.getElementById('statTotalAccounts').innerText = (s.total_accounts || 0).toLocaleString();
      document.getElementById('statTotalTransactions').innerText = (s.total_transactions || 0).toLocaleString();
      document.getElementById('statTransactionVolume').innerText = 'Rp ' + (s.transaction_volume || 0).toLocaleString('id-ID');
      document.getElementById('statActiveBanners').innerText = (s.active_banners || 0).toLocaleString();
    }
  } catch (e) {
    console.error('Failed to load dashboard stats', e);
  }

  loadRecentTransactionsForDashboard();
}

async function loadRecentTransactionsForDashboard() {
  const tbody = document.getElementById('dashboardRecentTxBody');
  if (!tbody) return;

  try {
    const { ok, json } = await safeFetch('/admin/transactions?limit=5', { headers: getAuthHeaders() });

    if (ok && json.data && json.data.length > 0) {
      tbody.innerHTML = json.data.map(tx => `
        <tr class="hover:bg-slate-50 transition">
          <td class="py-2.5 px-3 text-slate-500">${formatDateTime(tx.created_at)}</td>
          <td class="py-2.5 px-3 font-semibold text-slate-700">${tx.transaction_type}</td>
          <td class="py-2.5 px-3 text-slate-600 font-mono text-[11px]">${tx.from_account} &rarr; ${tx.to_account}</td>
          <td class="py-2.5 px-3 font-bold text-slate-900">Rp ${Number(tx.amount).toLocaleString('id-ID')}</td>
          <td class="py-2.5 px-3">
            <span class="inline-flex px-2.5 py-0.5 rounded-full text-[10px] font-bold ${tx.status === 'SUCCESS' ? 'bg-teal-50 text-[#00897B] border border-teal-200' : 'bg-rose-50 text-rose-700 border border-rose-200'}">
              ${tx.status}
            </span>
          </td>
        </tr>
      `).join('');
    } else {
      tbody.innerHTML = `<tr><td colspan="5" class="py-6 text-center text-slate-400">Belum ada transaksi tercatat</td></tr>`;
    }
  } catch (e) {
    console.error('Error loading dashboard transactions', e);
  }
}

