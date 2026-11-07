/**
 * Admin Users & Role-Based Access Control (RBAC) Module
 */

let allAdminUsers = [];

async function loadAdminUsers() {
  const tbody = document.getElementById('adminUsersTableBody');
  tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-xs text-slate-400">Memuat data petugas admin...</td></tr>';

  try {
    const { ok, json } = await safeFetch('/admin/users', { headers: getAuthHeaders() });

    if (ok && json.data) {
      allAdminUsers = json.data;
      renderAdminUsers(allAdminUsers);
    } else {
      tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-xs text-rose-500">Gagal memuat data petugas admin.</td></tr>';
    }
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="6" class="p-8 text-center text-xs text-rose-500">Error: ${err.message}</td></tr>`;
  }
}

function renderAdminUsers(users) {
  const tbody = document.getElementById('adminUsersTableBody');
  if (!users || users.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-xs text-slate-400">Belum ada petugas admin terdaftar.</td></tr>';
    return;
  }

  const currentUserData = localStorage.getItem('dmb_admin_user');
  let currentAdminId = '';
  if (currentUserData) {
    try { currentAdminId = JSON.parse(currentUserData).id; } catch (_) {}
  }

  tbody.innerHTML = users.map((u, idx) => {
    // Role Badge & Styling
    let roleBadge = '';
    let roleDesc = '';
    switch (u.role) {
      case 'SUPER_ADMIN':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-purple-100 text-purple-700 border border-purple-200 flex items-center gap-1 w-max"><i data-lucide="shield-alert" class="w-3 h-3"></i> SUPER ADMIN</span>';
        roleDesc = 'Akses Penuh Semua Modul';
        break;
      case 'CS':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-blue-100 text-blue-700 border border-blue-200 flex items-center gap-1 w-max"><i data-lucide="headphones" class="w-3 h-3"></i> CUSTOMER SERVICE</span>';
        roleDesc = 'Kelola Nasabah & Reset Device';
        break;
      case 'MARKETING':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800 border border-amber-200 flex items-center gap-1 w-max"><i data-lucide="sparkles" class="w-3 h-3"></i> MARKETING</span>';
        roleDesc = 'Kelola Banner & Konten Promosi';
        break;
      case 'COMPLIANCE':
      case 'AUDITOR':
        roleBadge = '<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800 border border-emerald-200 flex items-center gap-1 w-max"><i data-lucide="file-check" class="w-3 h-3"></i> AUDITOR / COMPLIANCE</span>';
        roleDesc = 'Audit Log & Laporan (Read-Only)';
        break;
      default:
        roleBadge = `<span class="px-2.5 py-1 rounded-full text-[10px] font-bold bg-slate-100 text-slate-700 border border-slate-200">${u.role}</span>`;
        roleDesc = 'Petugas Operasional';
    }

    const isCurrent = u.id === currentAdminId;
    const statusBadge = u.is_active
      ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200 flex items-center gap-1 w-max"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span> Aktif</span>'
      : '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200 flex items-center gap-1 w-max"><span class="w-1.5 h-1.5 rounded-full bg-rose-500"></span> Nonaktif</span>';

    const initials = (u.full_name || u.username).substring(0, 2).toUpperCase();
    const createdDate = u.created_at ? new Date(u.created_at).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' }) : '-';

    return `
      <tr class="border-b border-slate-100 hover:bg-slate-50/70 transition">
        <td class="p-4">
          <div class="flex items-center gap-3">
            <div class="w-9 h-9 rounded-xl bg-gradient-to-tr from-slate-800 to-slate-700 text-emerald-400 font-extrabold text-xs flex items-center justify-center shadow-sm">
              ${initials}
            </div>
            <div>
              <div class="font-bold text-xs text-slate-800 flex items-center gap-2">
                ${u.full_name || u.username}
                ${isCurrent ? '<span class="text-[9px] bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded border border-slate-200 font-semibold">Anda</span>' : ''}
              </div>
              <div class="text-[11px] text-slate-400">${u.email || '-'}</div>
            </div>
          </div>
        </td>
        <td class="p-4 text-xs font-mono font-bold text-slate-600">@${u.username}</td>
        <td class="p-4">
          ${roleBadge}
          <div class="text-[10px] text-slate-400 mt-1">${roleDesc}</div>
        </td>
        <td class="p-4">${statusBadge}</td>
        <td class="p-4 text-xs text-slate-500">${createdDate}</td>
        <td class="p-4 text-right">
          <div class="flex items-center justify-end gap-1.5">
            ${!isCurrent ? `
              <button onclick="toggleAdminStatus('${u.id}', ${!u.is_active})" title="${u.is_active ? 'Nonaktifkan Akun' : 'Aktifkan Akun'}"
                class="px-2.5 py-1.5 rounded-lg border text-xs font-semibold transition flex items-center gap-1 ${u.is_active ? 'border-amber-200 text-amber-700 hover:bg-amber-50' : 'border-emerald-200 text-emerald-700 hover:bg-emerald-50'}">
                <i data-lucide="${u.is_active ? 'user-x' : 'user-check'}" class="w-3.5 h-3.5"></i>
                <span class="hidden sm:inline">${u.is_active ? 'Nonaktifkan' : 'Aktifkan'}</span>
              </button>
              <button onclick="deleteAdminUser('${u.id}', '${u.username}')" title="Hapus Petugas"
                class="p-1.5 rounded-lg border border-rose-200 text-rose-600 hover:bg-rose-50 transition">
                <i data-lucide="trash-2" class="w-3.5 h-3.5"></i>
              </button>
            ` : '<span class="text-[11px] text-slate-400 italic px-2">Sesi Aktif</span>'}
          </div>
        </td>
      </tr>
    `;
  }).join('');

  lucide.createIcons();
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
  switch (role) {
    case 'SUPER_ADMIN':
      descBox.innerHTML = '<span class="text-purple-700 font-semibold">&bull; Hak Akses:</span> Memiliki kewenangan tertinggi untuk mengelola seluruh modul: Dashboard, Nasabah, Reset Device, CMS Banner Promosi, Pengaturan Bank, dan Manajemen Petugas.';
      break;
    case 'CS':
      descBox.innerHTML = '<span class="text-blue-700 font-semibold">&bull; Hak Akses:</span> Fokus pada operasional nasabah: Membuka data rekening, melakukan Unbind/Reset Device ID saat nasabah ganti smartphone, dan memblokir/mengaktifkan akun nasabah.';
      break;
    case 'MARKETING':
      descBox.innerHTML = '<span class="text-amber-700 font-semibold">&bull; Hak Akses:</span> Mengelola konten visual: Menambah, mengedit, dan mengatur urutan Banner Promosi Deposito & CSR yang tayang di aplikasi Mobile Banking Bank DMB.';
      break;
    case 'COMPLIANCE':
      descBox.innerHTML = '<span class="text-emerald-700 font-semibold">&bull; Hak Akses:</span> Read-Only monitoring audit perbankan untuk Auditor Internal & Kepatuhan Regulasi OJK: Hanya dapat melihat transaksi dan status nasabah tanpa izin memodifikasi.';
      break;
  }
}

async function handleCreateAdmin(e) {
  e.preventDefault();
  const btn = document.getElementById('submitNewAdminBtn');
  btn.disabled = true;
  btn.innerText = 'Menyimpan...';

  const payload = {
    full_name: document.getElementById('newAdminFullName').value.trim(),
    username: document.getElementById('newAdminUsername').value.trim(),
    email: document.getElementById('newAdminEmail').value.trim(),
    password: document.getElementById('newAdminPassword').value.trim(),
    role: document.getElementById('newAdminRole').value,
    is_active: document.getElementById('newAdminIsActive').checked
  };

  try {
    const { ok, json } = await safeFetch('/admin/users', {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify(payload)
    });

    if (ok && json.success) {
      showToast('Petugas admin baru berhasil didaftarkan!', 'success');
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
    lucide.createIcons();
  }
}

async function toggleAdminStatus(id, newStatus) {
  const actionText = newStatus ? 'mengaktifkan kembali' : 'menonaktifkan';
  if (!confirm(`Apakah Anda yakin ingin ${actionText} akun petugas ini?`)) return;

  try {
    const { ok, json } = await safeFetch(`/admin/users/${id}/status`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({ is_active: newStatus })
    });

    if (ok && json.success) {
      showToast('Status petugas berhasil diperbarui', 'success');
      loadAdminUsers();
    } else {
      showToast(json.message || 'Gagal mengubah status', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

async function deleteAdminUser(id, username) {
  if (!confirm(`Hapus permanen akun petugas "@${username}"? Tindakan ini tidak dapat dibatalkan.`)) return;

  try {
    const { ok, json } = await safeFetch(`/admin/users/${id}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });

    if (ok && json.success) {
      showToast(`Petugas @${username} berhasil dihapus`, 'info');
      loadAdminUsers();
    } else {
      showToast(json.message || 'Gagal menghapus petugas', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

