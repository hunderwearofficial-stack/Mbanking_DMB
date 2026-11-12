import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/account_repository.dart';
import 'product_simulator_sheet.dart';

class ProductCatalogScreen extends StatefulWidget {
  final int initialTabIndex;

  const ProductCatalogScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> with SingleTickerProviderStateMixin {
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

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
          _errorMessage = 'Gagal memuat katalog produk perbankan';
          _isLoading = false;
        });
      }
    }
  }

  void _showProductDetail(Map<String, dynamic> item, String category) {
    final code = item['kode_produk']?.toString() ?? '-';
    final name = item['nama_produk']?.toString() ?? 'Produk Bank DMB';
    final desc = item['deskripsi']?.toString() ??
        'Produk resmi perbankan PT BPR Dana Mandiri Bogor yang telah terdaftar dan diawasi oleh OJK serta dijamin oleh LPS.';

    final bool isDeposito = category.toLowerCase() == 'deposito';
    final bool isKredit = category.toLowerCase() == 'kredit' || category.toLowerCase() == 'pinjaman';

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
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Produk Resmi Bank DMB • Dijamin LPS',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: dmbGreen,
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
                  color: const Color(0xFFF8FAFC),
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
                    _buildModalRow(
                      'Suku Bunga / Imbal Hasil',
                      isDeposito
                          ? 's.d 6.25% p.a.'
                          : isKredit
                              ? 'Mulai 1.25% flat / bln'
                              : 'Kompetitif Berjenjang',
                      isHighlight: true,
                    ),
                    _buildModalRow('Lembaga Pengawas', 'Otoritas Jasa Keuangan (OJK)'),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Untuk pembukaan rekening $name, silakan kunjungi kantor operasional Bank DMB terdekat atau hubungi Petugas CS.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
                          ),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: primaryNavy,
                        ),
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
    final List kreditList = _catalog?['kredit'] as List? ?? [];
    final List depositoList = _catalog?['deposito'] as List? ?? [];

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
              'Katalog Produk Resmi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'PORTOFOLIO PERBANKAN RESMI',
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
            onPressed: _loadProducts,
            tooltip: 'Perbarui Katalog',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      // Banner Eksekutif Katalog Produk Bank DMB
                      _buildSummaryBanner(
                        tabunganCount: tabunganList.length,
                        kreditCount: kreditList.length,
                        depositoCount: depositoList.length,
                      ),
                      const SizedBox(height: 20),

                      // Tab Filter Kategori Produk
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: Colors.white,
                          unselectedLabelColor: textMuted,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [primaryNavy, royalBlue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: royalBlue.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          labelStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: [
                            Tab(text: 'Tabungan (${tabunganList.length})'),
                            Tab(text: 'Pinjaman (${kreditList.length})'),
                            Tab(text: 'Deposito (${depositoList.length})'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Daftar Produk Berdasarkan Tab yang Aktif
                      AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) {
                          switch (_tabController.index) {
                            case 1:
                              return _buildCategoryView(
                                title: 'Fasilitas Pinjaman & Pembiayaan',
                                badge: 'Kredit Resmi OJK',
                                items: kreditList,
                                category: 'kredit',
                              );
                            case 2:
                              return _buildCategoryView(
                                title: 'Portofolio Deposito Berjangka',
                                badge: 'Bunga s.d 6.25% p.a.',
                                items: depositoList,
                                category: 'deposito',
                              );
                            case 0:
                            default:
                              return _buildCategoryView(
                                title: 'Portofolio Tabungan Perorangan',
                                badge: 'Dijamin LPS',
                                items: tabunganList,
                                category: 'tabungan',
                              );
                          }
                        },
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSummaryBanner({
    required int tabunganCount,
    required int kreditCount,
    required int depositoCount,
  }) {
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
            'KATALOG PRODUK BANK DMB',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Simpanan & Pembiayaan Terpercaya',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Produk perbankan resmi berizin OJK dengan suku bunga kompetitif dan jaminan keamanan LPS.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: Colors.white.withOpacity(0.85),
              height: 1.4,
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBannerStatItem(Icons.savings_rounded, '$tabunganCount Produk', 'Tabungan'),
                Container(width: 1, height: 26, color: Colors.white.withOpacity(0.25)),
                _buildBannerStatItem(Icons.payments_rounded, '$kreditCount Produk', 'Pinjaman'),
                Container(width: 1, height: 26, color: Colors.white.withOpacity(0.25)),
                _buildBannerStatItem(Icons.inventory_2_rounded, '$depositoCount Produk', 'Deposito'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerStatItem(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: Colors.white.withOpacity(0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryView({
    required String title,
    required String badge,
    required List items,
    required String category,
  }) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 40, color: textMuted),
            const SizedBox(height: 10),
            Text(
              'Belum ada produk dalam kategori ini',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: titleDark,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                badge,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: royalBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map((item) {
          final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
          return _buildProductCard(map, category);
        }),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item, String category) {
    final code = item['kode_produk']?.toString() ?? '-';
    final name = item['nama_produk']?.toString() ?? 'Produk DMB';
    final desc = item['deskripsi']?.toString() ??
        'Produk resmi PT BPR Dana Mandiri Bogor berizin Otoritas Jasa Keuangan.';

    final bool isDeposito = category.toLowerCase() == 'deposito';
    final bool isKredit = category.toLowerCase() == 'kredit' || category.toLowerCase() == 'pinjaman';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showProductDetail(item, category),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDBEAFE)),
                      ),
                      child: Center(
                        child: Text(
                          code,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: royalBlue,
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
                            name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: titleDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.verified_rounded, size: 12, color: dmbGreen),
                              const SizedBox(width: 4),
                              Text(
                                isDeposito
                                    ? 'Dijamin LPS • Bunga 6.00% p.a.'
                                    : isKredit
                                        ? 'Bunga Kompetitif • Fleksibel'
                                        : 'Simpanan Bebas Biaya Admin',
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
                    ),
                    const Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => _showProductDetail(item, category),
                      child: Text(
                        'Lihat Detail & Ketentuan',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: royalBlue,
                        ),
                      ),
                    ),
                    if (isDeposito || isKredit)
                      ElevatedButton(
                        onPressed: () {
                          ProductSimulatorSheet.show(
                            context,
                            initialType: isDeposito ? 'DEPOSITO' : 'PINJAMAN',
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          isDeposito ? 'Simulasi' : 'Ajukan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

