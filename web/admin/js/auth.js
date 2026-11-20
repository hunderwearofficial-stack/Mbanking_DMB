/**
 * Authentication, Session Management, Self-Service Password Change & Idle Session Detector
 */

const IDLE_TIMEOUT_MS = 15 * 60 * 1000;      // 15 minutes total inactivity timeout
const IDLE_WARNING_MS = 13.5 * 60 * 1000;    // 13.5 minutes warning before auto-logout
let idleWarningTimer = null;
let idleLogoutTimer = null;
let idleWarningVisible = false;
let idleListenersAttached = false;

function checkAuth() {
  const token = localStorage.getItem('dmb_admin_token');
  const adminData = localStorage.getItem('dmb_admin_user');
  const loginScreen = document.getElementById('loginScreen');
  const mainLayout = document.getElementById('mainLayout');

  // Fetch and apply bank logo and identity immediately
  initAppBranding();

  if (!token) {
    stopIdleDetector();
    if (loginScreen) loginScreen.classList.remove('hidden');
    if (mainLayout) mainLayout.classList.add('hidden');
  } else {
    if (loginScreen) loginScreen.classList.add('hidden');
    if (mainLayout) mainLayout.classList.remove('hidden');
    let role = 'SUPER_ADMIN';
    if (adminData) {
      try {
        const admin = JSON.parse(adminData);
        role = (admin.role || 'SUPER_ADMIN').toUpperCase();
        const nameEl = document.getElementById('adminFullName');
        const roleEl = document.getElementById('adminRole');
        const avatarEl = document.getElementById('adminAvatarInitial');
        if (nameEl) nameEl.innerText = admin.full_name || 'Administrator';
        if (roleEl) roleEl.innerText = role;
        const headerRole = document.getElementById('headerRoleBadge');
        if (headerRole) headerRole.textContent = `Masuk sebagai ${admin.username || '-'} · ${role}`;
        if (avatarEl) {
          const initials = (admin.full_name || admin.username || 'AD').substring(0, 2).toUpperCase();
          avatarEl.innerText = initials;
        }
      } catch (e) {
        console.error('Error parsing admin session', e);
      }
    }

    if (typeof applyRoleNavigation === 'function') {
      applyRoleNavigation();
    }

    startIdleDetector();

    // Switch to current or default allowed tab
    const allowed = typeof getAllowedTabsForRole === 'function' ? getAllowedTabsForRole(role) : ['dashboard'];
    const targetTab = allowed.includes(currentTab) ? currentTab : (allowed[0] || 'dashboard');
    switchTab(targetTab);
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
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

async function handleLogin(e) {
  e.preventDefault();
  const alertBox = document.getElementById('loginAlert');
  const btn = document.getElementById('loginBtn');
  alertBox.classList.add('hidden');

  const username = document.getElementById('loginUsername').value.trim();
  const password = document.getElementById('loginPassword').value.trim();

  btn.disabled = true;
  btn.innerHTML = '<i data-lucide="loader-2" class="w-4 h-4 animate-spin inline mr-1.5"></i><span>Memverifikasi Otoritas...</span>';
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();

  try {
    const { ok, json } = await safeFetch('/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });

    if (ok && json.success) {
      localStorage.setItem('dmb_admin_token', json.data.token);
      localStorage.setItem('dmb_admin_user', JSON.stringify(json.data.admin));
      document.getElementById('loginPassword').value = '';
      showToast('Login berhasil! Selamat datang di Konsol Bank DMB.', 'success');
      currentTab = 'dashboard';
      checkAuth();
    } else {
      alertBox.innerText = json.message || 'Username atau password salah';
      alertBox.classList.remove('hidden');
    }
  } catch (err) {
    alertBox.innerText = 'Gagal menghubungi server (' + err.message + '). Pastikan backend server telah dijalankan.';
    alertBox.classList.remove('hidden');
  } finally {
    btn.disabled = false;
    btn.innerHTML = 'Masuk';
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  }
}

async function handleLogout() {
  const confirmed = await showConfirmModal({
    title: 'Keluar dari Konsol Backoffice',
    message: 'Apakah Anda yakin ingin mengakhiri sesi dan keluar dari konsol administrasi Bank DMB?',
    confirmText: 'Ya, Keluar Sistem',
    cancelText: 'Batal',
    variant: 'danger'
  });
  if (!confirmed) return;

  await performLogout('Anda telah keluar dari sistem.');
}

async function performLogout(toastMessage, toastType = 'info') {
  stopIdleDetector();
  try {
    await safeFetch('/admin/logout', {
      method: 'POST',
      headers: getAuthHeaders()
    });
  } catch (_) {
    // Ignore network failure during logout cleanup
  }
  localStorage.removeItem('dmb_admin_token');
  localStorage.removeItem('dmb_admin_user');
  if (toastMessage) showToast(toastMessage, toastType);
  checkAuth();
}

function handleSessionExpired() {
  stopIdleDetector();
  localStorage.removeItem('dmb_admin_token');
  localStorage.removeItem('dmb_admin_user');
  showToast('Sesi Anda telah berakhir. Silakan login kembali.', 'warning');
  checkAuth();
}

/**
 * Self-Service Officer Password Change Modal (POST /api/v1/admin/change-password)
 */
function openChangeMyPasswordModal() {
  const modal = document.getElementById('changeMyPasswordModal');
  const form = document.getElementById('changeMyPasswordForm');
  const errBox = document.getElementById('changeMyPasswordError');
  if (!modal) return;
  if (form) form.reset();
  if (errBox) errBox.classList.add('hidden');
  modal.classList.remove('hidden');
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function closeChangeMyPasswordModal() {
  const modal = document.getElementById('changeMyPasswordModal');
  if (modal) modal.classList.add('hidden');
}

function validateStrongAdminPassword(pw) {
  if (!pw || pw.length < 12) {
    return 'Kata sandi baru minimal 12 karakter.';
  }
  if (!/[A-Za-z]/.test(pw) || !/[0-9]/.test(pw)) {
    return 'Kata sandi baru wajib mengandung kombinasi huruf dan angka.';
  }
  return '';
}

async function handleChangeMyPassword(e) {
  e.preventDefault();
  const oldPassword = document.getElementById('myOldPassword').value;
  const newPassword = document.getElementById('myNewPassword').value;
  const confirmPassword = document.getElementById('myConfirmPassword').value;
  const errBox = document.getElementById('changeMyPasswordError');
  const btn = document.getElementById('submitChangeMyPasswordBtn');

  errBox.classList.add('hidden');

  const validationErr = validateStrongAdminPassword(newPassword);
  if (validationErr) {
    errBox.textContent = validationErr;
    errBox.classList.remove('hidden');
    return;
  }
  if (newPassword !== confirmPassword) {
    errBox.textContent = 'Konfirmasi kata sandi baru tidak cocok.';
    errBox.classList.remove('hidden');
    return;
  }
  if (oldPassword === newPassword) {
    errBox.textContent = 'Kata sandi baru tidak boleh sama dengan kata sandi saat ini.';
    errBox.classList.remove('hidden');
    return;
  }

  btn.disabled = true;
  btn.textContent = 'Menyimpan...';

  try {
    const { ok, json } = await safeFetch('/admin/change-password', {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({
        old_password: oldPassword,
        new_password: newPassword
      })
    });

    if (ok && json.success) {
      closeChangeMyPasswordModal();
      showToast(json.message || 'Kata sandi berhasil diperbarui!', 'success');
    } else {
      errBox.textContent = json.message || 'Gagal mengganti kata sandi.';
      errBox.classList.remove('hidden');
    }
  } catch (err) {
    errBox.textContent = 'Kesalahan jaringan: ' + err.message;
    errBox.classList.remove('hidden');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="key-round" class="w-4 h-4"></i><span>Simpan Kata Sandi Baru</span>';
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  }
}

/**
 * Idle Session Auto-Logout Detector (15 minutes inactivity with warning at 13.5 minutes)
 */
function resetIdleTimers() {
  if (!localStorage.getItem('dmb_admin_token')) return;
  if (idleWarningVisible) return; // Don't auto-dismiss warning without explicit user button click

  clearTimeout(idleWarningTimer);
  clearTimeout(idleLogoutTimer);

  idleWarningTimer = setTimeout(() => {
    showIdleWarningBanner();
  }, IDLE_WARNING_MS);

  idleLogoutTimer = setTimeout(() => {
    hideIdleWarningBanner();
    performLogout('Sesi otomatis berakhir karena tidak ada aktivitas selama 15 menit (Kepatuhan Keamanan OJK).', 'warning');
  }, IDLE_TIMEOUT_MS);
}

function showIdleWarningBanner() {
  idleWarningVisible = true;
  const modal = document.getElementById('idleSessionWarningModal');
  if (modal) {
    modal.classList.remove('hidden');
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  } else {
    showToast('Sesi Anda akan berakhir dalam 90 detik karena tidak ada aktivitas.', 'warning');
  }
}

function hideIdleWarningBanner() {
  idleWarningVisible = false;
  const modal = document.getElementById('idleSessionWarningModal');
  if (modal) modal.classList.add('hidden');
}

function extendIdleSession() {
  hideIdleWarningBanner();
  resetIdleTimers();
  showToast('Sesi aktif diperpanjang.', 'success');
}

function startIdleDetector() {
  if (!idleListenersAttached) {
    ['mousedown', 'keydown', 'scroll', 'touchstart'].forEach(evt => {
      document.addEventListener(evt, resetIdleTimers, { passive: true });
    });
    idleListenersAttached = true;
  }
  hideIdleWarningBanner();
  resetIdleTimers();
}

function stopIdleDetector() {
  clearTimeout(idleWarningTimer);
  clearTimeout(idleLogoutTimer);
  hideIdleWarningBanner();
}
