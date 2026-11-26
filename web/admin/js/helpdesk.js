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
      tbody.innerHTML = '<tr><td colspan="4" class="px-5 py-8 text-center text-slate-400">Belum ada FAQ.</td></tr>';
      return;
    }
    tbody.innerHTML = faqs.map(f => {
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
    }).join('');
  } catch (e) {
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
      tbody.innerHTML = '<tr><td colspan="5" class="px-5 py-8 text-center text-slate-400">Belum ada pertanyaan nasabah pada filter ini.</td></tr>';
      return;
    }
    tbody.innerHTML = items.map(item => {
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
    }).join('');
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
