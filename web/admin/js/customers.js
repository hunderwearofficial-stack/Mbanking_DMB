/**
 * Customer & Device Binding Management Module
 */

async function loadCustomers() {
  const searchInput = document.getElementById('customerSearchInput');
  const search = searchInput ? searchInput.value.trim() : '';
  const tbody = document.getElementById('customersTableBody');
  if (!tbody) return;

  tbody.innerHTML = `<tr><td colspan="5" class="py-8 text-center text-slate-400">Memuat data nasabah...</td></tr>`;

  try {
    const url = `/admin/customers?search=${encodeURIComponent(search)}`;
    const { ok, json } = await safeFetch(url, { headers: getAuthHeaders() });

    if (ok && json.data && json.data.customers && json.data.customers.length > 0) {
      tbody.innerHTML = json.data.customers.map(c => `
        <tr class="hover:bg-slate-50/80 transition">
          <td class="py-3 px-4">
            <div class="font-bold text-slate-900">${c.full_name}</div>
            <div class="text-[11px] text-slate-400">${c.email || '-'}</div>
          </td>
          <td class="py-3 px-4">
            <div class="font-mono font-semibold text-emerald-700">${c.cif}</div>
            <div class="text-[11px] text-slate-500 font-mono">${c.phone_number}</div>
          </td>
          <td class="py-3 px-4">
            ${c.device_id ? `
              <span class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-[11px] font-mono font-semibold bg-blue-50 text-blue-700 border border-blue-200">
                <i data-lucide="smartphone" class="w-3 h-3"></i>
                <span>${c.device_id}</span>
              </span>
            ` : `
              <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] text-slate-400 italic">
                Belum Terikat
              </span>
            `}
          </td>
          <td class="py-3 px-4">
            <span class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold ${c.is_active ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-800'}">
              <span class="w-1.5 h-1.5 rounded-full ${c.is_active ? 'bg-emerald-600' : 'bg-rose-600'}"></span>
              ${c.is_active ? 'Aktif' : 'Diblokir'}
            </span>
          </td>
          <td class="py-3 px-4">
            <div class="flex items-center justify-center gap-2">
              <button onclick="resetCustomerDevice('${c.id}', '${c.full_name}')"
                title="Buka ikatan perangkat agar nasabah dapat login di HP baru"
                class="px-2.5 py-1.5 rounded-lg text-[11px] font-bold bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-200 transition flex items-center gap-1">
                <i data-lucide="unlock" class="w-3 h-3"></i>
                <span>Unbind Device</span>
              </button>
              <button onclick="toggleCustomerStatus('${c.id}', ${!c.is_active})"
                class="px-2.5 py-1.5 rounded-lg text-[11px] font-bold ${c.is_active ? 'bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200' : 'bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200'} transition">
                ${c.is_active ? 'Blokir' : 'Aktifkan'}
              </button>
            </div>
          </td>
        </tr>
      `).join('');
      lucide.createIcons();
    } else {
      tbody.innerHTML = `<tr><td colspan="5" class="py-8 text-center text-slate-400">Tidak ada data nasabah ditemukan</td></tr>`;
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="5" class="py-8 text-center text-rose-500">Gagal memuat data: ${e.message}</td></tr>`;
  }
}

async function resetCustomerDevice(userId, fullName) {
  if (!confirm(`Konfirmasi reset ikatan perangkat (Unbind Device) untuk nasabah ${fullName}?\nNasabah akan dapat mengaitkan HP baru pada login berikutnya.`)) {
    return;
  }

  try {
    const { ok, json } = await safeFetch(`/admin/customers/${userId}/reset-device`, {
      method: 'POST',
      headers: getAuthHeaders()
    });

    if (ok && json.success) {
      showToast(`Device ID untuk ${fullName} berhasil di-reset!`, 'success');
      loadCustomers();
      loadDashboardStats();
    } else {
      showToast(json.message || 'Gagal mereset device', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

async function toggleCustomerStatus(userId, newStatus) {
  const actionText = newStatus ? 'mengaktifkan' : 'memblokir';
  if (!confirm(`Apakah Anda yakin ingin ${actionText} akun nasabah ini?`)) return;

  try {
    const { ok, json } = await safeFetch(`/admin/customers/${userId}/status`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ is_active: newStatus })
    });

    if (ok && json.success) {
      showToast(json.message, 'success');
      loadCustomers();
      loadDashboardStats();
    } else {
      showToast(json.message || 'Gagal mengubah status', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

