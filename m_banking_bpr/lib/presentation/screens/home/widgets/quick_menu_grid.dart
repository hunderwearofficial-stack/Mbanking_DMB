import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../mutation/mutation_screen.dart';
import '../../product/product_catalog_screen.dart';
import '../../loan/loan_screen.dart';
import '../../deposit/deposit_screen.dart';

class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    const Color royalBlue = Color(0xFF0062E3);
    const Color titleDark = Color(0xFF0B2546);

    // Menu utama: Mutasi, Pinjaman, Deposito, Katalog (inquiry CBS melalui backend).
    final List<Map<String, dynamic>> items = [
      {
        'title': 'Mutasi\nTabungan',
        'icon': Icons.history_rounded,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MutationScreen()),
          );
        },
      },
      {
        'title': 'Fasilitas\nPinjaman',
        'icon': Icons.credit_score_outlined,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoanScreen()),
          );
        },
      },
      {
        'title': 'Portofolio\nDeposito',
        'icon': Icons.savings_outlined,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DepositScreen()),
          );
        },
      },
      {
        'title': 'Katalog\nProduk',
        'icon': Icons.auto_stories_outlined,
        'onTap': () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
          );
        },
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Menu Utama',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: titleDark,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),

          // 4 Kolom Menu Sesuai API CBS DMB
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.72,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final item = items[index];

              return InkWell(
                onTap: item['onTap'] as VoidCallback,
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 62,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFF3F8FE),
                            Color(0xFFE8F1FC),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD6E6F9)),
                        boxShadow: [
                          BoxShadow(
                            color: royalBlue.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          item['icon'] as IconData,
                          color: royalBlue,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 32,
                      child: Text(
                        item['title'] as String,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

