import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/product_rates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';

class ProductCatalogScreen extends StatefulWidget {
  final int initialTabIndex;
  final bool isTab;

  const ProductCatalogScreen({
    super.key,
    this.initialTabIndex = 0,
    this.isTab = false,
  });

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> with SingleTickerProviderStateMixin {
  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;
  static const Color bgCanvas = AppColors.bgCanvas;

  late TabController _tabController;
  int _selectedSegment = 0;
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _catalog;

  @override
  void initState() {
    super.initState();
    _selectedSegment = widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _selectedSegment,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() => _selectedSegment = _tabController.index);
      }
    });
    _loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = context.read<AccountRepository>();
      final catalog = await repo.getProductsCatalog();
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _isLoading = false;
        });
      }
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

  void _showProductDetail(Map<String, dynamic> item, String category) {
    final code = item['kode_produk']?.toString() ?? '-';
    final name = item['nama_produk']?.toString() ?? 'Produk Bank DMB';
    final bool isDeposito = category.toLowerCase() == 'deposito';
    final bool isKredit = category.toLowerCase() == 'kredit' || category.toLowerCase() == 'pinjaman';

    final defaultDesc = isKredit
        ? 'Fasilitas pembiayaan resmi ${DynamicConfigService().config.bankName} yang berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK).'
        : 'Produk simpanan perbankan ${DynamicConfigService().config.bankName} (diawasi OJK). Simpanan dijamin LPS sesuai ketentuan yang berlaku.';
    final desc = item['deskripsi']?.toString() ?? defaultDesc;

    final rateInfo = isDeposito
        ? ProductRates.depositoLabel
        : isKredit
            ? ProductRates.kreditLabel
            : 'Sesuai ketentuan bank (hubungi CS)';

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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryNavy, royalBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        code,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isKredit ? AppColors.primaryLight : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isKredit
                                ? 'Produk Resmi Bank DMB • Diawasi OJK'
                                : 'Produk Resmi Bank DMB • Dijamin LPS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AuthUiTokens.deepCobalt,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: borderLight),
              const SizedBox(height: 14),
              Text(
                'Deskripsi Produk',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: textMuted,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                desc,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: titleDark,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgCanvas,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderLight),
                ),
                child: Column(
                  children: [
                    _buildModalRow('Kode Produk Resmi', code),
                    _buildModalRow(
                      'Kategori',
                      isDeposito
                          ? 'Deposito Berjangka'
                          : isKredit
                              ? 'Fasilitas Pembiayaan / Pinjaman'
                              : 'Tabungan Perorangan',
                    ),
                    _buildModalRow('Lembaga Pengawas', 'Otoritas Jasa Keuangan (OJK)'),
                    if (!isKredit)
                      _buildModalRow('Penjaminan Simpanan', 'Lembaga Penjamin Simpanan (LPS)'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Tutup',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
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
      padding: const EdgeInsets.symmetric(vertical: 4.5),
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
    final List tabunganList = _catalog?['tabungan'] as List? ?? [];
    final List depositoList = _catalog?['deposito'] as List? ?? [];
    final List kreditList = _catalog?['kredit'] as List? ?? [];

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DmbPageHeader(
              title: widget.isTab ? 'Produk Saya' : 'Katalog Produk',
              subtitle: 'Tabungan, Deposito Berjangka & Pembiayaan DMB',
              showBack: !widget.isTab,
              actionIcon: Icons.refresh_rounded,
              onAction: _loadProducts,
            ),

            // 3-Segment Control: Tabungan | Deposit | Kredit
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8EEF6)),
                  boxShadow: [
                    BoxShadow(
                      color: AuthUiTokens.royalBlue.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildSegmentTab(0, 'Tabungan'),
                    _buildSegmentTab(1, 'Deposit'),
                    _buildSegmentTab(2, 'Kredit'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AuthUiTokens.deepCobalt),
                          SizedBox(height: 16),
                          Text('Memuat katalog produk resmi...', style: TextStyle(color: textMuted)),
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
                                  onPressed: _loadProducts,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AuthUiTokens.deepCobalt,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  ),
                                  child: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildCategoryList(tabunganList, 'tabungan', 'Belum ada produk tabungan'),
                            _buildCategoryList(depositoList, 'deposito', 'Belum ada produk deposito'),
                            _buildCategoryList(kreditList, 'kredit', 'Belum ada produk kredit'),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentTab(int index, String label) {
    final isSelected = _selectedSegment == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _selectedSegment = index);
          _tabController.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AuthUiTokens.deepCobalt : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AuthUiTokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList(List rawList, String category, String emptyText) {
    final items = rawList.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadProducts,
        color: AuthUiTokens.deepCobalt,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 60),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AuthUiTokens.softBlueBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_outlined, size: 30, color: AuthUiTokens.royalBlue),
            ),
            const SizedBox(height: 14),
            Text(
              emptyText,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: AuthUiTokens.deepCobalt,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, idx) => _buildProductCard(items[idx], category, idx),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item, String category, int categoryIndex) {
    final name = item['nama_produk']?.toString() ?? 'Produk DMB';
    final desc = item['deskripsi']?.toString() ??
        'Produk resmi ${DynamicConfigService().config.bankName} berizin Otoritas Jasa Keuangan.';

    final bool isDeposito = category.toLowerCase() == 'deposito';
    final bool isKredit = category.toLowerCase() == 'kredit' || category.toLowerCase() == 'pinjaman';

    final IconData iconData;
    if (isDeposito) {
      iconData = Icons.trending_up_rounded;
    } else if (isKredit) {
      iconData = Icons.account_balance_wallet_rounded;
    } else {
      iconData = Icons.savings_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: AuthUiTokens.royalBlue.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showProductDetail(item, category),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AuthUiTokens.softBlueBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, color: AuthUiTokens.deepCobalt, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AuthUiTokens.titleDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Pelajari',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AuthUiTokens.royalBlue,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AuthUiTokens.royalBlue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
