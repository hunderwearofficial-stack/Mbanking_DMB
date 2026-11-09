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

  loadProductApplications();
}

async function loadProductApplications() {
  const tbody = document.getElementById('productApplicationsTableBody');
  if (!tbody) return;
  const filterEl = document.getElementById('appProductFilter');
  const type = filterEl ? filterEl.value : 'ALL';

  try {
    const { ok, json } = await safeFetch(`/admin/applications?type=${encodeURIComponent(type)}&limit=50`, {
      headers: getAuthHeaders()
    });

    if (ok && json.data && json.data.length > 0) {
      tbody.innerHTML = json.data.map(app => {
        const dt = app.created_at ? new Date(app.created_at).toLocaleString('id-ID') : '-';
        const isDeposito = app.product_type === 'DEPOSITO';
        const prodBadge = isDeposito
          ? `<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-teal-50 text-[#00897B] border border-teal-200">DEPOSITO</span>`
          : `<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-amber-50 text-amber-700 border border-amber-200">PINJAMAN</span>`;

        let statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800">MENUNGGU CS</span>`;
        if (app.status === 'CONTACTED') {
          statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800">DIHUBUNGI CS</span>`;
        } else if (app.status === 'APPROVED') {
          statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">DISETUJUI</span>`;
        } else if (app.status === 'REJECTED') {
          statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800">DITOLAK</span>`;
        }

        const amountFmt = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(app.amount || 0);
        const estFmt = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(app.estimated_return || 0);

        return `
          <tr class="hover:bg-slate-50/80 transition">
            <td class="py-3 px-4 font-mono text-[11px] text-slate-500">${dt}</td>
            <td class="py-3 px-4">
              <div class="font-bold text-slate-900">${app.full_name}</div>
              <div class="text-[11px] font-mono text-slate-500">CIF: ${app.cif || '-'} &bull; HP: ${app.phone_number}</div>
            </td>
            <td class="py-3 px-4">
              <div class="flex items-center gap-1.5 mb-0.5">${prodBadge}</div>
              <div class="font-bold text-slate-800 text-xs">${app.product_name}</div>
              <div class="text-[10px] text-slate-500">${app.purpose_or_source || ''}</div>
            </td>
            <td class="py-3 px-4">
              <div class="font-extrabold text-slate-900">${amountFmt}</div>
              <div class="text-[11px] text-slate-500">Tenor: <strong>${app.tenor_months} Bulan</strong> (${app.interest_rate || '-'})</div>
            </td>
            <td class="py-3 px-4">
              <div class="font-bold text-emerald-700">${estFmt}</div>
              <div class="text-[10px] text-slate-400">${isDeposito ? 'Est. Bunga Bersih' : 'Est. Angsuran/Bln'}</div>
            </td>
            <td class="py-3 px-4">
              ${statusBadge}
              ${app.admin_notes ? `<div class="text-[10px] text-slate-500 mt-1 italic">"${app.admin_notes}"</div>` : ''}
            </td>
            <td class="py-3 px-4">
              <div class="flex items-center justify-center gap-1.5">
                <button onclick="updateProductAppStatus('${app.id}', 'CONTACTED', '${app.product_name}', '${app.full_name}')"
                  class="px-2 py-1 rounded-lg text-[10px] font-bold bg-blue-50 hover:bg-blue-100 text-blue-700 border border-blue-200 transition">
                  Proses
                </button>
                <button onclick="updateProductAppStatus('${app.id}', 'APPROVED', '${app.product_name}', '${app.full_name}')"
                  class="px-2 py-1 rounded-lg text-[10px] font-bold bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200 transition">
                  Setujui
                </button>
                <button onclick="updateProductAppStatus('${app.id}', 'REJECTED', '${app.product_name}', '${app.full_name}')"
                  class="px-2 py-1 rounded-lg text-[10px] font-bold bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 transition">
                  Tolak
                </button>
              </div>
            </td>
          </tr>
        `;
      }).join('');
    } else {
      tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Belum ada pengajuan Deposito / Pinjaman dari aplikasi Mobile DMB</td></tr>`;
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-rose-500">Gagal memuat pengajuan: ${e.message}</td></tr>`;
  }
}

async function updateProductAppStatus(id, status, productName, customerName) {
  const note = prompt(`Masukkan catatan tindak lanjut untuk ${customerName} (${productName}) [Status: ${status}]:`, 'Petugas CS Bank DMB telah memverifikasi pengajuan Anda.');
  if (note === null) return;

  try {
    const { ok, json } = await safeFetch(`/admin/applications/${id}/status`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({ status: status, admin_notes: note })
    });
    if (ok && json.success) {
      showToast(`Status pengajuan ${customerName} diperbarui & notifikasi dikirim ke HP nasabah!`, 'success');
      loadProductApplications();
    } else {
      showToast(json.message || 'Gagal memperbarui status pengajuan', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
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

