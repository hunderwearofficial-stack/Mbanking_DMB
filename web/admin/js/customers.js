/**
 * Customer, Device Binding & Product Applications (Deposito & Pinjaman) Management Module
 */

const customerPagination = {
  page: 1,
  limit: 20,
  total: 0,
  subTab: 'customers' // 'customers' | 'applications'
};

let cachedApplications = [];

function getCustomerAdminRole() {
  try {
    return (JSON.parse(localStorage.getItem('dmb_admin_user') || '{}').role || 'SUPER_ADMIN').toUpperCase();
  } catch (_) {
    return 'SUPER_ADMIN';
  }
}

function switchCustomerSubTab(subTab) {
  const role = getCustomerAdminRole();
  if (role === 'MARKETING') {
    subTab = 'applications';
  }
  customerPagination.subTab = subTab;

  const subTabsBar = document.getElementById('customerSubTabsBar');
  const secCustomers = document.getElementById('customerDataSection');
  const secApps = document.getElementById('productApplicationsSection');
  const btnCustomers = document.getElementById('subTabBtnCustomers');
  const btnApps = document.getElementById('subTabBtnApplications');

  if (subTabsBar) {
    subTabsBar.classList.toggle('hidden', role === 'MARKETING');
  }

  if (secCustomers) {
    secCustomers.classList.toggle('hidden', subTab !== 'customers' || role === 'MARKETING');
  }
  if (secApps) {
    secApps.classList.toggle('hidden', subTab !== 'applications' && role !== 'MARKETING');
  }

  if (btnCustomers && btnApps) {
    if (subTab === 'customers') {
      btnCustomers.className = 'px-4 py-2 rounded-xl text-xs font-bold bg-[#033172] text-white shadow-xs transition flex items-center gap-2';
      btnApps.className = 'px-4 py-2 rounded-xl text-xs font-bold bg-white text-slate-600 border border-slate-200 hover:bg-slate-50 transition flex items-center gap-2';
    } else {
      btnApps.className = 'px-4 py-2 rounded-xl text-xs font-bold bg-[#033172] text-white shadow-xs transition flex items-center gap-2';
      btnCustomers.className = 'px-4 py-2 rounded-xl text-xs font-bold bg-white text-slate-600 border border-slate-200 hover:bg-slate-50 transition flex items-center gap-2';
    }
  }
}

function changeCustomerPage(delta) {
  const maxPage = Math.max(1, Math.ceil(customerPagination.total / customerPagination.limit));
  const next = customerPagination.page + delta;
  if (next < 1 || next > maxPage) return;
  customerPagination.page = next;
  loadCustomers(false);
}

function changeCustomerPageSize(newLimit) {
  customerPagination.limit = parseInt(newLimit, 10) || 20;
  customerPagination.page = 1;
  loadCustomers(false);
}

async function loadCustomers(resetPage = true) {
  const role = getCustomerAdminRole();
  if (role === 'MARKETING') {
    switchCustomerSubTab('applications');
    loadProductApplications();
    return;
  }

  // Ensure sub-tab visibility is initialized
  switchCustomerSubTab(customerPagination.subTab || 'customers');

  if (resetPage) {
    customerPagination.page = 1;
  }

  const searchInput = document.getElementById('customerSearchInput');
  const search = searchInput ? searchInput.value.trim() : '';
  const tbody = document.getElementById('customersTableBody');
  if (!tbody) return;

  tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-slate-400">Memuat data nasabah...</td></tr>`;

  try {
    const url = `/admin/customers?search=${encodeURIComponent(search)}&page=${customerPagination.page}&limit=${customerPagination.limit}`;
    const { ok, json } = await safeFetch(url, { headers: getAuthHeaders() });

    if (ok && json.data) {
      const customers = json.data.customers || [];
      customerPagination.total = typeof json.data.total === 'number' ? json.data.total : customers.length;
      customerPagination.page = json.data.page || customerPagination.page;
      customerPagination.limit = json.data.limit || customerPagination.limit;

      renderCustomerPaginationBar();

      const isReadOnly = role === 'COMPLIANCE' || role === 'AUDITOR';

      if (customers.length > 0) {
        tbody.innerHTML = customers.map(c => {
          const accList = Array.isArray(c.account_numbers) && c.account_numbers.length > 0
            ? c.account_numbers.map(a => `<span class="inline-block px-1.5 py-0.5 rounded bg-slate-100 text-slate-700 font-mono text-[10px] border border-slate-200">${esc(a)}</span>`).join(' ')
            : '<span class="text-[10px] text-slate-400 italic">Belum ada rekening</span>';

          const activatedBadge = c.activated
            ? `<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-[#EFF6FF] text-[#033172] border border-blue-200">Sudah Aktivasi</span>`
            : `<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-500 border border-slate-200">Belum Aktivasi</span>`;

          const loginFail = c.failed_login_attempts || 0;
          const pinFail = c.failed_pin_attempts || 0;
          const failBadge = (loginFail > 0 || pinFail > 0)
            ? `<div class="mt-1 text-[10px] font-bold ${loginFail >= 3 || pinFail >= 3 ? 'text-rose-600' : 'text-amber-600'}">Gagal Login: ${esc(loginFail)}x · PIN: ${esc(pinFail)}x</div>`
            : `<div class="mt-1 text-[10px] text-slate-400">Gagal Login: 0x</div>`;

          const createdDate = c.created_at ? new Date(c.created_at).toLocaleDateString('id-ID', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

          const hasDevice = Boolean(c.device_id);
          const actionsHtml = isReadOnly
            ? `<span class="text-[10px] font-semibold text-slate-400 italic">Read-Only (Kepatuhan)</span>`
            : `<div class="flex items-center justify-center gap-1.5">
                <button type="button"
                  onclick="resetCustomerDevice(${jsArg(c.id)}, ${jsArg(c.full_name)})"
                  ${!hasDevice ? 'disabled' : ''}
                  title="${hasDevice ? 'Buka ikatan perangkat agar nasabah dapat login di HP baru' : 'Perangkat belum terikat'}"
                  class="px-2.5 py-1.5 rounded-lg text-[11px] font-bold bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-200 transition flex items-center gap-1 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-amber-50">
                  <i data-lucide="unlock" class="w-3 h-3"></i>
                  <span>Unbind Device</span>
                </button>
                <button type="button"
                  onclick="toggleCustomerStatus(${jsArg(c.id)}, ${!c.is_active}, ${jsArg(c.full_name)})"
                  class="px-2.5 py-1.5 rounded-lg text-[11px] font-bold ${c.is_active ? 'bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200' : 'bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200'} transition">
                  ${c.is_active ? 'Blokir' : 'Aktifkan'}
                </button>
              </div>`;

          return `
            <tr class="hover:bg-slate-50/80 transition align-top">
              <td class="py-3.5 px-4">
                <div class="font-bold text-slate-900">${esc(c.full_name)}</div>
                <div class="text-[11px] text-slate-500 font-mono">CIF: <span class="font-bold text-emerald-700">${esc(c.cif)}</span>${c.username ? ` · @${esc(c.username)}` : ''}</div>
                <div class="text-[10px] text-slate-400 mt-0.5">Terdaftar: ${esc(createdDate)}</div>
              </td>
              <td class="py-3.5 px-4">
                <div class="text-xs font-mono font-semibold text-slate-700">${esc(c.phone_number || '-')}</div>
                <div class="text-[11px] text-slate-400 truncate max-w-[180px]">${esc(c.email || '-')}</div>
                <div class="mt-1.5 flex flex-wrap gap-1">${accList}</div>
              </td>
              <td class="py-3.5 px-4">
                ${activatedBadge}
                ${failBadge}
              </td>
              <td class="py-3.5 px-4">
                ${c.device_id ? `
                  <span class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-[11px] font-mono font-semibold bg-blue-50 text-blue-700 border border-blue-200">
                    <i data-lucide="smartphone" class="w-3 h-3"></i>
                    <span>${esc(c.device_id)}</span>
                  </span>
                  <div class="mt-1">${deviceKeyBadge(c)}</div>
                ` : `
                  <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] text-slate-400 italic">
                    Belum Terikat Perangkat
                  </span>
                  <div class="mt-1">${deviceKeyBadge(c)}</div>
                `}
              </td>
              <td class="py-3.5 px-4">
                <span class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold ${c.is_active ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-800'}">
                  <span class="w-1.5 h-1.5 rounded-full ${c.is_active ? 'bg-emerald-600' : 'bg-rose-600'}"></span>
                  ${c.is_active ? 'Aktif' : 'Diblokir'}
                </span>
              </td>
              <td class="py-3.5 px-4 text-center">
                ${actionsHtml}
              </td>
            </tr>
          `;
        }).join('');
        if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
      } else {
        tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-slate-400">Tidak ada data nasabah ditemukan</td></tr>`;
      }
    } else {
      tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-slate-400">Tidak ada data nasabah ditemukan</td></tr>`;
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-rose-500">Gagal memuat data: ${esc(e.message)}</td></tr>`;
  }

  loadProductApplications();
  loadDeviceBindingSummary();
}

function renderCustomerPaginationBar() {
  const infoEl = document.getElementById('customerPaginationInfo');
  const prevBtn = document.getElementById('customerPrevPageBtn');
  const nextBtn = document.getElementById('customerNextPageBtn');
  const limitSel = document.getElementById('customerPageSizeSelect');

  const total = customerPagination.total || 0;
  const limit = customerPagination.limit || 20;
  const page = customerPagination.page || 1;
  const maxPage = Math.max(1, Math.ceil(total / limit));

  if (infoEl) {
    infoEl.textContent = `Halaman ${page} dari ${maxPage} • Total ${total.toLocaleString('id-ID')} Nasabah`;
  }
  if (prevBtn) {
    prevBtn.disabled = page <= 1;
  }
  if (nextBtn) {
    nextBtn.disabled = page >= maxPage;
  }
  if (limitSel) {
    limitSel.value = String(limit);
  }
}

/**
 * Device key status of a customer. "Terverifikasi hardware" is shown ONLY for keys whose
 * attestation was verified by the server (Android Key Attestation / Apple App Attest).
 */
function deviceKeyBadge(c) {
  const keyStatus = c.device_key_status || (c.device_key_algorithm ? 'ACTIVE' : '');
  const secLevel = esc(c.device_key_security_level || c.device_security_level || '-');
  const attest = c.device_attestation_status || '';

  if (!keyStatus && !c.device_key_algorithm) {
    return `<span class="inline-flex px-2 py-0.5 rounded text-[10px] font-semibold bg-slate-100 text-slate-500 border border-slate-200">Belum ada kunci hardware</span>`;
  }
  if (attest === 'HARDWARE_VERIFIED') {
    return `<span class="inline-flex px-2 py-0.5 rounded text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">Kunci terverifikasi hardware · ${secLevel}</span>`;
  }
  const label = attest === 'FAILED' ? 'Attestation gagal' : `Kunci ${esc(keyStatus || 'aktif')} · belum terverifikasi`;
  return `<span class="inline-flex px-2 py-0.5 rounded text-[10px] font-bold bg-amber-50 text-amber-800 border border-amber-200">${label} · ${secLevel}</span>`;
}

async function loadDeviceBindingSummary() {
  const grid = document.getElementById('dbSummaryGrid');
  const badge = document.getElementById('dbModeBadge');
  if (!grid) return;
  try {
    const { ok, json } = await safeFetch('/admin/device-binding/summary', { headers: getAuthHeaders() });
    if (!ok || !json.data) {
      grid.textContent = 'Ringkasan tidak tersedia untuk peran Anda.';
      return;
    }
    const s = json.data;
    if (badge) {
      badge.textContent = `Mode ${s.mode} · attestation ${s.attestation_mode}`;
      badge.className = s.protection_disabled
        ? 'px-2.5 py-1 rounded-full text-[10px] font-bold bg-rose-600 text-white'
        : (s.attestation_mode !== 'enforce'
          ? 'px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800'
          : 'px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800');
    }
    const alertEl = document.getElementById('dbProtectionAlert');
    if (alertEl) {
      if (s.protection_disabled) {
        alertEl.classList.remove('hidden');
        alertEl.textContent = `PROTEKSI KUNCI PERANGKAT NONAKTIF (mode ${s.configured_mode}, attestation ${s.attestation_mode}) `
          + `hingga ${s.off_until || 'tanpa batas'} — alasan: ${s.off_reason || '-'}. Seluruh perubahan tercatat di Audit Trail.`;
      } else if (s.configured_mode === 'off' && s.mode !== 'off') {
        alertEl.classList.remove('hidden');
        alertEl.textContent = `Saklar DEVICE_BINDING_MODE=off sudah kedaluwarsa (${s.off_until}); proteksi aktif kembali (mode ${s.mode}). Perbarui konfigurasi server.`;
      } else {
        alertEl.classList.add('hidden');
      }
    }
    const tile = (label, value, warn) => `
      <div class="rounded-xl border ${warn ? 'border-rose-200 bg-rose-50/60' : 'border-slate-200 bg-slate-50/60'} p-3">
        <div class="text-[10px] font-semibold uppercase tracking-wider text-slate-500">${label}</div>
        <div class="text-lg font-extrabold ${warn ? 'text-rose-700' : 'text-slate-900'}">${esc(String(value ?? 0))}</div>
      </div>`;
    grid.innerHTML = [
      tile('Perangkat terikat', s.bound_customers),
      tile('Kunci aktif', s.enrolled_customers),
      tile('Terverifikasi hardware', s.hardware_verified_keys),
      tile('Belum terverifikasi', s.unverified_keys, s.unverified_keys > 0 && s.attestation_mode === 'enforce'),
      tile('ID format lama', s.legacy_identifiers),
      tile('Attestation gagal (24j)', s.attestation_failed_24h, s.attestation_failed_24h > 0),
      tile('Tanda tangan ditolak (24j)', s.signature_rejected_24h, s.signature_rejected_24h > 0),
      tile('Replay terdeteksi (24j)', s.challenge_replay_24h, s.challenge_replay_24h > 0),
    ].join('');
  } catch (e) {
    grid.textContent = 'Gagal memuat ringkasan: ' + e.message;
  }
}

async function loadProductApplications() {
  const tbody = document.getElementById('productApplicationsTableBody');
  if (!tbody) return;
  const filterEl = document.getElementById('appProductFilter');
  const statusFilterEl = document.getElementById('appStatusFilter');
  const type = filterEl ? filterEl.value : 'ALL';
  const statusFilter = statusFilterEl ? statusFilterEl.value : 'ALL';

  tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Memuat pengajuan produk nasabah...</td></tr>`;

  try {
    const { ok, json } = await safeFetch(`/admin/applications?type=${encodeURIComponent(type)}&limit=100`, {
      headers: getAuthHeaders()
    });

    if (ok && Array.isArray(json.data)) {
      cachedApplications = type === 'ALL'
        ? json.data.filter(a => (a.product_type || '').toUpperCase() !== 'PENCAIRAN_DEPOSITO')
        : json.data;
      const badgeCount = document.getElementById('productAppsCountBadge');
      const pendingCount = cachedApplications.filter(a => a.status === 'PENDING').length;
      if (badgeCount) {
        badgeCount.textContent = pendingCount > 0 ? `${pendingCount} Baru` : String(cachedApplications.length);
      }

      const filtered = statusFilter === 'ALL'
        ? cachedApplications
        : cachedApplications.filter(a => (a.status || 'PENDING').toUpperCase() === statusFilter);

      const role = getCustomerAdminRole();
      const isReadOnly = role === 'COMPLIANCE' || role === 'AUDITOR';

      if (filtered.length > 0) {
        paginateTableData('productApplications', filtered, 'productApplicationsTableBody', (pageRows) => pageRows.map(app => {
          const dt = app.created_at ? new Date(app.created_at).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }) : '-';
          const isDeposito = app.product_type === 'DEPOSITO';
          const isTabungan = app.product_type === 'TABUNGAN';
          const isDisbursement = app.product_type === 'PENCAIRAN_DEPOSITO';
          const prodBadge = isDisbursement
            ? `<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-indigo-50 text-indigo-700 border border-indigo-200">PENCAIRAN DEPOSITO</span>`
            : isTabungan
              ? `<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-sky-50 text-sky-700 border border-sky-200">TABUNGAN</span>`
              : isDeposito
                ? `<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-[#EFF6FF] text-[#033172] border border-blue-200">DEPOSITO</span>`
                : `<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-amber-50 text-amber-700 border border-amber-200">PINJAMAN</span>`;

          let statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800">DIAJUKAN</span>`;
          if (app.status === 'CONTACTED') {
            statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800">DIPROSES / DIHUBUNGI</span>`;
          } else if (app.status === 'APPROVED') {
            statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">SELESAI</span>`;
          } else if (app.status === 'REJECTED') {
            statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800">DIBATALKAN</span>`;
          }

          const amountFmt = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(app.amount || 0);
          const estFmt = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(app.estimated_return || 0);

          const actionsHtml = isReadOnly
            ? `<span class="text-[10px] font-semibold text-slate-400 italic">Read-Only</span>`
            : `<div class="flex items-center justify-center gap-1.5 flex-wrap">
                <button type="button" onclick="updateProductAppStatus(${jsArg(app.id)}, 'CONTACTED', ${jsArg(app.product_name)}, ${jsArg(app.full_name)}, ${jsArg(app.admin_notes || '')})"
                  class="px-2 py-1 rounded-lg text-[10px] font-bold bg-blue-50 hover:bg-blue-100 text-blue-700 border border-blue-200 transition">
                  Proses
                </button>
                <button type="button" onclick="updateProductAppStatus(${jsArg(app.id)}, 'APPROVED', ${jsArg(app.product_name)}, ${jsArg(app.full_name)}, ${jsArg(app.admin_notes || '')})"
                  class="px-2 py-1 rounded-lg text-[10px] font-bold bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200 transition">
                  Selesai
                </button>
                <button type="button" onclick="updateProductAppStatus(${jsArg(app.id)}, 'REJECTED', ${jsArg(app.product_name)}, ${jsArg(app.full_name)}, ${jsArg(app.admin_notes || '')})"
                  class="px-2 py-1 rounded-lg text-[10px] font-bold bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 transition">
                  Batalkan
                </button>
              </div>`;

          return `
            <tr class="hover:bg-slate-50/80 transition align-top">
              <td class="py-3 px-4 font-mono text-[11px] text-slate-500 whitespace-nowrap">${esc(dt)}</td>
              <td class="py-3 px-4">
                <div class="font-bold text-slate-900">${esc(app.full_name)}</div>
                <div class="text-[11px] font-mono text-slate-500">CIF: ${esc(app.cif || '-')} &bull; HP: ${esc(app.phone_number)}</div>
              </td>
              <td class="py-3 px-4">
                <div class="flex items-center gap-1.5 mb-0.5">${prodBadge}</div>
                <div class="font-bold text-slate-800 text-xs">${esc(app.product_name)}</div>
                <div class="text-[10px] text-slate-500">${esc(app.purpose_or_source || '')}</div>
              </td>
              <td class="py-3 px-4">
                <div class="font-extrabold text-slate-900">${esc(amountFmt)}</div>
                <div class="text-[11px] text-slate-500">Tenor: <strong>${esc(app.tenor_months)} Bulan</strong> (${esc(app.interest_rate || '-')})</div>
              </td>
              <td class="py-3 px-4">
                <div class="font-bold text-emerald-700">${esc(estFmt)}</div>
                <div class="text-[10px] text-slate-400">${isDeposito ? 'Est. Bunga Bersih' : 'Est. Angsuran/Bln'} · indikatif dari aplikasi, bukan suku bunga yang disepakati</div>
              </td>
              <td class="py-3 px-4">
                ${statusBadge}
                ${app.admin_notes ? `<div class="text-[10px] text-slate-500 mt-1 italic max-w-xs">"${esc(app.admin_notes)}"</div>` : ''}
              </td>
              <td class="py-3 px-4 text-center">
                ${actionsHtml}
              </td>
            </tr>
          `;
        }).join(''), { resetPage: true });
      } else {
        hideTablePagination('productApplicationsTableBody');
        tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Belum ada pengajuan Deposito / Pinjaman yang sesuai filter</td></tr>`;
      }
    } else {
      hideTablePagination('productApplicationsTableBody');
      tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-slate-400">Belum ada pengajuan Deposito / Pinjaman dari aplikasi Mobile DMB</td></tr>`;
    }
  } catch (e) {
    hideTablePagination('productApplicationsTableBody');
    tbody.innerHTML = `<tr><td colspan="7" class="py-8 text-center text-rose-500">Gagal memuat pengajuan: ${esc(e.message)}</td></tr>`;
  }
}

async function updateProductAppStatus(id, initialStatus, productName, customerName, existingNotes = '') {
  const defaultNote = existingNotes || 'Petugas CS Bank DMB telah memverifikasi pengajuan Anda.';
  const result = await showConfirmModal({
    title: `Tindak Lanjut Pengajuan Produk`,
    message: `Perbarui status pengajuan ${productName} untuk nasabah ${customerName}. Notifikasi pembaruan akan dikirim otomatis ke aplikasi nasabah.`,
    confirmText: 'Simpan & Kirim Notifikasi',
    cancelText: 'Batal',
    variant: initialStatus === 'REJECTED' ? 'danger' : 'primary',
    selectLabel: 'Status Pengajuan',
    selectDefaultValue: initialStatus,
    selectOptions: [
      { value: 'PENDING', label: 'Diajukan — Menunggu Tinjauan Petugas' },
      { value: 'CONTACTED', label: 'Diproses — Sedang Dihubungi CS / Tim Lapangan' },
      { value: 'APPROVED', label: 'Selesai — Proses Tindak Lanjut Selesai' },
      { value: 'REJECTED', label: 'Dibatalkan — Pengajuan Dibatalkan' }
    ],
    showInput: true,
    requireInput: true,
    inputType: 'textarea',
    inputLabel: 'Catatan Tindak Lanjut Petugas (Admin Notes)',
    inputPlaceholder: 'Tuliskan hasil verifikasi atau jadwal kunjungan kantor cabang...',
    inputDefaultValue: defaultNote
  });

  if (!result) return;

  const chosenStatus = result.selectValue || initialStatus;
  const note = (result.value || '').trim();

  try {
    const { ok, json } = await safeFetch(`/admin/applications/${encodeURIComponent(id)}/status`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({ status: chosenStatus, admin_notes: note })
    });
    if (ok && json.success) {
      showToast(`Status pengajuan ${customerName} diperbarui menjadi ${chosenStatus}!`, 'success');
      loadProductApplications();
      if (typeof loadDepositDisbursements === 'function') loadDepositDisbursements();
    } else {
      showToast(json.message || 'Gagal memperbarui status pengajuan', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

async function resetCustomerDevice(userId, fullName) {
  const confirmed = await showConfirmModal({
    title: 'Konfirmasi Reset Ikatan Perangkat (Unbind Device)',
    message: `Buka ikatan perangkat untuk nasabah ${fullName}? Kunci keamanan kriptografis perangkat akan dicabut dan seluruh sesi login aktif diakhiri. Nasabah dapat mengikat perangkat baru melalui verifikasi OTP pada aplikasi.`,
    confirmText: 'Ya, Unbind Device',
    cancelText: 'Batal',
    variant: 'warning'
  });
  if (!confirmed) return;

  try {
    const { ok, json } = await safeFetch(`/admin/customers/${encodeURIComponent(userId)}/reset-device`, {
      method: 'POST',
      headers: getAuthHeaders()
    });

    if (ok && json.success) {
      showToast(json.message || `Permintaan reset perangkat untuk ${fullName} diajukan untuk persetujuan.`, 'success');
      loadCustomers(false);
      if (typeof loadDashboardStats === 'function') loadDashboardStats();
    } else {
      showToast(json.message || 'Gagal mereset device', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

async function toggleCustomerStatus(userId, newStatus, fullName = 'nasabah ini') {
  const actionText = newStatus ? 'mengaktifkan kembali' : 'memblokir';
  const confirmed = await showConfirmModal({
    title: newStatus ? 'Aktifkan Akun Nasabah' : 'Blokir Akun Nasabah',
    message: newStatus
      ? `Apakah Anda yakin ingin ${actionText} akun ${fullName}? Counter gagal login & PIN akan di-reset ke 0.`
      : `Apakah Anda yakin ingin ${actionText} akun ${fullName}? Seluruh sesi login nasabah akan segera dicabut.`,
    confirmText: newStatus ? 'Ya, Aktifkan Akun' : 'Ya, Blokir Akun',
    cancelText: 'Batal',
    variant: newStatus ? 'primary' : 'danger'
  });
  if (!confirmed) return;

  try {
    const { ok, json } = await safeFetch(`/admin/customers/${encodeURIComponent(userId)}/status`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ is_active: newStatus })
    });

    if (ok && json.success) {
      showToast(json.message || 'Status akun nasabah diperbarui', 'success');
      loadCustomers(false);
      if (typeof loadDashboardStats === 'function') loadDashboardStats();
    } else {
      showToast(json.message || 'Gagal mengubah status', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

async function loadDepositDisbursements() {
  const tbody = document.getElementById('depositDisbursementsTableBody');
  const badgeCount = document.getElementById('disbursementsCountBadge');
  const statusFilter = document.getElementById('disbursementStatusFilter')?.value || 'ALL';
  if (!tbody) return;

  try {
    const { ok, json } = await safeFetch('/admin/applications?type=PENCAIRAN_DEPOSITO&limit=100', {
      headers: getAuthHeaders()
    });
    if (!ok || !json.success) {
      tbody.innerHTML = `<tr><td colspan="6" class="px-5 py-8 text-center text-rose-500">${esc(json.message || 'Gagal memuat pengajuan pencairan deposito')}</td></tr>`;
      return;
    }

    const apps = json.data?.applications || json.data || [];
    const pendingCount = apps.filter(a => (a.status || 'PENDING').toUpperCase() === 'PENDING').length;
    if (badgeCount) {
      badgeCount.textContent = pendingCount > 0 ? `${pendingCount} Baru (${apps.length} Total)` : `${apps.length} pengajuan`;
    }

    const filtered = statusFilter === 'ALL'
      ? apps
      : apps.filter(a => (a.status || 'PENDING').toUpperCase() === statusFilter);

    const role = getCustomerAdminRole();
    const isReadOnly = role === 'COMPLIANCE' || role === 'AUDITOR';

    if (filtered.length === 0) {
      hideTablePagination('depositDisbursementsTableBody');
      tbody.innerHTML = '<tr><td colspan="6" class="px-5 py-10 text-center text-slate-400">Belum ada pengajuan pencairan deposito pada filter ini.</td></tr>';
      return;
    }

    paginateTableData('depositDisbursements', filtered, 'depositDisbursementsTableBody', (pageRows) => pageRows.map(app => {
      const dt = app.created_at ? new Date(app.created_at).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }) : '-';
      const amountFmt = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(app.amount || 0);

      let statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800">DIAJUKAN</span>`;
      if (app.status === 'CONTACTED') {
        statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800">DIPROSES / DIHUBUNGI</span>`;
      } else if (app.status === 'APPROVED') {
        statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">SELESAI</span>`;
      } else if (app.status === 'REJECTED') {
        statusBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800">DIBATALKAN</span>`;
      }

      const actionsHtml = isReadOnly
        ? `<span class="text-[10px] font-semibold text-slate-400 italic">Read-Only</span>`
        : `<div class="flex items-center justify-end gap-1.5 flex-wrap">
            <button type="button" onclick="updateProductAppStatus(${jsArg(app.id)}, 'CONTACTED', ${jsArg(app.product_name)}, ${jsArg(app.full_name)}, ${jsArg(app.admin_notes || '')})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-blue-50 hover:bg-blue-100 text-blue-700 border border-blue-200 transition">
              Proses
            </button>
            <button type="button" onclick="updateProductAppStatus(${jsArg(app.id)}, 'APPROVED', ${jsArg(app.product_name)}, ${jsArg(app.full_name)}, ${jsArg(app.admin_notes || '')})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200 transition">
              Selesai
            </button>
            <button type="button" onclick="updateProductAppStatus(${jsArg(app.id)}, 'REJECTED', ${jsArg(app.product_name)}, ${jsArg(app.full_name)}, ${jsArg(app.admin_notes || '')})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 transition">
              Batalkan
            </button>
          </div>`;

      return `
        <tr class="hover:bg-slate-50/80 transition align-top">
          <td class="px-5 py-3.5 font-mono text-[11px] text-slate-500 whitespace-nowrap">${esc(dt)}</td>
          <td class="px-5 py-3.5">
            <div class="font-bold text-slate-900">${esc(app.full_name)}</div>
            <div class="text-[11px] font-mono text-slate-500">CIF: ${esc(app.cif || '-')} &bull; HP: ${esc(app.phone_number)}</div>
          </td>
          <td class="px-5 py-3.5">
            <div class="font-bold text-slate-800">${esc(app.product_name)}</div>
            <div class="text-[11px] text-slate-600 mt-0.5">${esc(app.purpose_or_source || '-')}</div>
            <div class="text-[10px] text-slate-400 mt-0.5">Tenor ${esc(app.tenor_months || 0)} Bulan &bull; Bunga ${esc(app.interest_rate || '-')}</div>
          </td>
          <td class="px-5 py-3.5 font-extrabold text-slate-900 whitespace-nowrap">${esc(amountFmt)}</td>
          <td class="px-5 py-3.5">
            ${statusBadge}
            ${app.admin_notes ? `<div class="text-[10px] text-slate-500 mt-1 italic max-w-xs">"${esc(app.admin_notes)}"</div>` : ''}
          </td>
          <td class="px-5 py-3.5 text-right">${actionsHtml}</td>
        </tr>
      `;
    }).join(''), { resetPage: true });
  } catch (e) {
    hideTablePagination('depositDisbursementsTableBody');
    tbody.innerHTML = `<tr><td colspan="6" class="px-5 py-8 text-center text-rose-500">Error: ${esc(e.message)}</td></tr>`;
  }
}
