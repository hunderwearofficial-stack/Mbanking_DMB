/**
 * Bank Identity, Logo & System Configuration Module
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
      document.getElementById('cfgWhatsApp').value = c.whatsapp_cs || '';
      document.getElementById('cfgEmail').value = c.email_cs || '';
      document.getElementById('cfgWebsite').value = c.website_url || '';
      document.getElementById('cfgEnforceDevice').checked = c.enforce_device_binding;
      document.getElementById('cfgMaintenance').checked = c.maintenance_mode;
      document.getElementById('cfgMaintenanceMsg').value = c.maintenance_message || '';

      // Live UI sync everywhere
      updateDOMBranding(c);
    }
  } catch (e) {
    console.error('Failed to load bank settings', e);
  }
}

/**
 * Upload Logo File Handler (PNG, JPG, WebP, SVG)
 */
async function handleLogoUpload(input) {
  if (!input.files || input.files.length === 0) return;
  const file = input.files[0];

  // Validation
  const validExtensions = ['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml'];
  if (!validExtensions.includes(file.type) && !file.name.endsWith('.svg')) {
    showToast('Format file harus berupa PNG, JPG, WebP, atau SVG', 'error');
    input.value = '';
    return;
  }

  if (file.size > 5 * 1024 * 1024) {
    showToast('Ukuran file maksimum adalah 5MB', 'error');
    input.value = '';
    return;
  }

  const uploadBox = document.getElementById('logoUploadBox');
  const uploadText = document.getElementById('logoUploadText');
  const originalText = uploadText.innerHTML;

  uploadText.innerHTML = '<span class="text-emerald-600 font-bold flex items-center justify-center gap-2"><i data-lucide="loader-2" class="w-4 h-4 animate-spin"></i> Sedang mengunggah logo ke server...</span>';
  lucide.createIcons();

  const formData = new FormData();
  formData.append('file', file);

  try {
    const token = localStorage.getItem('dmb_admin_token');
    const res = await fetch(`${API_BASE}/admin/upload`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`
      },
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

      showToast('Logo Bank berhasil diunggah! Klik Simpan Pengaturan di bawah.', 'success');
      uploadText.innerHTML = `<span class="text-emerald-700 font-bold flex items-center justify-center gap-1.5"><i data-lucide="check-circle-2" class="w-4 h-4 text-emerald-600"></i> ${file.name} berhasil diunggah (${(file.size / 1024).toFixed(1)} KB)</span>`;
      lucide.createIcons();
    } else {
      showToast(json.message || 'Gagal mengunggah logo', 'error');
      uploadText.innerHTML = originalText;
      lucide.createIcons();
    }
  } catch (err) {
    showToast('Gagal mengunggah: ' + err.message, 'error');
    uploadText.innerHTML = originalText;
    lucide.createIcons();
  }
}

async function handleSaveConfig(e) {
  e.preventDefault();
  const btn = document.getElementById('saveConfigBtn');
  btn.disabled = true;
  btn.innerText = 'Menyimpan...';

  const payload = {
    bank_name: document.getElementById('cfgBankName').value.trim(),
    bank_short_name: document.getElementById('cfgBankShortName').value.trim(),
    tagline: document.getElementById('cfgTagline').value.trim(),
    logo_url: document.getElementById('cfgLogoUrl').value.trim(),
    head_office_address: document.getElementById('cfgAddress').value.trim(),
    call_center: document.getElementById('cfgCallCenter').value.trim(),
    whatsapp_cs: document.getElementById('cfgWhatsApp').value.trim(),
    email_cs: document.getElementById('cfgEmail').value.trim(),
    website_url: document.getElementById('cfgWebsite').value.trim(),
    enforce_device_binding: document.getElementById('cfgEnforceDevice').checked,
    maintenance_mode: document.getElementById('cfgMaintenance').checked,
    maintenance_message: document.getElementById('cfgMaintenanceMsg').value.trim()
  };

  try {
    const { ok, json } = await safeFetch('/admin/config', {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify(payload)
    });

    if (ok && json.success) {
      showToast('Logo & Pengaturan bank berhasil disimpan!', 'success');
      loadConfig();
    } else {
      showToast(json.message || 'Gagal menyimpan pengaturan', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="check" class="w-4 h-4"></i><span>Simpan Seluruh Pengaturan & Logo</span>';
    lucide.createIcons();
  }
}
