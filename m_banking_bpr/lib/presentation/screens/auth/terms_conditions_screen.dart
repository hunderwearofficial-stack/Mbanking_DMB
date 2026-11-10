import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';

class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key});

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = true;

  // 3 Distinct Mandatory Banking Consent Checkboxes - Must be checked ONE BY ONE!
  bool _agreeTerms = false;
  bool _agreePrivacyData = false;
  bool _agreeSecurityOwnership = false;

  bool get _isAllAgreed => _agreeTerms && _agreePrivacyData && _agreeSecurityOwnership;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    // Hide floating down button when near the bottom
    final isNearBottom = (maxScroll - currentScroll) <= 80;

    if (isNearBottom && _showScrollToBottom) {
      setState(() => _showScrollToBottom = false);
    } else if (!isNearBottom && !_showScrollToBottom) {
      setState(() => _showScrollToBottom = true);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onProceed() {
    if (!_isAllAgreed) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Stack(
          children: [
            // Single Unified Scrollable Page (No Popups, Checkboxes & Button in-page at the bottom!)
            SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 4,
                bottom: MediaQuery.of(context).padding.bottom + 36,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Headline Title
                  const Text(
                    'Ringkasan Informasi dan Syarat Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      height: 1.28,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Date Updated
                  const Text(
                    'Diperbarui pada 10 November 2026',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF64748B),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Subtitle Instruction
                  const Text(
                    'Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // RIPLAY Teal Subheading
                  const Text(
                    'Ringkasan Informasi Produk dan Layanan (RIPLAY) Versi Personal',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D9488), // Bank Teal Green
                      height: 1.35,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Metadata Table (Nama Penerbit, Nama Produk, Jenis Produk, Deskripsi)
                  _buildMetaRow('Nama Penerbit', 'PT BPR Dana Mandiri Bogor'),
                  _buildMetaRow('Nama Produk', 'DMB Mobile'),
                  _buildMetaRow('Jenis Produk', 'Mobile Banking'),
                  _buildMetaRow(
                    'Deskripsi',
                    'Fasilitas elektronik channel yang disediakan oleh Bank serta dapat diakses dan digunakan oleh Nasabah untuk melakukan Transaksi Finansial dan/atau Non-Finansial melalui Smartphone.',
                  ),

                  const SizedBox(height: 22),

                  // Section I: Fitur Utama
                  _buildSectionHeader('I. Fitur Utama'),
                  const SizedBox(height: 10),

                  _buildNumberedHeader('1. Pembukaan & Pengelolaan Rekening Simpanan meliputi:'),
                  _buildSubItem('a. Tabungan DMB Utama'),
                  _buildSubItem('b. Tabungan Mandiri Masa Depan'),
                  _buildSubItem('c. Tabungan Simpanan Pelajar (SimPel)'),
                  _buildSubItem('d. Deposito Berjangka DMB'),
                  _buildSubItem('e. Tabungan Rencana Impian'),

                  const SizedBox(height: 12),

                  _buildNumberedHeader('2. Transaksi Finansial & Pembayaran meliputi:'),
                  _buildSubItem('a. Transfer Antar Rekening Bank DMB'),
                  _buildSubItem('b. Transfer Online Antar Bank Nasional & BI-FAST'),
                  _buildSubItem('c. Pembayaran Tagihan Rutin (PLN, PDAM, BPJS Kesehatan)'),
                  _buildSubItem('d. Pembelian Pulsa, Paket Data & Token Listrik'),
                  _buildSubItem('e. Top Up Dompet Digital (GoPay, OVO, Dana, ShopeePay)'),

                  const SizedBox(height: 12),

                  _buildNumberedHeader('3. Pengajuan Produk Pinjaman & Kredit meliputi:'),
                  _buildSubItem('a. Kredit Modal Kerja UMKM'),
                  _buildSubItem('b. Kredit Konsumtif & Multiguna'),
                  _buildSubItem('c. Kredit Pegawai & Payroll'),

                  const SizedBox(height: 12),

                  _buildNumberedHeader('4. Layanan Informasi & Pengaturan Akun meliputi:'),
                  _buildSubItem('a. Informasi Saldo Real-Time 24 Jam'),
                  _buildSubItem('b. Riwayat Mutasi Rekening & E-Statement'),
                  _buildSubItem('c. Single Hardware Device Binding Security'),
                  _buildSubItem('d. Pembaruan Profil & Ubah PIN Transaksi'),

                  const SizedBox(height: 22),

                  // Section II: Manfaat & Keuntungan
                  _buildSectionHeader('II. Manfaat & Keuntungan'),
                  const SizedBox(height: 10),
                  _buildBulletPoint(
                    '1. Kemudahan bertransaksi 24/7 di mana saja dan kapan saja tanpa perlu antre di kantor cabang.',
                  ),
                  _buildBulletPoint(
                    '2. Perlindungan keamanan bertingkat dengan enkripsi data AES-256 dan pengikatan perangkat tunggal (Single Device Binding).',
                  ),
                  _buildBulletPoint(
                    '3. Suku bunga tabungan dan deposito kompetitif serta dijamin oleh Lembaga Penjamin Simpanan (LPS) sesuai ketentuan yang berlaku.',
                  ),
                  _buildBulletPoint(
                    '4. Bebas biaya administrasi bulanan untuk pengelolaan rekening mobile banking DMB Mobile.',
                  ),

                  const SizedBox(height: 22),

                  // Section III: Biaya & Batas Limit Transaksi
                  _buildSectionHeader('III. Biaya Layanan & Batas Limit Transaksi'),
                  const SizedBox(height: 10),
                  _buildNumberedHeader('1. Struktur Biaya Transaksi:'),
                  _buildSubItem('a. Biaya Administrasi Bulanan Mobile Banking: Gratis (Rp 0)'),
                  _buildSubItem('b. Transfer Antar-Rekening Bank DMB: Gratis (Rp 0)'),
                  _buildSubItem('c. Transfer Antar-Bank Online: Sesuai tarif switching nasional'),
                  _buildSubItem('d. Biaya SMS OTP: Mengikuti tarif resmi masing-masing operator seluler'),

                  const SizedBox(height: 12),

                  _buildNumberedHeader('2. Batas Limit Transaksi Harian (Harian Per Akun):'),
                  _buildSubItem('a. Transfer Antar-Rekening DMB: Maksimal Rp 50.000.000 / hari'),
                  _buildSubItem('b. Transfer Antar-Bank Online: Maksimal Rp 25.000.000 / hari'),
                  _buildSubItem('c. Pembayaran & Pembelian: Maksimal Rp 10.000.000 / hari'),

                  const SizedBox(height: 22),

                  // Section IV: Syarat & Ketentuan Penggunaan (Ketentuan Pokok)
                  _buildSectionHeader('IV. Syarat & Ketentuan Penggunaan'),
                  const SizedBox(height: 10),
                  _buildBulletPoint(
                    '1. Kepesertaan: Nasabah wajib memiliki rekening simpanan aktif di PT BPR Dana Mandiri Bogor dan nomor telepon seluler aktif terverifikasi.',
                  ),
                  _buildBulletPoint(
                    '2. Kerahasiaan Akses: Nasabah bertanggung jawab penuh atas kerahasiaan Kata Sandi, PIN 6 digit, dan Kode OTP. Petugas Bank DMB TIDAK PERNAH meminta data rahasia tersebut.',
                  ),
                  _buildBulletPoint(
                    '3. Larangan Perangkat Root/Jailbreak: Nasabah dilarang menginstal DMB Mobile pada smartphone yang sistem operasinya telah dimodifikasi (Root / Jailbreak) demi menjaga keamanan dari malware.',
                  ),
                  _buildBulletPoint(
                    '4. Otorisasi Hukum (UU ITE): Setiap instruksi transaksi yang diotorisasi dengan PIN/OTP yang sah bersifat final, mengikat secara hukum, dan diakui sebagai alat bukti yang sah di pengadilan.',
                  ),
                  _buildBulletPoint(
                    '5. Pemblokiran Akun: Akses akun akan diblokir otomatis apabila salah memasukkan PIN sebanyak 3 (tiga) kali berturut-turut untuk mencegah tindak kejahatan.',
                  ),

                  const SizedBox(height: 22),

                  // Section V: Perlindungan Data Pribadi (UU PDP No. 27/2022)
                  _buildSectionHeader('V. Pelindungan Data Pribadi (UU No. 27 Tahun 2022)'),
                  const SizedBox(height: 10),
                  _buildBulletPoint(
                    '1. Bank memproses data pribadi nasabah semata-mata untuk verifikasi identitas, mitigasi risiko fraud, dan pelaksanaan layanan perbankan.',
                  ),
                  _buildBulletPoint(
                    '2. Data nasabah disimpan dalam Data Center domestik di Indonesia dengan standar enkripsi militer AES-256 dan protokol TLS 1.3.',
                  ),
                  _buildBulletPoint(
                    '3. Bank berkomitmen penuh tidak membagikan atau mengalihkan data nasabah kepada pihak ketiga tanpa persetujuan eksplisit nasabah atau perintah regulator perbankan yang sah.',
                  ),

                  const SizedBox(height: 22),

                  // Section VI: Pengaduan Nasabah & Call Center
                  _buildSectionHeader('VI. Layanan Pengaduan Konsumen & Penyelesaian Sengketa'),
                  const SizedBox(height: 10),
                  _buildBulletPoint(
                    '1. Layanan pengaduan resmi Bank DMB dapat dihubungi melalui Call Center (0251) 832-1234, WhatsApp Resmi di 0811-9988-7766, atau Kantor Cabang PT BPR Dana Mandiri Bogor.',
                  ),
                  _buildBulletPoint(
                    '2. Nasabah berhak menyampaikan sengketa kepada Lembaga Alternatif Penyelesaian Sengketa Sektor Jasa Keuangan (LAPS SJK) atau Otoritas Jasa Keuangan (OJK).',
                  ),

                  const SizedBox(height: 28),

                  // Divider Before Agreement Section
                  Container(
                    height: 1.5,
                    color: const Color(0xFFE2E8F0),
                    margin: const EdgeInsets.only(bottom: 24),
                  ),

                  // In-Page Consent Section (No Popup, Part of the Page at the Very Bottom!)
                  const Text(
                    'Persetujuan Layanan Nasabah',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Silakan centang satu per satu seluruh poin persetujuan di bawah ini untuk melanjutkan:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Checkbox 1: Syarat & Ketentuan Layanan (Checked manually one by one)
                  _buildCheckboxItem(
                    value: _agreeTerms,
                    onChanged: (val) => setState(() => _agreeTerms = val ?? false),
                    text:
                        'Saya telah membaca, memahami, dan menyetujui seluruh isi Syarat & Ketentuan Layanan DMB Mobile PT BPR Dana Mandiri Bogor.',
                  ),

                  const SizedBox(height: 12),

                  // Checkbox 2: Perlindungan Data Pribadi (UU PDP) (Checked manually one by one)
                  _buildCheckboxItem(
                    value: _agreePrivacyData,
                    onChanged: (val) => setState(() => _agreePrivacyData = val ?? false),
                    text:
                        'Saya menyetujui Pemrosesan Data Pribadi (UU PDP No. 27/2022) untuk keperluan transaksi perbankan dan verifikasi layanan.',
                  ),

                  const SizedBox(height: 12),

                  // Checkbox 3: Kebenaran Data & Kerahasiaan PIN/OTP (Checked manually one by one)
                  _buildCheckboxItem(
                    value: _agreeSecurityOwnership,
                    onChanged: (val) => setState(() => _agreeSecurityOwnership = val ?? false),
                    text:
                        'Saya menyatakan bahwa data yang didaftarkan adalah benar milik saya, serta saya bertanggung jawab penuh menjaga kerahasiaan Kata Sandi, PIN, dan Kode OTP saya.',
                  ),

                  const SizedBox(height: 28),

                  // Primary Action Button: "Setuju & Lanjutkan" (Active only when all 3 are checked one by one!)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isAllAgreed ? _onProceed : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16984B), // DMB Green
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        elevation: _isAllAgreed ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isAllAgreed ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Setuju & Lanjutkan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Floating Scroll-to-Bottom Button (Visible only when not at bottom, to easily reach checkboxes)
            if (_showScrollToBottom)
              Positioned(
                right: 20,
                bottom: 24,
                child: GestureDetector(
                  onTap: _scrollToBottom,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_downward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.justify,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: Color(0xFF334155),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0D9488), // Bank Teal Green
      ),
    );
  }

  Widget _buildNumberedHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E293B),
        height: 1.4,
      ),
    );
  }

  Widget _buildSubItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 18, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF475569),
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textAlign: TextAlign.justify,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF334155),
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildCheckboxItem({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String text,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF16984B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  color: value ? const Color(0xFF0F172A) : const Color(0xFF334155),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
