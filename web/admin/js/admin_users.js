/**
 * Admin Users & Role-Based Access Control (RBAC) Module
 * Dilengkapi pencarian & filter peran, validasi sandi minimal 12 karakter (kombinasi huruf & angka),
 * indikator lockout akun petugas, serta Edit / Reset Sandi Petugas (PUT /api/v1/admin/users/:id).
 */

let allAdminUsers = [];
let editingAdminUserId = null;

async function loadAdminUsers() {
  const tbody = document.getElementById('adminUsersTableBody');
  if (!tbody) return;
  tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-xs text-slate-400">Memuat data petugas admin...</td></tr>';

  try {
    const { ok, json } = await safeFetch('/admin/users', { headers: getAuthHeaders() });

    if (ok && json.data) {
      allAdminUsers = json.data;
      filterAdminUsersTable();
    } else {
      tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-xs text-rose-500">Gagal memuat data petugas admin.</td></tr>';
    }
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="6" class="p-8 text-center text-xs text-rose-500">Error: ${esc(err.message)}</td></tr>`;
  }
}

function filterAdminUsersTable() {
  const searchEl = document.getElementById('adminUserSearchInput');
  const roleEl = document.getElementById('adminUserRoleFilter');
  const q = (searchEl ? searchEl.value.trim().toLowerCase() : '');
  const roleFilter = (roleEl ? roleEl.value : 'ALL');

  const filtered = allAdminUsers.filter(u => {
    const matchRole = roleFilter === 'ALL' || (u.role || '').toUpperCase() === roleFilter;
    const matchQuery = !q ||
      (u.full_name || '').toLowerCase().includes(q) ||
      (u.username || '').toLowerCase().includes(q) ||
      (u.email || '').toLowerCase().includes(q);
    return matchRole && matchQuery;
  });

  renderAdminUsers(filtered);
}

function renderAdminUsers(users) {
  const tbody = document.getElementById('adminUsersTableBody');
  if (!tbody) return;
  if (!users || users.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-xs text-slate-400">Tidak ada petugas admin yang sesuai dengan filter.</td></tr>';
    return;
  }

  const currentUserData = localStorage.getItem('dmb_admin_user');
  let currentAdminId = '';
  if (currentUserData) {
    try { currentAdminId = JSON.parse(currentUserData).id; } catch (_) {}
  }

  const nowTs = Date.now();

  tbody.innerHTML = users.map((u) => {
    let roleBadge = '';
    let roleDesc = '';
    switch (u.role) {
      case 'SUPER_ADMIN':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-purple-100 text-purple-700 border border-purple-200 flex items-center gap-1 w-max"><i data-lucide="shield-alert" class="w-3 h-3"></i> SUPER ADMIN</span>';
        roleDesc = 'Akses Penuh Seluruh Modul & Tata Kelola';
        break;
      case 'CS':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-100 text-blue-700 border border-blue-200 flex items-center gap-1 w-max"><i data-lucide="headphones" class="w-3 h-3"></i> CUSTOMER SERVICE</span>';
        roleDesc = 'Layanan Nasabah, Reset Device & Pengajuan';
        break;
      case 'MARKETING':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800 border border-amber-200 flex items-center gap-1 w-max"><i data-lucide="sparkles" class="w-3 h-3"></i> MARKETING</span>';
        roleDesc = 'Konten Aplikasi, Push FCM & Pengajuan Produk';
        break;
      case 'COMPLIANCE':
      case 'AUDITOR':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800 border border-emerald-200 flex items-center gap-1 w-max"><i data-lucide="file-check" class="w-3 h-3"></i> AUDITOR / COMPLIANCE</span>';
        roleDesc = 'Audit Trail, SK Layanan & Checker Kepatuhan';
        break;
      default:
        roleBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-slate-100 text-slate-700 border border-slate-200">${esc(u.role)}</span>`;
        roleDesc = 'Petugas Operasional';
    }

    const isCurrent = u.id === currentAdminId;
    const isLocked = u.locked_until && new Date(u.locked_until).getTime() > nowTs;
    const failedCount = u.failed_login_attempts || 0;

    let statusBadge = u.is_active
      ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200 flex items-center gap-1 w-max"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span> Aktif</span>'
      : '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200 flex items-center gap-1 w-max"><span class="w-1.5 h-1.5 rounded-full bg-rose-500"></span> Nonaktif</span>';

    let lockoutBadge = '';
    if (isLocked) {
      const lockTime = new Date(u.locked_until).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' });
      lockoutBadge = `<span class="mt-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800 border border-rose-300 flex items-center gap-1 w-max"><i data-lucide="lock" class="w-3 h-3"></i> Terkunci s/d ${esc(lockTime)}</span>`;
    } else if (failedCount > 0) {
      lockoutBadge = `<span class="mt-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-50 text-amber-800 border border-amber-200 flex items-center gap-1 w-max">Gagal Login: ${esc(failedCount)}x</span>`;
    }

    const initials = (u.full_name || u.username || 'AD').substring(0, 2).toUpperCase();
    const createdDate = u.created_at ? new Date(u.created_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' }) : '-';

    return `
      <tr class="border-b border-slate-100 hover:bg-slate-50/70 transition align-top">
        <td class="p-4">
          <div class="flex items-center gap-3">
            <div class="w-9 h-9 rounded-xl bg-gradient-to-tr from-slate-800 to-slate-700 text-emerald-400 font-extrabold text-xs flex items-center justify-center shadow-sm">
              ${esc(initials)}
            </div>
            <div>
              <div class="font-bold text-xs text-slate-800 flex items-center gap-2">
                ${esc(u.full_name || u.username)}
                ${isCurrent ? '<span class="text-[9px] bg-teal-50 text-[#00897B] px-1.5 py-0.5 rounded border border-teal-200 font-bold">Anda</span>' : ''}
              </div>
              <div class="text-[11px] text-slate-400">${esc(u.email || '-')}</div>
            </div>
          </div>
        </td>
        <td class="p-4 text-xs font-mono font-bold text-slate-600">@${esc(u.username)}</td>
        <td class="p-4">
          ${roleBadge}
          <div class="text-[10px] text-slate-400 mt-1">${roleDesc}</div>
        </td>
        <td class="p-4">
          ${statusBadge}
          ${lockoutBadge}
        </td>
        <td class="p-4 text-xs text-slate-500">${esc(createdDate)}</td>
        <td class="p-4 text-right">
          <div class="flex items-center justify-end gap-1.5 flex-wrap">
            <button type="button" onclick="openEditAdminModal(${jsArg(u.id)})" title="Edit Profil / Reset Kata Sandi Petugas"
              class="px-2.5 py-1.5 rounded-lg border border-slate-200 text-slate-700 hover:bg-slate-100 text-xs font-semibold transition flex items-center gap-1">
              <i data-lucide="key-round" class="w-3.5 h-3.5 text-[#00897B]"></i>
              <span>Edit / Reset Sandi</span>
            </button>
            ${!isCurrent ? `
              <button type="button" onclick="resetAdminMFA(${jsArg(u.id)}, ${jsArg(u.username)})" title="Ajukan Reset MFA TOTP Petugas"
                class="px-2.5 py-1.5 rounded-lg border border-indigo-200 text-indigo-700 hover:bg-indigo-50 text-xs font-semibold transition flex items-center gap-1">
                <i data-lucide="shield-off" class="w-3.5 h-3.5"></i>
                <span class="hidden sm:inline">Reset MFA</span>
              </button>
              <button type="button" onclick="toggleAdminStatus(${jsArg(u.id)}, ${!u.is_active}, ${jsArg(u.username)})" title="${u.is_active ? 'Nonaktifkan Akun' : 'Aktifkan Akun & Buka Kunci'}"
                class="px-2.5 py-1.5 rounded-lg border text-xs font-semibold transition flex items-center gap-1 ${u.is_active ? 'border-amber-200 text-amber-700 hover:bg-amber-50' : 'border-emerald-200 text-emerald-700 hover:bg-emerald-50'}">
                <i data-lucide="${u.is_active ? 'user-x' : 'user-check'}" class="w-3.5 h-3.5"></i>
                <span class="hidden sm:inline">${u.is_active ? 'Nonaktifkan' : 'Aktifkan'}</span>
              </button>
              <button type="button" onclick="deleteAdminUser(${jsArg(u.id)}, ${jsArg(u.username)})" title="Hapus Petugas"
                class="p-1.5 rounded-lg border border-rose-200 text-rose-600 hover:bg-rose-50 transition">
                <i data-lucide="trash-2" class="w-3.5 h-3.5"></i>
              </button>
            ` : ''}
          </div>
        </td>
      </tr>
    `;
  }).join('');

  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function openCreateAdminModal() {
  document.getElementById('createAdminModal').classList.remove('hidden');
  document.getElementById('createAdminForm').reset();
  document.getElementById('newAdminRole').value = 'CS';
  updateRoleDescription();
}

function closeCreateAdminModal() {
  document.getElementById('createAdminModal').classList.add('hidden');
}

function updateRoleDescription() {
  const role = document.getElementById('newAdminRole').value;
  const descBox = document.getElementById('roleDescBox');
  if (!descBox) return;
  switch (role) {
    case 'SUPER_ADMIN':
      descBox.innerHTML = '<span class="text-purple-700 font-semibold">&bull; Hak Akses:</span> Memiliki kewenangan tertinggi untuk mengelola seluruh modul: Dashboard, Nasabah &amp; Perangkat, Konten Aplikasi, Syarat &amp; Ketentuan, Notifikasi Push, Audit Trail, Petugas &amp; Hak Akses, serta Pengaturan Operasional &amp; CBS.';
      break;
    case 'CS':
      descBox.innerHTML = '<span class="text-blue-700 font-semibold">&bull; Hak Akses:</span> Fokus pada layanan nasabah: Membuka data rekening, melakukan Unbind/Reset Device ID saat nasabah ganti smartphone, memblokir/mengaktifkan akun, memproses pengajuan produk, dan melihat dokumen Syarat &amp; Ketentuan (Read-Only).';
      break;
    case 'MARKETING':
      descBox.innerHTML = '<span class="text-amber-700 font-semibold">&bull; Hak Akses:</span> Mengelola Konten Aplikasi Mobile (teks, gambar layar &amp; carousel banner beranda dengan alur Maker-Checker), kampanye Notifikasi Push Firebase, dan menindaklanjuti Pengajuan Produk Nasabah.';
      break;
    case 'COMPLIANCE':
      descBox.innerHTML = '<span class="text-emerald-700 font-semibold">&bull; Hak Akses:</span> Pengawasan Kepatuhan &amp; Audit OJK: Memantau Audit Trail berantai SHA-256, menyetujui/mengelola versi dokumen Syarat &amp; Ketentuan (Maker-Checker), meninjau persetujuan Konten Aplikasi &amp; Push Notification, serta melihat status nasabah secara Read-Only.';
      break;
  }
}

function validateOfficerPassword(pw) {
  if (!pw || pw.length < 12) {
    return 'Password petugas wajib minimal 12 karakter.';
  }
  if (!/[A-Za-z]/.test(pw) || !/[0-9]/.test(pw)) {
    return 'Password petugas wajib mengandung kombinasi huruf dan angka.';
  }
  return '';
}

async function handleCreateAdmin(e) {
  e.preventDefault();
  const password = document.getElementById('newAdminPassword').value.trim();
  const newRole = document.getElementById('newAdminRole').value;
  const checkerRole = newRole === 'SUPER_ADMIN' || newRole === 'COMPLIANCE';
  // Checker roles get a system-issued password on approval (MA-03); the input is not sent.
  if (!checkerRole) {
    const pwErr = validateOfficerPassword(password);
    if (pwErr) {
      showToast(pwErr, 'error');
      return;
    }
  }

  const btn = document.getElementById('submitNewAdminBtn');
  btn.disabled = true;
  btn.innerText = 'Menyimpan...';

  const payload = {
    full_name: document.getElementById('newAdminFullName').value.trim(),
    username: document.getElementById('newAdminUsername').value.trim(),
    email: document.getElementById('newAdminEmail').value.trim(),
    password: checkerRole ? '' : password,
    role: newRole,
    is_active: document.getElementById('newAdminIsActive').checked
  };

  try {
    const { ok, json } = await safeFetch('/admin/users', {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify(payload)
    });

    if (ok && json.success) {
      showToast(json.message || 'Petugas admin baru berhasil didaftarkan!', 'success');
      closeCreateAdminModal();
      loadAdminUsers();
    } else {
      showToast(json.message || 'Gagal menambahkan petugas', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="check" class="w-4 h-4"></i><span>Daftarkan Petugas</span>';
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  }
}

/**
 * Edit / Reset Sandi Petugas Modal (PUT /api/v1/admin/users/:id)
 */
function openEditAdminModal(id) {
  const user = allAdminUsers.find(u => u.id === id);
  if (!user) return;
  editingAdminUserId = id;
  document.getElementById('editAdminUsernameDisplay').textContent = '@' + user.username;
  document.getElementById('editAdminFullName').value = user.full_name || '';
  document.getElementById('editAdminEmail').value = user.email || '';
  document.getElementById('editAdminRole').value = user.role || 'CS';
  const resetBox = document.getElementById('editAdminResetPassword');
  if (resetBox) resetBox.checked = false;
  document.getElementById('editAdminModal').classList.remove('hidden');
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function closeEditAdminModal() {
  editingAdminUserId = null;
  document.getElementById('editAdminModal').classList.add('hidden');
}

async function handleEditAdminSubmit(e) {
  e.preventDefault();
  if (!editingAdminUserId) return;

  const fullName = document.getElementById('editAdminFullName').value.trim();
  const email = document.getElementById('editAdminEmail').value.trim();
  const role = document.getElementById('editAdminRole').value;
  const resetBox = document.getElementById('editAdminResetPassword');
  const resetPassword = Boolean(resetBox && resetBox.checked);

  const btn = document.getElementById('submitEditAdminBtn');
  btn.disabled = true;
  btn.textContent = 'Menyimpan...';

  const payload = {
    full_name: fullName,
    email: email,
    role: role
  };
  if (resetPassword) {
    payload.reset_password = true;
  }

  try {
    const { ok, json } = await safeFetch(`/admin/users/${encodeURIComponent(editingAdminUserId)}`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify(payload)
    });

    if (ok && json.success) {
      showToast(json.message || 'Data petugas berhasil diperbarui!', 'success');
      closeEditAdminModal();
      loadAdminUsers();
    } else {
      showToast(json.message || 'Gagal memperbarui data petugas', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="check" class="w-4 h-4"></i><span>Simpan Perubahan</span>';
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  }
}

async function toggleAdminStatus(id, newStatus, username = '') {
  const actionText = newStatus ? 'mengaktifkan kembali' : 'menonaktifkan';
  const confirmed = await showConfirmModal({
    title: newStatus ? 'Aktifkan Akun Petugas' : 'Nonaktifkan Akun Petugas',
    message: newStatus
      ? `Apakah Anda yakin ingin ${actionText} akun petugas @${username}? Penguncian gagal login (lockout) juga akan dibuka.`
      : `Apakah Anda yakin ingin ${actionText} akun petugas @${username}? Petugas tidak akan dapat login ke konsol backoffice.`,
    confirmText: newStatus ? 'Ya, Aktifkan' : 'Ya, Nonaktifkan',
    cancelText: 'Batal',
    variant: newStatus ? 'primary' : 'warning'
  });
  if (!confirmed) return;

  try {
    const { ok, json } = await safeFetch(`/admin/users/${encodeURIComponent(id)}/status`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({ is_active: newStatus })
    });

    if (ok && json.success) {
      showToast(json.message || 'Status petugas berhasil diperbarui', 'success');
      loadAdminUsers();
    } else {
      showToast(json.message || 'Gagal mengubah status', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

async function resetAdminMFA(id, username = '') {
  const confirmed = await showConfirmModal({
    title: 'Ajukan Reset MFA Petugas',
    message: `Ajukan reset autentikator (MFA TOTP) untuk akun @${username}? Permintaan akan masuk ke antrean Persetujuan (Maker-Checker) dan petugas wajib enroll ulang setelah disetujui.`,
    confirmText: 'Ya, Ajukan Reset MFA',
    cancelText: 'Batal',
    variant: 'warning'
  });
  if (!confirmed) return;

  try {
    const { ok, json } = await safeFetch(`/admin/users/${encodeURIComponent(id)}/reset-mfa`, {
      method: 'POST',
      headers: getAuthHeaders()
    });
    if (ok && json.success) {
      showToast(json.message || 'Permintaan reset MFA petugas diajukan', 'success');
      if (typeof loadApprovals === 'function') loadApprovals();
    } else {
      showToast(json.message || 'Gagal mengajukan reset MFA', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

async function deleteAdminUser(id, username) {
  const confirmed = await showConfirmModal({
    title: 'Nonaktifkan Akun Petugas',
    message: `Nonaktifkan akun petugas "@${username}"? Petugas tidak akan bisa login lagi, namun riwayat audit tetap tersimpan.`,
    confirmText: 'Ya, Nonaktifkan',
    cancelText: 'Batal',
    variant: 'danger'
  });
  if (!confirmed) return;

  try {
    const { ok, json } = await safeFetch(`/admin/users/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });

    if (ok && json.success) {
      showToast(json.message || `Petugas @${username} berhasil dinonaktifkan`, 'info');
      loadAdminUsers();
    } else {
      showToast(json.message || 'Gagal menonaktifkan petugas', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}
