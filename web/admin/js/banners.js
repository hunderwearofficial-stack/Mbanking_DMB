/**
 * CMS Marketing Banners Management Module
 */

let cachedBanners = [];

async function loadBanners() {
  const tbody = document.getElementById('bannersTableBody');
  const previewGrid = document.getElementById('bannerPreviewGrid');
  if (!tbody || !previewGrid) return;

  tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-slate-400">Memuat banner...</td></tr>`;

  try {
    const { ok, json } = await safeFetch('/admin/banners', { headers: getAuthHeaders() });

    if (ok && json.data) {
      cachedBanners = json.data;

      // Render Visual Preview Cards matching Figma App
      if (cachedBanners.length > 0) {
        previewGrid.innerHTML = cachedBanners.map(b => `
          <div class="rounded-2xl p-5 text-white shadow-md relative overflow-hidden transition hover:scale-[1.01]" style="background: linear-gradient(135deg, ${b.bg_color || '#0A3B66'}, ${b.accent_color || '#16984B'})">
            <div class="flex items-center justify-between mb-2">
              <span class="text-[10px] font-extrabold uppercase tracking-wider px-2 py-0.5 rounded-full bg-white/20 backdrop-blur-sm">
                ${b.tag || 'PROMO'}
              </span>
              ${b.badge_text ? `
                <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-400 text-slate-900 shadow-sm">
                  ${b.badge_text}
                </span>
              ` : ''}
            </div>
            <h5 class="text-sm font-extrabold mb-1 drop-shadow-sm">${b.title}</h5>
            <p class="text-xs text-white/90 line-clamp-2">${b.highlight}</p>
            <div class="mt-4 pt-2 border-t border-white/10 flex items-center justify-between text-[10px] text-white/70">
              <span>Urutan: #${b.display_order}</span>
              <span class="font-bold ${b.is_active ? 'text-emerald-300' : 'text-rose-300'}">
                ${b.is_active ? '● Tayang' : '○ Nonaktif'}
              </span>
            </div>
          </div>
        `).join('');
      } else {
        previewGrid.innerHTML = `<div class="col-span-3 text-center py-6 text-slate-400 text-xs">Belum ada banner promosi</div>`;
      }

      // Render Table
      if (cachedBanners.length > 0) {
        tbody.innerHTML = cachedBanners.map(b => `
          <tr class="hover:bg-slate-50 transition">
            <td class="py-3 px-4 font-mono font-bold text-slate-600">#${b.display_order}</td>
            <td class="py-3 px-4">
              <div class="font-bold text-slate-900">${b.title}</div>
              <div class="text-[10px] text-slate-400 uppercase font-semibold">${b.tag}</div>
            </td>
            <td class="py-3 px-4 max-w-xs truncate text-slate-600">${b.highlight}</td>
            <td class="py-3 px-4">
              ${b.badge_text ? `<span class="px-2 py-0.5 rounded text-[10px] font-bold bg-amber-100 text-amber-800">${b.badge_text}</span>` : '-'}
            </td>
            <td class="py-3 px-4">
              <span class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold ${b.is_active ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-100 text-slate-600'}">
                ${b.is_active ? 'Aktif' : 'Nonaktif'}
              </span>
            </td>
            <td class="py-3 px-4">
              <div class="flex items-center justify-center gap-2">
                <button onclick="editBanner('${b.id}')"
                  class="p-1.5 rounded-lg text-slate-600 hover:text-emerald-700 hover:bg-emerald-50 border border-slate-200 transition" title="Edit">
                  <i data-lucide="edit-3" class="w-3.5 h-3.5"></i>
                </button>
                <button onclick="deleteBanner('${b.id}', '${b.title}')"
                  class="p-1.5 rounded-lg text-slate-600 hover:text-rose-700 hover:bg-rose-50 border border-slate-200 transition" title="Hapus">
                  <i data-lucide="trash-2" class="w-3.5 h-3.5"></i>
                </button>
              </div>
            </td>
          </tr>
        `).join('');
        lucide.createIcons();
      } else {
        tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-slate-400">Belum ada banner terdaftar</td></tr>`;
      }
    }
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="6" class="py-8 text-center text-rose-500">Error: ${e.message}</td></tr>`;
  }
}

function openBannerModal(banner = null) {
  document.getElementById('bannerForm').reset();
  document.getElementById('bannerId').value = banner ? banner.id : '';
  document.getElementById('bannerModalTitle').innerText = banner ? 'Edit Banner Promosi' : 'Tambah Banner Promosi';

  if (banner) {
    document.getElementById('bannerTag').value = banner.tag || '';
    document.getElementById('bannerTitle').value = banner.title || '';
    document.getElementById('bannerHighlight').value = banner.highlight || '';
    document.getElementById('bannerBadgeText').value = banner.badge_text || '';
    document.getElementById('bannerDisplayOrder').value = banner.display_order || 1;
    document.getElementById('bannerBgColor').value = banner.bg_color || '#0A3B66';
    document.getElementById('bannerBgColorPicker').value = banner.bg_color || '#0A3B66';
    document.getElementById('bannerAccentColor').value = banner.accent_color || '#16984B';
    document.getElementById('bannerAccentColorPicker').value = banner.accent_color || '#16984B';
    document.getElementById('bannerTargetUrl').value = banner.target_url || '';
    document.getElementById('bannerIsActive').checked = banner.is_active;
  } else {
    document.getElementById('bannerBgColor').value = '#0A3B66';
    document.getElementById('bannerBgColorPicker').value = '#0A3B66';
    document.getElementById('bannerAccentColor').value = '#16984B';
    document.getElementById('bannerAccentColorPicker').value = '#16984B';
    document.getElementById('bannerDisplayOrder').value = (cachedBanners.length + 1);
    document.getElementById('bannerIsActive').checked = true;
  }

  document.getElementById('bannerModal').classList.remove('hidden');
}

function closeBannerModal() {
  document.getElementById('bannerModal').classList.add('hidden');
}

function editBanner(id) {
  const b = cachedBanners.find(x => x.id === id);
  if (b) openBannerModal(b);
}

async function handleSaveBanner(e) {
  e.preventDefault();
  const id = document.getElementById('bannerId').value;
  const payload = {
    tag: document.getElementById('bannerTag').value.trim(),
    title: document.getElementById('bannerTitle').value.trim(),
    highlight: document.getElementById('bannerHighlight').value.trim(),
    badge_text: document.getElementById('bannerBadgeText').value.trim(),
    display_order: parseInt(document.getElementById('bannerDisplayOrder').value) || 1,
    bg_color: document.getElementById('bannerBgColor').value.trim(),
    accent_color: document.getElementById('bannerAccentColor').value.trim(),
    target_url: document.getElementById('bannerTargetUrl').value.trim(),
    is_active: document.getElementById('bannerIsActive').checked
  };

  try {
    const url = id ? `/admin/banners/${id}` : '/admin/banners';
    const method = id ? 'PUT' : 'POST';

    const { ok, json } = await safeFetch(url, {
      method: method,
      headers: getAuthHeaders(),
      body: JSON.stringify(payload)
    });

    if (ok && json.success) {
      showToast(id ? 'Banner berhasil diperbarui' : 'Banner berhasil ditambahkan', 'success');
      closeBannerModal();
      loadBanners();
      loadDashboardStats();
    } else {
      showToast(json.message || 'Gagal menyimpan banner', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

async function deleteBanner(id, title) {
  if (!confirm(`Hapus banner "${title}"?`)) return;

  try {
    const { ok, json } = await safeFetch(`/admin/banners/${id}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });

    if (ok && json.success) {
      showToast('Banner berhasil dihapus', 'success');
      loadBanners();
      loadDashboardStats();
    } else {
      showToast(json.message || 'Gagal menghapus banner', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

