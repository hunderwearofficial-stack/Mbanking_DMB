/**
 * API Client & Network Service
 * Centralizes all HTTP calls, token authorization headers, error handling, and branding sync.
 */

// Dynamically determine backend API base URL
const API_BASE = (window.location.protocol === 'file:' || window.location.port !== '8080')
  ? 'http://localhost:8080/api/v1'
  : `${window.location.origin}/api/v1`;

/**
 * Returns standard authorization headers with JWT Bearer Token
 */
function getAuthHeaders() {
  const token = localStorage.getItem('dmb_admin_token');
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
  };
}

/**
 * Robust wrapper around fetch with JSON response parsing and HTTP error detection
 */
async function safeFetch(endpoint, options = {}) {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE}${endpoint}`;

  try {
    const res = await fetch(url, options);

    // Auto-detect expired token
    if (res.status === 401) {
      handleSessionExpired();
      return { ok: false, status: 401, json: { message: 'Sesi telah berakhir' } };
    }

    const text = await res.text();
    let json = {};
    if (text) {
      try {
        json = JSON.parse(text);
      } catch (err) {
        if (!res.ok) {
          throw new Error(`Server mengembalikan status HTTP ${res.status} ${res.statusText}`);
        }
        throw new Error('Format data yang diterima bukan JSON valid');
      }
    }

    return {
      ok: res.ok,
      status: res.status,
      json: json
    };
  } catch (err) {
    throw new Error(err.message || 'Koneksi ke server API gagal');
  }
}

/**
 * Global Branding & Logo Synchronizer
 * Loads the official bank logo from backend on page load and updates everywhere
 */
async function initAppBranding() {
  try {
    const res = await fetch(`${API_BASE}/config`);
    if (res.ok) {
      const json = await res.json();
      if (json.data) {
        updateDOMBranding(json.data);
      }
    }
  } catch (e) {
    console.warn('Branding load skipped (offline mode)', e);
  }
}

function updateDOMBranding(c) {
  if (!c) return;
  const logoUrl = c.logo_url || '';
  const bankName = c.bank_name || 'PT BPR DANA MANDIRI BOGOR';
  const shortName = c.bank_short_name || 'Bank DMB';
  const tagline = c.tagline || 'Mitra Terpercaya Menuju Sejahtera';

  // 1. Sidebar Brand
  const sidebarLogo = document.getElementById('sidebarLogoImg');
  const sidebarFallback = document.getElementById('sidebarLogoFallback');
  if (sidebarLogo) {
    if (logoUrl) {
      sidebarLogo.src = logoUrl;
      sidebarLogo.classList.remove('hidden');
      if (sidebarFallback) sidebarFallback.classList.add('hidden');
    } else {
      sidebarLogo.classList.add('hidden');
      if (sidebarFallback) sidebarFallback.classList.remove('hidden');
    }
  }

  const sidebarBankTitle = document.getElementById('sidebarBankTitle');
  if (sidebarBankTitle) sidebarBankTitle.innerText = shortName.toUpperCase();
  const sidebarBankSub = document.getElementById('sidebarBankSub');
  if (sidebarBankSub) sidebarBankSub.innerText = bankName.toUpperCase();

  // 2. Login Page Brand
  const loginLogo = document.getElementById('loginLogoImg');
  const loginFallback = document.getElementById('loginLogoFallback');
  if (loginLogo) {
    if (logoUrl) {
      loginLogo.src = logoUrl;
      loginLogo.classList.remove('hidden');
      if (loginFallback) loginFallback.classList.add('hidden');
    } else {
      loginLogo.classList.add('hidden');
      if (loginFallback) loginFallback.classList.remove('hidden');
    }
  }

  const loginHeroLogo = document.getElementById('loginHeroLogoImg');
  if (loginHeroLogo && logoUrl) {
    loginHeroLogo.src = logoUrl;
    loginHeroLogo.classList.remove('hidden');
  }

  const loginBankName = document.getElementById('loginBankName');
  if (loginBankName) loginBankName.innerText = shortName.toUpperCase();
  const loginBankSub = document.getElementById('loginBankSub');
  if (loginBankSub) loginBankSub.innerText = bankName.toUpperCase();
  const loginHeroTagline = document.getElementById('loginHeroTagline');
  if (loginHeroTagline) loginHeroTagline.innerText = tagline;

  // 3. Settings Tab Preview
  const cfgLogoPreview = document.getElementById('cfgLogoPreview');
  if (cfgLogoPreview && logoUrl) cfgLogoPreview.src = logoUrl;
  const cfgBankShortNameDisplay = document.getElementById('cfgBankShortNameDisplay');
  if (cfgBankShortNameDisplay) cfgBankShortNameDisplay.innerText = shortName;
  const cfgTaglineDisplay = document.getElementById('cfgTaglineDisplay');
  if (cfgTaglineDisplay) cfgTaglineDisplay.innerText = tagline;
  const cfgBankNameBadge = document.getElementById('cfgBankNameBadge');
  if (cfgBankNameBadge) cfgBankNameBadge.innerText = bankName;

  // 4. Browser Title & Favicon
  document.title = `${shortName} - Backoffice & Portal Admin M-Banking`;
}
