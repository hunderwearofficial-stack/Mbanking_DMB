import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';

class EStatementScreen extends StatefulWidget {
  const EStatementScreen({super.key});

  @override
  State<EStatementScreen> createState() => _EStatementScreenState();
}

class _EStatementScreenState extends State<EStatementScreen> {
  int _selectedMonthIndex = 0;
  bool _isDownloading = false;

  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

  final List<Map<String, String>> _periods = [
    {'title': 'November 2026', 'subtitle': 'Bulan Berjalan (Hingga Hari Ini)', 'code': '2026-11'},
    {'title': 'Oktober 2026', 'subtitle': 'Periode 1 Bulan Penuh', 'code': '2026-10'},
    {'title': 'September 2026', 'subtitle': 'Periode 1 Bulan Penuh', 'code': '2026-09'},
    {'title': 'Agustus 2026', 'subtitle': 'Periode 1 Bulan Penuh', 'code': '2026-08'},
  ];

  void _downloadStatement(String periodTitle) {
    setState(() => _isDownloading = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'e-Statement PDF $periodTitle berhasil diunduh ke folder Dokumen.',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: titleDark,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
              'e-Statement Rekening',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'LAPORAN REKENING KORAN ELEKTRONIK',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: royalBlue,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
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
                    color: const Color(0xFF0062E3).withOpacity(0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Laporan Rekening Koran',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Unduh mutasi berkala resmi berstempel digital Bank DMB dalam format PDF terverifikasi.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: Colors.white.withOpacity(0.88),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 2. Rekening Terpilih
            Text(
              'Rekening Sumber',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 10),

            BlocBuilder<AccountCubit, AccountState>(
              builder: (context, state) {
                String accNum = '-';
                String accType = 'Tabungan Mikro DMB (Kode 20)';
                double balance = 0.0;

                if (state is AccountLoaded) {
                  accNum = state.account.accountNumber;
                  accType = state.account.accountType;
                  balance = state.account.balance;
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
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
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded, color: royalBlue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accType,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: titleDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'No. Rek: $accNum',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatRupiah(balance),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: primaryNavy,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 3. Pilih Periode Laporan
            Text(
              'Pilih Periode Mutasi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 10),

            ...List.generate(_periods.length, (index) {
              final isSelected = _selectedMonthIndex == index;
              final p = _periods[index];

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSelected ? royalBlue : borderLight, width: isSelected ? 1.5 : 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onTap: () => setState(() => _selectedMonthIndex = index),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.calendar_month_rounded,
                        color: isSelected ? royalBlue : textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                  title: Text(
                    p['title']!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? royalBlue : titleDark,
                    ),
                  ),
                  subtitle: Text(
                    p['subtitle']!,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                  ),
                  trailing: Radio<int>(
                    value: index,
                    groupValue: _selectedMonthIndex,
                    activeColor: royalBlue,
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedMonthIndex = val);
                    },
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            // 4. Download Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryNavy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                ),
                onPressed: _isDownloading
                    ? null
                    : () => _downloadStatement(_periods[_selectedMonthIndex]['title']!),
                icon: _isDownloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  _isDownloading
                      ? 'Sedang Menyiapkan Dokumen PDF...'
                      : 'Unduh e-Statement PDF (${_periods[_selectedMonthIndex]['title']})',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Legal note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: royalBlue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dokumen e-Statement resmi dilindungi keamanan enkripsi digital dan diakui sebagai bukti mutasi perbankan yang sah.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

