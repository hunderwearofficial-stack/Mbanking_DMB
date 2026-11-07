/**
 * App Core & Navigation Controller
 */

let currentTab = 'dashboard';

document.addEventListener('DOMContentLoaded', () => {
  initAppBranding();
  lucide.createIcons();
  checkAuth();
  startLiveClock();
});

function startLiveClock() {
  const clockEl = document.getElementById('currentDateTime');
  if (!clockEl) return;
  const update = () => {
    const now = new Date();
    const options = { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' };
    clockEl.innerText = now.toLocaleDateString('id-ID', options) + ' WIB';
  };
  update();
  setInterval(update, 30000);
}

function switchTab(tabId) {
  currentTab = tabId;
  const tabs = ['dashboard', 'customers', 'banners', 'transactions', 'admin-users', 'settings'];

  tabs.forEach(t => {
    const el = document.getElementById(`tab-${t}`);
    const nav = document.getElementById(`nav-${t}`);
    if (!el || !nav) return;

    if (t === tabId) {
      el.classList.remove('hidden');
      nav.className = 'nav-item w-full flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-bold text-[#00897B] bg-teal-50/90 border border-teal-200/80 shadow-xs transition';
    } else {
      el.classList.add('hidden');
      nav.className = 'nav-item w-full flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-semibold text-slate-600 hover:text-slate-900 hover:bg-slate-100/70 transition';
    }
  });

  const titleMap = {
    'dashboard': 'Dashboard',
    'customers': 'Manajemen Nasabah & Device Binding',
    'banners': 'CMS Banner Promosi Mobile Banking',
    'transactions': 'Audit Transaksi M-Banking',
    'admin-users': 'Manajemen Petugas & Hak Akses (RBAC)',
    'settings': 'Pengaturan Logo & Identitas Bank'
  };
  document.getElementById('pageTitle').innerText = titleMap[tabId] || 'Portal Admin';

  refreshCurrentTab();
}

function refreshCurrentTab() {
  if (currentTab === 'dashboard') loadDashboardStats();
  if (currentTab === 'customers') loadCustomers();
  if (currentTab === 'banners') loadBanners();
  if (currentTab === 'transactions') loadTransactions();
  if (currentTab === 'admin-users') loadAdminUsers();
  if (currentTab === 'settings') loadConfig();
}

/**
 * Floating Toast Notification
 */
function showToast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toast = document.createElement('div');
  const colors = {
    success: 'bg-[#00897B] text-white shadow-lg shadow-teal-900/20 border border-teal-600/30',
    error: 'bg-rose-600 text-white shadow-lg shadow-rose-900/20',
    info: 'bg-slate-800 text-white shadow-lg shadow-slate-900/20'
  };

  toast.className = `p-3.5 px-4 rounded-xl shadow-lg text-xs font-semibold pointer-events-auto transform transition-all duration-300 translate-y-2 opacity-0 flex items-center gap-2 ${colors[type] || colors.info}`;
  toast.innerText = message;
  container.appendChild(toast);

  setTimeout(() => {
    toast.classList.remove('translate-y-2', 'opacity-0');
  }, 10);

  setTimeout(() => {
    toast.classList.add('opacity-0', 'translate-y-2');
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

