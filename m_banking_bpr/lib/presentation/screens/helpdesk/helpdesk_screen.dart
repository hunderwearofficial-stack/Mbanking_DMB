import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/bank_contact.dart';
import '../../../data/repositories/account_repository.dart';

class _ChatMessage {
  final bool isBot;
  final String text;
  final bool showContactCard;
  final List<String> suggestions;

  const _ChatMessage({
    required this.isBot,
    required this.text,
    this.showContactCard = false,
    this.suggestions = const [],
  });
}

class _FaqRule {
  final String id;
  final String topic;
  final List<String> keywords;
  final String answer;

  const _FaqRule({
    this.id = '',
    required this.topic,
    required this.keywords,
    required this.answer,
  });
}

class HelpdeskScreen extends StatefulWidget {
  final bool isTab;
  const HelpdeskScreen({super.key, this.isTab = false});

  @override
  State<HelpdeskScreen> createState() => _HelpdeskScreenState();
}

class _HelpdeskScreenState extends State<HelpdeskScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = Color(0xFFE2E8F0);

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  List<_FaqRule> _dynamicRules = [];

  static const List<String> _defaultTopics = [
    'Lupa PIN / Password',
    'Ganti HP / Perangkat',
    'Kredit & KKM',
    'Deposito & Pencairan',
    'Mutasi & Saldo',
    'Jam & Lokasi Kantor',
    'Hubungi Contact Center',
  ];

  List<_FaqRule> get _activeRules => _dynamicRules.isNotEmpty ? _dynamicRules : _rules;

  static final List<_FaqRule> _rules = [
    const _FaqRule(
      topic: 'Lupa PIN / Password',
      keywords: ['pin', 'password', 'sandi', 'lupa', 'blokir', 'terkunci', 'login', 'masuk'],
      answer:
          'Jika lupa password, gunakan menu "Lupa Password" di halaman Login dan ikuti verifikasi OTP ke nomor HP terdaftar.\n\n'
          'Jika akun/PIN terblokir karena salah memasukkan PIN/password berulang kali, silakan hubungi Contact Center Bank DMB untuk pembukaan blokir.',
    ),
    const _FaqRule(
      topic: 'Ganti HP / Perangkat',
      keywords: ['hp', 'perangkat', 'device', 'ganti', 'pindah', 'unbind', 'reset device'],
      answer:
          'Demi keamanan, 1 akun myDMB terikat pada 1 perangkat smartphone.\n\n'
          'Jika Anda berganti HP, silakan hubungi Contact Center Bank DMB untuk melakukan reset ikatan perangkat (Unbind Device), lalu lakukan aktivasi ulang dengan verifikasi OTP di HP baru.',
    ),
    const _FaqRule(
      topic: 'Kredit & KKM',
      keywords: ['kredit', 'pinjaman', 'kkm', 'kilat', 'mil', 'kmg', 'angsuran', 'hadir', 'pertemuan', 'tunggak'],
      answer:
          'Anda dapat memantau seluruh fasilitas kredit melalui menu Kredit & Jadwal Angsuran di Beranda:\n'
          '• KKM Reguler & KILAT KKM: menampilkan tagihan mingguan, status bayar, dan kehadiran kelompok.\n'
          '• MIL & KMG: menampilkan sisa pokok, progres, serta jadwal angsuran.\n\n'
          'Pengajuan kredit baru dapat dilakukan melalui menu Ajukan Kredit.',
    ),
    const _FaqRule(
      topic: 'Deposito & Pencairan',
      keywords: ['deposito', 'bilyet', 'cair', 'pencairan', 'aro', 'jatuh tempo', 'bunga'],
      answer:
          'Untuk melihat rincian bilyet deposito, buka menu Deposito di Beranda lalu klik bilyet yang ingin dilihat.\n\n'
          'Pengajuan pencairan deposito (Pokok, Bunga, atau Pokok & Bunga) dapat langsung diajukan dari halaman Detail Deposito dan akan ditindaklanjuti oleh petugas Bank DMB.',
    ),
    const _FaqRule(
      topic: 'Mutasi & Saldo',
      keywords: ['mutasi', 'saldo', 'rekening', 'transaksi', 'riwayat', 'tabungan'],
      answer:
          '• Informasi Saldo: menampilkan ringkasan saldo seluruh rekening tabungan aktif (dapat diintip/disembunyikan).\n'
          '• Mutasi: menampilkan riwayat transaksi Tabungan, Deposito, maupun Pinjaman per rekening dengan rentang maksimal 31 hari.',
    ),
    const _FaqRule(
      topic: 'Status Pengajuan',
      keywords: ['pengajuan', 'ajukan', 'status', 'diajukan', 'proses', 'selesai'],
      answer:
          'Seluruh pengajuan produk (Kredit, Deposito, Tabungan, dan Pencairan Deposito) dapat dipantau di menu Status Pengajuan di Beranda:\n'
          '• Diajukan: menunggu peninjauan petugas\n'
          '• Diproses: sedang ditindaklanjuti / dihubungi petugas\n'
          '• Selesai: proses tindak lanjut telah selesai',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _ChatMessage(
        isBot: true,
        text:
            'Halo! Saya Asisten Virtual Bank DMB.\nPilih topik di bawah atau ketik pertanyaan Anda.',
        suggestions: _defaultTopics,
      ),
    );
    _loadDynamicFaqs();
  }

  Future<void> _loadDynamicFaqs() async {
    try {
      final list = await context.read<AccountRepository>().getHelpdeskFaqs();
      if (!mounted || list.isEmpty) return;
      final loaded = list.map((m) {
        final kws = (m['keywords'] ?? '')
            .toString()
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
        return _FaqRule(
          id: (m['id'] ?? '').toString(),
          topic: (m['topic'] ?? '').toString(),
          keywords: kws,
          answer: (m['answer'] ?? '').toString(),
        );
      }).where((r) => r.topic.isNotEmpty && r.answer.isNotEmpty).toList();

      if (loaded.isNotEmpty && mounted) {
        setState(() {
          _dynamicRules = loaded;
          if (_messages.length == 1 && _messages.first.isBot) {
            _messages[0] = _ChatMessage(
              isBot: true,
              text: _messages.first.text,
              suggestions: [
                ...loaded.take(6).map((e) => e.topic),
                'Jam & Lokasi Kantor',
                'Hubungi Contact Center',
              ],
            );
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label disalin: $value',
          style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: primaryNavy,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleSend([String? preset]) {
    final text = (preset ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;
    if (preset == null) _inputCtrl.clear();

    final reply = _buildBotReply(text);
    setState(() {
      _messages.add(_ChatMessage(isBot: false, text: text));
      _messages.add(reply.message);
    });

    if (preset == null || !reply.answered) {
      context.read<AccountRepository>().logHelpdeskInquiry(
            question: text,
            matchedFaqId: reply.matchedFaqId,
            isAnswered: reply.answered,
          );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  ({ _ChatMessage message, String matchedFaqId, bool answered }) _buildBotReply(String query) {
    final q = query.toLowerCase();

    if (q.contains('contact center') ||
        q.contains('hubungi') ||
        q.contains('cs') ||
        q.contains('operator') ||
        q.contains('komplain') ||
        q.contains('keluhan') ||
        q.contains('telepon') ||
        q.contains('telp') ||
        q.contains('email')) {
      return (
        message: const _ChatMessage(
          isBot: true,
          text:
              'Anda dapat langsung menghubungi Contact Center resmi Bank DMB melalui telepon atau email berikut:',
          showContactCard: true,
        ),
        matchedFaqId: '',
        answered: true,
      );
    }

    if (q.contains('jam') ||
        q.contains('lokasi') ||
        q.contains('kantor') ||
        q.contains('alamat') ||
        q.contains('buka') ||
        q.contains('tutup')) {
      return (
        message: _ChatMessage(
          isBot: true,
          text:
              'Informasi Kantor Pusat & Layanan Bank DMB:\n'
              '• Alamat: ${BankContact.headOfficeAddress}\n'
              '• Jam Layanan: ${BankContact.officeHours}',
          showContactCard: true,
        ),
        matchedFaqId: '',
        answered: true,
      );
    }

    _FaqRule? bestRule;
    int bestScore = 0;
    for (final rule in _activeRules) {
      if (rule.topic.toLowerCase() == q) {
        bestRule = rule;
        bestScore = 999;
        break;
      }
      int score = 0;
      for (final kw in rule.keywords) {
        if (q.contains(kw)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestRule = rule;
      }
    }

    if (bestRule != null && bestScore > 0) {
      return (
        message: _ChatMessage(
          isBot: true,
          text: bestRule.answer,
          suggestions: const ['Hubungi Contact Center'],
        ),
        matchedFaqId: bestRule.id,
        answered: true,
      );
    }

    final fallbackSuggestions = _activeRules.take(3).map((e) => e.topic).toList();
    return (
      message: _ChatMessage(
        isBot: true,
        text:
            'Maaf, saya belum menemukan jawaban yang sesuai untuk pertanyaan tersebut.\n\n'
            'Pertanyaan Anda sudah kami catat untuk peningkatan layanan. Silakan hubungi Contact Center resmi Bank DMB melalui telepon atau email di bawah ini:',
        showContactCard: true,
        suggestions: fallbackSuggestions,
      ),
      matchedFaqId: '',
      answered: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: !widget.isTab,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pusat Bantuan',
              style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              'Asisten Virtual Bank DMB',
              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Contact Center',
            onPressed: () => _handleSend('Hubungi Contact Center'),
            icon: const Icon(Icons.support_agent_outlined, color: primaryNavy, size: 22),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _buildMessageItem(_messages[i]),
            ),
          ),
          // Input bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: titleDark),
                      decoration: InputDecoration(
                        hintText: 'Ketik pertanyaan Anda...',
                        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: borderLight),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: borderLight),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: primaryNavy),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => _handleSend(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryNavy,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        elevation: 0,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: msg.isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: msg.isBot ? Colors.white : primaryNavy,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(msg.isBot ? 4 : 14),
                  bottomRight: Radius.circular(msg.isBot ? 14 : 4),
                ),
                border: msg.isBot ? Border.all(color: borderLight) : null,
              ),
              child: Text(
                msg.text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.45,
                  color: msg.isBot ? titleDark : Colors.white,
                ),
              ),
            ),
          ),
          if (msg.showContactCard) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderLight),
                ),
                child: Column(
                  children: [
                    _contactRow(
                      icon: Icons.phone_outlined,
                      label: 'Telepon Call Center',
                      value: BankContact.callCenterDisplay,
                      onTap: () => _copy(BankContact.callCenterDial, 'Nomor Call Center'),
                    ),
                    const Divider(height: 1, indent: 48, endIndent: 14, color: Color(0xFFF1F5F9)),
                    _contactRow(
                      icon: Icons.email_outlined,
                      label: 'Email Pengaduan & Layanan',
                      value: BankContact.email,
                      onTap: () => _copy(BankContact.email, 'Email Bank DMB'),
                    ),
                    const Divider(height: 1, indent: 48, endIndent: 14, color: Color(0xFFF1F5F9)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule_outlined, size: 18, color: textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Jam Layanan: ${BankContact.officeHours}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (msg.suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: msg.suggestions.map((s) {
                return ActionChip(
                  label: Text(
                    s,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: primaryNavy,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: borderLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  onPressed: () => _handleSend(s),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: primaryNavy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted)),
                  Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: primaryNavy,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.copy_rounded, size: 16, color: textMuted),
          ],
        ),
      ),
    );
  }
}
