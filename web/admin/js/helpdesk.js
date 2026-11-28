let cachedHelpdeskFaqs = [];

async function loadHelpdeskAdmin() {
  await Promise.all([loadHelpdeskFaqs(), loadHelpdeskInquiries()]);
}

async function loadHelpdeskFaqs() {
  const tbody = document.getElementById('helpdeskFaqTableBody');
  if (!tbody) return;
  try {
    const { ok, json } = await safeFetch('/admin/helpdesk/faqs', { headers: getAuthHeaders() });
    if (!ok || !json.success) {
      tbody.innerHTML = `<tr><td colspan="4" class="px-5 py-8 text-center text-rose-500">${esc(json.message || 'Gagal memuat FAQ')}</td></tr>`;
      return;
    }
    const faqs = json.data || [];
    cachedHelpdeskFaqs = faqs;
    const role = typeof getCustomerAdminRole === 'function' ? getCustomerAdminRole() : 'SUPER_ADMIN';
    const isReadOnly = role === 'COMPLIANCE' || role === 'AUDITOR';

    if (faqs.length === 0) {
      hideTablePagination('helpdeskFaqTableBody');
      tbody.innerHTML = '<tr><td colspan="4" class="px-5 py-8 text-center text-slate-400">Belum ada FAQ.</td></tr>';
      return;
    }
    paginateTableData('helpdeskFaqs', faqs, 'helpdeskFaqTableBody', (pageRows) => pageRows.map(f => {
      const badge = f.is_active
        ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">Aktif</span>'
        : '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-600">Nonaktif</span>';
      const actions = isReadOnly
        ? '<span class="text-[10px] text-slate-400 italic">Read-Only</span>'
        : `<div class="flex items-center justify-end gap-1.5">
            <button type="button" onclick="editHelpdeskFaq(${jsArg(f.id)})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-blue-50 hover:bg-blue-100 text-blue-700 border border-blue-200">Edit</button>
            <button type="button" onclick="deleteHelpdeskFaq(${jsArg(f.id)}, ${jsArg(f.topic)})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200">Hapus</button>
          </div>`;
      return `
        <tr class="hover:bg-slate-50/70 align-top">
          <td class="px-5 py-3.5">
            <div class="font-bold text-slate-900">${esc(f.topic)}</div>
            <div class="text-[11px] text-slate-500 mt-0.5">Kata kunci: <span class="font-mono">${esc(f.keywords)}</span></div>
          </td>
          <td class="px-5 py-3.5 text-slate-700 max-w-md whitespace-pre-line">${esc(f.answer)}</td>
          <td class="px-5 py-3.5">${badge}</td>
          <td class="px-5 py-3.5 text-right">${actions}</td>
        </tr>
      `;
    }).join(''), { resetPage: true });
  } catch (e) {
    hideTablePagination('helpdeskFaqTableBody');
    tbody.innerHTML = `<tr><td colspan="4" class="px-5 py-8 text-center text-rose-500">Error: ${esc(e.message)}</td></tr>`;
  }
}

async function loadHelpdeskInquiries() {
  const tbody = document.getElementById('helpdeskInquiriesTableBody');
  const badge = document.getElementById('helpdeskOpenBadge');
  const filter = document.getElementById('inquiryStatusFilter')?.value || 'OPEN';
  if (!tbody) return;
  try {
    const { ok, json } = await safeFetch(`/admin/helpdesk/inquiries?status=${encodeURIComponent(filter)}`, {
      headers: getAuthHeaders()
    });
    if (!ok || !json.success) {
      tbody.innerHTML = `<tr><td colspan="5" class="px-5 py-8 text-center text-rose-500">${esc(json.message || 'Gagal memuat pertanyaan')}</td></tr>`;
      return;
    }
    const items = json.data || [];
    const openCount = items.filter(i => i.status === 'OPEN').length;
    if (badge) {
      badge.textContent = `${openCount} belum dijawab`;
    }
    const role = typeof getCustomerAdminRole === 'function' ? getCustomerAdminRole() : 'SUPER_ADMIN';
    const isReadOnly = role === 'COMPLIANCE' || role === 'AUDITOR';

    if (items.length === 0) {
      hideTablePagination('helpdeskInquiriesTableBody');
      tbody.innerHTML = '<tr><td colspan="5" class="px-5 py-8 text-center text-slate-400">Belum ada pertanyaan nasabah pada filter ini.</td></tr>';
      return;
    }
    paginateTableData('helpdeskInquiries', items, 'helpdeskInquiriesTableBody', (pageRows) => pageRows.map(item => {
      const dt = item.created_at ? new Date(item.created_at).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short' }) : '-';
      const stBadge = item.status === 'RESOLVED'
        ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">RESOLVED</span>'
        : '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800">OPEN</span>';
      const actions = isReadOnly
        ? '<span class="text-[10px] text-slate-400 italic">Read-Only</span>'
        : `<div class="flex items-center justify-end gap-1.5 flex-wrap">
            <button type="button" onclick="promoteInquiryToFaq(${jsArg(item.id)}, ${jsArg(item.question)})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-[#EFF6FF] hover:bg-blue-100 text-[#033172] border border-blue-200">Jadikan FAQ</button>
            ${item.status !== 'RESOLVED' ? `<button type="button" onclick="resolveHelpdeskInquiry(${jsArg(item.id)})"
              class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-slate-100 hover:bg-slate-200 text-slate-700">Tandai Selesai</button>` : ''}
          </div>`;
      return `
        <tr class="hover:bg-slate-50/70 align-top">
          <td class="px-5 py-3.5 font-mono text-[11px] text-slate-500 whitespace-nowrap">${esc(dt)}</td>
          <td class="px-5 py-3.5">
            <div class="font-bold text-slate-900">${esc(item.full_name || 'Nasabah')}</div>
            <div class="text-[11px] font-mono text-slate-500">CIF: ${esc(item.cif || '-')} &bull; HP: ${esc(item.phone_number || '-')}</div>
          </td>
          <td class="px-5 py-3.5 text-slate-800 font-medium max-w-md">${esc(item.question)}</td>
          <td class="px-5 py-3.5">${stBadge}</td>
          <td class="px-5 py-3.5 text-right">${actions}</td>
        </tr>
      `;
    }).join(''), { resetPage: true });
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="5" class="px-5 py-8 text-center text-rose-500">Error: ${esc(e.message)}</td></tr>`;
  }
}

function openFaqEditor(prefillTopic = '', prefillKeywords = '') {
  document.getElementById('faqEditId').value = '';
  document.getElementById('faqEditorTitle').textContent = 'Tambah FAQ Chatbot';
  document.getElementById('faqTopicInput').value = prefillTopic;
  document.getElementById('faqKeywordsInput').value = prefillKeywords;
  document.getElementById('faqAnswerInput').value = '';
  document.getElementById('faqSortInput').value = '10';
  document.getElementById('faqActiveInput').checked = true;
  document.getElementById('faqEditorCard').classList.remove('hidden');
}

function closeFaqEditor() {
  document.getElementById('faqEditorCard').classList.add('hidden');
}

function editHelpdeskFaq(id) {
  const faq = cachedHelpdeskFaqs.find(f => f.id === id);
  if (!faq) return;
  document.getElementById('faqEditId').value = faq.id;
  document.getElementById('faqEditorTitle').textContent = 'Edit FAQ Chatbot';
  document.getElementById('faqTopicInput').value = faq.topic || '';
  document.getElementById('faqKeywordsInput').value = faq.keywords || '';
  document.getElementById('faqAnswerInput').value = faq.answer || '';
  document.getElementById('faqSortInput').value = String(faq.sort_order ?? 10);
  document.getElementById('faqActiveInput').checked = faq.is_active !== false;
  document.getElementById('faqEditorCard').classList.remove('hidden');
}

function promoteInquiryToFaq(inquiryId, question) {
  const words = (question || '').toLowerCase().replace(/[^a-z0-9\s]/g, '').split(/\s+/).filter(w => w.length >= 3).slice(0, 5);
  openFaqEditor(question.slice(0, 80), words.join(','));
  resolveHelpdeskInquiry(inquiryId, true);
}

async function saveHelpdeskFaq() {
  const id = document.getElementById('faqEditId').value.trim();
  const topic = document.getElementById('faqTopicInput').value.trim();
  const keywords = document.getElementById('faqKeywordsInput').value.trim();
  const answer = document.getElementById('faqAnswerInput').value.trim();
  const sortOrder = parseInt(document.getElementById('faqSortInput').value || '10', 10) || 0;
  const isActive = document.getElementById('faqActiveInput').checked;

  if (!topic || !keywords || !answer) {
    showToast('Topik, kata kunci, dan jawaban wajib diisi!', 'error');
    return;
  }

  const url = id ? `/admin/helpdesk/faqs/${encodeURIComponent(id)}` : '/admin/helpdesk/faqs';
  const method = id ? 'PUT' : 'POST';

  try {
    const { ok, json } = await safeFetch(url, {
      method,
      headers: getAuthHeaders(),
      body: JSON.stringify({ topic, keywords, answer, sort_order: sortOrder, is_active: isActive })
    });
    if (ok && json.success) {
      showToast(id ? 'FAQ diperbarui!' : 'FAQ baru ditambahkan!', 'success');
      closeFaqEditor();
      loadHelpdeskFaqs();
    } else {
      showToast(json.message || 'Gagal menyimpan FAQ', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

async function deleteHelpdeskFaq(id, topic) {
  const confirmed = await showConfirmModal({
    title: 'Hapus FAQ Chatbot',
    message: `Yakin ingin menghapus topik "${topic}" dari chatbot?`,
    confirmText: 'Ya, Hapus',
    cancelText: 'Batal',
    variant: 'danger'
  });
  if (!confirmed) return;
  try {
    const { ok, json } = await safeFetch(`/admin/helpdesk/faqs/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });
    if (ok && json.success) {
      showToast('FAQ dihapus', 'success');
      loadHelpdeskFaqs();
    } else {
      showToast(json.message || 'Gagal menghapus FAQ', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  }
}

async function resolveHelpdeskInquiry(id, silent = false) {
  try {
    const { ok, json } = await safeFetch(`/admin/helpdesk/inquiries/${encodeURIComponent(id)}`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({ status: 'RESOLVED' })
    });
    if (ok && json.success) {
      if (!silent) showToast('Pertanyaan ditandai selesai', 'success');
      loadHelpdeskInquiries();
    }
  } catch (_) {}
}

// ==================== EXCEL / CSV FAQ IMPORT ====================
let pendingFaqImportItems = [];

function downloadFaqExcelTemplate() {
  const rows = [
    ['Topik', 'Kata Kunci', 'Jawaban', 'Aktif', 'Urutan'],
    ['Cara Tarik Tunai', 'tarik,tunai,atm,cash', 'Penarikan tunai dapat dilakukan langsung melalui kantor kas Bank DMB terdekat.', 'YA', '10'],
    ['Jam Operasional', 'jam,buka,tutup,operasional', 'Layanan kantor Bank DMB buka Senin - Jumat pukul 08.00 - 15.30 WIB.', 'YA', '11']
  ];
  const csv = '\uFEFF' + rows.map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\r\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'Template_FAQ_Bank_DMB.csv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function cancelFaqExcelImport() {
  pendingFaqImportItems = [];
  const card = document.getElementById('faqImportPreviewCard');
  const inp = document.getElementById('faqExcelInput');
  if (card) card.classList.add('hidden');
  if (inp) inp.value = '';
}

async function handleFaqExcelSelect(input) {
  const file = input && input.files && input.files[0];
  if (!file) return;
  try {
    const name = file.name.toLowerCase();
    let tableRows = [];
    if (name.endsWith('.xlsx')) {
      const buf = await file.arrayBuffer();
      tableRows = await parseXlsxFirstSheet(buf);
    } else if (name.endsWith('.csv') || name.endsWith('.txt')) {
      const text = await file.text();
      tableRows = parseCsvRows(text);
    } else {
      showToast('Format file harus .xlsx atau .csv', 'error');
      return;
    }
    const parsed = normalizeFaqRows(tableRows);
    if (parsed.length === 0) {
      showToast('Tidak ditemukan baris FAQ valid (wajib ada kolom Topik & Jawaban)', 'error');
      return;
    }
    pendingFaqImportItems = parsed;
    renderFaqImportPreview();
  } catch (e) {
    showToast('Gagal membaca file Excel: ' + e.message, 'error');
  } finally {
    input.value = '';
  }
}

function normalizeFaqRows(rows) {
  if (!rows || rows.length === 0) return [];
  let startIdx = 0;
  let colMap = { topic: 0, keywords: 1, answer: 2, active: 3, sort: 4 };
  const first = rows[0].map(c => String(c || '').trim().toLowerCase());
  if (first.some(h => h.includes('topik') || h.includes('topic') || h.includes('jawaban') || h.includes('answer'))) {
    startIdx = 1;
    const findCol = (preds, def) => {
      const i = first.findIndex(h => preds.some(p => h.includes(p)));
      return i >= 0 ? i : def;
    };
    colMap = {
      topic: findCol(['topik', 'topic', 'judul'], 0),
      keywords: findCol(['kata kunci', 'keyword'], 1),
      answer: findCol(['jawaban', 'answer', 'isi'], 2),
      active: findCol(['aktif', 'active', 'status'], 3),
      sort: findCol(['urutan', 'sort', 'order'], 4),
    };
  }
  const out = [];
  for (let i = startIdx; i < rows.length; i++) {
    const r = rows[i] || [];
    const topic = String(r[colMap.topic] ?? '').trim();
    const answer = String(r[colMap.answer] ?? '').trim();
    if (!topic || !answer) continue;
    const keywords = String(r[colMap.keywords] ?? '').trim() || topic.toLowerCase();
    const activeRaw = String(r[colMap.active] ?? 'YA').trim().toLowerCase();
    const isActive = !['tidak', 'no', 'false', '0', 'nonaktif'].includes(activeRaw);
    const sortOrder = parseInt(String(r[colMap.sort] ?? ''), 10) || (out.length + 1);
    out.push({ topic, keywords, answer, is_active: isActive, sort_order: sortOrder });
  }
  return out;
}

function renderFaqImportPreview() {
  const card = document.getElementById('faqImportPreviewCard');
  const countEl = document.getElementById('faqImportCount');
  const tbody = document.getElementById('faqImportPreviewBody');
  if (!card || !tbody) return;
  if (countEl) countEl.textContent = String(pendingFaqImportItems.length);
  tbody.innerHTML = pendingFaqImportItems.map((item, idx) => `
    <tr class="hover:bg-slate-50 align-top">
      <td class="px-3 py-2 text-slate-400 font-mono">${idx + 1}</td>
      <td class="px-3 py-2 font-bold text-slate-800">${esc(item.topic)}</td>
      <td class="px-3 py-2 font-mono text-[11px] text-slate-600">${esc(item.keywords)}</td>
      <td class="px-3 py-2 text-slate-700 max-w-md whitespace-pre-line">${esc(item.answer)}</td>
      <td class="px-3 py-2">${item.is_active ? '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">Aktif</span>' : '<span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-600">Nonaktif</span>'}</td>
      <td class="px-3 py-2 font-mono">${item.sort_order}</td>
    </tr>
  `).join('');
  card.classList.remove('hidden');
}

async function submitFaqExcelImport() {
  if (!pendingFaqImportItems.length) return;
  const btn = document.getElementById('faqImportSubmitBtn');
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Mengimpor...';
  }
  try {
    const { ok, json } = await safeFetch('/admin/helpdesk/faqs/import', {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ items: pendingFaqImportItems })
    });
    if (ok && json.success) {
      showToast(`${json.data?.imported || pendingFaqImportItems.length} FAQ berhasil diimpor`, 'success');
      cancelFaqExcelImport();
      loadHelpdeskFaqs();
    } else {
      showToast(json.message || 'Gagal mengimpor FAQ', 'error');
    }
  } catch (e) {
    showToast('Error: ' + e.message, 'error');
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = 'Impor ke Chatbot';
    }
  }
}

function parseCsvRows(text) {
  const clean = text.replace(/^\uFEFF/, '');
  const firstLine = clean.split(/\r?\n/)[0] || '';
  const delim = (firstLine.split(';').length > firstLine.split(',').length) ? ';' : ',';
  const rows = [];
  let row = [];
  let cell = '';
  let inQuotes = false;
  for (let i = 0; i < clean.length; i++) {
    const ch = clean[i];
    if (inQuotes) {
      if (ch === '"' && clean[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') { inQuotes = false; }
      else { cell += ch; }
    } else {
      if (ch === '"') { inQuotes = true; }
      else if (ch === delim) { row.push(cell); cell = ''; }
      else if (ch === '\r') { /* skip */ }
      else if (ch === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
      else { cell += ch; }
    }
  }
  if (cell.length > 0 || row.length > 0) { row.push(cell); rows.push(row); }
  return rows;
}

async function parseXlsxFirstSheet(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  const view = new DataView(arrayBuffer);
  // Locate End of Central Directory (0x06054b50)
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65558); i--) {
    if (view.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('File bukan arsip XLSX yang valid');
  const cdOffset = view.getUint32(eocd + 16, true);
  const totalEntries = view.getUint16(eocd + 10, true);
  const decoder = new TextDecoder('utf-8');
  const files = {};
  let pos = cdOffset;
  for (let e = 0; e < totalEntries; e++) {
    if (view.getUint32(pos, true) !== 0x02014b50) break;
    const compMethod = view.getUint16(pos + 10, true);
    const compSize = view.getUint32(pos + 20, true);
    const nameLen = view.getUint16(pos + 28, true);
    const extraLen = view.getUint16(pos + 30, true);
    const commentLen = view.getUint16(pos + 32, true);
    const localHeaderOffset = view.getUint32(pos + 42, true);
    const fileName = decoder.decode(bytes.subarray(pos + 46, pos + 46 + nameLen));
    pos += 46 + nameLen + extraLen + commentLen;
    if (fileName === 'xl/sharedStrings.xml' || fileName === 'xl/worksheets/sheet1.xml') {
      const lhNameLen = view.getUint16(localHeaderOffset + 26, true);
      const lhExtraLen = view.getUint16(localHeaderOffset + 28, true);
      const dataStart = localHeaderOffset + 30 + lhNameLen + lhExtraLen;
      const slice = bytes.subarray(dataStart, dataStart + compSize);
      if (compMethod === 0) {
        files[fileName] = decoder.decode(slice);
      } else if (compMethod === 8) {
        const ds = new DecompressionStream('deflate-raw');
        const writer = ds.writable.getWriter();
        writer.write(slice);
        writer.close();
        const outBuf = await new Response(ds.readable).arrayBuffer();
        files[fileName] = decoder.decode(outBuf);
      }
    }
  }
  if (!files['xl/worksheets/sheet1.xml']) throw new Error('Sheet1 tidak ditemukan di file XLSX');
  const dom = new DOMParser();
  const sharedStrings = [];
  if (files['xl/sharedStrings.xml']) {
    const ssDoc = dom.parseFromString(files['xl/sharedStrings.xml'], 'application/xml');
    ssDoc.querySelectorAll('si').forEach(si => {
      const parts = Array.from(si.querySelectorAll('t')).map(t => t.textContent || '');
      sharedStrings.push(parts.join(''));
    });
  }
  const sheetDoc = dom.parseFromString(files['xl/worksheets/sheet1.xml'], 'application/xml');
  const colIndex = (ref) => {
    const letters = (ref || '').replace(/[0-9]/g, '');
    let idx = 0;
    for (let i = 0; i < letters.length; i++) idx = idx * 26 + (letters.charCodeAt(i) - 64);
    return Math.max(0, idx - 1);
  };
  const result = [];
  sheetDoc.querySelectorAll('sheetData > row').forEach(rowEl => {
    const rowArr = [];
    rowEl.querySelectorAll('c').forEach(c => {
      const ref = c.getAttribute('r') || '';
      const idx = colIndex(ref);
      const t = c.getAttribute('t') || '';
      let val = '';
      if (t === 's') {
        const vEl = c.querySelector('v');
        val = vEl ? (sharedStrings[parseInt(vEl.textContent, 10)] ?? '') : '';
      } else if (t === 'inlineStr') {
        val = Array.from(c.querySelectorAll('t')).map(n => n.textContent || '').join('');
      } else {
        const vEl = c.querySelector('v');
        val = vEl ? (vEl.textContent || '') : '';
      }
      while (rowArr.length <= idx) rowArr.push('');
      rowArr[idx] = val;
    });
    if (rowArr.some(v => String(v).trim() !== '')) result.push(rowArr);
  });
  return result;
}
