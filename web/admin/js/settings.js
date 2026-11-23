/**
 * Bank Identity, Logo, Operational Settings & Core Banking System (CBS) Health Module
 */

async function loadConfig() {
  try {
    const { ok, json } = await safeFetch('/admin/config', { headers: getAuthHeaders() });

    if (ok && json.data) {
      const c = json.data;
      document.getElementById('cfgBankName').value = c.bank_name || 'PT BPR DANA MANDIRI BOGOR';
      document.getElementById('cfgBankShortName').value = c.bank_short_name || 'Bank DMB';
      document.getElementById('cfgTagline').value = c.tagline || 'Mitra Terpercaya Menuju Sejahtera';
      document.getElementById('cfgLogoUrl').value = c.logo_url || '';
      document.getElementById('cfgAddress').value = c.head_office_address || '';
      document.getElementById('cfgCallCenter').value = c.call_center || '';
      document.getElementById('cfgWhatsApp').value = c.whats_app_cs || c.whatsapp_cs || '';
      document.getElementById('cfgEmail').value = c.email_cs || '';
      document.getElementById('cfgWebsite').value = c.website_url || '';
      document.getElementById('cfgMaintenance').checked = Boolean(c.maintenance_mode);
      document.getElementById('cfgMaintenanceMsg').value = c.maintenance_message || '';
      if (document.getElementById('cfgMaxLoginAttempts')) {
        document.getElementById('cfgMaxLoginAttempts').value = c.max_login_attempts || 5;
      }
      if (document.getElementById('cfgOtpProvider')) {
        document.getElementById('cfgOtpProvider').value = c.otp_provider || 'SANDBOX';
      }
      if (document.getElementById('cfgOtpGatewayUrl')) {
        document.getElementById('cfgOtpGatewayUrl').value = c.otp_gateway_url || 'https://api.jatismobile.com/v1/sms/send';
      }
      // Secrets are write-only (audit DMB-006): the API never returns their values,
      // only whether they are configured. Leave the field empty to keep the current value.
      if (document.getElementById('cfgOtpGatewayToken')) {
        const el = document.getElementById('cfgOtpGatewayToken');
        el.value = '';
        el.placeholder = c.otp_gateway_token_set
          ? 'Token tersimpan (kosongkan untuk tetap memakai token saat ini)'
          : 'Masukkan API Key / Token SMS Gateway';
      }

      // Live UI sync everywhere
      updateDOMBranding(c);
    }
  } catch (e) {
    console.error('Failed to load bank settings', e);
  }

  checkCbsHealth();
}

/**
 * Upload Logo File Handler (PNG, JPG, WebP only — max 5MB)
 * Fixes XSS vulnerability by escaping file.name via esc().
 */
async function handleLogoUpload(input) {
  if (!input.files || input.files.length === 0) return;
  const file = input.files[0];

  const validExtensions = ['image/png', 'image/jpeg', 'image/webp'];
  if (!validExtensions.includes(file.type)) {
    showToast('Format file harus berupa PNG, JPG, atau WebP', 'error');
    input.value = '';
    return;
  }

  if (file.size > 5 * 1024 * 1024) {
    showToast('Ukuran file maksimum adalah 5MB', 'error');
    input.value = '';
    return;
  }

  const uploadText = document.getElementById('logoUploadText');
  const originalText = uploadText.innerHTML;

  uploadText.innerHTML = '<span class="text-emerald-600 font-bold flex items-center justify-center gap-2"><i data-lucide="loader-2" class="w-4 h-4 animate-spin"></i> Sedang mengunggah logo ke server...</span>';
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();

  const formData = new FormData();
  formData.append('file', file);
  formData.append('category', 'logo');

  try {
    const res = await fetch(`${API_BASE}/admin/upload?category=logo`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: getAuthHeaders(false),
      body: formData
    });

    const json = await res.json();
    if (res.ok && json.success) {
      const fileUrl = json.data.url;
      document.getElementById('cfgLogoUrl').value = fileUrl;
      document.getElementById('cfgLogoPreview').src = fileUrl;

      // Update sidebar & login screen branding instantly
      updateDOMBranding({
        logo_url: fileUrl,
        bank_name: document.getElementById('cfgBankName').value,
        bank_short_name: document.getElementById('cfgBankShortName').value,
        tagline: document.getElementById('cfgTagline').value
      });

      showToast('Logo berhasil diunggah. Klik Simpan Seluruh Pengaturan untuk menyimpan.', 'success');
      uploadText.innerHTML = `<span class="text-emerald-700 font-bold flex items-center justify-center gap-1.5"><i data-lucide="check-circle-2" class="w-4 h-4 text-emerald-600"></i> ${esc(file.name)} berhasil diunggah (${(file.size / 1024).toFixed(1)} KB)</span>`;
      if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
    } else {
      showToast(json.message || 'Gagal mengunggah logo', 'error');
      uploadText.innerHTML = originalText;
      if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
    }
  } catch (err) {
    showToast('Gagal mengunggah: ' + err.message, 'error');
    uploadText.innerHTML = originalText;
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  } finally {
    input.value = '';
  }
}

async function handleSaveConfig(e) {
  e.preventDefault();
  const btn = document.getElementById('saveConfigBtn');
  btn.disabled = true;
  btn.innerText = 'Menyimpan...';

  const maxAttemptsEl = document.getElementById('cfgMaxLoginAttempts');
  let maxAttempts = maxAttemptsEl ? parseInt(maxAttemptsEl.value, 10) : 5;
  if (isNaN(maxAttempts) || maxAttempts < 3) maxAttempts = 3;
  if (maxAttempts > 10) maxAttempts = 10;
  if (maxAttemptsEl) maxAttemptsEl.value = maxAttempts;

  const waValue = document.getElementById('cfgWhatsApp').value.trim();

  const payload = {
    bank_name: document.getElementById('cfgBankName').value.trim(),
    bank_short_name: document.getElementById('cfgBankShortName').value.trim(),
    tagline: document.getElementById('cfgTagline').value.trim(),
    logo_url: document.getElementById('cfgLogoUrl').value.trim(),
    call_center: document.getElementById('cfgCallCenter').value.trim(),
    whats_app_cs: waValue,
    whatsapp_cs: waValue,
    email_cs: document.getElementById('cfgEmail').value.trim(),
    website_url: document.getElementById('cfgWebsite').value.trim(),
    head_office_address: document.getElementById('cfgAddress').value.trim(),
    max_login_attempts: maxAttempts,
    maintenance_mode: document.getElementById('cfgMaintenance').checked,
    maintenance_message: document.getElementById('cfgMaintenanceMsg').value.trim(),
    otp_provider: document.getElementById('cfgOtpProvider') ? document.getElementById('cfgOtpProvider').value : 'SANDBOX',
    otp_gateway_url: document.getElementById('cfgOtpGatewayUrl') ? document.getElementById('cfgOtpGatewayUrl').value.trim() : '',
    otp_gateway_token: document.getElementById('cfgOtpGatewayToken') ? document.getElementById('cfgOtpGatewayToken').value.trim() : ''
  };

  try {
    const { ok, json } = await safeFetch('/admin/config', {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify(payload)
    });

    if (ok && json.success) {
      showToast(json.message || 'Pengaturan operasional, identitas & logo bank berhasil disimpan!', 'success');
      loadConfig();
    } else {
      showToast(json.message || 'Gagal menyimpan pengaturan', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="check" class="w-4 h-4"></i><span>Simpan Seluruh Pengaturan & Logo</span>';
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  }
}

/**
 * Core Banking System (CBS) Health Check & OAuth2 Token Refresh
 * Calls GET /api/v1/admin/cbs/health and POST /api/v1/admin/cbs/refresh-token
 */
async function checkCbsHealth() {
  const badges = [
    document.getElementById('cbsHealthBadge'),
    document.getElementById('dashCbsHealthBadge')
  ].filter(Boolean);
  const details = [
    document.getElementById('cbsHealthDetail'),
    document.getElementById('dashCbsHealthDetail')
  ].filter(Boolean);

  badges.forEach(b => {
    b.textContent = 'Memeriksa...';
    b.className = 'px-2.5 py-1 rounded-full text-[11px] font-bold bg-slate-100 text-slate-600 border border-slate-200';
  });

  try {
    const { ok, json } = await safeFetch('/admin/cbs/health', { headers: getAuthHeaders() });
    if (ok && json.success) {
      const d = json.data || {};
      const providerName = d.provider || d.mode || 'CBS OpenAPI';
      const latency = d.latency_ms !== undefined ? ` · ${d.latency_ms} ms` : '';
      badges.forEach(b => {
        b.textContent = 'TERHUBUNG (ONLINE)';
        b.className = 'px-2.5 py-1 rounded-full text-[11px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200';
      });
      details.forEach(el => {
        el.innerHTML = `<span class="text-emerald-700 font-semibold">${esc(json.message || 'Koneksi Core Banking System sehat')}</span> &middot; Provider: <b>${esc(providerName)}</b>${esc(latency)} &middot; Dicek: ${esc(new Date().toLocaleTimeString('id-ID'))} WIB`;
      });
    } else {
      badges.forEach(b => {
        b.textContent = 'GANGGUAN / OFFLINE';
        b.className = 'px-2.5 py-1 rounded-full text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200';
      });
      details.forEach(el => {
        el.textContent = (json && json.message) || 'Core Banking System tidak dapat dihubungi.';
      });
    }
  } catch (err) {
    badges.forEach(b => {
      b.textContent = 'TIDAK TERJANGKAU';
      b.className = 'px-2.5 py-1 rounded-full text-[11px] font-bold bg-rose-50 text-rose-700 border border-rose-200';
    });
    details.forEach(el => {
      el.textContent = 'Gagal memeriksa status CBS: ' + err.message;
    });
  }
}

async function refreshCbsConnectionToken() {
  const btns = [
    document.getElementById('cbsRefreshTokenBtn'),
    document.getElementById('dashCbsRefreshTokenBtn')
  ].filter(Boolean);

  btns.forEach(b => {
    b.disabled = true;
    b.textContent = 'Menyegarkan Token...';
  });

  try {
    const { ok, json } = await safeFetch('/admin/cbs/refresh-token', {
      method: 'POST',
      headers: getAuthHeaders()
    });
    if (ok && json.success) {
      showToast(json.message || 'Token koneksi OAuth2 CBS berhasil diperbarui!', 'success');
      await checkCbsHealth();
    } else {
      showToast((json && json.message) || 'Gagal menyegarkan token koneksi CBS', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  } finally {
    btns.forEach(b => {
      b.disabled = false;
      b.innerHTML = '<i data-lucide="key-round" class="w-3.5 h-3.5"></i><span>Segarkan Token Koneksi</span>';
    });
    if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
  }
}
