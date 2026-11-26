import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/utils/currency_formatter.dart';

class LoanKkmBundle {
  final Map<String, dynamic> account;
  final Map<String, dynamic> detail;
  final Map<String, dynamic> kkm;

  const LoanKkmBundle({
    required this.account,
    required this.detail,
    required this.kkm,
  });
}

class LoanKkmDetailScreen extends StatefulWidget {
  final List<LoanKkmBundle> kkmLoans;
  final int initialLoanIndex;
  final int initialTabIndex;

  const LoanKkmDetailScreen({
    super.key,
    required this.kkmLoans,
    this.initialLoanIndex = 0,
    this.initialTabIndex = 0,
  });

  @override
  State<LoanKkmDetailScreen> createState() => _LoanKkmDetailScreenState();
}

class _LoanKkmDetailScreenState extends State<LoanKkmDetailScreen> {
  static const Color headerNavy = Color(0xFF102A43);
  static const Color activeBlue = Color(0xFF114B8E);
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;

  late int _selectedLoanIndex;
  late int _selectedTabIndex;

  @override
  void initState() {
    super.initState();
    _selectedLoanIndex = widget.initialLoanIndex.clamp(0, widget.kkmLoans.length - 1);
    _selectedTabIndex = widget.initialTabIndex.clamp(0, 1);
  }

  LoanKkmBundle get _current => widget.kkmLoans[_selectedLoanIndex];

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.kkmLoans.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: Column(
        children: [
          // Dark Navy Header (matching PDF Pages 2-4)
          Container(
            color: headerNavy,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pinjaman KKM',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$activeCount pinjaman aktif',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  // Top Tab Switcher: Pinjaman | Bayar & Hadir
                  Row(
                    children: [
                      Expanded(child: _buildMainTabButton(0, 'Pinjaman')),
                      const SizedBox(width: 10),
                      Expanded(child: _buildMainTabButton(1, 'Bayar & Hadir')),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (widget.kkmLoans.length > 1 && _selectedTabIndex == 0) ...[
                    _buildLoanSelectorRow(),
                    const SizedBox(height: 12),
                  ],

                  if (widget.kkmLoans.length > 1 && _selectedTabIndex == 1) ...[
                    _buildCompactLoanChips(),
                    const SizedBox(height: 10),
                  ],

                  Expanded(
                    child: _selectedTabIndex == 0
                        ? _buildPinjamanTab()
                        : _buildBayarHadirTab(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTabButton(int index, String label) {
    final isSelected = _selectedTabIndex == index;
    return Material(
      color: isSelected ? activeBlue : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? activeBlue : borderLight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : titleDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoanSelectorRow() {
    return Row(
      children: List.generate(widget.kkmLoans.length, (idx) {
        final bundle = widget.kkmLoans[idx];
        final isSelected = idx == _selectedLoanIndex;
        final jenis = (bundle.kkm['jenis'] ?? bundle.detail['jenis_kkm'] ?? '').toString().toLowerCase();
        final title = jenis == 'kilat' ? 'KILAT KKM' : 'KKM Reguler';
        final plafon = Money.tryParse(bundle.detail['plafon'] ?? bundle.account['plafon']) ?? Money.zero();

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: idx < widget.kkmLoans.length - 1 ? 10 : 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _selectedLoanIndex = idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFEAF7EE) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF4CAF50) : borderLight,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: titleDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.formatRupiah(plafon),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCompactLoanChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(widget.kkmLoans.length, (idx) {
          final bundle = widget.kkmLoans[idx];
          final isSelected = idx == _selectedLoanIndex;
          final jenis = (bundle.kkm['jenis'] ?? bundle.detail['jenis_kkm'] ?? '').toString().toLowerCase();
          final title = jenis == 'kilat' ? 'KILAT KKM' : 'KKM Reguler';
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? const Color(0xFF15803D) : titleDark,
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFFEAF7EE),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? const Color(0xFF4CAF50) : borderLight,
              ),
              onSelected: (_) => setState(() => _selectedLoanIndex = idx),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPinjamanTab() {
    final detail = _current.detail;
    final kkm = _current.kkm;
    final jenis = (kkm['jenis'] ?? detail['jenis_kkm'] ?? '').toString().toLowerCase();
    final isKilat = jenis == 'kilat';

    final setoran = _asMap(kkm['setoran']);
    final tunggakan = _asMap(setoran['tunggakan']);
    final tunggakKali = _asInt(tunggakan['kali']);
    final tunggakNominal = Money.tryParse(tunggakan['nominal']) ?? Money.zero();

    final progres = _asMap(detail['progres']);
    final plafon = Money.tryParse(detail['plafon'] ?? _current.account['plafon']) ?? Money.zero();
    final setoranNominal = Money.tryParse(setoran['nominal'] ?? _asMap(kkm['minggu_ini'])['setoran']);
    final jumlahKali = _asInt(setoran['jumlah']);
    final sudahKali = _asInt(setoran['sudah']);
    final sisaKali = _asInt(setoran['sisa']);
    final sisaUang = Money.tryParse(progres['sisa_tagihan'] ?? detail['baki_debet']) ?? Money.zero();

    final pinjamanObj = _asMap(kkm['pinjaman']);
    final tglCair = _formatShortDate(pinjamanObj['tanggal_cair']);
    final tglLunas = _formatShortDate(detail['tanggal_jatuh_tempo']);
    final angsuranBulanan = Money.tryParse(detail['angsuran']);
    final jatuhTempoBerikut = _formatDayOnly(detail['jatuh_tempo_berikutnya']);
    final sebelumnya = _asList(pinjamanObj['sebelumnya']);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderLight),
          ),
          child: Column(
            children: [
              // Status row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: tunggakKali > 0
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tunggakKali > 0
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 14,
                            color: tunggakKali > 0
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFF15803D),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tunggakKali > 0 ? 'Ada tunggakan' : 'Bayar tepat waktu',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: tunggakKali > 0
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 18, color: Color(0xFFF1F5F9)),
              _buildDetailRow(
                'Pinjaman',
                CurrencyFormatter.formatRupiah(plafon),
                subValue: isKilat ? 'bunga dipotong saat cair' : null,
              ),
              const Divider(height: 18, color: Color(0xFFF1F5F9)),
              _buildDetailRow(
                'Bayar tiap minggu',
                setoranNominal != null
                    ? '${CurrencyFormatter.formatRupiah(setoranNominal)} × $jumlahKali kali'
                    : '$jumlahKali kali',
              ),
              const Divider(height: 18, color: Color(0xFFF1F5F9)),
              _buildDetailRow('Sudah / sisa bayar', '$sudahKali / $sisaKali kali'),
              const Divider(height: 18, color: Color(0xFFF1F5F9)),
              _buildDetailRow(
                'Tunggakan',
                tunggakKali > 0
                    ? '$tunggakKali kali • ${CurrencyFormatter.formatRupiah(tunggakNominal)}'
                    : 'Tidak ada',
                valueColor: tunggakKali > 0 ? const Color(0xFFB91C1C) : titleDark,
              ),
              const Divider(height: 18, color: Color(0xFFF1F5F9)),
              _buildDetailRow(
                'Sisa uang yang dibayar',
                CurrencyFormatter.formatRupiah(sisaUang),
              ),
              const Divider(height: 18, color: Color(0xFFF1F5F9)),
              _buildDetailRow('Cair → lunas', '$tglCair → $tglLunas'),
              if (angsuranBulanan != null) ...[
                const Divider(height: 18, color: Color(0xFFF1F5F9)),
                _buildDetailRow(
                  'Angsuran bulanan',
                  jatuhTempoBerikut != '-'
                      ? 'Tiap tgl $jatuhTempoBerikut • ${CurrencyFormatter.formatRupiah(angsuranBulanan)}'
                      : CurrencyFormatter.formatRupiah(angsuranBulanan),
                ),
              ],
            ],
          ),
        ),

        if (sebelumnya.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...sebelumnya.map((prev) {
            final ke = prev['pinjaman_ke']?.toString() ?? '-';
            final prevPlafon = Money.tryParse(prev['plafon']) ?? Money.zero();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderLight),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sebelumnya: pinjaman ke-$ke • ${CurrencyFormatter.formatRupiah(prevPlafon)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Lunas',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: titleDark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildBayarHadirTab() {
    final kkm = _current.kkm;
    final detail = _current.detail;
    final setoran = _asMap(kkm['setoran']);
    final tunggakan = _asMap(setoran['tunggakan']);
    final kehadiran = _asMap(kkm['kehadiran']);
    final mingguIni = _asMap(kkm['minggu_ini']);
    final mingguan = _asList(kkm['mingguan']);

    final sudahKali = _asInt(setoran['sudah']);
    final tunggakKali = _asInt(tunggakan['kali']);
    final sisaKali = _asInt(setoran['sisa']);
    final hadir = _asInt(kehadiran['hadir']);
    final izin = _asInt(kehadiran['izin']);
    final tidakHadir = _asInt(kehadiran['tidak_hadir']);
    final dari = _asInt(kehadiran['dari']);
    final tglLunas = _formatShortDate(detail['tanggal_jatuh_tempo']);
    final currentWeekNo = mingguIni['minggu_ke'];

    return Column(
      children: [
        // 3 Metric Boxes
        Row(
          children: [
            Expanded(
              child: _buildMetricBox(
                value: '$sudahKali kali',
                label: 'Sudah bayar',
                bg: const Color(0xFFEAF7EE),
                textColor: const Color(0xFF15803D),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricBox(
                value: '$tunggakKali kali',
                label: 'Tunggakan',
                bg: const Color(0xFFFDECEC),
                textColor: const Color(0xFFB91C1C),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricBox(
                value: dari > 0 ? '$hadir/$dari' : '–',
                label: 'Hadir',
                bg: const Color(0xFFEAF7EE),
                textColor: const Color(0xFF15803D),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Sisa $sisaKali kali • Lunas $tglLunas • Izin $izin • Tidak hadir $tidakHadir',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 12),

        // Weekly Table Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bayar dan hadir tiap minggu',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: titleDark,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text('Ke-', style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: textMuted)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Tanggal', style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: textMuted)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Bayar', style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: textMuted)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Hadir', style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: textMuted)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 10, color: borderLight),
                Expanded(
                  child: mingguan.isEmpty
                      ? Center(
                          child: Text(
                            'Belum ada jadwal mingguan',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: mingguan.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (_, i) {
                            final row = mingguan[i];
                            final ke = row['minggu_ke'];
                            final tgl = _formatShortDate(row['tanggal']);
                            final status = (row['status'] ?? '').toString().toLowerCase();
                            final setoranAmt = Money.tryParse(row['setoran']) ?? Money.zero();
                            final hadirMap = row['hadir'] is Map
                                ? Map<String, dynamic>.from(row['hadir'] as Map)
                                : null;
                            final isThisWeek = currentWeekNo != null && ke == currentWeekNo;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 34,
                                    child: Text(
                                      '${ke ?? '-'}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: titleDark,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      tgl,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: titleDark,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: _buildPayStatusWidget(status, setoranAmt, isThisWeek),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: _buildAttendanceWidget(hadirMap),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Geser ke atas: minggu lalu • ke bawah: minggu depan',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildPayStatusWidget(String status, Money setoranAmt, bool isThisWeek) {
    if (status == 'sudah') {
      return _pill('Sudah', const Color(0xFFDCFCE7), const Color(0xFF15803D));
    }
    if (status == 'belum') {
      return _pill('Tunggak', const Color(0xFFFEE2E2), const Color(0xFFB91C1C));
    }
    if (isThisWeek) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pill('Minggu ini', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
          const SizedBox(height: 2),
          Text(
            CurrencyFormatter.formatRupiah(setoranAmt),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: titleDark,
            ),
          ),
        ],
      );
    }
    return Text(
      CurrencyFormatter.formatRupiah(setoranAmt),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: textMuted,
      ),
    );
  }

  Widget _buildAttendanceWidget(Map<String, dynamic>? hadirMap) {
    if (hadirMap == null) {
      return Text('–', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted));
    }
    final status = (hadirMap['status'] ?? '').toString().toLowerCase();
    if (status == 'hadir') {
      return _pill('Hadir', const Color(0xFFDCFCE7), const Color(0xFF15803D));
    }
    if (status == 'izin') {
      return _pill('Izin', const Color(0xFFFEF3C7), const Color(0xFFB45309));
    }
    if (status == 'tidak_hadir') {
      return _pill('Tidak hadir', const Color(0xFFFEE2E2), const Color(0xFFB91C1C));
    }
    return _pill('Tidak ditagih', const Color(0xFFE2E8F0), titleDark);
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildMetricBox({
    required String value,
    required String label,
    required Color bg,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    String? subValue,
    Color valueColor = titleDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  ),
                ),
                if (subValue != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subValue,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<Map<String, dynamic>> _asList(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  int _asInt(dynamic v) => int.tryParse((v ?? '0').toString()) ?? 0;

  String _formatShortDate(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return '-';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} $yy';
  }

  String _formatDayOnly(dynamic raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw.toString().trim());
    if (dt == null) return '-';
    return '${dt.day}';
  }
}
