import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';
import 'deposit_application_bottom_sheet.dart';
import 'deposit_detail_screen.dart';

class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _deposits = [];
  List<Map<String, dynamic>> _applications = [];
  bool _isLoadingApps = false;
  int _activeMainTab = 0; // 0: Deposito Saya, 1: Riwayat Pengajuan
  int _selectedFilterIndex = 0; // 0: Semua, 1: Aktif, 2: Non-Aktif / Lainnya

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
        if (mounted) {
          setState(() {
            _deposits = [];
            _isLoading = false;
          });
        }
        return;
      }

      if (!mounted) return;
      final repo = context.read<AccountRepository>();
      final items = await repo.getDeposits(cifNumber: cif);

      if (mounted) {
        setState(() {
          _deposits = items;
          _isLoading = false;
        });
      }
      _fetchApplications();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiException.humanize(
            e,
            fallback: 'Layanan sedang mengalami gangguan. Silakan coba kembali beberapa saat lagi.',
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchApplications() async {
    if (!mounted) return;
    setState(() => _isLoadingApps = true);
    try {
      final repo = context.read<AccountRepository>();
      final allApps = await repo.getProductApplications();
      final depositApps = allApps.where((a) {
        final t = (a['product_type'] ?? '').toString().toUpperCase();
        return t == 'DEPOSITO' || t == 'PENCAIRAN_DEPOSITO';
      }).toList();
      if (mounted) {
        setState(() {
          _applications = depositApps;
          _isLoadingApps = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingApps = false);
      }
    }
  }

  void _showToast(String message) {
    AppToast.showSuccess(context, message);
  }

  String _field(Map<String, dynamic> item, List<String> keys) {
    for (final k in keys) {
      final v = item[k];
      if (v != null && v.toString().trim().isNotEmpty && v.toString().trim() != 'null') {
        return v.toString();
      }
    }
    return '-';
  }

  void _showDepositDetailSheet(BuildContext context, Map<String, dynamic> initialItem) {
    final accNo = initialItem['nomor_rekening']?.toString() ?? '-';
    final repo = context.read<AccountRepository>();
    final Future<Map<String, dynamic>?> detailFuture = (accNo != '-' && accNo.isNotEmpty)
        ? repo.getDepositDetail(accNo).catchError((_) => null)
        : Future.value(null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FutureBuilder<Map<String, dynamic>?>(
        future: detailFuture,
        builder: (ctx, snapshot) {
          final item = {
            ...initialItem,
            if (snapshot.data != null) ...snapshot.data!,
          };
          final isLoadingDetail = snapshot.connectionState == ConnectionState.waiting;
          final prodName = _field(item, ['nama_produk', 'produk']);
          final nominal = Money.tryParse(item['nominal']);
          final rateVal = item['suku_bunga_tahunan'] ?? item['suku_bunga'];
          final rate = rateVal != null && rateVal.toString().isNotEmpty ? '$rateVal% p.a.' : '-';
          final jatuhTempo = _field(item, ['tanggal_jatuh_tempo', 'tgl_jatuh_tempo']);
          final statusKet = _field(item, ['status_rekening_keterangan', 'status']);
          final isAktif = statusKet.toLowerCase() == 'aktif';
          final canCopy = accNo.isNotEmpty && accNo != '-';

          return SafeArea(
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
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.successBorder),
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
                  if (isLoadingDetail) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(
                      minHeight: 2,
                      color: royalBlue,
                      backgroundColor: borderLight,
                    ),
                  ],
                  const SizedBox(height: 18),
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
                        _buildModalRow('Nomor Bilyet', _field(item, ['nomor_bilyet', 'no_bilyet'])),
                        _buildModalRow('Sistem Perpanjangan', _field(item, ['jenis_aro', 'instruksi_aro'])),
                        _buildModalRow('Rekening Pencairan', _field(item, ['rekening_pencairan_bunga', 'rekening_pencairan'])),
                        _buildModalRow('Kantor Pelayanan', _field(item, ['nama_kantor', 'kantor'])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (canCopy)
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
          );
        },
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
    Money? totalDana = const Money.zero();
    int countAktif = 0;
    int countLainnya = 0;

    for (final item in _deposits) {
      final nominal = Money.tryParse(item['nominal']);
      totalDana = (totalDana == null || nominal == null) ? null : totalDana + nominal;
      final status = item['status_rekening_keterangan']?.toString().toLowerCase() ?? '';
      if (status == 'aktif') {
        countAktif++;
      } else {
        countLainnya++;
      }
    }

    final filteredList = _deposits.where((item) {
      final status = item['status_rekening_keterangan']?.toString().toLowerCase() ?? '';
      if (_selectedFilterIndex == 1) return status == 'aktif';
      if (_selectedFilterIndex == 2) return status != 'aktif';
      return true;
    }).toList();

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Clean Header Row
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AuthUiTokens.inputBorder),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 17,
                          color: AuthUiTokens.deepCobalt,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Portofolio Deposito',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AuthUiTokens.titleDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _activeMainTab == 0 ? _fetchDepositData : _fetchApplications,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AuthUiTokens.inputBorder),
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          size: 19,
                          color: AuthUiTokens.deepCobalt,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Tab Switcher: Deposito Saya vs Riwayat Pengajuan
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderLight),
                ),
                child: Row(
                  children: [
                    _buildMainTabItem(0, 'Deposito Saya', _deposits.length),
                    _buildMainTabItem(1, 'Riwayat Pengajuan', _applications.length),
                  ],
                ),
              ),
            ),

            if (_activeMainTab == 1)
              Expanded(child: _buildApplicationsHistoryView())
            else
              Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchDepositData,
                color: const Color(0xFF033172),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF033172)),
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
                                      backgroundColor: const Color(0xFF033172),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.lock_outline_rounded, size: 34, color: Color(0xFF0F9D76)),
                                      ),
                                      const SizedBox(height: 18),
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
                                        'Buka bilyet deposito berjangka dengan suku bunga kompetitif dan dijamin oleh LPS.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted, height: 1.4),
                                      ),
                                      const SizedBox(height: 22),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF033172),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                        onPressed: () => DepositApplicationBottomSheet.show(context, onSuccess: _fetchDepositData),
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        label: Text(
                                          'Buka Deposito Baru',
                                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
                                children: [
                                  _buildSummaryBanner(totalDana, countAktif),
                                  const SizedBox(height: 16),

                                  if (countLainnya > 0) ...[
                                    _buildFilterTabs(_deposits.length, countAktif, countLainnya),
                                    const SizedBox(height: 14),
                                  ],

                                  ...filteredList.map((item) => _buildDepositCard(item)),

                                  const SizedBox(height: 6),
                                  Text(
                                    'Simpanan dijamin LPS sesuai ketentuan yang berlaku.',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: textMuted,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
              ),
            ),
            if (_activeMainTab == 0 && !_isLoading && _errorMessage == null && _deposits.isNotEmpty)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => DepositApplicationBottomSheet.show(
                        context,
                        onSuccess: _fetchDepositData,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF033172),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(
                        'Buka Deposito',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBanner(Money? totalDana, int activeCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF033172),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF033172).withOpacity(0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total deposito',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.80),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            CurrencyFormatter.formatRupiah(totalDana),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$activeCount deposito aktif',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(int all, int aktif, int lainnya) {
    return Row(
      children: [
        _buildFilterChip(0, 'Semua ($all)'),
        const SizedBox(width: 8),
        _buildFilterChip(1, 'Aktif ($aktif)'),
        const SizedBox(width: 8),
        _buildFilterChip(2, 'Lainnya ($lainnya)'),
      ],
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8.5, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF033172) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : titleDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepositCard(Map<String, dynamic> item) {
    final prodName = item['nama_produk']?.toString() ?? '-';
    final nominal = Money.tryParse(item['nominal']);
    final jatuhTempo = item['tanggal_jatuh_tempo']?.toString() ?? '-';
    final statusKet = item['status_rekening_keterangan']?.toString() ?? '';
    final isAktif = statusKet.toLowerCase() == 'aktif';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () async {
            final res = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DepositDetailScreen(initialItem: item),
              ),
            );
            if (res == true && mounted) {
              _fetchDepositData();
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isAktif ? const Color(0xFFDDF7EC) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: isAktif ? const Color(0xFF0F9D76) : textMuted,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prodName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Jatuh tempo $jatuhTempo',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  CurrencyFormatter.formatRupiah(nominal),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: titleDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainTabItem(int index, String label, int count) {
    final isSelected = _activeMainTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeMainTab = index);
          if (index == 1 && _applications.isEmpty && !_isLoadingApps) {
            _fetchApplications();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF033172) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : textMuted,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.22)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : titleDark,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplicationsHistoryView() {
    if (_isLoadingApps && _applications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF033172)),
            SizedBox(height: 16),
            Text('Memuat riwayat pengajuan...', style: TextStyle(color: textMuted)),
          ],
        ),
      );
    }

    if (_applications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchApplications,
        color: const Color(0xFF033172),
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 48),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.history_rounded, size: 34, color: Color(0xFF033172)),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Belum Ada Riwayat Pengajuan',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pengajuan pembukaan maupun pencairan deposito Anda akan tampil di sini.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: textMuted, height: 1.4),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchApplications,
      color: const Color(0xFF033172),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
        itemCount: _applications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _buildApplicationCard(_applications[index]),
      ),
    );
  }

  Widget _buildApplicationCard(Map<String, dynamic> app) {
    final productType = (app['product_type'] ?? '').toString().toUpperCase();
    final isDisbursement = productType == 'PENCAIRAN_DEPOSITO';
    final status = (app['status'] ?? 'PENDING').toString().toUpperCase();
    final productName = (app['product_name'] ?? 'Deposito').toString();
    final purpose = (app['purpose_or_source'] ?? '').toString().trim();
    final adminNotes = (app['admin_notes'] ?? '').toString().trim();
    final amount = Money.tryParse(app['amount']) ?? Money.zero();
    final tenor = app['tenor_months']?.toString() ?? '-';
    final rate = (app['interest_rate'] ?? '').toString().trim();
    final createdAt = _formatAppDate(app['created_at']);

    Color statusBg = const Color(0xFFFEF3C7);
    Color statusText = const Color(0xFFB45309);
    String statusLabel = 'Menunggu';
    if (status == 'CONTACTED') {
      statusBg = const Color(0xFFDBEAFE);
      statusText = const Color(0xFF1D4ED8);
      statusLabel = 'Diproses CS';
    } else if (status == 'APPROVED') {
      statusBg = const Color(0xFFDCFCE7);
      statusText = const Color(0xFF15803D);
      statusLabel = 'Disetujui';
    } else if (status == 'REJECTED') {
      statusBg = const Color(0xFFFEE2E2);
      statusText = const Color(0xFFB91C1C);
      statusLabel = 'Ditolak';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: isDisbursement ? const Color(0xFFEEF2FF) : const Color(0xFFE6F4F1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  isDisbursement ? 'PENCAIRAN DEPOSITO' : 'PEMBUKAAN DEPOSITO',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isDisbursement ? const Color(0xFF4338CA) : const Color(0xFF0F766E),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: statusText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            productName,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: titleDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${CurrencyFormatter.formatRupiah(amount)} • Tenor $tenor Bln${rate.isNotEmpty && rate != '-' ? ' ($rate)' : ''}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF033172),
            ),
          ),
          if (purpose.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgCanvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                purpose,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: titleDark,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (adminNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Catatan Bank: "$adminNotes"',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: textMuted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Diajukan: $createdAt',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAppDate(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
  }
}
