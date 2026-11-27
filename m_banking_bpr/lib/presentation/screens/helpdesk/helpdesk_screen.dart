import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/bank_contact.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/auth_ui_kit.dart';

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
          'Demi keamanan, 1 akun DMB terikat pada 1 perangkat smartphone.\n\n'
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

  IconData _topicIcon(String topic) {
    final t = topic.toLowerCase();
    if (t.contains('pin') || t.contains('password')) return Icons.lock_outline_rounded;
    if (t.contains('hp') || t.contains('perangkat')) return Icons.phone_android_rounded;
    if (t.contains('kredit') || t.contains('kkm')) return Icons.credit_card_outlined;
    if (t.contains('deposito') || t.contains('pencairan')) return Icons.description_outlined;
    if (t.contains('mutasi') || t.contains('saldo')) return Icons.trending_up_rounded;
    if (t.contains('status')) return Icons.verified_user_outlined;
    if (t.contains('jam') || t.contains('kantor')) return Icons.account_balance_outlined;
    if (t.contains('contact') || t.contains('hubungi')) return Icons.chat_bubble_outline_rounded;
    return Icons.help_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final topicList = _dynamicRules.isNotEmpty
        ? _dynamicRules.map((e) => e.topic).toList()
        : _defaultTopics;
    final showTopicGrid = _messages.length <= 1;

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Clean Light Header (matching Pusat Bantuan reference)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Row(
                children: [
                  if (!widget.isTab) ...[
                    Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AuthUiTokens.inputBorder),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 19,
                            color: AuthUiTokens.deepCobalt,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pusat Bantuan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AuthUiTokens.deepCobalt,
                            letterSpacing: -0.35,
                          ),
                        ),
                        Text(
                          'Asisten Virtual & Contact Center Bank DMB',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!showTopicGrid)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_messages.length > 1) {
                            _messages.removeRange(1, _messages.length);
                          }
                        });
                      },
                      child: Text(
                        'Topik',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AuthUiTokens.deepCobalt,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Body: Popular Topic Grid (initial) OR Chat History
            Expanded(
              child: showTopicGrid
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Greeting Banner Card
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFE8EEF6)),
                              boxShadow: [
                                BoxShadow(
                                  color: AuthUiTokens.deepCobalt.withValues(alpha: 0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: AuthUiTokens.softBlueBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.headset_mic_rounded,
                                    color: AuthUiTokens.deepCobalt,
                                    size: 20,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 32,
                                  margin: const EdgeInsets.symmetric(horizontal: 12),
                                  color: const Color(0xFFE2E8F0),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Halo! Saya Asisten Virtual Bank DMB.',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: AuthUiTokens.deepCobalt,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Pilih topik di bawah atau ketik pertanyaan Anda.',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          color: textMuted,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Topik Populer',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AuthUiTokens.deepCobalt,
                                ),
                              ),
                              InkWell(
                                onTap: () => _handleSend('Hubungi Contact Center'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Contact Center',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AuthUiTokens.royalBlue,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: AuthUiTokens.royalBlue,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: topicList.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: 64,
                            ),
                            itemBuilder: (_, idx) {
                              final topic = topicList[idx];
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _handleSend(topic),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFE8EEF6)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AuthUiTokens.deepCobalt.withValues(alpha: 0.03),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: AuthUiTokens.softBlueBg,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            _topicIcon(topic),
                                            size: 18,
                                            color: AuthUiTokens.deepCobalt,
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(
                                            topic,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: titleDark,
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 16,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _buildMessageItem(_messages[i]),
                    ),
            ),

            // Floating Pill Input Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFE8EEF6)),
                    boxShadow: [
                      BoxShadow(
                        color: AuthUiTokens.deepCobalt.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inputCtrl,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _handleSend(),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: titleDark),
                          decoration: InputDecoration(
                            hintText: 'Ketik pertanyaan Anda...',
                            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () => _handleSend(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AuthUiTokens.deepCobalt,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            elevation: 0,
                            shape: const CircleBorder(),
                          ),
                          child: const Icon(Icons.send_rounded, size: 17),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
