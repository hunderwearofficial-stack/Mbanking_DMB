/**
 * App Core, Navigation Controller, RBAC & Enterprise Modal System
 */

let currentTab = 'dashboard';

const ROLE_ALLOWED_TABS = {
  SUPER_ADMIN: ['dashboard', 'customers', 'content', 'terms', 'push', 'approvals', 'audit', 'admin-users', 'settings'],
  CS: ['dashboard', 'customers', 'terms'],
  MARKETING: ['dashboard', 'content', 'push', 'customers'],
  COMPLIANCE: ['dashboard', 'customers', 'content', 'terms', 'push', 'approvals', 'audit'],
  AUDITOR: ['dashboard', 'customers', 'content', 'terms', 'push', 'audit']
};

function getCurrentUser() {
  try {
    return JSON.parse(localStorage.getItem('dmb_admin_user') || '{}') || {};
  } catch (_) {
    return {};
  }
}

function getAllowedTabsForRole(role) {
  const r = (role || 'SUPER_ADMIN').toUpperCase();
  return ROLE_ALLOWED_TABS[r] || ROLE_ALLOWED_TABS.SUPER_ADMIN;
}

document.addEventListener('DOMContentLoaded', () => {
  initAppBranding();
  if (window.lucide && typeof lucide.createIcons === 'function') {
    lucide.createIcons();
  }
  startLiveClock();
  checkAuth();
});

function startLiveClock() {
  const clockEl = document.getElementById('currentDateTime');
  if (!clockEl) return;
  const update = () => {
    const now = new Date();
    const options = {
      weekday: 'long',
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    };
    clockEl.innerText = now.toLocaleDateString('id-ID', options) + ' WIB';
  };
  update();
  setInterval(update, 15000);
}

/**
 * Mobile / Tablet Responsive Sidebar Drawer (< 1024px)
 */
function openMobileSidebar() {
  const sidebar = document.getElementById('adminSidebar');
  const backdrop = document.getElementById('sidebarBackdrop');
  if (sidebar) {
    sidebar.classList.remove('-translate-x-full');
  }
  if (backdrop) {
    backdrop.classList.remove('hidden');
  }
}

function closeMobileSidebar() {
  const sidebar = document.getElementById('adminSidebar');
  const backdrop = document.getElementById('sidebarBackdrop');
  if (sidebar) {
    sidebar.classList.add('-translate-x-full');
  }
  if (backdrop) {
    backdrop.classList.add('hidden');
  }
}

function toggleMobileSidebar() {
  const sidebar = document.getElementById('adminSidebar');
  if (!sidebar) return;
  if (sidebar.classList.contains('-translate-x-full')) {
    openMobileSidebar();
  } else {
    closeMobileSidebar();
  }
}

/**
 * Apply Role-Based Access Control (RBAC) visibility to Sidebar & Quick Actions
 */
function applyRoleNavigation() {
  const user = getCurrentUser();
  const role = (user.role || 'SUPER_ADMIN').toUpperCase();
  const allowed = new Set(getAllowedTabsForRole(role));
  const allTabs = ['dashboard', 'customers', 'content', 'terms', 'push', 'approvals', 'audit', 'admin-users', 'settings'];

  allTabs.forEach(t => {
    const navBtn = document.getElementById(`nav-${t}`);
    if (navBtn) {
      navBtn.classList.toggle('hidden', !allowed.has(t));
    }
  });

  // Update customers nav label for MARKETING (only Product Applications)
  const navCustomersLabel = document.getElementById('navCustomersLabel');
  if (navCustomersLabel) {
    navCustomersLabel.textContent = role === 'MARKETING' ? 'Pengajuan Produk' : 'Nasabah & Perangkat';
  }

  // Hide empty sidebar section headers
  const grpLayanan = document.getElementById('nav-group-layanan');
  if (grpLayanan) {
    grpLayanan.classList.toggle('hidden', !allowed.has('customers'));
  }
  const grpKonten = document.getElementById('nav-group-konten');
  if (grpKonten) {
    grpKonten.classList.toggle('hidden', !(allowed.has('content') || allowed.has('terms') || allowed.has('push')));
  }
  const grpTataKelola = document.getElementById('nav-group-tatakelola');
  if (grpTataKelola) {
    grpTataKelola.classList.toggle('hidden', !(allowed.has('audit') || allowed.has('admin-users') || allowed.has('settings')));
  }

  // Dashboard quick actions visibility based on role
  const qaCustomers = document.getElementById('qaBtnCustomers');
  if (qaCustomers) qaCustomers.classList.toggle('hidden', !allowed.has('customers') || role === 'COMPLIANCE');
  const qaContent = document.getElementById('qaBtnContent');
  if (qaContent) qaContent.classList.toggle('hidden', !allowed.has('content'));
  const qaSettings = document.getElementById('qaBtnSettings');
  if (qaSettings) qaSettings.classList.toggle('hidden', !allowed.has('settings'));
  const qaAudit = document.getElementById('qaBtnAudit');
  if (qaAudit) qaAudit.classList.toggle('hidden', !allowed.has('audit'));

  // Dashboard CBS card only for SUPER_ADMIN
  const dashCbsCard = document.getElementById('dashboardCbsCard');
  if (dashCbsCard) {
    dashCbsCard.classList.toggle('hidden', role !== 'SUPER_ADMIN');
  }
}

function switchTab(tabId) {
  // Backward compatibility aliases
  if (tabId === 'cms-mobile' || tabId === 'cms' || tabId === 'banners') tabId = 'content';
  if (tabId === 'transactions') tabId = 'audit';

  const user = getCurrentUser();
  const role = (user.role || 'SUPER_ADMIN').toUpperCase();
  const allowed = getAllowedTabsForRole(role);

  if (!allowed.includes(tabId)) {
    tabId = allowed[0] || 'dashboard';
  }

  currentTab = tabId;
  const tabs = ['dashboard', 'customers', 'approvals', 'audit', 'content', 'terms', 'push', 'admin-users', 'settings'];

  let matched = false;
  tabs.forEach(t => {
    const el = document.getElementById(`tab-${t}`);
    const nav = document.getElementById(`nav-${t}`);
    if (!el) return;

    if (t === tabId) {
      matched = true;
      el.classList.remove('hidden');
      if (nav) {
        nav.classList.remove('text-slate-600', 'hover:text-slate-900', 'hover:bg-slate-100/70', 'font-semibold');
        nav.classList.add('text-[#00897B]', 'bg-teal-50/90', 'border', 'border-teal-200/80', 'shadow-xs', 'font-bold');
      }
    } else {
      el.classList.add('hidden');
      if (nav) {
        nav.classList.remove('text-[#00897B]', 'bg-teal-50/90', 'border', 'border-teal-200/80', 'shadow-xs', 'font-bold');
        nav.classList.add('text-slate-600', 'hover:text-slate-900', 'hover:bg-slate-100/70', 'font-semibold');
      }
    }
  });

  if (!matched) {
    const dashEl = document.getElementById('tab-dashboard');
    if (dashEl) dashEl.classList.remove('hidden');
    tabId = 'dashboard';
    currentTab = 'dashboard';
  }

  const titleMap = {
    'dashboard': 'Dashboard Eksekutif',
    'customers': role === 'MARKETING' ? 'Pengajuan Produk Nasabah' : 'Nasabah, Perangkat & Pengajuan Produk',
    'audit': 'Audit Trail & Integritas Keamanan OJK',
    'content': 'Konten Aplikasi & Pratinjau Layar',
    'terms': 'Syarat & Ketentuan Layanan (Maker-Checker)',
    'push': 'Notifikasi Push (FCM HTTP v1)',
    'admin-users': 'Manajemen Petugas & Hak Akses (RBAC)',
    'settings': 'Pengaturan Operasional & Core Banking'
  };
  const pageTitleEl = document.getElementById('pageTitle');
  if (pageTitleEl) pageTitleEl.innerText = titleMap[tabId] || 'Portal Admin';

  // Close mobile sidebar drawer on navigation
  closeMobileSidebar();

  if (window.lucide && typeof lucide.createIcons === 'function') {
    lucide.createIcons();
  }

  refreshCurrentTab();
}

function refreshCurrentTab() {
  try {
    if (currentTab === 'dashboard' && typeof loadDashboardStats === 'function') loadDashboardStats();
    if (currentTab === 'customers' && typeof loadCustomers === 'function') loadCustomers();
    if (currentTab === 'content' && typeof loadContent === 'function') loadContent();
    if (currentTab === 'terms' && typeof loadTermsVersions === 'function') loadTermsVersions();
    if (currentTab === 'push' && typeof loadPush === 'function') loadPush();
    if (currentTab === 'approvals' && typeof loadApprovals === 'function') loadApprovals();
    if (currentTab === 'audit' && typeof loadAuditLogs === 'function') loadAuditLogs();
    if (currentTab === 'admin-users' && typeof loadAdminUsers === 'function') loadAdminUsers();
    if (currentTab === 'settings' && typeof loadConfig === 'function') loadConfig();
  } catch (err) {
    console.error('Error in refreshCurrentTab:', err);
  }
}

/**
 * Floating Toast Notification
 */
function showToast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toastEl = document.createElement('div');
  const colors = {
    success: 'bg-[#00897B] text-white shadow-lg shadow-teal-900/20 border border-teal-600/30',
    error: 'bg-rose-600 text-white shadow-lg shadow-rose-900/20 border border-rose-500/30',
    warning: 'bg-amber-600 text-white shadow-lg shadow-amber-900/20 border border-amber-500/30',
    info: 'bg-slate-800 text-white shadow-lg shadow-slate-900/20 border border-slate-700'
  };

  toastEl.className = `p-3.5 px-4 rounded-xl shadow-lg text-xs font-semibold pointer-events-auto transform transition-all duration-300 translate-y-2 opacity-0 flex items-center gap-2 max-w-md ${colors[type] || colors.info}`;
  toastEl.innerText = message;
  container.appendChild(toastEl);

  setTimeout(() => {
    toastEl.classList.remove('translate-y-2', 'opacity-0');
  }, 10);

  setTimeout(() => {
    toastEl.classList.add('opacity-0', 'translate-y-2');
    setTimeout(() => toastEl.remove(), 300);
  }, 4000);
}

// Keep safe alias in case any legacy inline handler calls toast()
const toast = showToast;

/**
 * Reusable Accessible Enterprise Confirmation & Input Modal System
 * Replaces all native browser confirm() and prompt() calls.
 *
 * Options:
 * - title: string
 * - message: string (plain text)
 * - htmlMessage: optional trusted HTML string
 * - confirmText: string (default 'Konfirmasi')
 * - cancelText: string (default 'Batal')
 * - variant: 'primary' | 'danger' | 'warning' (default 'primary')
 * - requireInput: boolean | 'optional' (if true, input cannot be empty; if 'optional', input is shown but can be empty)
 * - showInput: boolean (shows input field)
 * - inputType: 'text' | 'textarea' | 'datetime-local' | 'password' | 'select' (default 'text')
 * - inputLabel: string
 * - inputPlaceholder: string
 * - inputDefaultValue: string
 * - inputHelp: string
 * - selectOptions: array of { value, label } (optional secondary or primary select)
 * - selectLabel: string
 * - selectDefaultValue: string
 *
 * Returns a Promise:
 * - If input/select is used: resolves to { confirmed: true, value: string, selectValue: string } or null/false when cancelled.
 *   For convenience:
 *   - When showInput or requireInput is set and selectOptions is NOT set, resolves to the input string (or null if cancelled).
 *   - When selectOptions IS set and showInput/requireInput is set, resolves to { value, selectValue } (or null if cancelled).
 *   - When neither input nor select is used, resolves to boolean (true if confirmed, false if cancelled).
 */
let activeConfirmResolver = null;

function showConfirmModal(opts = {}) {
  return new Promise((resolve) => {
    const modal = document.getElementById('enterpriseConfirmModal');
    if (!modal) {
      // Fallback only if DOM missing
      resolve(false);
      return;
    }

    if (activeConfirmResolver) {
      activeConfirmResolver(false);
      activeConfirmResolver = null;
    }

    const titleEl = document.getElementById('ecmTitle');
    const msgEl = document.getElementById('ecmMessage');
    const iconWrap = document.getElementById('ecmIconWrap');
    const iconEl = document.getElementById('ecmIcon');
    const inputWrap = document.getElementById('ecmInputWrap');
    const inputLabel = document.getElementById('ecmInputLabel');
    const inputField = document.getElementById('ecmInputField');
    const textareaField = document.getElementById('ecmTextareaField');
    const inputHelp = document.getElementById('ecmInputHelp');
    const inputError = document.getElementById('ecmInputError');
    const selectWrap = document.getElementById('ecmSelectWrap');
    const selectLabel = document.getElementById('ecmSelectLabel');
    const selectField = document.getElementById('ecmSelectField');
    const confirmBtn = document.getElementById('ecmConfirmBtn');
    const cancelBtn = document.getElementById('ecmCancelBtn');

    const variant = opts.variant || 'primary';
    const hasInput = Boolean(opts.requireInput || opts.showInput);
    const isRequired = opts.requireInput === true;
    const hasSelect = Array.isArray(opts.selectOptions) && opts.selectOptions.length > 0;
    const inputType = opts.inputType || 'text';

    titleEl.textContent = opts.title || 'Konfirmasi Tindakan';
    if (opts.htmlMessage) {
      msgEl.innerHTML = opts.htmlMessage;
    } else {
      msgEl.textContent = opts.message || '';
    }

    // Styling by variant
    if (variant === 'danger') {
      iconWrap.className = 'w-10 h-10 rounded-2xl bg-rose-50 text-rose-600 border border-rose-200 flex items-center justify-center shrink-0';
      iconEl.setAttribute('data-lucide', 'alert-triangle');
      confirmBtn.className = 'px-4 py-2.5 rounded-xl text-xs font-bold text-white bg-rose-600 hover:bg-rose-700 shadow-sm transition flex items-center gap-1.5';
    } else if (variant === 'warning') {
      iconWrap.className = 'w-10 h-10 rounded-2xl bg-amber-50 text-amber-600 border border-amber-200 flex items-center justify-center shrink-0';
      iconEl.setAttribute('data-lucide', 'shield-alert');
      confirmBtn.className = 'px-4 py-2.5 rounded-xl text-xs font-bold text-white bg-amber-600 hover:bg-amber-700 shadow-sm transition flex items-center gap-1.5';
    } else {
      iconWrap.className = 'w-10 h-10 rounded-2xl bg-teal-50 text-[#00897B] border border-teal-200 flex items-center justify-center shrink-0';
      iconEl.setAttribute('data-lucide', 'check-circle-2');
      confirmBtn.className = 'px-4 py-2.5 rounded-xl text-xs font-bold text-white bg-[#00897B] hover:bg-[#00796B] shadow-sm transition flex items-center gap-1.5';
    }

    confirmBtn.textContent = opts.confirmText || 'Konfirmasi';
    cancelBtn.textContent = opts.cancelText || 'Batal';
    cancelBtn.classList.toggle('hidden', opts.hideCancel === true);

    // Optional Select Dropdown
    if (hasSelect) {
      selectWrap.classList.remove('hidden');
      selectLabel.textContent = opts.selectLabel || 'Pilih Status';
      selectField.innerHTML = opts.selectOptions.map(o =>
        `<option value="${esc(o.value)}" ${o.value === opts.selectDefaultValue ? 'selected' : ''}>${esc(o.label)}</option>`
      ).join('');
    } else {
      selectWrap.classList.add('hidden');
    }

    // Optional Input / Textarea / Datetime-local
    inputError.classList.add('hidden');
    if (hasInput) {
      inputWrap.classList.remove('hidden');
      inputLabel.innerHTML = esc(opts.inputLabel || 'Catatan / Keterangan') + (isRequired ? ' <span class="text-rose-500">*</span>' : '');
      if (inputType === 'textarea') {
        inputField.classList.add('hidden');
        textareaField.classList.remove('hidden');
        textareaField.placeholder = opts.inputPlaceholder || '';
        textareaField.value = opts.inputDefaultValue !== undefined ? opts.inputDefaultValue : '';
      } else {
        textareaField.classList.add('hidden');
        inputField.classList.remove('hidden');
        inputField.type = inputType;
        inputField.placeholder = opts.inputPlaceholder || '';
        inputField.value = opts.inputDefaultValue !== undefined ? opts.inputDefaultValue : '';
      }
      if (opts.inputHelp) {
        inputHelp.textContent = opts.inputHelp;
        inputHelp.classList.remove('hidden');
      } else {
        inputHelp.classList.add('hidden');
      }
    } else {
      inputWrap.classList.add('hidden');
    }

    modal.classList.remove('hidden');
    if (window.lucide && typeof lucide.createIcons === 'function') {
      lucide.createIcons();
    }

    setTimeout(() => {
      if (hasInput) {
        if (inputType === 'textarea') textareaField.focus();
        else inputField.focus();
      } else {
        confirmBtn.focus();
      }
    }, 30);

    const cleanup = () => {
      modal.classList.add('hidden');
      confirmBtn.onclick = null;
      cancelBtn.onclick = null;
      document.removeEventListener('keydown', onKeyDown);
      activeConfirmResolver = null;
    };

    const onCancel = () => {
      cleanup();
      resolve(hasInput || hasSelect ? null : false);
    };

    const onConfirm = () => {
      let val = '';
      if (hasInput) {
        val = (inputType === 'textarea' ? textareaField.value : inputField.value);
        if (isRequired && !val.trim()) {
          inputError.textContent = 'Kolom ini wajib diisi sebelum melanjutkan.';
          inputError.classList.remove('hidden');
          return;
        }
      }
      const selVal = hasSelect ? selectField.value : '';
      cleanup();
      if (hasSelect && hasInput) {
        resolve({ value: val, selectValue: selVal });
      } else if (hasInput) {
        resolve(val);
      } else if (hasSelect) {
        resolve(selVal);
      } else {
        resolve(true);
      }
    };

    const onKeyDown = (e) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onCancel();
      } else if (e.key === 'Enter' && inputType !== 'textarea' && !modal.classList.contains('hidden')) {
        if (document.activeElement !== cancelBtn) {
          e.preventDefault();
          onConfirm();
        }
      }
    };

    activeConfirmResolver = (v) => {
      cleanup();
      resolve(v);
    };

    confirmBtn.onclick = onConfirm;
    cancelBtn.onclick = onCancel;
    document.addEventListener('keydown', onKeyDown);
  });
}
