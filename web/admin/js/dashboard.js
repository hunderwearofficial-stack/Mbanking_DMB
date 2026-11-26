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

  // Load recent applications, recent audit trail, and OTP posture
  loadDashboardRecentApplications();
  loadDashboardRecentAudit();
  loadDashboardOtpPosture();
}

async function loadDashboardRecentApplications() {
  const tbody = document.getElementById('dashRecentAppsBody');
  const pendingEl = document.getElementById('statPendingApps');
  const detailEl = document.getElementById('statPendingAppsDetail');
  try {
    const { ok, json } = await safeFetch('/admin/applications?limit=20', { headers: getAuthHeaders() });
    if (!ok || !json.data) {
      if (tbody) tbody.innerHTML = '<tr><td colspan="4" class="px-5 py-6 text-center text-slate-400">Belum ada data pengajuan.</td></tr>';
      return;
    }
    const apps = Array.isArray(json.data.applications) ? json.data.applications : (Array.isArray(json.data) ? json.data : []);
    const pendingCount = apps.filter(a => (a.status || 'PENDING').toUpperCase() === 'PENDING').length;
    if (pendingEl) pendingEl.innerText = pendingCount.toLocaleString('id-ID');
    if (detailEl) detailEl.innerText = pendingCount > 0 ? `${pendingCount} menunggu tindak lanjut (${apps.length} total)` : `${apps.length} total pengajuan tercatat`;

    if (!tbody) return;
    const recent = apps.slice(0, 5);
    if (recent.length === 0) {
      tbody.innerHTML = '<tr><td colspan="4" class="px-5 py-6 text-center text-slate-400">Belum ada pengajuan layanan dari nasabah.</td></tr>';
      return;
    }
    const escFn = typeof esc === 'function' ? esc : (s => String(s || ''));
    tbody.innerHTML = recent.map(a => {
      const name = escFn(a.customer_name || a.full_name || a.user_name || a.cif || 'Nasabah');
      const product = escFn((a.product_name || a.type || a.product_type || 'Layanan').replace(/_/g, ' '));
      const amount = a.amount ? new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 }).format(a.amount) : '-';
      const st = (a.status || 'PENDING').toUpperCase();
      let badgeCls = 'bg-amber-50 text-amber-700 border-amber-200';
      if (st === 'APPROVED' || st === 'COMPLETED') badgeCls = 'bg-emerald-50 text-emerald-700 border-emerald-200';
      else if (st === 'REJECTED') badgeCls = 'bg-rose-50 text-rose-700 border-rose-200';
      else if (st === 'CONTACTED') badgeCls = 'bg-blue-50 text-blue-700 border-blue-200';
      return `
        <tr class="hover:bg-slate-50/70">
          <td class="px-5 py-3 font-bold text-slate-800">${name}</td>
          <td class="px-4 py-3 text-slate-600">${product}</td>
          <td class="px-4 py-3 font-semibold text-slate-700">${amount}</td>
          <td class="px-5 py-3 text-right">
            <span class="px-2 py-0.5 rounded-full text-[10px] font-bold border ${badgeCls}">${escFn(st)}</span>
          </td>
        </tr>`;
    }).join('');
  } catch (e) {
    if (tbody) tbody.innerHTML = '<tr><td colspan="4" class="px-5 py-6 text-center text-slate-400">Tidak dapat memuat antrean pengajuan.</td></tr>';
  }
}

async function loadDashboardRecentAudit() {
  const container = document.getElementById('dashRecentAuditList');
  if (!container) return;
  try {
    const { ok, json } = await safeFetch('/admin/audit-logs?limit=5', { headers: getAuthHeaders() });
    const rows = ok && Array.isArray(json.data) ? json.data.slice(0, 5) : [];
    if (rows.length === 0) {
      container.innerHTML = '<div class="px-5 py-6 text-center text-xs text-slate-400">Belum ada aktivitas audit tercatat.</div>';
      return;
    }
    const escFn = typeof esc === 'function' ? esc : (s => String(s || ''));
    container.innerHTML = rows.map(l => {
      const dt = l.created_at ? new Date(l.created_at).toLocaleString('id-ID', { dateStyle: 'short', timeStyle: 'short' }) : '-';
      const actor = escFn(l.actor_name || l.actor_type || 'SYSTEM');
      const action = escFn(l.action || '-');
      const target = escFn(l.target || '');
      return `
        <div class="px-5 py-3 flex items-center justify-between gap-3 hover:bg-slate-50/70">
          <div class="min-w-0">
            <div class="text-xs font-bold text-slate-800 truncate">${action}${target ? ' &bull; ' + target : ''}</div>
            <div class="text-[11px] text-slate-500 truncate">Oleh <span class="font-semibold text-slate-700">${actor}</span></div>
          </div>
          <span class="text-[10px] font-semibold text-slate-400 shrink-0">${escFn(dt)}</span>
        </div>`;
    }).join('');
  } catch (_) {
    container.innerHTML = '<div class="px-5 py-6 text-center text-xs text-slate-400">Akses audit trail terbatas untuk peran ini.</div>';
  }
}

async function loadDashboardOtpPosture() {
  const badge = document.getElementById('dashOtpModeBadge');
  if (!badge) return;
  try {
    const { ok, json } = await safeFetch('/admin/config', { headers: getAuthHeaders() });
    if (ok && json.data) {
      const prov = (json.data.otp_provider || 'SANDBOX').toUpperCase();
      if (prov === 'SANDBOX_DUMMY') {
        badge.innerText = 'Sandbox Dummy (123456)';
        badge.className = 'font-bold text-amber-600';
      } else if (prov === 'SANDBOX') {
        badge.innerText = 'Sandbox Log';
        badge.className = 'font-bold text-blue-600';
      } else {
        badge.innerText = prov + ' (Aktif)';
        badge.className = 'font-bold text-emerald-700';
      }
    }
  } catch (_) {}
}
