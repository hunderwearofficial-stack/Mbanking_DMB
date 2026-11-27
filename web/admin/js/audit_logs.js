/**
 * Audit Trail & Log Keamanan Sistem (Kepatuhan POJK MRTI)
 * Mendukung filter Actor Type (ALL, NASABAH, ADMIN, SYSTEM), pencarian kata kunci,
 * rentang tanggal (Dari & Sampai Tanggal), keyset pagination (before_seq),
 * kolom No. Urut (#seq), IP & Perangkat, Detail Perubahan, Hash Integritas SHA-256, dan Export CSV.
 */

let cachedAuditLogs = [];
let auditHasMore = false;
let auditLastSeq = 0;
let auditCurrentPage = 1;
let auditPageSize = 15;

async function loadAuditLogs(append = false) {
  const tbody = document.getElementById('auditLogsTableBody');
  const loadMoreWrap = document.getElementById('auditLoadMoreWrap');
  const loadMoreBtn = document.getElementById('auditLoadMoreBtn');
  const countBadge = document.getElementById('auditCountBadge');
  if (!tbody) return;

  const actorFilterEl = document.getElementById('auditActorFilter');
  const searchEl = document.getElementById('auditSearchInput');
  const fromEl = document.getElementById('auditFromDate');
  const toEl = document.getElementById('auditToDate');

  const actorType = actorFilterEl ? actorFilterEl.value : 'ALL';
  const search = searchEl ? searchEl.value.trim() : '';
  const fromDate = fromEl ? fromEl.value : '';
  const toDate = toEl ? toEl.value : '';

  if (!append) {
    cachedAuditLogs = [];
    auditLastSeq = 0;
    auditCurrentPage = 1;
    const paginationBar = document.getElementById('auditPaginationBar');
    if (paginationBar) paginationBar.classList.add('hidden');
    tbody.innerHTML = `<tr><td colspan="8" class="py-8 text-center text-slate-400">Memuat data audit trail keamanan...</td></tr>`;
  } else if (loadMoreBtn) {
    loadMoreBtn.disabled = true;
    loadMoreBtn.textContent = 'Memuat lebih banyak...';
  }

  const params = new URLSearchParams();
  params.set('actor_type', actorType);
  params.set('limit', '100');
  if (search) params.set('search', search);
  if (fromDate) params.set('from', fromDate);
  if (toDate) params.set('to', toDate);
  if (append && auditLastSeq > 0) {
    params.set('before_seq', String(auditLastSeq));
  }

  try {
    const { ok, json } = await safeFetch(`/admin/audit-logs?${params.toString()}`, {
      headers: getAuthHeaders()
    });

    if (ok && Array.isArray(json.data)) {
      let rows = json.data;

      // Client-side fallback filtering in case backend ignores search/from/to
      if (search) {
        const q = search.toLowerCase();
        rows = rows.filter(l =>
          (l.action || '').toLowerCase().includes(q) ||
          (l.actor_name || '').toLowerCase().includes(q) ||
          (l.target || '').toLowerCase().includes(q) ||
          (l.details || '').toLowerCase().includes(q) ||
          (l.ip_address || '').toLowerCase().includes(q) ||
          (l.device_id || '').toLowerCase().includes(q)
        );
      }
      if (fromDate) {
        const fromTs = new Date(fromDate + 'T00:00:00').getTime();
        if (!isNaN(fromTs)) {
          rows = rows.filter(l => !l.created_at || new Date(l.created_at).getTime() >= fromTs);
        }
      }
      if (toDate) {
        const toTs = new Date(toDate + 'T23:59:59.999').getTime();
        if (!isNaN(toTs)) {
          rows = rows.filter(l => !l.created_at || new Date(l.created_at).getTime() <= toTs);
        }
      }

      if (append) {
        const existingSeqs = new Set(cachedAuditLogs.map(x => x.seq || x.id));
        rows.forEach(r => {
          if (!existingSeqs.has(r.seq || r.id)) {
            cachedAuditLogs.push(r);
          }
        });
      } else {
        cachedAuditLogs = rows;
      }

      // Compute lowest seq for keyset pagination
      if (json.data.length > 0) {
        const seqs = json.data.map(x => Number(x.seq) || 0).filter(n => n > 0);
        if (seqs.length > 0) {
          auditLastSeq = Math.min(...seqs);
        }
      }
      auditHasMore = json.data.length >= 100 && auditLastSeq > 1;

      if (countBadge) {
        countBadge.textContent = `${cachedAuditLogs.length} Entri Dimuat`;
      }

      renderAuditLogsTable();
    } else {
      if (!append) {
        cachedAuditLogs = [];
        tbody.innerHTML = `<tr><td colspan="8" class="py-8 text-center text-slate-400">Belum ada rekam jejak audit keamanan yang cocok dengan filter</td></tr>`;
      }
      auditHasMore = false;
    }
  } catch (e) {
    if (!append) {
      tbody.innerHTML = `<tr><td colspan="8" class="py-8 text-center text-rose-500">Error: ${esc(e.message)}</td></tr>`;
    } else {
      showToast('Gagal memuat halaman berikutnya: ' + e.message, 'error');
    }
    auditHasMore = false;
  } finally {
    if (loadMoreWrap) {
      loadMoreWrap.classList.toggle('hidden', !auditHasMore);
    }
    if (loadMoreBtn) {
      loadMoreBtn.disabled = false;
      loadMoreBtn.innerHTML = '<i data-lucide="chevrons-down" class="w-3.5 h-3.5"></i><span>Muat 100 Lagi</span>';
      if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
    }
  }
}

function resetAuditFilters() {
  const actorFilterEl = document.getElementById('auditActorFilter');
  const searchEl = document.getElementById('auditSearchInput');
  const fromEl = document.getElementById('auditFromDate');
  const toEl = document.getElementById('auditToDate');
  if (actorFilterEl) actorFilterEl.value = 'ALL';
  if (searchEl) searchEl.value = '';
  if (fromEl) fromEl.value = '';
  if (toEl) toEl.value = '';
  loadAuditLogs(false);
}

function goToAuditPage(page) {
  const totalPages = Math.max(1, Math.ceil((cachedAuditLogs ? cachedAuditLogs.length : 0) / auditPageSize));
  auditCurrentPage = Math.min(Math.max(1, Number(page) || 1), totalPages);
  renderAuditLogsTable();
}

function changeAuditPageSize(size) {
  auditPageSize = Math.max(1, Number(size) || 15);
  auditCurrentPage = 1;
  renderAuditLogsTable();
}

function renderAuditPagination(total, totalPages, startIdx, endIdx) {
  const bar = document.getElementById('auditPaginationBar');
  const infoEl = document.getElementById('auditPageInfo');
  const btnsEl = document.getElementById('auditPageButtons');
  if (!bar || !infoEl || !btnsEl) return;

  if (total === 0) {
    bar.classList.add('hidden');
    return;
  }

  bar.classList.remove('hidden');
  infoEl.textContent = `Menampilkan ${startIdx + 1}–${endIdx} dari ${total} entri`;

  const pages = [];
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pages.push(i);
  } else {
    pages.push(1);
    if (auditCurrentPage > 3) pages.push('...');
    const startP = Math.max(2, auditCurrentPage - 1);
    const endP = Math.min(totalPages - 1, auditCurrentPage + 1);
    for (let i = startP; i <= endP; i++) pages.push(i);
    if (auditCurrentPage < totalPages - 2) pages.push('...');
    pages.push(totalPages);
  }

  const prevDisabled = auditCurrentPage <= 1;
  const nextDisabled = auditCurrentPage >= totalPages;

  let html = `
    <button type="button" onclick="goToAuditPage(${auditCurrentPage - 1})" ${prevDisabled ? 'disabled' : ''}
      class="px-2.5 py-1.5 rounded-lg text-xs font-semibold border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 disabled:opacity-40 disabled:cursor-not-allowed transition">
      Sebelumnya
    </button>
  `;

  html += pages.map(p => {
    if (p === '...') {
      return '<span class="px-1.5 text-xs text-slate-400">…</span>';
    }
    const active = p === auditCurrentPage;
    return `
      <button type="button" onclick="goToAuditPage(${p})"
        class="min-w-[30px] px-2 py-1.5 rounded-lg text-xs font-bold border transition ${active ? 'bg-[#033172] text-white border-[#033172]' : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'}">
        ${p}
      </button>
    `;
  }).join('');

  html += `
    <button type="button" onclick="goToAuditPage(${auditCurrentPage + 1})" ${nextDisabled ? 'disabled' : ''}
      class="px-2.5 py-1.5 rounded-lg text-xs font-semibold border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 disabled:opacity-40 disabled:cursor-not-allowed transition">
      Berikutnya
    </button>
  `;

  btnsEl.innerHTML = html;
}

function renderAuditLogsTable() {
  const tbody = document.getElementById('auditLogsTableBody');
  const paginationBar = document.getElementById('auditPaginationBar');
  if (!tbody) return;

  if (!cachedAuditLogs || cachedAuditLogs.length === 0) {
    if (paginationBar) paginationBar.classList.add('hidden');
    tbody.innerHTML = `<tr><td colspan="8" class="py-8 text-center text-slate-400">Belum ada rekam jejak audit keamanan yang cocok dengan filter</td></tr>`;
    return;
  }

  const total = cachedAuditLogs.length;
  const totalPages = Math.max(1, Math.ceil(total / auditPageSize));
  if (auditCurrentPage > totalPages) auditCurrentPage = totalPages;
  const startIdx = (auditCurrentPage - 1) * auditPageSize;
  const endIdx = Math.min(startIdx + auditPageSize, total);
  const pageItems = cachedAuditLogs.slice(startIdx, endIdx);

  tbody.innerHTML = pageItems.map((log, idx) => {
    const rawStatus = (log.status || 'SUCCESS').toUpperCase();
    let statusClass = 'bg-emerald-100 text-emerald-800 border-emerald-200';
    let statusLabel = rawStatus;
    if (rawStatus === 'WARNING') {
      statusClass = 'bg-amber-100 text-amber-800 border-amber-200';
    } else if (rawStatus === 'DANGER' || rawStatus === 'FAILED' || rawStatus === 'ERROR') {
      statusClass = 'bg-rose-100 text-rose-800 border-rose-200';
      if (rawStatus === 'DANGER') statusLabel = 'FAILED / DANGER';
    }

    let actorBadge = '<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-blue-100 text-blue-800">NASABAH</span>';
    if (log.actor_type === 'ADMIN') {
      actorBadge = '<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-purple-100 text-purple-800">ADMIN</span>';
    } else if (log.actor_type === 'SYSTEM') {
      actorBadge = '<span class="px-2 py-0.5 rounded text-[10px] font-extrabold bg-slate-200 text-slate-800">SYSTEM</span>';
    }

    const seqDisplay = log.seq ? `#${esc(log.seq)}` : `#${startIdx + idx + 1}`;
    const fullHash = log.hash || '';
    const prevHash = log.prev_hash || '';
    const shortHash = fullHash ? fullHash.substring(0, 10) + '…' : 'legacy';
    const hashTooltip = fullHash
      ? `SHA-256: ${fullHash}${prevHash ? '\nPrev: ' + prevHash : ''}`
      : 'Entri sebelum rantai hash diaktifkan';

    return `
      <tr class="hover:bg-slate-50 transition align-top">
        <td class="py-3 px-3.5 font-mono font-bold text-slate-500 whitespace-nowrap">${seqDisplay}</td>
        <td class="py-3 px-3.5 text-slate-600 whitespace-nowrap font-mono text-[11px]">${esc(formatDateTime(log.created_at))}</td>
        <td class="py-3 px-3.5">
          <div class="flex items-center gap-1.5 flex-wrap">
            ${actorBadge}
            <span class="font-bold text-slate-800">${esc(log.actor_name || '-')}</span>
          </div>
          ${log.actor_id ? `<div class="text-[10px] font-mono text-slate-400 mt-0.5">ID: ${esc(log.actor_id)}</div>` : ''}
        </td>
        <td class="py-3 px-3.5">
          <div class="font-mono font-bold text-slate-900 whitespace-nowrap">${esc(log.action)}</div>
          <div class="font-mono text-slate-500 text-[11px] mt-0.5">Target: ${esc(log.target || '-')}</div>
        </td>
        <td class="py-3 px-3.5 font-mono text-[11px] text-slate-600">
          <div class="font-semibold text-slate-700">IP: ${esc(log.ip_address || '-')}</div>
          <div class="text-[10px] text-slate-500 truncate max-w-[160px]" title="${esc(log.device_id || '-')}">Dev: ${esc(log.device_id || '-')}</div>
        </td>
        <td class="py-3 px-3.5 text-slate-600 max-w-md break-words leading-relaxed text-[11.5px]">${esc(log.details || '-')}</td>
        <td class="py-3 px-3.5 whitespace-nowrap">
          <span title="${esc(hashTooltip)}"
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md font-mono text-[10px] font-semibold ${fullHash ? 'bg-[#EFF6FF] text-[#033172] border border-blue-200' : 'bg-slate-100 text-slate-400 border border-slate-200'} cursor-help">
            <i data-lucide="link-2" class="w-3 h-3"></i>
            <span>${esc(shortHash)}</span>
          </span>
        </td>
        <td class="py-3 px-3.5 whitespace-nowrap text-right">
          <span class="inline-flex px-2 py-0.5 rounded-full border text-[10px] font-bold ${statusClass}">
            ${esc(statusLabel)}
          </span>
        </td>
      </tr>
    `;
  }).join('');

  renderAuditPagination(total, totalPages, startIdx, endIdx);
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function exportAuditLogsCSV() {
  if (!cachedAuditLogs || cachedAuditLogs.length === 0) {
    showToast('Belum ada data audit log untuk di-export', 'info');
    return;
  }
  const headers = [
    'No. Urut (#seq)',
    'Waktu (UTC/ISO)',
    'Tipe Aktor',
    'ID Aktor',
    'Nama & Peran Aktor',
    'Aksi',
    'Target',
    'Alamat IP',
    'Device ID',
    'Status',
    'Detail Perubahan',
    'Hash Integritas (SHA-256)',
    'Prev Hash'
  ];
  const rows = cachedAuditLogs.map(l => [
    l.seq || '',
    l.created_at || '',
    l.actor_type || '',
    l.actor_id || '',
    l.actor_name || '',
    l.action || '',
    l.target || '',
    l.ip_address || '',
    l.device_id || '',
    l.status || '',
    l.details || '',
    l.hash || '',
    l.prev_hash || ''
  ].map(csvCell));

  const csvContent = 'data:text/csv;charset=utf-8,' + [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
  const encodedUri = encodeURI(csvContent);
  const link = document.createElement('a');
  link.setAttribute('href', encodedUri);
  link.setAttribute('download', `Audit_Trail_Mbanking_DMB_${new Date().toISOString().slice(0, 10)}.csv`);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  showToast('File CSV Audit Trail berhasil diunduh', 'success');
}

function formatDateTime(isoString) {
  if (!isoString) return '-';
  const d = new Date(isoString);
  return d.toLocaleDateString('id-ID', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
}
