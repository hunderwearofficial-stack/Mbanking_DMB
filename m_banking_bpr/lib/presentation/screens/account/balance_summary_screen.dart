import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../../widgets/auth_ui_kit.dart';
import '../../widgets/empty_state_view.dart';

class BalanceSummaryScreen extends StatefulWidget {
  const BalanceSummaryScreen({super.key});

  @override
  State<BalanceSummaryScreen> createState() => _BalanceSummaryScreenState();
}

class _BalanceSummaryScreenState extends State<BalanceSummaryScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = Color(0xFFE2E8F0);

  bool _isLoading = true;
  bool _hideBalances = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _accounts = [];

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
  }

  Future<void> _fetchAccounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authState = context.read<AuthCubit>().state;
      String? cif;
      if (authState is AuthAuthenticated) cif = authState.user.cif;
      if (cif == null || cif.isEmpty) {
        cif = await context.read<AuthCubit>().authRepository.secureStorage.getCIF();
      }
      if (!mounted) return;
      if (cif == null || cif.isEmpty) {
        setState(() {
          _accounts = [];
          _isLoading = false;
        });
        return;
      }
      final list = await context.read<AccountRepository>().getSavingsAccounts(cifNumber: cif);
      if (mounted) {
        setState(() {
          _accounts = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiException.humanize(e, fallback: 'Gagal memuat ringkasan saldo.');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeAccounts = _accounts.where((a) {
      final status = (a['status_rekening_keterangan'] ?? '').toString().toLowerCase();
      final code = int.tryParse((a['status_rekening'] ?? '1').toString()) ?? 1;
      return status == 'aktif' || code == 1;
    }).toList();
    final listToShow = activeAccounts.isNotEmpty ? activeAccounts : _accounts;

    Money totalSaldo = Money.zero();
    for (final acc in listToShow) {
      totalSaldo = totalSaldo + (Money.tryParse(acc['saldo']) ?? Money.zero());
    }

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DmbPageHeader(
              title: 'Informasi Saldo',
              subtitle: 'Ringkasan seluruh rekening tabungan',
              actionIcon: _hideBalances ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              onAction: () => setState(() => _hideBalances = !_hideBalances),
            ),
            Expanded(
              child: RefreshIndicator(
        onRefresh: _fetchAccounts,
        color: primaryNavy,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryNavy))
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(onPressed: _fetchAccounts, child: const Text('Coba Lagi')),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Summary Header Panel
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: primaryNavy,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Saldo Aktif (${listToShow.length} rekening)',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.78),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() => _hideBalances = !_hideBalances),
                                  child: Icon(
                                    _hideBalances ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    size: 18,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _hideBalances ? 'Rp ••••••••' : CurrencyFormatter.formatRupiah(totalSaldo),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 8),
                        child: Text(
                          'DAFTAR REKENING',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: textMuted,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderLight),
                        ),
                        child: listToShow.isEmpty
                            ? const EmptyStateView(
                                icon: Icons.account_balance_wallet_outlined,
                                title: 'Belum Ada Rekening Aktif',
                                subtitle: 'Rekening tabungan aktif Anda akan tampil di halaman ini.',
                              )
                            : Column(
                                children: List.generate(listToShow.length, (i) {
                                  final acc = listToShow[i];
                                  final prodName = (acc['nama_produk'] ?? 'Tabungan DMB').toString();
                                  final accNo = (acc['nomor_rekening'] ?? '-').toString();
                                  final saldo = Money.tryParse(acc['saldo']) ?? Money.zero();
                                  final blokir = Money.tryParse(acc['saldo_blokir']) ?? Money.zero();

                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    prodName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: titleDark,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    accNo,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 12,
                                                      color: textMuted,
                                                    ),
                                                  ),
                                                  if (!blokir.isZero && !_hideBalances) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Saldo blokir: ${CurrencyFormatter.formatRupiah(blokir)}',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 11,
                                                        color: const Color(0xFFB45309),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              _hideBalances ? 'Rp ••••••' : CurrencyFormatter.formatRupiah(saldo),
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: primaryNavy,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (i < listToShow.length - 1)
                                        const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                                    ],
                                  );
                                }),
                              ),
                      ),
                    ],
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
