import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/money/money.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/auth_ui_kit.dart';
import '../../widgets/empty_state_view.dart';

class ApplicationStatusScreen extends StatefulWidget {
  const ApplicationStatusScreen({super.key});

  @override
  State<ApplicationStatusScreen> createState() => _ApplicationStatusScreenState();
}

class _ApplicationStatusScreenState extends State<ApplicationStatusScreen> {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = Color(0xFFE2E8F0);

  bool _isLoading = true;
  List<Map<String, dynamic>> _apps = [];
  int _selectedFilter = 0; // 0: Semua, 1: Diajukan, 2: Proses, 3: Selesai

  @override
  void initState() {
    super.initState();
    _fetchApps();
  }

  Future<void> _fetchApps() async {
    setState(() => _isLoading = true);
    try {
      final list = await context.read<AccountRepository>().getProductApplications();
      if (mounted) {
        setState(() {
          _apps = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredApps {
    return _apps.where((a) {
      final s = (a['status'] ?? 'PENDING').toString().toUpperCase();
      if (_selectedFilter == 1) return s == 'PENDING';
      if (_selectedFilter == 2) return s == 'CONTACTED';
      if (_selectedFilter == 3) return s == 'APPROVED' || s == 'REJECTED';
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ['Semua', 'Diajukan', 'Proses', 'Selesai'];
    final items = _filteredApps;

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DmbPageHeader(
              title: 'Status Pengajuan',
              subtitle: 'Pantau progres pengajuan produk Anda',
              actionIcon: Icons.refresh_rounded,
              onAction: _fetchApps,
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: List.generate(filters.length, (idx) {
                final active = _selectedFilter == idx;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = idx),
                    child: Container(
                      margin: EdgeInsets.only(right: idx < filters.length - 1 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? primaryNavy : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        filters[idx],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const Divider(height: 1, color: borderLight),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchApps,
              color: primaryNavy,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: primaryNavy))
                  : items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 36),
                            EmptyStateView(
                              icon: Icons.assignment_outlined,
                              title: 'Belum Ada Pengajuan',
                              subtitle: 'Pengajuan Kredit, Deposito, Tabungan, dan Pencairan Deposito Anda akan tampil di sini.',
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderLight),
                              ),
                              child: Column(
                                children: List.generate(items.length, (i) {
                                  return Column(
                                    children: [
                                      _buildRow(items[i]),
                                      if (i < items.length - 1)
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

  Widget _buildRow(Map<String, dynamic> app) {
    final ptype = (app['product_type'] ?? '').toString().toUpperCase();
    final status = (app['status'] ?? 'PENDING').toString().toUpperCase();
    final productName = (app['product_name'] ?? 'Produk DMB').toString();
    final purpose = (app['purpose_or_source'] ?? '').toString().trim();
    final notes = (app['admin_notes'] ?? '').toString().trim();
    final amount = Money.tryParse(app['amount']) ?? Money.zero();
    final tenor = app['tenor_months']?.toString() ?? '-';

    String typeLabel = 'Kredit';
    if (ptype == 'DEPOSITO') typeLabel = 'Deposito';
    if (ptype == 'PENCAIRAN_DEPOSITO') typeLabel = 'Pencairan Deposito';
    if (ptype == 'TABUNGAN') typeLabel = 'Tabungan';

    String statusLabel = 'Diajukan';
    Color statusBg = const Color(0xFFF1F5F9);
    Color statusFg = titleDark;
    if (status == 'CONTACTED') {
      statusLabel = 'Diproses';
      statusBg = const Color(0xFFDBEAFE);
      statusFg = const Color(0xFF1D4ED8);
    } else if (status == 'APPROVED') {
      statusLabel = 'Selesai';
      statusBg = const Color(0xFFDCFCE7);
      statusFg = const Color(0xFF15803D);
    } else if (status == 'REJECTED') {
      statusLabel = 'Dibatalkan';
      statusBg = const Color(0xFFFEE2E2);
      statusFg = const Color(0xFFB91C1C);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                typeLabel.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: primaryNavy,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.plusJakartaSans(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusFg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            productName,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: titleDark),
          ),
          const SizedBox(height: 2),
          Text(
            ptype == 'TABUNGAN'
                ? 'Setoran Awal: ${CurrencyFormatter.formatRupiah(amount)}'
                : '${CurrencyFormatter.formatRupiah(amount)} • Tenor $tenor Bln',
            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600, color: primaryNavy),
          ),
          if (purpose.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(purpose, style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: textMuted)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Catatan Bank: "$notes"',
              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontStyle: FontStyle.italic, color: titleDark),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _formatDate(app['created_at']),
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw.toString().trim());
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
  }
}
