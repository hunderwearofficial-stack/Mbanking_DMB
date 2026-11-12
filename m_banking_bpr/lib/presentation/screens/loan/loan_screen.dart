import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../helpdesk/helpdesk_screen.dart';

class LoanScreen extends StatefulWidget {
  const LoanScreen({super.key});

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen> {
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _loans = [];

  @override
  void initState() {
    super.initState();
    _fetchLoanData();
  }

  Future<void> _fetchLoanData() async {
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
      final loans = await repo.getLoans(cifNumber: cif);

      if (mounted) {
        setState(() {
          _loans = loans;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal memuat data pinjaman';
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

  void _showLoanDetailSheet(BuildContext context, Map<String, dynamic> loan) {
    final accNo = loan['nomor_rekening']?.toString() ?? '-';
    final prodName = loan['nama_produk']?.toString() ?? 'Kredit Modal Kerja';
    final plafon = (loan['plafon'] ?? 0).toDouble();
    final bakiDebet = (loan['baki_debet'] ?? 0).toDouble();
    final statusKet = loan['status_rekening_keterangan']?.toString() ?? 'Aktif';
    final kolKet = loan['kolektibilitas_keterangan']?.toString() ?? 'Lancar';

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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prodName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No. Rekening: $accNo',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Text(
                      statusKet.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: dmbGreen,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 14),

              _buildDetailRow('Plafon Pinjaman', CurrencyFormatter.formatRupiah(plafon)),
              _buildDetailRow('Sisa Pokok (Baki Debet)', CurrencyFormatter.formatRupiah(bakiDebet), isBold: true),
              _buildDetailRow('Pokok Terbayar', CurrencyFormatter.formatRupiah((plafon - bakiDebet).clamp(0, plafon))),
              _buildDetailRow('Status Kolektibilitas', '$kolKet (Kol 1)', isGreen: true),
              _buildDetailRow('Sistem Pembayaran', 'Autodebet Rekening Tabungan Utama'),
              _buildDetailRow('Kantor Pelayanan', 'KC Bogor Pusat (Jl. Pajajaran 88)'),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                    );
                  },
                  icon: const Icon(Icons.support_agent_rounded, size: 20),
                  label: Text(
                    'Konsultasi Petugas Kredit (AO)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
                color: isGreen ? dmbGreen : titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalPlafon = 0;
    double totalBakiDebet = 0;

    for (final loan in _loans) {
      totalPlafon += (loan['plafon'] ?? 0).toDouble();
      totalBakiDebet += (loan['baki_debet'] ?? 0).toDouble();
    }

    double progress = 0.0;
    if (totalPlafon > 0) {
      progress = ((totalPlafon - totalBakiDebet) / totalPlafon).clamp(0.0, 1.0);
    }

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Fasilitas Pinjaman',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'PORTOFOLIO PINJAMAN AKTIF',
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
            onPressed: _fetchLoanData,
            tooltip: 'Perbarui Data',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchLoanData,
        color: primaryNavy,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primaryNavy),
                    SizedBox(height: 16),
                    Text('Memuat data fasilitas pinjaman...', style: TextStyle(color: textMuted)),
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
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: titleDark),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _fetchLoanData,
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loans.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFDBEAFE)),
                                ),
                                child: const Icon(Icons.credit_score_outlined, color: royalBlue, size: 36),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Belum Ada Fasilitas Pinjaman',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: titleDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Anda belum memiliki pinjaman aktif di Bank DMB. Ajukan pinjaman modal kerja atau kredit mikro dengan bunga kompetitif.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted, height: 1.45),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryNavy,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const HelpdeskScreen()),
                                  );
                                },
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                label: const Text('Konsultasi Pengajuan Pinjaman'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Executive Summary Header Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0B356D),
                                    Color(0xFF0062E3),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0062E3).withOpacity(0.25),
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
                                    'TOTAL BAKI DEBET PINJAMAN',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withOpacity(0.85),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CurrencyFormatter.formatRupiah(totalBakiDebet),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Progress Bar Pelunasan
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total Plafon: ${CurrencyFormatter.formatRupiah(totalPlafon)}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          color: Colors.white.withOpacity(0.90),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${(progress * 100).toStringAsFixed(1)}% Lunas',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 7,
                                      backgroundColor: Colors.white.withOpacity(0.25),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // 2. Daftar Fasilitas Pinjaman Langsung dari Core Banking
                            Text(
                              'Daftar Fasilitas Pinjaman Bank DMB',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 12),

                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _loans.length,
                              itemBuilder: (context, index) {
                                final loan = _loans[index];
                                final rawAccNo = loan['nomor_rekening']?.toString() ?? '-';
                                final formattedAcc = _formatAccountNumber(rawAccNo);
                                final productName = loan['nama_produk']?.toString() ?? 'Kredit Modal Kerja';
                                final plafon = (loan['plafon'] ?? 0).toDouble();
                                final bakiDebet = (loan['baki_debet'] ?? 0).toDouble();
                                final statusKet = loan['status_rekening_keterangan']?.toString() ?? 'Aktif';
                                final kolKet = loan['kolektibilitas_keterangan']?.toString() ?? 'Lancar';

                                double itemProgress = 0.0;
                                if (plafon > 0) {
                                  itemProgress = ((plafon - bakiDebet) / plafon).clamp(0.0, 1.0);
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: borderLight),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.02),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top Header: Product Name + Status
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              productName,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: titleDark,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF0FDF4),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFBBF7D0)),
                                            ),
                                            child: Text(
                                              statusKet.toUpperCase(),
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: dmbGreen,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 6),

                                      // No Rekening + Copy
                                      Row(
                                        children: [
                                          Text(
                                            formattedAcc,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12.5,
                                              color: textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          InkWell(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: rawAccNo));
                                              _showToast('Nomor rekening disalin: $rawAccNo');
                                            },
                                            child: const Icon(Icons.copy_rounded, size: 13, color: royalBlue),
                                          ),
                                        ],
                                      ),

                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                                      ),

                                      // Baki Debet & Plafon
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Sisa Pokok (Baki Debet)',
                                                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                CurrencyFormatter.formatRupiah(bakiDebet),
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                  color: titleDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Plafon Kredit',
                                                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                CurrencyFormatter.formatRupiah(plafon),
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: primaryNavy,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 14),

                                      // Progress Indicator
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: itemProgress,
                                          minHeight: 6,
                                          backgroundColor: const Color(0xFFE2E8F0),
                                          valueColor: const AlwaysStoppedAnimation<Color>(dmbGreen),
                                        ),
                                      ),

                                      const SizedBox(height: 14),

                                      // Bottom Info Row: Kolektibilitas + Action Detail
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.verified_rounded, size: 14, color: dmbGreen),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Kol: $kolKet',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: dmbGreen,
                                                ),
                                              ),
                                            ],
                                          ),
                                          InkWell(
                                            onTap: () => _showLoanDetailSheet(context, loan),
                                            child: Row(
                                              children: [
                                                Text(
                                                  'Lihat Rincian',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: royalBlue,
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                                const Icon(Icons.chevron_right_rounded, size: 16, color: royalBlue),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }

  String _formatAccountNumber(String acc) {
    if (acc.length == 16) {
      return '${acc.substring(0, 4)} ${acc.substring(4, 8)} ${acc.substring(8, 12)} ${acc.substring(12)}';
    }
    return acc;
  }
}
