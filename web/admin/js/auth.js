/**
 * Authentication & Session Management Module
 */

function checkAuth() {
  const token = localStorage.getItem('dmb_admin_token');
  const adminData = localStorage.getItem('dmb_admin_user');
  const loginScreen = document.getElementById('loginScreen');
  const mainLayout = document.getElementById('mainLayout');

  // Fetch and apply bank logo and identity immediately
  initAppBranding();

  if (!token) {
    if (loginScreen) loginScreen.classList.remove('hidden');
    if (mainLayout) mainLayout.classList.add('hidden');
  } else {
    if (loginScreen) loginScreen.classList.add('hidden');
    if (mainLayout) mainLayout.classList.remove('hidden');
    if (adminData) {
      try {
        const admin = JSON.parse(adminData);
        const nameEl = document.getElementById('adminFullName');
        const roleEl = document.getElementById('adminRole');
        const avatarEl = document.getElementById('adminAvatarInitial');
        if (nameEl) nameEl.innerText = admin.full_name || 'Administrator';
        if (roleEl) roleEl.innerText = admin.role || 'SUPER_ADMIN';
        if (avatarEl) {
          const initials = (admin.full_name || admin.username || 'AD').substring(0, 2).toUpperCase();
          avatarEl.innerText = initials;
        }
      } catch (e) {
        console.error('Error parsing admin session', e);
      }
    }
    // Initialize Dashboard
    loadDashboardStats();
  }
}

function toggleLoginPasswordVisibility() {
  const passInp = document.getElementById('loginPassword');
  const eyeIcon = document.getElementById('loginEyeIcon');
  if (!passInp) return;
  if (passInp.type === 'password') {
    passInp.type = 'text';
    if (eyeIcon) eyeIcon.setAttribute('data-lucide', 'eye-off');
  } else {
    passInp.type = 'password';
    if (eyeIcon) eyeIcon.setAttribute('data-lucide', 'eye');
  }
  lucide.createIcons();
}

async function handleLogin(e) {
  e.preventDefault();
  const alertBox = document.getElementById('loginAlert');
  const btn = document.getElementById('loginBtn');
  alertBox.classList.add('hidden');

  const username = document.getElementById('loginUsername').value.trim();
  const password = document.getElementById('loginPassword').value.trim();

  btn.disabled = true;
  btn.innerHTML = '<i data-lucide="loader-2" class="w-4 h-4 animate-spin"></i><span>Memverifikasi Otoritas...</span>';
  lucide.createIcons();

  try {
    const { ok, json } = await safeFetch('/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });

    if (ok && json.success) {
      localStorage.setItem('dmb_admin_token', json.data.token);
      localStorage.setItem('dmb_admin_user', JSON.stringify(json.data.admin));
      showToast('Login berhasil! Selamat datang di Konsol Bank DMB.', 'success');
      checkAuth();
    } else {
      alertBox.innerText = json.message || 'Username atau password salah';
      alertBox.classList.remove('hidden');
    }
  } catch (err) {
    alertBox.innerText = 'Gagal menghubungi server (' + err.message + '). Pastikan backend server.exe telah dijalankan.';
    alertBox.classList.remove('hidden');
  } finally {
    btn.disabled = false;
    btn.innerHTML = 'Masuk';
    lucide.createIcons();
  }
}

function handleLogout() {
  if (confirm('Apakah Anda yakin ingin keluar dari konsol admin?')) {
    localStorage.removeItem('dmb_admin_token');
    localStorage.removeItem('dmb_admin_user');
    showToast('Anda telah keluar dari sistem.', 'info');
    checkAuth();
  }
}

function handleSessionExpired() {
  localStorage.removeItem('dmb_admin_token');
  showToast('Sesi Anda telah berakhir. Silakan login kembali.', 'info');
  checkAuth();
}
