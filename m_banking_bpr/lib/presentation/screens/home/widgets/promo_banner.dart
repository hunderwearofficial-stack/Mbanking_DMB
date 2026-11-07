import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/api_endpoints.dart';

class BannerItem {
  final String tag;
  final String title;
  final String highlight;
  final String? badgeText;
  final Color bgColor;
  final Color accentColor;
  final IconData icon;

  const BannerItem({
    required this.tag,
    required this.title,
    required this.highlight,
    this.badgeText,
    required this.bgColor,
    required this.accentColor,
    required this.icon,
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    Color parseHex(String? hex, Color fallback) {
      if (hex == null || hex.isEmpty) return fallback;
      try {
        final buffer = StringBuffer();
        if (hex.length == 6 || hex.length == 7) buffer.write('ff');
        buffer.write(hex.replaceFirst('#', ''));
        return Color(int.parse(buffer.toString(), radix: 16));
      } catch (_) {
        return fallback;
      }
    }

    return BannerItem(
      tag: json['tag'] as String? ?? 'BPR DANA MANDIRI BOGOR',
      title: json['title'] as String? ?? 'PROMOSI SPESIAL DMB',
      highlight: json['highlight'] as String? ?? '',
      badgeText: json['badge_text'] as String?,
      bgColor: parseHex(json['bg_color'] as String?, const Color(0xFF0A3B66)),
      accentColor: parseHex(json['accent_color'] as String?, AppColors.primary),
      icon: _getIconByName(json['icon_name'] as String?),
    );
  }

  static IconData _getIconByName(String? name) {
    switch (name) {
      case 'savings':
        return Icons.savings_rounded;
      case 'verified_user':
        return Icons.verified_user_rounded;
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'trending_up':
        return Icons.trending_up_rounded;
      default:
        return Icons.groups_rounded;
    }
  }
}

class FigmaPromoSection extends StatefulWidget {
  const FigmaPromoSection({super.key});

  @override
  State<FigmaPromoSection> createState() => _FigmaPromoSectionState();
}

class _FigmaPromoSectionState extends State<FigmaPromoSection> {
  int _activePromo = 0;
  final PageController _pageController = PageController(viewportFraction: 0.88);

  // Default banners matching Bank DMB Figma Design
  List<BannerItem> _banners = const [
    BannerItem(
      tag: 'BPR DANA MANDIRI BOGOR',
      title: 'SIMPANAN NASABAH DIMANFAATKAN',
      highlight: 'UNTUK PENGEMBANGAN USAHA PEREMPUAN MIKRO PRODUKTIF',
      icon: Icons.groups_rounded,
      bgColor: Color(0xFF1E293B),
      accentColor: Color(0xFFFFB703),
      badgeText: 'CSR DMB',
    ),
    BannerItem(
      tag: 'DEPOSITO BERJANGKA DMB',
      title: 'BUNGA KOMPETITIF 6,25% P.A.',
      highlight: 'DAPAT DICAIRKAN SEWAKTU-WAKTU TANPA PENALTI',
      icon: Icons.savings_rounded,
      bgColor: Color(0xFF0F172A),
      accentColor: AppColors.primary,
      badgeText: 'Bunga 6.25%',
    ),
    BannerItem(
      tag: 'SOLUSI KEUANGAN ANDA',
      title: 'TABUNGAN MANDIRI DMB',
      highlight: 'SIMPANAN AMAN & DIJAMIN LPS HINGGA 2 MILYAR',
      icon: Icons.verified_user_rounded,
      bgColor: Color(0xFF0B4371),
      accentColor: Color(0xFF38BDF8),
      badgeText: 'Dijamin LPS',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchDynamicBanners();
  }

  Future<void> _fetchDynamicBanners() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ));
      final response = await dio.get('${ApiEndpoints.baseUrl}/api/v1/banners');
      if (response.statusCode == 200 && response.data['data'] != null) {
        final list = response.data['data'] as List;
        if (list.isNotEmpty && mounted) {
          setState(() {
            _banners = list.map((e) => BannerItem.fromJson(e as Map<String, dynamic>)).toList();
          });
        }
      }
    } catch (_) {
      // Graceful Wi-Fi fallback to laptop IP if localhost fails
      try {
        final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
        final response = await dio.get('${ApiEndpoints.fallbackUrl}/api/v1/banners');
        if (response.statusCode == 200 && response.data['data'] != null) {
          final list = response.data['data'] as List;
          if (list.isNotEmpty && mounted) {
            setState(() {
              _banners = list.map((e) => BannerItem.fromJson(e as Map<String, dynamic>)).toList();
            });
          }
        }
      } catch (_) {
        // Keep default Bank DMB banners
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row: "Promo buat kamu" + "Lihat Semua" matching wondr
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Promo buat kamu',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Katalog Promosi & Penawaran Spesial Bank DMB'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text(
                  'Lihat Semua',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFEA580C), // Orange like wondr
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal Banner Carousel
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _banners.length,
            onPageChanged: (idx) => setState(() => _activePromo = idx),
            itemBuilder: (context, index) {
              final banner = _banners[index];
              return _buildPromoCard(banner);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPromoCard(BannerItem banner) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: banner.bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background Icon Watermark
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(
              banner.icon,
              size: 80,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        banner.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  if (banner.badgeText != null && banner.badgeText!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB703),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        banner.badgeText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    banner.highlight,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: banner.accentColor,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
              const Text(
                'www.bprdanamandiribogor.co.id',
                style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
