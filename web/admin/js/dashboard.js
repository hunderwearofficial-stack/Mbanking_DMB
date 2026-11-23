/**
 * Dashboard & KPI Overview Module
 */

async function loadDashboardStats() {
  try {
    const { ok, json } = await safeFetch('/admin/stats', { headers: getAuthHeaders() });

    if (ok && json.data) {
      const s = json.data;
      document.getElementById('statTotalUsers').innerText = (s.total_users || 0).toLocaleString('id-ID');
      document.getElementById('statActiveUsers').innerText = (s.active_users || 0).toLocaleString('id-ID');
      document.getElementById('statBoundDevices').innerText = (s.bound_devices || 0).toLocaleString('id-ID');
      document.getElementById('statTotalAccounts').innerText = (s.total_accounts || 0).toLocaleString('id-ID');
    }
  } catch (e) {
    console.error('Failed to load dashboard stats', e);
  }

  if (typeof loadContentSummary === 'function') loadContentSummary();

  // Check CBS health on dashboard if current user is SUPER_ADMIN
  const user = typeof getCurrentUser === 'function' ? getCurrentUser() : {};
  if ((user.role || '').toUpperCase() === 'SUPER_ADMIN' && typeof checkCbsHealth === 'function') {
    checkCbsHealth();
  }
}
