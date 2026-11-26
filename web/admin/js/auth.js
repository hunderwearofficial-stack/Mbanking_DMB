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
  localStorage.removeItem('dmb_admin_token');
  const adminData = localStorage.getItem('dmb_admin_user');
  const loginScreen = document.getElementById('loginScreen');
  const mainLayout = document.getElementById('mainLayout');

  // Fetch and apply bank logo and identity immediately
  initAppBranding();

  if (!adminData) {
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
  const totpInput = document.getElementById('loginTotpCode');
  const totpCode = totpInput ? totpInput.value.trim() : '';

  btn.disabled = true;
  btn.innerHTML = '<i data-lucide="loader-2" class="w-4 h-4 animate-spin inline mr-1.5"></i><span>Memverifikasi Otoritas...</span>';
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();

  try {
    const { ok, json } = await safeFetch('/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password, totp_code: totpCode })
    });

    if (ok && json.success) {
      if (json.data && json.data.password_change_required) {
        document.getElementById('loginPassword').value = '';
        if (totpInput) totpInput.value = '';
        openInitialPasswordModal(json.data.admin);
        return;
      }
      if (json.data && json.data.mfa_setup_required) {
        document.getElementById('loginPassword').value = '';
        await openMfaSetupModal(json.data.admin);
        return;
      }
      localStorage.setItem('dmb_admin_user', JSON.stringify(json.data.admin));
      document.getElementById('loginPassword').value = '';
      if (totpInput) totpInput.value = '';
      const mfaGrp = document.getElementById('loginMfaGroup');
      if (mfaGrp) mfaGrp.classList.add('hidden');
      showToast('Login berhasil! Selamat datang di Konsol Bank DMB.', 'success');
      currentTab = 'dashboard';
      checkAuth();
    } else {
      const errCode = json.response_code || json.code || '';
      const mfaFlag = (json.errors && json.errors.mfa_required) || (json.data && json.data.mfa_required);
      if (errCode === 'MFA_REQUIRED' || errCode === 'MFA_INVALID' || mfaFlag) {
        const mfaGrp = document.getElementById('loginMfaGroup');
        if (mfaGrp) mfaGrp.classList.remove('hidden');
        if (totpInput) totpInput.focus();
      }
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
  if (!localStorage.getItem('dmb_admin_user')) return;
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

async function openMfaSetupModal(admin) {
  let modal = document.getElementById('mfaSetupModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'mfaSetupModal';
    modal.className = 'fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4';
    modal.innerHTML = `
      <div class="bg-white rounded-2xl shadow-2xl border border-slate-200 max-w-md w-full p-6 space-y-4">
        <h3 class="text-base font-extrabold text-slate-900">Aktivasi MFA Petugas (Wajib)</h3>
        <p class="text-xs text-slate-600">Masukkan kunci rahasia berikut ke aplikasi Google Authenticator / Microsoft Authenticator, lalu masukkan kode 6 digit.</p>
        <div class="p-3 rounded-xl bg-slate-50 border border-slate-200 space-y-1">
          <div class="text-[10px] font-bold text-slate-500 uppercase">Secret Key (Base32)</div>
          <div id="mfaSecretText" class="text-xs font-mono font-bold text-slate-900 select-all break-all">Memuat...</div>
        </div>
        <div class="space-y-1">
          <label class="block text-xs font-bold text-slate-700">Kode Autentikator (6 Digit)</label>
          <input type="text" id="mfaConfirmCode" maxlength="6" inputmode="numeric" placeholder="000000"
            class="w-full px-3.5 py-2.5 text-sm font-mono text-center tracking-widest rounded-xl border border-slate-300 focus:outline-none focus:border-[#033172]">
        </div>
        <div id="mfaSetupErr" class="hidden text-xs text-rose-600 font-semibold"></div>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" onclick="closeMfaSetupModal()" class="px-4 py-2 rounded-xl text-xs font-bold text-slate-600 hover:bg-slate-100">Batal</button>
          <button type="button" onclick="confirmMfaSetup()" class="px-4 py-2 rounded-xl text-xs font-bold text-white bg-[#033172] hover:bg-[#022454]">Aktifkan &amp; Masuk</button>
        </div>
      </div>`;
    document.body.appendChild(modal);
  }
  modal.classList.remove('hidden');
  const errEl = document.getElementById('mfaSetupErr');
  if (errEl) errEl.classList.add('hidden');
  try {
    const { ok, json } = await safeFetch('/admin/mfa/setup', { method: 'POST', headers: getAuthHeaders() });
    if (ok && json.data) {
      document.getElementById('mfaSecretText').textContent = json.data.secret || '-';
    } else if (errEl) {
      errEl.textContent = json.message || 'Gagal menyiapkan MFA';
      errEl.classList.remove('hidden');
    }
  } catch (err) {
    if (errEl) { errEl.textContent = err.message; errEl.classList.remove('hidden'); }
  }
}

function closeMfaSetupModal() {
  const modal = document.getElementById('mfaSetupModal');
  if (modal) modal.classList.add('hidden');
}

async function confirmMfaSetup() {
  const code = (document.getElementById('mfaConfirmCode')?.value || '').trim();
  const errEl = document.getElementById('mfaSetupErr');
  if (errEl) errEl.classList.add('hidden');
  try {
    const { ok, json } = await safeFetch('/admin/mfa/confirm', {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ code })
    });
    if (ok && json.success) {
      closeMfaSetupModal();
      localStorage.setItem('dmb_admin_user', JSON.stringify(json.data.admin));
      showToast('MFA berhasil diaktifkan!', 'success');
      currentTab = 'dashboard';
      checkAuth();
    } else if (errEl) {
      errEl.textContent = json.message || 'Kode MFA tidak valid';
      errEl.classList.remove('hidden');
    }
  } catch (err) {
    if (errEl) { errEl.textContent = err.message; errEl.classList.remove('hidden'); }
  }
}

/**
 * First-login replacement of a password issued by another officer or by the system
 * (audit MA-03). Uses the short-lived setup cookie from /admin/login.
 */
function openInitialPasswordModal(admin) {
  let modal = document.getElementById('initialPasswordModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'initialPasswordModal';
    modal.className = 'fixed inset-0 z-50 bg-slate-900/60 flex items-center justify-center p-4';
    modal.innerHTML = `
      <div class="bg-white rounded-2xl shadow-2xl border border-slate-200 max-w-md w-full p-6 space-y-4">
        <h3 class="text-base font-extrabold text-slate-900">Ganti Kata Sandi Awal (Wajib)</h3>
        <p class="text-xs text-slate-600">Kata sandi Anda dibuat oleh petugas lain atau oleh sistem. Buat kata sandi baru yang hanya Anda ketahui sebelum menggunakan konsol.</p>
        <div class="space-y-1">
          <label for="initialPwNew" class="block text-xs font-bold text-slate-700">Kata Sandi Baru</label>
          <input type="password" id="initialPwNew" autocomplete="new-password" minlength="12"
            class="w-full px-3.5 py-2.5 text-sm rounded-xl border border-slate-300 focus:outline-none focus:border-[#033172]">
        </div>
        <div class="space-y-1">
          <label for="initialPwConfirm" class="block text-xs font-bold text-slate-700">Ulangi Kata Sandi Baru</label>
          <input type="password" id="initialPwConfirm" autocomplete="new-password" minlength="12"
            class="w-full px-3.5 py-2.5 text-sm rounded-xl border border-slate-300 focus:outline-none focus:border-[#033172]">
        </div>
        <p class="text-[10px] text-slate-400">Minimal 12 karakter, kombinasi huruf &amp; angka.</p>
        <div id="initialPwErr" class="hidden text-xs text-rose-600 font-semibold"></div>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" id="initialPwCancel" class="px-4 py-2 rounded-xl text-xs font-bold text-slate-600 hover:bg-slate-100">Batal</button>
          <button type="button" id="initialPwSubmit" class="px-4 py-2 rounded-xl text-xs font-bold text-white bg-[#033172] hover:bg-[#022454]">Simpan Kata Sandi</button>
        </div>
      </div>`;
    document.body.appendChild(modal);
    document.getElementById('initialPwCancel').addEventListener('click', () => modal.classList.add('hidden'));
    document.getElementById('initialPwSubmit').addEventListener('click', submitInitialPassword);
  }
  document.getElementById('initialPwNew').value = '';
  document.getElementById('initialPwConfirm').value = '';
  document.getElementById('initialPwErr').classList.add('hidden');
  modal.classList.remove('hidden');
  document.getElementById('initialPwNew').focus();
}

async function submitInitialPassword() {
  const modal = document.getElementById('initialPasswordModal');
  const errEl = document.getElementById('initialPwErr');
  const pw = document.getElementById('initialPwNew').value;
  const confirmPw = document.getElementById('initialPwConfirm').value;
  const showErr = (msg) => { errEl.textContent = msg; errEl.classList.remove('hidden'); };
  errEl.classList.add('hidden');
  if (pw.length < 12 || !/[A-Za-z]/.test(pw) || !/[0-9]/.test(pw)) {
    showErr('Kata sandi minimal 12 karakter dan wajib mengandung huruf dan angka.');
    return;
  }
  if (pw !== confirmPw) {
    showErr('Konfirmasi kata sandi tidak sama.');
    return;
  }
  try {
    const { ok, json } = await safeFetch('/admin/mfa/password', {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ new_password: pw })
    });
    if (!ok || !json.success) {
      showErr(json.message || 'Gagal mengganti kata sandi. Silakan login ulang.');
      return;
    }
    modal.classList.add('hidden');
    if (json.data && json.data.mfa_setup_required) {
      showToast('Kata sandi berhasil diganti. Lanjutkan pendaftaran MFA.', 'success');
      await openMfaSetupModal(json.data.admin);
      return;
    }
    localStorage.setItem('dmb_admin_user', JSON.stringify(json.data.admin));
    showToast('Kata sandi berhasil diganti. Selamat datang di Konsol Bank DMB.', 'success');
    currentTab = 'dashboard';
    checkAuth();
  } catch (err) {
    showErr(err.message);
  }
}
