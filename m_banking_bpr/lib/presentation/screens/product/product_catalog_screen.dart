import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/product_rates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/dynamic_config_service.dart';
import '../../../data/repositories/account_repository.dart';
import '../../widgets/app_validation_feedback.dart';
import 'product_simulator_sheet.dart';

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
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _catalog;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
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
                              color: isKredit ? royalBlue : dmbGreen,
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
                    _buildModalRow('Suku Bunga / Imbal Hasil', rateInfo, isHighlight: true),
                    _buildModalRow('Lembaga Pengawas', 'Otoritas Jasa Keuangan (OJK)'),
                    if (!isKredit)
                      _buildModalRow('Penjaminan Simpanan', 'Lembaga Penjamin Simpanan (LPS)'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (isDeposito || isKredit)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      ProductSimulatorSheet.show(
                        context,
                        initialType: isDeposito ? 'DEPOSITO' : 'PINJAMAN',
                        initialProductName: name,
                      );
                    },
                    icon: Icon(
                      isDeposito ? Icons.calculate_rounded : Icons.request_quote_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isDeposito ? 'Simulasi & Buka Bilyet Deposito' : 'Simulasi & Ajukan Pinjaman',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      AppToast.showInfo(
                        context,
                        'Untuk pembukaan rekening $name, silakan kunjungi kantor operasional Bank DMB terdekat atau hubungi Petugas CS.',
                        title: 'Pembukaan Tabungan',
                      );
                    },
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    label: Text(
                      'Konsultasi Pembukaan Tabungan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
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

    final List<({Map<String, dynamic> item, String category, int index})> allProducts = [
      for (int i = 0; i < tabunganList.length; i++)
        if (tabunganList[i] is Map<String, dynamic>)
          (item: tabunganList[i] as Map<String, dynamic>, category: 'tabungan', index: i),
      for (int i = 0; i < depositoList.length; i++)
        if (depositoList[i] is Map<String, dynamic>)
          (item: depositoList[i] as Map<String, dynamic>, category: 'deposito', index: i),
      for (int i = 0; i < kreditList.length; i++)
        if (kreditList[i] is Map<String, dynamic>)
          (item: kreditList[i] as Map<String, dynamic>, category: 'kredit', index: i),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF033172),
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: widget.isTab ? 20 : 8,
        leadingWidth: widget.isTab ? 0 : 64,
        leading: widget.isTab
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 0.5,
                  shadowColor: Colors.black.withOpacity(0.08),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Center(
                      child: Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF033172)),
                    ),
                  ),
                ),
              ),
        title: Text(
          widget.isTab ? 'Produk Saya' : 'Katalog Produk',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF033172),
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 0.5,
              shadowColor: Colors.black.withOpacity(0.08),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _loadProducts,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF0A2A66)),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        color: primaryNavy,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primaryNavy),
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
                : allProducts.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(32),
                        children: [
                          const SizedBox(height: 60),
                          const Icon(Icons.inventory_2_outlined, size: 48, color: textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'Belum ada produk tersedia',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                        itemCount: allProducts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, idx) {
                          final entry = allProducts[idx];
                          return _buildProductCard(entry.item, entry.category, entry.index);
                        },
                      ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item, String category, int categoryIndex) {
    final name = item['nama_produk']?.toString() ?? 'Produk DMB';
    final desc = item['deskripsi']?.toString() ??
        'Produk resmi ${DynamicConfigService().config.bankName} berizin Otoritas Jasa Keuangan.';

    final bool isDeposito = category.toLowerCase() == 'deposito';
    final bool isKredit = category.toLowerCase() == 'kredit' || category.toLowerCase() == 'pinjaman';

    final Color iconBg;
    final Color iconColor;
    final IconData iconData;
    if (isDeposito) {
      iconBg = const Color(0xFFE6F7F1);
      iconColor = const Color(0xFF0F9D76);
      iconData = Icons.lock_outline_rounded;
    } else if (isKredit) {
      iconBg = const Color(0xFFE0F2FE);
      iconColor = const Color(0xFF0369A1);
      iconData = categoryIndex.isEven ? Icons.person_outline_rounded : Icons.format_list_bulleted_rounded;
    } else {
      iconBg = const Color(0xFFEFF6FF);
      iconColor = const Color(0xFF0A2A66);
      iconData = Icons.account_balance_wallet_outlined;
    }

    return Container(
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
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showProductDetail(item, category),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(iconData, color: iconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0A2A66),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Pelajari',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0A2A66),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFF0A2A66),
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
