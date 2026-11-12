import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';

class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _deposits = [];
  int _selectedFilterIndex = 0; // 0: Semua, 1: Aktif, 2: Blokir

  @override
  void initState() {
    super.initState();
    _fetchDepositData();
  }

  Future<void> _fetchDepositData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authState = context.read<AuthCubit>().state;
      String? cif;
      if (authState is AuthAuthenticated) {
        cif = authState.user.cif;
      }
      if (cif == null || cif.isEmpty) {
        final storage = context.read<AuthCubit>().authRepository.secureStorage;
        cif = await storage.getCIF();
      }
      if (cif == null || cif.isEmpty) {
        cif = '001000309659';
      }

      final repo = context.read<AccountRepository>();
      final items = await repo.getDeposits(cifNumber: cif);

      if (mounted) {
        setState(() {
          _deposits = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal memuat data portofolio deposito';
          _isLoading = false;
        });
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: primaryNavy,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDepositDetailSheet(BuildContext context, Map<String, dynamic> item) {
    final accNo = item['nomor_rekening']?.toString() ?? '-';
    final prodName = item['nama_produk']?.toString() ?? 'DEPOSITO BERJANGKA';
    final nominal = (item['nominal'] ?? 0).toDouble();
    final rate = '${item['suku_bunga_tahunan'] ?? 6.0}% p.a.';
    final jatuhTempo = item['tanggal_jatuh_tempo']?.toString() ?? '-';
    final statusKet = item['status_rekening_keterangan']?.toString() ?? 'Aktif';
    final isAktif = statusKet.toLowerCase() == 'aktif';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: borderLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: const Icon(Icons.savings_rounded, color: dmbGreen, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prodName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'No. Rekening: $accNo',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAktif ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusKet.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isAktif ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgCanvas,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderLight),
                ),
                child: Column(
                  children: [
                    _buildModalRow('Nominal Penempatan', CurrencyFormatter.formatRupiah(nominal), isHighlight: true),
                    const Divider(height: 16),
                    _buildModalRow('Suku Bunga', rate),
                    _buildModalRow('Tanggal Jatuh Tempo', jatuhTempo),
                    _buildModalRow('Nomor Bilyet', 'BLT-DMB-${accNo.length >= 6 ? accNo.substring(accNo.length - 6) : accNo}'),
                    _buildModalRow('Sistem Perpanjangan', 'Automatic Roll Over (ARO)'),
                    _buildModalRow('Rekening Pencairan', '0500103000006961'),
                    _buildModalRow('Kantor Pelayanan', 'KC Bogor Utama'),
                    _buildModalRow('Jaminan Simpanan', 'Dijamin LPS s.d. Rp 2 Miliar'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: accNo));
                    Navigator.pop(sheetCtx);
                    _showToast('Nomor rekening $accNo berhasil disalin!');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(
                    'Salin Nomor Rekening Bilyet',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w700,
                color: isHighlight ? royalBlue : titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalDana = 0;
    int countAktif = 0;
    int countBlokir = 0;

    for (final item in _deposits) {
      final nominal = (item['nominal'] ?? 0).toDouble();
      totalDana += nominal;
      final status = item['status_rekening_keterangan']?.toString().toLowerCase() ?? '';
      if (status == 'aktif') {
        countAktif++;
      } else {
        countBlokir++;
      }
    }

    final filteredList = _deposits.where((item) {
      final status = item['status_rekening_keterangan']?.toString().toLowerCase() ?? '';
      if (_selectedFilterIndex == 1) return status == 'aktif';
      if (_selectedFilterIndex == 2) return status != 'aktif';
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Portofolio Deposito',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'INVESTASI BERJANGKA RESMI',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22, color: titleDark),
            onPressed: _fetchDepositData,
            tooltip: 'Perbarui Data',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDepositData,
        color: primaryNavy,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primaryNavy),
                    SizedBox(height: 16),
                    Text('Memuat data bilyet deposito...', style: TextStyle(color: textMuted)),
                  ],
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 48, color: textMuted),
                          const SizedBox(height: 14),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchDepositData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _deposits.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.savings_outlined, size: 36, color: royalBlue),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Belum Ada Bilyet Deposito',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: titleDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Buka bilyet deposito berjangka Bank DMB dengan suku bunga kompetitif dan dijamin oleh LPS.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          // Banner Total Deposito
                          _buildSummaryBanner(totalDana, _deposits.length),
                          const SizedBox(height: 20),

                          // Filter Tabs
                          _buildFilterTabs(_deposits.length, countAktif, countBlokir),
                          const SizedBox(height: 16),

                          // Header Daftar Bilyet
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Daftar Bilyet Deposito (${filteredList.length})',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: titleDark,
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.verified_user_rounded, size: 14, color: dmbGreen),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Dijamin LPS',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: dmbGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Cards List
                          ...filteredList.map((item) => _buildDepositCard(item)),
                        ],
                      ),
      ),
    );
  }

  Widget _buildSummaryBanner(double totalDana, int totalBilyet) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B356D),
            Color(0xFF0062E3),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: royalBlue.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'PT BPR DANA MANDIRI BOGOR',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.95),
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'RESMI LPS',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'TOTAL INVESTASI DEPOSITO',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.formatRupiah(totalDana),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$totalBilyet Bilyet Terdaftar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.trending_up_rounded, color: Color(0xFF86EFAC), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Bunga 6.00% p.a.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF86EFAC),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(int all, int aktif, int blokir) {
    return Row(
      children: [
        _buildFilterChip(0, 'Semua ($all)'),
        const SizedBox(width: 8),
        _buildFilterChip(1, 'Aktif ($aktif)'),
        const SizedBox(width: 8),
        _buildFilterChip(2, 'Blokir ($blokir)'),
      ],
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8.5),
          decoration: BoxDecoration(
            color: isSelected ? primaryNavy : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? primaryNavy : borderLight),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepositCard(Map<String, dynamic> item) {
    final accNo = item['nomor_rekening']?.toString() ?? '-';
    final prodName = item['nama_produk']?.toString() ?? 'DEPOSITO 01 BULAN';
    final nominal = (item['nominal'] ?? 0).toDouble();
    final rate = '${item['suku_bunga_tahunan'] ?? 6.0}% p.a.';
    final jatuhTempo = item['tanggal_jatuh_tempo']?.toString() ?? '-';
    final statusKet = item['status_rekening_keterangan']?.toString() ?? 'Aktif';
    final isAktif = statusKet.toLowerCase() == 'aktif';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showDepositDetailSheet(context, item),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Icon(Icons.savings_rounded, color: dmbGreen, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        prodName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isAktif ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusKet.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isAktif ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Nominal Penempatan',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted),
                  ),
                  Text(
                    CurrencyFormatter.formatRupiah(nominal),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: titleDark,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16, color: borderLight),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No. Rekening',
                        style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        accNo,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: titleDark,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Suku Bunga',
                        style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rate,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: royalBlue,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Jatuh Tempo',
                        style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        jatuhTempo,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: titleDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

