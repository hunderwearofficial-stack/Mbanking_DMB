/**
 * Konten Aplikasi — elemen konten layar Flutter yang dikelola dari server
 * (internal/mobilecontent registry), dilengkapi:
 * - Catatan Perubahan (Revision Note) untuk setiap simpan draf
 * - Live Visual Mobile Mockup Preview untuk setiap layar (Splash, Onboarding, Login, Beranda, Pusat Bantuan, Kontak, Syarat & Ketentuan)
 * - Galeri Aset & Gambar Server (GET /api/v1/admin/assets & DELETE /api/v1/admin/assets/:filename)
 */
const contentState = {
  schema: null,      // { pages, fields }
  current: null,     // { live, live_version, published_at, published, open }
  values: {},        // values being edited
  note: '',          // revision note
  page: null,
  dirty: false,
  history: [],
  assets: [],
  assetCategoryFilter: 'ALL',
  assetSelectTargetKey: null
};

const CONTENT_STATUS = {
  DRAFT: ['Draf', 'bg-amber-50 text-amber-700 border-amber-200'],
  PENDING_APPROVAL: ['Menunggu Persetujuan', 'bg-blue-50 text-blue-700 border-blue-200'],
  PUBLISHED: ['Dipublikasikan', 'bg-emerald-50 text-emerald-700 border-emerald-200'],
  ARCHIVED: ['Arsip', 'bg-slate-100 text-slate-500 border-slate-200']
};

function currentAdmin() {
  try { return JSON.parse(localStorage.getItem('dmb_admin_user') || '{}'); } catch (_) { return {}; }
}
function canEditContent() { return ['SUPER_ADMIN', 'MARKETING'].includes(currentAdmin().role); }
function canApproveContent() { return ['SUPER_ADMIN', 'MARKETING', 'COMPLIANCE'].includes(currentAdmin().role); }
function contentDate(v) {
  if (!v) return '-';
  try { return new Date(v).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }); } catch (_) { return String(v); }
}
function statusPill(status) {
  const [label, cls] = CONTENT_STATUS[status] || [status, 'bg-slate-50 text-slate-600 border-slate-200'];
  return `<span class="inline-flex px-2 py-0.5 rounded-full border text-[10px] font-bold ${cls}">${esc(label)}</span>`;
}

function mapKeyToAssetCategory(key) {
  if (!key) return 'banner';
  const k = key.toLowerCase();
  if (k.includes('logo')) return 'logo';
  if (k.includes('banner')) return 'banner';
  if (k.includes('splash')) return 'splash_bg';
  if (k.includes('onboarding')) return 'onboarding_bg';
  if (k.includes('login')) return 'login_bg';
  return 'banner';
}

async function loadContent(skipDirtyConfirm = false) {
  const form = document.getElementById('contentForm');
  if (!form) return;
  if (!skipDirtyConfirm && contentState.dirty) {
    const ok = await showConfirmModal({
      title: 'Muat Ulang Konten',
      message: 'Terdapat perubahan draf yang belum disimpan. Muat ulang dan batalkan perubahan lokal?',
      confirmText: 'Ya, Muat Ulang',
      cancelText: 'Batal',
      variant: 'warning'
    });
    if (!ok) return;
  }
  try {
    if (!contentState.schema) {
      const s = await safeFetch('/admin/content/schema', { headers: getAuthHeaders() });
      if (!s.ok) throw new Error(s.json.message || 'Struktur konten tidak dapat dimuat');
      contentState.schema = s.json.data;
    }
    const c = await safeFetch('/admin/content', { headers: getAuthHeaders() });
    if (!c.ok) throw new Error(c.json.message || 'Konten tidak dapat dimuat');
    contentState.current = c.json.data;
    const open = c.json.data.open;
    contentState.values = Object.assign({}, c.json.data.live, open ? open.values : {});
    contentState.note = (open && open.note) ? open.note : '';
    const noteInput = document.getElementById('contentRevisionNote');
    if (noteInput) noteInput.value = contentState.note;
    contentState.dirty = false;
    if (!contentState.page) contentState.page = contentState.schema.pages[0].id;
    renderContentStatus();
    renderContentPages();
    renderContentPage();
    renderMobileMockupPreview();
  } catch (err) {
    const infoEl = document.getElementById('contentLiveInfo');
    if (infoEl) infoEl.textContent = err.message;
    form.innerHTML = '';
  }
}

function onRevisionNoteInput(val) {
  contentState.note = val;
  contentState.dirty = true;
  renderContentStatus();
}

function renderContentStatus() {
  if (!contentState.current) return;
  const cur = contentState.current;
  const pub = cur.published;
  document.getElementById('contentLiveInfo').innerHTML = cur.live_version > 0
    ? `<b>Versi ${esc(cur.live_version)}</b> &middot; dipublikasikan ${esc(contentDate(cur.published_at))} oleh ${esc(pub && pub.published_by_name || '-')}`
    : '<b>Versi 0</b> &middot; konten bawaan aplikasi (belum ada perubahan yang dipublikasikan)';
  const open = cur.open;
  const me = currentAdmin();
  let openTxt = 'Tidak ada. Ubah nilai pada formulir lalu klik <b>Simpan Draf</b>.';
  if (open) {
    openTxt = `${statusPill(open.status)} <b>Versi ${esc(open.version_number)}</b> &middot; dibuat ${esc(open.created_by_name)}`;
    if (open.status === 'PENDING_APPROVAL') openTxt += ` &middot; diajukan ${esc(open.submitted_by_name || '-')} (${esc(contentDate(open.submitted_at))})`;
    const changed = changedFromLive(open.values).length;
    openTxt += ` &middot; ${changed} elemen berbeda dari yang tampil`;
  }
  if (contentState.dirty) openTxt += ' <span class="ml-1 px-2 py-0.5 rounded-full bg-rose-50 text-rose-700 border border-rose-200 text-[10px] font-bold">Belum disimpan</span>';
  document.getElementById('contentOpenInfo').innerHTML = openTxt;

  const pending = open && open.status === 'PENDING_APPROVAL';
  const draft = open && open.status === 'DRAFT';
  const isMaker = open && (open.created_by === me.id || open.submitted_by === me.id);
  const set = (id, enabled, title) => {
    const b = document.getElementById(id);
    if (!b) return;
    b.disabled = !enabled;
    b.title = title || '';
  };
  set('contentSaveBtn', canEditContent() && !pending && contentState.dirty, pending ? 'Revisi sedang menunggu persetujuan' : '');
  set('contentSubmitBtn', canEditContent() && draft && !contentState.dirty, contentState.dirty ? 'Simpan draf terlebih dahulu' : '');
  set('contentApproveBtn', canApproveContent() && pending && !isMaker, isMaker ? 'Maker-checker: harus disetujui petugas lain' : '');
  set('contentRejectBtn', canApproveContent() && pending, '');
  set('contentDiscardBtn', canEditContent() && draft, '');

  const noteInput = document.getElementById('contentRevisionNote');
  if (noteInput) {
    noteInput.disabled = !canEditContent() || Boolean(pending);
  }
}

function changedFromLive(values) {
  if (!contentState.current || !contentState.schema) return [];
  const live = contentState.current.live;
  return contentState.schema.fields.filter(f => (values[f.key] || '') !== (live[f.key] || '')).map(f => f.key);
}

function renderContentPages() {
  const nav = document.getElementById('contentPageList');
  if (!nav || !contentState.schema) return;
  const changed = new Set(changedFromLive(contentState.values));
  nav.innerHTML = contentState.schema.pages.map(p => {
    const fields = contentState.schema.fields.filter(f => f.page === p.id);
    const n = fields.filter(f => changed.has(f.key)).length;
    const active = p.id === contentState.page;
    return `<button type="button" onclick="selectContentPage(${jsArg(p.id)})"
      class="w-full text-left px-3 py-2.5 rounded-xl text-xs transition flex items-center justify-between gap-2 ${active ? 'bg-teal-50 text-[#00897B] font-bold border border-teal-200' : 'text-slate-700 hover:bg-slate-50 font-semibold border border-transparent'}">
      <span>${esc(p.name)}<span class="block text-[10px] font-medium text-slate-400">${fields.length} elemen</span></span>
      ${n ? `<span class="px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-800 text-[10px] font-bold">${n} diubah</span>` : ''}
    </button>`;
  }).join('');
}

function selectContentPage(id) {
  contentState.page = id;
  renderContentPages();
  renderContentPage();
  renderMobileMockupPreview();
}

function renderContentPage() {
  if (!contentState.schema) return;
  const page = contentState.schema.pages.find(p => p.id === contentState.page);
  if (!page) return;
  const fields = contentState.schema.fields.filter(f => f.page === page.id);
  document.getElementById('contentPageHeader').innerHTML = `
    <div class="flex flex-col sm:flex-row sm:items-start justify-between gap-2">
      <div>
        <h4 class="text-sm font-black text-slate-900">${esc(page.name)}</h4>
        <p class="text-xs text-slate-500 mt-1">${esc(page.description)}</p>
      </div>
      <code class="text-[10px] text-slate-400 bg-slate-50 px-2 py-1 rounded border border-slate-200">${esc(page.screen)}</code>
    </div>
    ${page.static && page.static.length ? `<details class="mt-3 text-xs text-slate-600">
      <summary class="cursor-pointer font-bold text-slate-500">Elemen layar ini yang tetap di kode aplikasi (${page.static.length})</summary>
      <ul class="list-disc pl-5 mt-2 space-y-1">${page.static.map(s => `<li>${esc(s)}</li>`).join('')}</ul>
    </details>` : ''}`;

  const pending = contentState.current.open && contentState.current.open.status === 'PENDING_APPROVAL';
  const readOnly = pending || !canEditContent();
  const groups = [];
  fields.forEach(f => {
    let g = groups.find(x => x.name === f.group);
    if (!g) groups.push(g = { name: f.group, fields: [] });
    g.fields.push(f);
  });
  document.getElementById('contentForm').innerHTML = (readOnly ? `<div class="p-3 rounded-xl bg-blue-50 border border-blue-200 text-xs text-blue-800">${pending
      ? 'Revisi sedang menunggu persetujuan; formulir hanya dapat dibaca. Setujui atau kembalikan ke draf untuk mengubah.'
      : 'Peran Anda hanya dapat melihat konten.'}</div>` : '') +
    groups.map(g => `
    <fieldset class="bg-white rounded-2xl border border-slate-200/80 shadow-xs p-5 space-y-4">
      <legend class="px-2 text-[11px] font-extrabold text-slate-500 uppercase tracking-wider">${esc(g.name)}</legend>
      ${g.fields.map(f => renderContentField(f, readOnly)).join('')}
    </fieldset>`).join('');
  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function renderContentField(f, readOnly) {
  const v = contentState.values[f.key] || '';
  const live = contentState.current.live[f.key] || '';
  const id = 'cf_' + f.key.replace(/[^a-z0-9]/gi, '_');
  const dis = readOnly ? 'disabled' : '';
  const base = 'w-full px-3.5 py-2.5 text-xs rounded-xl border border-slate-200 focus:outline-none focus:border-[#00897B] disabled:bg-slate-50 disabled:text-slate-500';
  const onInput = `oninput="setContentValue(${jsArg(f.key)}, this.value)"`;
  let input;
  switch (f.type) {
    case 'multiline':
      input = `<textarea id="${id}" rows="3" maxlength="${f.max}" class="${base}" ${onInput} ${dis}>${esc(v)}</textarea>`;
      break;
    case 'bool':
      input = `<label class="inline-flex items-center gap-2 text-xs font-semibold text-slate-700">
        <input id="${id}" type="checkbox" class="w-4 h-4 accent-[#00897B]" ${v === 'true' ? 'checked' : ''}
          onchange="setContentValue(${jsArg(f.key)}, this.checked ? 'true' : 'false')" ${dis}> Tampilkan di aplikasi</label>`;
      break;
    case 'enum':
      input = `<select id="${id}" class="${base}" onchange="setContentValue(${jsArg(f.key)}, this.value)" ${dis}>
        ${(f.options || []).map(o => `<option value="${esc(o.value)}" ${o.value === v ? 'selected' : ''}>${esc(o.label)}</option>`).join('')}</select>`;
      break;
    case 'image': {
      const preview = v && (v.startsWith('/admin/') || v.startsWith('https://'))
        ? `<img src="${esc(v)}" alt="" class="h-16 w-28 object-cover rounded-lg border border-slate-200 bg-slate-50">`
        : `<div class="h-16 w-28 rounded-lg border border-dashed border-slate-300 bg-slate-50 flex items-center justify-center text-[10px] text-slate-400 text-center px-1">${v ? 'URL gambar' : 'Gambar bawaan aplikasi'}</div>`;
      input = `<div class="flex flex-col sm:flex-row gap-3 sm:items-center">
        ${preview}
        <div class="flex-1 space-y-2">
          <input id="${id}" type="text" maxlength="${f.max}" placeholder="Kosong = gambar bawaan aplikasi (PNG, JPG, atau WebP)" value="${esc(v)}" class="${base}" ${onInput} ${dis}>
          ${readOnly ? '' : `<div class="flex flex-wrap gap-2 items-center">
            <label class="px-3 py-1.5 rounded-lg text-[11px] font-bold text-white bg-[#00897B] hover:bg-[#00796B] cursor-pointer flex items-center gap-1">
              <i data-lucide="upload" class="w-3 h-3"></i><span>Unggah Gambar</span>
              <input type="file" accept="image/png,image/jpeg,image/webp" class="hidden" onchange="uploadContentImage(${jsArg(f.key)}, this)">
            </label>
            <button type="button" onclick="openAssetGalleryForSlot(${jsArg(f.key)})" class="px-3 py-1.5 rounded-lg text-[11px] font-bold text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 flex items-center gap-1">
              <i data-lucide="images" class="w-3 h-3 text-[#00897B]"></i><span>Pilih dari Galeri Server</span>
            </button>
            <button type="button" onclick="setContentValue(${jsArg(f.key)}, ''); renderContentPage();" class="px-3 py-1.5 rounded-lg text-[11px] font-bold text-slate-600 bg-slate-100 hover:bg-slate-200">Pakai Gambar Bawaan</button>
            <span id="${id}_status" class="text-[11px] text-slate-500"></span>
          </div>`}
        </div>
      </div>`;
      break;
    }
    default:
      input = `<input id="${id}" type="${f.type === 'email' ? 'email' : f.type === 'phone' ? 'tel' : 'text'}" maxlength="${f.max}" value="${esc(v)}" class="${base}" ${onInput} ${dis}>`;
  }
  const changed = v !== live;
  return `<div class="space-y-1.5">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <label for="${id}" class="text-xs font-bold text-slate-800">${esc(f.label)}${f.required ? ' <span class="text-rose-500">*</span>' : ''}</label>
      <span class="text-[10px] text-slate-400">Dipakai di: ${esc(f.used)}</span>
    </div>
    ${input}
    <div class="flex flex-wrap items-center justify-between gap-2 text-[10.5px]">
      <span class="text-slate-400">${esc(f.help || '')}${f.type === 'text' || f.type === 'multiline' ? ` (maks. ${f.max} karakter)` : ''}</span>
      ${changed ? `<span class="text-amber-700 font-semibold">Diubah &middot; tampil sekarang: ${esc(live || '(kosong)').slice(0, 80)}</span>` : ''}
    </div>
  </div>`;
}

function setContentValue(key, value) {
  contentState.values[key] = value;
  contentState.dirty = true;
  renderContentStatus();
  renderContentPages();
  renderMobileMockupPreview();
}

/**
 * Live Visual Mobile Mockup Preview
 * Renders an interactive smartphone screen preview reflecting the currently edited page & values
 */
function renderMobileMockupPreview() {
  const container = document.getElementById('mobileMockupScreen');
  const pageTitleBadge = document.getElementById('mobileMockupPageBadge');
  if (!container || !contentState.schema) return;

  const v = contentState.values || {};
  const pageId = contentState.page || 'umum';
  const logoUrl = v['app.logo'] || 'images/bank_logo.png';
  const announcement = (v['app.announcement'] || '').trim();

  const pageObj = contentState.schema.pages.find(p => p.id === pageId);
  if (pageTitleBadge && pageObj) {
    pageTitleBadge.textContent = pageObj.name;
  }

  const announceHtml = announcement
    ? `<div class="mx-3 mt-2 p-2 rounded-lg bg-amber-50 border border-amber-200 text-[9px] text-amber-800 font-semibold flex items-start gap-1.5">
        <span class="text-amber-600 font-black">!</span>
        <span class="leading-tight">${esc(announcement)}</span>
      </div>`
    : '';

  if (pageId === 'splash') {
    const bgColor = '#091324';
    const tagline = v['splash.tagline'] || 'Sahabat Finansial Terpercaya Anda';
    const disclaimer = v['app.footer'] || 'PT BPR Dana Mandiri Bogor berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS).';

    container.innerHTML = `
      <div class="h-full flex flex-col justify-between p-4 text-center relative overflow-hidden text-white"
           style="background: linear-gradient(155deg, ${esc(bgColor)} 0%, #0B3A7D 55%, #196BB8 100%);">
        <div class="relative z-10 flex-1 flex flex-col items-center justify-center px-3 -mt-4">
          <svg viewBox="0 0 180 180" class="w-24 h-24 drop-shadow-[0_4px_12px_rgba(0,0,0,0.3)]" fill="none" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <linearGradient id="dmbCyan" x1="0" y1="0" x2="180" y2="180" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stop-color="#57DDD3"/>
                <stop offset="55%" stop-color="#2EA2CE"/>
                <stop offset="100%" stop-color="#1A4B96"/>
              </linearGradient>
            </defs>
            <g transform="rotate(-10 88 96)">
              <path d="M96 24 A62 62 0 0 1 150 78" stroke="url(#dmbCyan)" stroke-width="8" stroke-linecap="round"/>
              <path d="M94 39 A47 47 0 0 1 135 80" stroke="url(#dmbCyan)" stroke-width="8" stroke-linecap="round"/>
              <path d="M92 54 A32 32 0 0 1 120 82" stroke="url(#dmbCyan)" stroke-width="8" stroke-linecap="round"/>
              <circle cx="84" cy="90" r="16" stroke="url(#dmbCyan)" stroke-width="11"/>
              <path d="M46 94 A38 38 0 0 0 122 94" stroke="#FFFFFF" stroke-width="14" stroke-linecap="butt"/>
              <path d="M46 156 A38 38 0 0 1 122 156" stroke="url(#dmbCyan)" stroke-width="14" stroke-linecap="butt"/>
            </g>
          </svg>
          <div class="mt-1 text-xl font-extrabold tracking-tight leading-none">
            <span class="text-[#57DDD3]">my</span><span class="text-white">DMB</span>
          </div>
          ${tagline ? `<div class="mt-2.5 text-[10.5px] font-semibold tracking-wide leading-snug text-white/95 drop-shadow-[0_1px_4px_rgba(0,0,0,0.5)]">${esc(tagline)}</div>` : ''}
          <div class="mt-3 px-2 py-0.5 rounded-full bg-white/10 border border-white/15 text-[7.5px] text-sky-100">
            Latar gedung &amp; logo animasi dibundel di APK
          </div>
        </div>
        <div class="relative z-10 text-[7.5px] font-medium text-white/90 leading-relaxed px-1 drop-shadow-[0_1px_4px_rgba(0,0,0,0.75)]">
          ${esc(disclaimer)}
        </div>
      </div>`;
    return;
  }

  if (pageId === 'onboarding') {
    const bg = v['onboarding.background'] || '/admin/uploads/onboarding_hero.jpg';
    const title = v['onboarding.title'] || 'Solusi Finansial Terpercaya untuk Keluarga & UMKM';
    const subtitle = v['onboarding.subtitle'] || 'Pantau saldo tabungan, mutasi rekening, deposito, dan pinjaman Anda secara aman dan real-time.';
    const btnTxt = v['onboarding.button_text'] || 'Masuk Sekarang';

    container.innerHTML = `
      <div class="h-full flex flex-col justify-between p-4 relative overflow-hidden text-white bg-[#04122E]">
        ${bg ? `<img src="${esc(bg)}" alt="" class="absolute inset-0 w-full h-full object-cover pointer-events-none" onerror="this.style.display='none'">` : ''}
        <div class="absolute inset-0 pointer-events-none"
             style="background: linear-gradient(180deg, rgba(4,18,46,0.48) 0%, rgba(4,18,46,0) 28%, rgba(4,18,46,0.22) 52%, rgba(4,18,46,0.88) 74%, #04122E 92%);"></div>
        <div class="relative z-10 pt-1 flex items-center justify-between">
          <img src="${esc(logoUrl)}" alt="Logo" class="h-7 object-contain drop-shadow" onerror="this.style.display='none'">
        </div>
        <div class="relative z-10 mt-auto space-y-2.5">
          <div class="text-[13px] font-extrabold leading-snug text-white">${esc(title)}</div>
          <div class="text-[8.5px] text-white/85 leading-relaxed">${esc(subtitle)}</div>
          <div class="pt-1">
            <div class="w-full py-2 rounded-full bg-[#0077FF] text-white text-center text-[10px] font-bold shadow-sm">
              ${esc(btnTxt)}
            </div>
          </div>
        </div>
      </div>`;
    return;
  }

  if (pageId === 'login') {
    const slide1Badge = v['login.hero_slide1_badge'] || 'TABUNGAN DANA MANDIRI';
    const slide1Title = v['login.hero_slide1_title'] || 'Menabung aman, usaha makin lancar';
    const title = v['login.title'] || 'Selamat datang';
    const subtitle = v['login.subtitle'] || 'Masuk ke akun DMB Anda';
    const footer = v['app.footer'] || 'PT BPR Dana Mandiri Bogor berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS).';

    container.innerHTML = `
      <div class="h-full flex flex-col justify-between bg-[#F4F7FB] text-slate-800 overflow-y-auto relative">
        <div class="px-4 pt-4 pb-2 space-y-2.5">
          <div class="flex items-center justify-between">
            <img src="${esc(logoUrl)}" alt="Logo" class="h-7 object-contain" onerror="this.style.display='none'">
            <span class="px-2 py-0.5 rounded-full bg-white border border-slate-200 text-[7.5px] font-bold text-[#0550A6] shadow-2xs">Terlindungi</span>
          </div>
          <div>
            <div class="text-[8px] font-extrabold tracking-wider text-[#0550A6] uppercase">${esc(slide1Badge)}</div>
            <div class="text-[13px] font-extrabold leading-snug mt-0.5 text-[#0A1628]">${esc(slide1Title)}</div>
            <div class="flex items-center gap-1 mt-1.5">
              <span class="w-4 h-1 rounded-full bg-[#0550A6]"></span>
              <span class="w-1 h-1 rounded-full bg-slate-300"></span>
              <span class="w-1 h-1 rounded-full bg-slate-300"></span>
            </div>
          </div>
        </div>
        ${announceHtml}
        <div class="px-3 pb-2 flex-1">
          <div class="bg-white rounded-2xl p-3.5 shadow-sm border border-slate-100 space-y-2.5">
            <div>
              <div class="text-[12px] font-extrabold text-slate-900">${esc(title)}</div>
              <div class="text-[9px] text-slate-500 whitespace-pre-line leading-tight mt-0.5">${esc(subtitle)}</div>
            </div>
            <div>
              <div class="text-[8.5px] font-bold text-slate-700 mb-1">No. HP atau Username</div>
              <div class="px-2.5 py-2 rounded-xl bg-slate-100 text-[9px] text-slate-400">Contoh: 0812 3456 7890</div>
            </div>
            <div>
              <div class="text-[8.5px] font-bold text-slate-700 mb-1">Password</div>
              <div class="px-2.5 py-1.5 rounded-xl bg-slate-100 flex items-center justify-between text-[9px] text-slate-700">
                <span>••••••••</span>
                <span class="text-slate-500 text-[10px]">👁</span>
              </div>
            </div>
            <div class="flex items-center gap-1.5 pt-0.5">
              <div class="flex-1 py-2 rounded-xl bg-[#033172] text-white text-center text-[9.5px] font-bold">Masuk</div>
              <div class="w-8 h-8 rounded-xl bg-sky-50 text-[#0550A6] flex items-center justify-center text-[11px] font-bold">☝</div>
            </div>
            <div class="flex items-center justify-between text-[8.5px] font-bold text-[#0550A6] pt-0.5">
              <span>Lupa password?</span>
              <span>Daftar</span>
            </div>
          </div>
        </div>
        <div class="px-4 pb-3 pt-1 text-center text-[8px] text-slate-500 leading-tight">${esc(footer)}</div>
      </div>`;
    return;
  }

  if (pageId === 'terms') {
    const headline = v['terms.headline'] || 'Ringkasan Informasi dan Syarat Ketentuan DMB Mobile';
    const instruction = v['terms.instruction'] || 'Baca dan setujui Syarat & Ketentuan layanan.';
    container.innerHTML = `
      <div class="h-full flex flex-col justify-between p-3.5 bg-slate-50 text-slate-800">
        <div class="space-y-2">
          <div class="flex items-center gap-2 pb-2 border-b border-slate-200">
            <img src="${esc(logoUrl)}" alt="Logo" class="h-5 object-contain" onerror="this.style.display='none'">
            <span class="text-[9px] font-extrabold text-slate-700">Syarat &amp; Ketentuan</span>
          </div>
          <div class="text-[10.5px] font-extrabold text-slate-900 leading-snug">${esc(headline)}</div>
          <div class="text-[8.5px] text-slate-500 leading-relaxed">${esc(instruction)}</div>
          <div class="p-2.5 rounded-xl bg-white border border-slate-200 text-[8.5px] text-slate-500 space-y-1">
            <div class="font-bold text-slate-700">Pratinjau Dokumen PDF Resmi</div>
            <p>Isi pasal dan pernyataan persetujuan dikelola pada tab <b>Syarat &amp; Ketentuan</b>.</p>
          </div>
        </div>
        <div class="py-2 rounded-xl bg-[#00897B] text-white text-center text-[9.5px] font-bold">Setuju &amp; Lanjutkan</div>
      </div>`;
    return;
  }

  if (pageId === 'helpdesk' || pageId === 'kontak') {
    const introTitle = v['helpdesk.intro_title'] || 'Butuh Bantuan?';
    const introText = v['helpdesk.intro_text'] || '';
    const callDisp = v['contact.call_center_display'] || '(0251) 832-1234';
    const waDisp = v['contact.whatsapp_display'] || '0811-9988-7766';
    const email = v['contact.email'] || 'layanan@bprdanamandiri.co.id';
    const addr = v['contact.office_address'] || 'Jl. Pajajaran No. 88, Kota Bogor';
    const hours = v['contact.office_hours'] || 'Senin - Jumat (08.00 - 15.30 WIB)';

    container.innerHTML = `
      <div class="h-full flex flex-col justify-between p-3.5 bg-slate-50 text-slate-800 overflow-y-auto">
        <div class="space-y-2">
          <div class="p-2.5 rounded-xl bg-gradient-to-r from-[#0A3B66] to-[#00897B] text-white">
            <div class="text-[11px] font-extrabold">${esc(introTitle)}</div>
            <div class="text-[8.5px] text-white/85 leading-snug mt-0.5">${esc(introText)}</div>
          </div>
          <div class="p-2 rounded-xl bg-white border border-slate-200 space-y-1">
            <div class="text-[8px] font-bold text-slate-400 uppercase">Call Center Resmi</div>
            <div class="text-[10px] font-extrabold text-slate-800">${esc(callDisp)}</div>
            <div class="text-[8px] text-slate-500">${esc(v['helpdesk.call_center_desc'] || '')}</div>
          </div>
          <div class="p-2 rounded-xl bg-white border border-slate-200 space-y-1">
            <div class="text-[8px] font-bold text-emerald-600 uppercase">WhatsApp CS</div>
            <div class="text-[10px] font-extrabold text-slate-800">${esc(waDisp)}</div>
            <div class="text-[8px] text-slate-500">${esc(v['helpdesk.whatsapp_desc'] || '')}</div>
          </div>
          <div class="p-2 rounded-xl bg-white border border-slate-200 space-y-1">
            <div class="text-[8px] font-bold text-blue-600 uppercase">Email &amp; Kantor Pusat</div>
            <div class="text-[9px] font-bold text-slate-800 break-all">${esc(email)}</div>
            <div class="text-[8px] text-slate-500">${esc(addr)}</div>
            <div class="text-[8px] text-[#00897B] font-semibold">${esc(hours)}</div>
          </div>
        </div>
      </div>`;
    return;
  }

  if (pageId === 'produk') {
    const heroImg = v['company.hero_image'] || '';
    const heroTitle = v['company.hero_title'] || 'Mitra Keuangan UMKM Bogor Sejak 1989';
    const aboutDesc = v['company.about_description'] || '';
    const estYear = v['company.established_year'] || '1989';
    const branches = (v['company.branches'] || '')
      .split('\n')
      .map(l => l.trim())
      .filter(Boolean)
      .map(l => {
        const idx = l.indexOf('|');
        return idx > 0 ? { name: l.slice(0, idx).trim(), addr: l.slice(idx + 1).trim() } : { name: l, addr: '' };
      });

    container.innerHTML = `
      <div class="h-full flex flex-col bg-[#F6F6F2] text-slate-800 overflow-y-auto">
        <div class="relative h-44 bg-gradient-to-br from-[#0A2A66] to-[#134A8E] text-white p-3 flex flex-col justify-between overflow-hidden shrink-0">
          ${heroImg ? `<img src="${esc(heroImg)}" alt="" class="absolute inset-0 w-full h-full object-cover">` : ''}
          <div class="absolute inset-0 bg-gradient-to-b from-black/25 via-black/20 to-black/75"></div>
          <div class="relative z-10 flex items-center gap-2">
            <span class="w-6 h-6 rounded-full bg-white text-[#0A2A66] flex items-center justify-center text-[10px] font-bold">‹</span>
            <span class="text-[11px] font-extrabold">Profil Bank DMB</span>
          </div>
          <div class="relative z-10 pb-3">
            <div class="text-[12px] font-black leading-tight">${esc(heroTitle)}</div>
            <div class="text-[8px] text-white/90 line-clamp-2 mt-1">${esc(aboutDesc)}</div>
          </div>
        </div>
        <div class="-mt-4 mx-2.5 px-2 py-2 rounded-xl bg-[#144296] text-white grid grid-cols-4 text-center shadow-md relative z-20">
          <div><div class="text-[6.5px] text-white/75">Tahun Berdiri</div><div class="text-[10px] font-black">${esc(estYear)}</div></div>
          <div><div class="text-[6.5px] text-white/75">Kantor</div><div class="text-[10px] font-black">${branches.length}</div></div>
          <div><div class="text-[6.5px] text-white/75">Diawasi</div><div class="text-[10px] font-black">OJK</div></div>
          <div><div class="text-[6.5px] text-white/75">Dijamin</div><div class="text-[10px] font-black">LPS</div></div>
        </div>
        <div class="p-3 space-y-2">
          ${branches.slice(0, 4).map((b, i) => `
            <div class="p-2 rounded-xl bg-white shadow-xs flex items-start gap-2">
              <div class="w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[9px] ${i % 2 === 0 ? 'bg-blue-50 text-[#0A2A66]' : 'bg-emerald-50 text-emerald-700'}">🏢</div>
              <div class="min-w-0">
                <div class="text-[9.5px] font-extrabold text-[#0A2A66] truncate">${esc(b.name)}</div>
                <div class="text-[7.5px] text-slate-500 line-clamp-2">${esc(b.addr)}</div>
              </div>
            </div>
          `).join('')}
        </div>
      </div>`;
    return;
  }

  // Default / 'home' / 'umum': Beranda preview matching current HomeScreen
  const greetTitle = v['home.greeting_title'] || 'Selamat datang,';
  const greetSub = v['home.greeting_subtitle'] || 'Semoga harimu lancar.';
  const greetNote = v['home.greeting_note'] || '';
  const banners = [1, 2, 3].map(n => ({
    n,
    visible: v[`home.banner${n}_visible`] !== 'false',
    tag: v[`home.banner${n}_tag`] || 'INFO',
    title: v[`home.banner${n}_title`] || `Banner ${n}`,
    subtitle: v[`home.banner${n}_subtitle`] || '',
    image: v[`home.banner${n}_image`] ?? (n === 1 ? '/admin/uploads/home_promo_plant.jpg' : ''),
    action: v[`home.banner${n}_action`] || 'none'
  })).filter(b => b.visible);
  const firstBanner = banners[0] || null;

  container.innerHTML = `
    <div class="h-full flex flex-col justify-between bg-[#F4F7FB] text-slate-800 overflow-y-auto relative">
      <div class="p-3 space-y-2.5 flex-1">
        <div class="flex items-center justify-between">
          <img src="${esc(logoUrl)}" alt="Logo" class="h-6 object-contain" onerror="this.style.display='none'">
          <span class="text-[8px] bg-white border border-slate-200 text-[#0550A6] px-2 py-0.5 rounded-full font-bold shadow-2xs">🛡 Terlindungi</span>
        </div>
        <div>
          <div class="text-[9px] text-slate-500">${esc(greetTitle)}</div>
          <div class="text-[13px] font-extrabold text-[#0A1628] leading-tight">Ibu Siti Aminah</div>
          <div class="text-[8.5px] text-slate-500">${esc(greetSub)}</div>
          ${greetNote ? `<div class="text-[8px] text-slate-400">${esc(greetNote)}</div>` : ''}
        </div>
        <div class="p-3 rounded-2xl bg-gradient-to-br from-[#033172] to-[#0550A6] text-white space-y-2 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-[7.5px] text-sky-200 uppercase font-bold">Dana Mandiri</div>
              <div class="text-[10px] font-bold tracking-wide">•••• •••• •••• 3653</div>
            </div>
            <span class="px-2 py-0.5 rounded-full bg-white/15 text-white text-[7.5px] font-bold">Salin</span>
          </div>
          <div class="flex items-end justify-between">
            <div>
              <div class="text-[7.5px] text-white/75">Saldo Tersedia</div>
              <div class="text-[12px] font-black">Rp ••••••••</div>
            </div>
            <span class="px-2 py-0.5 rounded-full bg-[#00E5FF] text-[#033172] text-[7.5px] font-bold">👁 Lihat</span>
          </div>
        </div>
        ${announceHtml}
        ${firstBanner ? `
          <div class="rounded-2xl overflow-hidden relative h-20 shadow-xs ${firstBanner.image ? 'bg-[#033172] text-white' : 'bg-gradient-to-r from-[#EAF3FE] to-[#DCEBFE] border border-[#D6E6FA] text-[#0A1628]'}">
            ${firstBanner.image ? `<img src="${esc(firstBanner.image)}" alt="" class="absolute inset-0 w-full h-full object-cover object-right">` : ''}
            ${firstBanner.image ? `<div class="absolute inset-0" style="background: linear-gradient(90deg, #033172 0%, rgba(3,49,114,0.86) 44%, rgba(3,49,114,0) 72%);"></div>` : ''}
            <div class="relative z-10 h-full p-2.5 pr-14 flex flex-col justify-between">
              <div class="text-[9.5px] font-extrabold leading-snug line-clamp-2">${esc(firstBanner.title)}</div>
              <div>
                <span class="inline-block px-2 py-0.5 rounded-full text-[7.5px] font-bold ${firstBanner.image ? 'bg-white text-[#033172]' : 'bg-[#033172] text-white'}">Pelajari</span>
              </div>
            </div>
          </div>
        ` : '<div class="text-[9px] text-slate-400 italic">Semua banner promo disembunyikan</div>'}
        <div class="grid grid-cols-3 gap-1.5 pt-1 text-center">
          <div class="p-1.5 rounded-xl bg-white border border-slate-100 text-[7.5px] font-bold text-[#0A1628]">Mutasi</div>
          <div class="p-1.5 rounded-xl bg-white border border-slate-100 text-[7.5px] font-bold text-[#0A1628]">Pinjaman</div>
          <div class="p-1.5 rounded-xl bg-white border border-slate-100 text-[7.5px] font-bold text-[#0A1628]">Deposito</div>
        </div>
        <div class="p-2.5 rounded-xl bg-white border border-slate-100 space-y-1">
          <div class="text-[8.5px] font-extrabold text-[#0A1628]">Aktivitas Terakhir</div>
          <div class="flex items-center justify-between text-[7.5px] text-slate-500">
            <span>Setoran Tabungan</span>
            <span class="font-bold text-emerald-600">+Rp 500.000</span>
          </div>
        </div>
      </div>
      <div class="mx-2 mb-2 px-2 py-1.5 rounded-full bg-[#033172] text-white flex items-center justify-around text-[7px] font-bold shadow-md">
        <span class="bg-white/15 px-2 py-0.5 rounded-full">Beranda</span>
        <span class="text-white/75">Katalog</span>
        <span class="text-white/75">DMB</span>
        <span class="text-white/75">Akun Saya</span>
      </div>
    </div>`;
}

async function uploadContentImage(key, input) {
  const file = input.files && input.files[0];
  if (!file) return;

  // Strict client-side validation: PNG, JPG, WebP only, max 5MB
  const validTypes = ['image/png', 'image/jpeg', 'image/webp'];
  if (!validTypes.includes(file.type)) {
    showToast('Format gambar harus PNG, JPG, atau WebP.', 'error');
    input.value = '';
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    showToast('Ukuran gambar maksimum adalah 5 MB.', 'error');
    input.value = '';
    return;
  }

  const status = document.getElementById('cf_' + key.replace(/[^a-z0-9]/gi, '_') + '_status');
  if (status) status.textContent = 'Mengunggah...';
  const fd = new FormData();
  fd.append('file', file);
  const category = mapKeyToAssetCategory(key);
  fd.append('category', category);
  try {
    const res = await fetch(`${API_BASE}/admin/upload?category=${encodeURIComponent(category)}`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: getAuthHeaders(false),
      body: fd
    });
    const json = await res.json();
    if (!res.ok || !json.success) throw new Error(json.message || 'Gagal mengunggah');
    setContentValue(key, json.data.url);
    renderContentPage();
    renderMobileMockupPreview();
    showToast('Gambar berhasil diunggah. Simpan draf lalu ajukan persetujuan.', 'success');
  } catch (err) {
    if (status) status.textContent = err.message;
    showToast(err.message, 'error');
  } finally {
    input.value = '';
  }
}

async function contentRequest(path, method, body, okMsg) {
  const { ok, json } = await safeFetch(path, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined });
  showToast(ok && json.success ? okMsg : (json.message || 'Tindakan gagal'), ok && json.success ? 'success' : 'error');
  if (ok && json.success) {
    contentState.dirty = false;
    await loadContent(true);
    if (!document.getElementById('contentHistoryView').classList.contains('hidden')) loadContentHistory();
  }
  return ok && json.success;
}

function saveContentDraft() {
  if (!contentState.dirty || !contentState.current) return;
  const noteInput = document.getElementById('contentRevisionNote');
  const note = noteInput ? noteInput.value.trim() : contentState.note;
  contentRequest('/admin/content/draft', 'PUT', {
    values: contentState.values,
    note: note
  }, 'Draf disimpan beserta catatan perubahan. Belum tampil di aplikasi sampai disetujui.');
}

function openRevision() {
  return contentState.current ? contentState.current.open : null;
}

function submitContent() {
  const o = openRevision();
  if (!o) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}/submit`, 'POST', null, 'Revisi diajukan. Persetujuan harus dilakukan oleh petugas lain (Maker-Checker).');
}

async function approveContent() {
  const o = openRevision();
  if (!o) return;
  const confirmed = await showConfirmModal({
    title: `Setujui & Publikasikan Versi ${o.version_number}`,
    message: `Setujui dan publikasikan konten aplikasi versi ${o.version_number}? Perubahan akan langsung tampil di aplikasi Mobile Banking nasabah.`,
    confirmText: 'Ya, Setujui & Publikasikan',
    cancelText: 'Batal',
    variant: 'primary'
  });
  if (!confirmed) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}/approve`, 'POST', null, `Versi ${o.version_number} berhasil dipublikasikan.`);
}

async function rejectContent() {
  const o = openRevision();
  if (!o) return;
  const reason = await showConfirmModal({
    title: 'Kembalikan Revisi ke Draf',
    message: 'Tuliskan alasan penolakan / catatan koreksi untuk pembuat draf:',
    confirmText: 'Kembalikan ke Draf',
    cancelText: 'Batal',
    variant: 'danger',
    requireInput: true,
    inputType: 'textarea',
    inputLabel: 'Alasan Dikembalikan ke Draf',
    inputPlaceholder: 'Contoh: Perbaiki nomor Call Center atau resolusi banner...'
  });
  if (!reason) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}/reject`, 'POST', { reason: reason.trim() }, 'Revisi dikembalikan ke draf.');
}

async function discardContent() {
  const o = openRevision();
  if (!o) return;
  const confirmed = await showConfirmModal({
    title: 'Buang Draf Revisi',
    message: `Buang seluruh perubahan pada draf versi ${o.version_number}? Versi yang saat ini tampil di aplikasi nasabah tidak akan berubah.`,
    confirmText: 'Ya, Buang Draf',
    cancelText: 'Batal',
    variant: 'danger'
  });
  if (!confirmed) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(o.id)}`, 'DELETE', null, 'Draf berhasil dibuang.');
}

function switchContentView(view) {
  document.getElementById('contentEditorView').classList.toggle('hidden', view !== 'editor');
  document.getElementById('contentHistoryView').classList.toggle('hidden', view !== 'history');
  const assetsView = document.getElementById('contentAssetsView');
  if (assetsView) assetsView.classList.toggle('hidden', view !== 'assets');

  if (view === 'history') loadContentHistory();
  if (view === 'assets') loadServerAssets();
}

async function loadContentHistory() {
  const body = document.getElementById('contentHistoryBody');
  body.innerHTML = '<tr><td colspan="7" class="py-6 text-center text-slate-400">Memuat...</td></tr>';
  const { ok, json } = await safeFetch('/admin/content/revisions?limit=100', { headers: getAuthHeaders() });
  if (!ok || !Array.isArray(json.data)) {
    body.innerHTML = `<tr><td colspan="7" class="py-6 text-center text-rose-600">${esc(json.message || 'Riwayat tidak dapat dimuat')}</td></tr>`;
    return;
  }
  contentState.history = json.data;
  if (!json.data.length) {
    body.innerHTML = '<tr><td colspan="7" class="py-6 text-center text-slate-400">Belum ada revisi. Versi 0 = konten bawaan aplikasi.</td></tr>';
    return;
  }
  body.innerHTML = json.data.map(r => `<tr class="hover:bg-slate-50 align-top">
    <td class="py-3 px-4 font-black">v${esc(r.version_number)}</td>
    <td class="py-3 px-4">${statusPill(r.status)}</td>
    <td class="py-3 px-4">${esc(r.created_by_name)}<div class="text-[10px] text-slate-400">${esc(contentDate(r.created_at))}</div></td>
    <td class="py-3 px-4">${esc(r.submitted_by_name || '-')}<div class="text-[10px] text-slate-400">${r.submitted_at ? esc(contentDate(r.submitted_at)) : ''}</div></td>
    <td class="py-3 px-4">${esc(r.published_by_name || '-')}<div class="text-[10px] text-slate-400">${r.published_at ? esc(contentDate(r.published_at)) : ''}</div></td>
    <td class="py-3 px-4 text-slate-600">${esc(r.note || '-')}</td>
    <td class="py-3 px-4 text-right whitespace-nowrap space-x-2">
      <button type="button" onclick="showContentDiff(${jsArg(r.id)})" class="text-[#00897B] font-bold hover:underline">Lihat perubahan</button>
      ${(r.status === 'PUBLISHED' || r.status === 'ARCHIVED') && canEditContent() ? `<button type="button" onclick="rollbackContent(${jsArg(r.id)}, ${jsArg(r.version_number)})" class="text-slate-600 font-bold hover:underline">Pulihkan ke draf</button>` : ''}
    </td></tr>`).join('');
}

function showContentDiff(id) {
  const list = contentState.history;
  const i = list.findIndex(r => r.id === id);
  if (i < 0) return;
  const r = list[i];
  const prev = list.slice(i + 1).find(x => x.status === 'PUBLISHED' || x.status === 'ARCHIVED');
  const fields = contentState.schema.fields;
  const base = prev ? prev.values : Object.fromEntries(fields.map(f => [f.key, f.default]));
  const rows = fields.filter(f => (r.values[f.key] ?? '') !== (base[f.key] ?? '')).map(f => `<tr class="align-top">
      <td class="py-2 px-3 font-semibold">${esc(f.label)}<div class="text-[10px] text-slate-400">${esc(f.key)}</div></td>
      <td class="py-2 px-3 text-rose-700 line-through decoration-rose-300">${esc(base[f.key] ?? '')}</td>
      <td class="py-2 px-3 text-emerald-700">${esc(r.values[f.key] ?? '')}</td></tr>`).join('');
  const panel = document.getElementById('contentDiffPanel');
  panel.classList.remove('hidden');
  panel.innerHTML = `<h5 class="text-xs font-bold text-slate-800 mb-2">Perubahan versi ${esc(r.version_number)} dibanding ${prev ? 'versi ' + esc(prev.version_number) : 'nilai bawaan di kode aplikasi'}</h5>
    ${rows ? `<table class="w-full text-xs"><thead class="text-slate-500"><tr><th class="text-left py-1 px-3">Elemen</th><th class="text-left py-1 px-3">Sebelumnya</th><th class="text-left py-1 px-3">Versi ini</th></tr></thead><tbody class="divide-y divide-slate-100">${rows}</tbody></table>`
      : '<p class="text-xs text-slate-500">Tidak ada perubahan nilai.</p>'}`;
}

async function rollbackContent(id, version) {
  const confirmed = await showConfirmModal({
    title: `Pulihkan Versi ${version} ke Draf`,
    message: `Salin seluruh isi versi ${version} ke draf baru? Draf tetap perlu diajukan dan disetujui petugas lain sebelum tampil di aplikasi.`,
    confirmText: 'Ya, Salin ke Draf',
    cancelText: 'Batal',
    variant: 'warning'
  });
  if (!confirmed) return;
  contentRequest(`/admin/content/revisions/${encodeURIComponent(id)}/rollback`, 'POST', null, `Isi versi ${version} disalin ke draf.`);
}

/**
 * Galeri Aset & Gambar Server (GET /api/v1/admin/assets & DELETE /api/v1/admin/assets/:filename)
 */
function openAssetGalleryForSlot(fieldKey) {
  contentState.assetSelectTargetKey = fieldKey || null;
  switchContentView('assets');
}

async function loadServerAssets() {
  const grid = document.getElementById('serverAssetsGrid');
  const targetBanner = document.getElementById('assetSelectTargetBanner');
  if (!grid) return;

  if (targetBanner) {
    if (contentState.assetSelectTargetKey && contentState.schema) {
      const f = contentState.schema.fields.find(x => x.key === contentState.assetSelectTargetKey);
      targetBanner.classList.remove('hidden');
      targetBanner.innerHTML = `
        <div class="flex items-center justify-between gap-2">
          <span>Memilih gambar untuk elemen: <b>${esc(f ? f.label : contentState.assetSelectTargetKey)}</b> (<code>${esc(contentState.assetSelectTargetKey)}</code>)</span>
          <button type="button" onclick="cancelAssetSlotSelection()" class="text-xs font-bold text-rose-700 hover:underline">Batal Pilih Slot</button>
        </div>`;
    } else {
      targetBanner.classList.add('hidden');
    }
  }

  grid.innerHTML = `<div class="col-span-full py-10 text-center text-xs text-slate-400">Memuat galeri aset dari server...</div>`;

  try {
    const { ok, json } = await safeFetch('/admin/assets', { headers: getAuthHeaders() });
    if (!ok || !Array.isArray(json.data)) {
      grid.innerHTML = `<div class="col-span-full py-10 text-center text-xs text-slate-400">${esc((json && json.message) || 'Belum ada aset gambar yang diunggah di server.')}</div>`;
      return;
    }
    contentState.assets = json.data;
    renderServerAssetsGrid();
  } catch (err) {
    grid.innerHTML = `<div class="col-span-full py-10 text-center text-xs text-rose-500">Gagal memuat galeri aset: ${esc(err.message)}</div>`;
  }
}

function cancelAssetSlotSelection() {
  contentState.assetSelectTargetKey = null;
  switchContentView('editor');
}

function filterServerAssets(cat) {
  contentState.assetCategoryFilter = cat;
  renderServerAssetsGrid();
}

function renderServerAssetsGrid() {
  const grid = document.getElementById('serverAssetsGrid');
  if (!grid) return;

  const filter = contentState.assetCategoryFilter || 'ALL';
  const items = filter === 'ALL'
    ? contentState.assets
    : contentState.assets.filter(a => (a.category || '').toLowerCase() === filter.toLowerCase());

  if (!items.length) {
    grid.innerHTML = `<div class="col-span-full py-10 text-center text-xs text-slate-400">Tidak ada gambar pada kategori ini.</div>`;
    return;
  }

  const imageFields = (contentState.schema && contentState.schema.fields)
    ? contentState.schema.fields.filter(f => f.type === 'image')
    : [];

  grid.innerHTML = items.map(a => {
    const sizeKB = ((a.size_bytes || 0) / 1024).toFixed(1);
    const updated = a.updated_at ? contentDate(a.updated_at) : '-';
    const inUse = Boolean(a.in_use);
    const usedByList = Array.isArray(a.used_by) ? a.used_by.join(', ') : (a.used_by || '');
    const badge = inUse
      ? `<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">Aktif Digunakan</span>`
      : `<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-600 border border-slate-200">Tidak Terpakai</span>`;

    return `
      <div class="rounded-2xl border border-slate-200/80 bg-white overflow-hidden shadow-xs flex flex-col justify-between">
        <div>
          <div class="h-36 bg-slate-100 relative flex items-center justify-center overflow-hidden border-b border-slate-100">
            <img src="${esc(a.url)}" alt="${esc(a.filename)}" class="max-h-full max-w-full object-contain">
            <span class="absolute top-2 left-2 px-2 py-0.5 rounded-md bg-slate-900/75 text-white text-[9px] font-mono uppercase">${esc(a.category || 'image')}</span>
            <div class="absolute top-2 right-2">${badge}</div>
          </div>
          <div class="p-3.5 space-y-1">
            <div class="font-mono text-[11px] font-bold text-slate-800 truncate" title="${esc(a.filename)}">${esc(a.filename)}</div>
            <div class="text-[10px] text-slate-400">${esc(sizeKB)} KB &middot; ${esc(updated)}</div>
            ${usedByList ? `<div class="text-[10px] text-emerald-700 font-medium truncate" title="${esc(usedByList)}">Dipakai: ${esc(usedByList)}</div>` : ''}
          </div>
        </div>
        <div class="p-3 pt-0 flex flex-wrap items-center gap-1.5">
          ${contentState.assetSelectTargetKey && canEditContent() ? `
            <button type="button" onclick="applyAssetToSlot(${jsArg(a.url)}, ${jsArg(contentState.assetSelectTargetKey)})"
              class="flex-1 py-1.5 px-2.5 rounded-lg text-[11px] font-bold text-white bg-[#00897B] hover:bg-[#00796B] transition">
              Pasang ke Slot Ini
            </button>
          ` : (canEditContent() && imageFields.length ? `
            <select onchange="if(this.value) { applyAssetToSlot(${jsArg(a.url)}, this.value); this.value=''; }"
              class="flex-1 py-1.5 px-2 rounded-lg text-[10.5px] font-semibold border border-slate-200 bg-slate-50 text-slate-700">
              <option value="">Pasang ke Elemen...</option>
              ${imageFields.map(f => `<option value="${esc(f.key)}">${esc(f.label)} (${esc(f.key)})</option>`).join('')}
            </select>
          ` : '')}
          ${canEditContent() ? `
            <button type="button"
              onclick="deleteServerAsset(${jsArg(a.filename)}, ${inUse})"
              ${inUse ? 'disabled title="Aset sedang digunakan dan tidak dapat dihapus"' : 'title="Hapus aset yang tidak terpakai"'}
              class="p-1.5 rounded-lg border border-rose-200 text-rose-600 hover:bg-rose-50 disabled:opacity-35 disabled:cursor-not-allowed transition">
              <i data-lucide="trash-2" class="w-3.5 h-3.5"></i>
            </button>
          ` : ''}
        </div>
      </div>`;
  }).join('');

  if (window.lucide && typeof lucide.createIcons === 'function') lucide.createIcons();
}

function applyAssetToSlot(url, fieldKey) {
  if (!fieldKey) return;
  setContentValue(fieldKey, url);
  contentState.assetSelectTargetKey = null;
  if (contentState.schema) {
    const f = contentState.schema.fields.find(x => x.key === fieldKey);
    if (f) contentState.page = f.page;
  }
  switchContentView('editor');
  renderContentPages();
  renderContentPage();
  renderMobileMockupPreview();
  showToast(`Gambar dipasang ke ${fieldKey}. Klik Simpan Draf untuk menyimpan.`, 'success');
}

async function uploadNewGalleryAsset(input) {
  const file = input.files && input.files[0];
  if (!file) return;

  const validTypes = ['image/png', 'image/jpeg', 'image/webp'];
  if (!validTypes.includes(file.type)) {
    showToast('Format gambar harus PNG, JPG, atau WebP.', 'error');
    input.value = '';
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    showToast('Ukuran gambar maksimum adalah 5 MB.', 'error');
    input.value = '';
    return;
  }

  const catSelect = document.getElementById('galleryUploadCategory');
  const category = catSelect ? catSelect.value : 'banner';
  const fd = new FormData();
  fd.append('file', file);
  fd.append('category', category);

  try {
    const res = await fetch(`${API_BASE}/admin/upload?category=${encodeURIComponent(category)}`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: getAuthHeaders(false),
      body: fd
    });
    const json = await res.json();
    if (!res.ok || !json.success) throw new Error(json.message || 'Gagal mengunggah gambar');
    showToast(`Gambar ${json.data.filename} berhasil diunggah ke galeri server!`, 'success');
    loadServerAssets();
  } catch (err) {
    showToast(err.message, 'error');
  } finally {
    input.value = '';
  }
}

async function deleteServerAsset(filename, inUse) {
  if (inUse) {
    showToast('Gambar sedang aktif digunakan oleh konten aplikasi dan tidak dapat dihapus.', 'warning');
    return;
  }
  const confirmed = await showConfirmModal({
    title: 'Hapus File Gambar dari Server',
    message: `Hapus berkas "${filename}" secara permanen dari server? Tindakan ini tidak dapat dibatalkan.`,
    confirmText: 'Ya, Hapus Gambar',
    cancelText: 'Batal',
    variant: 'danger'
  });
  if (!confirmed) return;

  try {
    const { ok, json } = await safeFetch(`/admin/assets/${encodeURIComponent(filename)}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });
    if (ok && json.success) {
      showToast(`Aset ${filename} berhasil dihapus.`, 'success');
      loadServerAssets();
    } else {
      showToast(json.message || 'Gagal menghapus aset', 'error');
    }
  } catch (err) {
    showToast('Error: ' + err.message, 'error');
  }
}

/** Dashboard card: content version shown in the app and pending approvals. */
async function loadContentSummary() {
  const v = document.getElementById('statContentVersion');
  const p = document.getElementById('statContentPending');
  if (!v) return;
  const { ok, json } = await safeFetch('/admin/content', { headers: getAuthHeaders() });
  if (!ok || !json.data) {
    v.textContent = '-';
    if (p) p.textContent = 'Tidak tersedia untuk peran Anda';
    return;
  }
  v.textContent = 'v' + json.data.live_version;
  const o = json.data.open;
  if (p) p.textContent = o ? (o.status === 'PENDING_APPROVAL' ? `v${o.version_number} menunggu persetujuan` : `Draf v${o.version_number} belum diajukan`) : 'Tidak ada perubahan berjalan';
}
