/**
 * API Client & Network Service
 * Centralizes all HTTP calls, token authorization headers, error handling, and branding sync.
 */

// The console is served by the backend itself (/admin) and talks to the same origin
// (/api/v1) on any host or port — the CSP only allows same-origin requests anyway.
// Only a file opened directly from disk falls back to the local backend.
const API_BASE = window.location.protocol === 'file:'
  ? 'http://localhost:8080/api/v1'
  : `${window.location.origin}/api/v1`;

/**
 * SECURITY (audit DMB-017): every server-provided value inserted into HTML must
 * be escaped. esc() escapes for HTML text/attribute context; jsArg() produces a
 * safely quoted JavaScript string literal for use inside onclick="..." handlers.
 */
function esc(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/`/g, '&#96;');
}

function jsArg(value) {
  return esc(JSON.stringify(value === null || value === undefined ? '' : String(value)));
}

/** Prevents spreadsheet formula injection when exporting CSV. */
function csvCell(value) {
  let s = value === null || value === undefined ? '' : String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return '"' + s.replace(/"/g, '""') + '"';
}

/**
 * Returns standard authorization headers with JWT Bearer Token and CSRF header
 */
function getAuthHeaders(includeJsonContentType = true) {
  const token = localStorage.getItem('dmb_admin_token');
  const headers = {
    'X-Requested-With': 'dmb-admin'
  };
  if (includeJsonContentType) {
    headers['Content-Type'] = 'application/json';
  }
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  return headers;
}

/**
 * Robust wrapper around fetch with JSON response parsing, CSRF headers, credentials, and HTTP error detection
 */
async function safeFetch(endpoint, options = {}) {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE}${endpoint}`;

  const mergedHeaders = Object.assign({
    'X-Requested-With': 'dmb-admin'
  }, options.headers || {});

  const fetchOpts = Object.assign({}, options, {
    credentials: 'same-origin',
    headers: mergedHeaders
  });

  try {
    const res = await fetch(url, fetchOpts);

    // Auto-detect expired token for authenticated requests
    if (res.status === 401 && !endpoint.includes('/login')) {
      handleSessionExpired();
      return { ok: false, status: 401, json: { message: 'Sesi telah berakhir. Silakan login kembali.' } };
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

// Alias apiCall to safeFetch for convenience
const apiCall = safeFetch;

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

  // 1. Sidebar Brand & Mobile Drawer Brand
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
  const mobileTopbarLogo = document.getElementById('mobileTopbarLogoImg');
  if (mobileTopbarLogo && logoUrl) {
    mobileTopbarLogo.src = logoUrl;
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
