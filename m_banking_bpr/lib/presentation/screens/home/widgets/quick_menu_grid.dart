import 'package:flutter/material.dart';
import '../../deposit/deposit_screen.dart';
import '../../loan/loan_screen.dart';
import '../../mutation/mutation_screen.dart';
import '../../profile/company_profile_screen.dart';

enum _MenuIconType { mutasi, pinjaman, deposito, profil }

/// 4-column circular quick menu row with dual-tone fintech icons matching myDMB.
class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        label: 'Mutasi',
        type: _MenuIconType.mutasi,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MutationScreen()),
        ),
      ),
      (
        label: 'Fasilitas\nPinjaman',
        type: _MenuIconType.pinjaman,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoanScreen()),
        ),
      ),
      (
        label: 'Portofolio\nDeposit',
        type: _MenuIconType.deposito,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DepositScreen()),
        ),
      ),
      (
        label: 'Profil\nDMB',
        type: _MenuIconType.profil,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CompanyProfileScreen()),
        ),
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: item.onTap,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE8EEF6)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0550A6).withOpacity(0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _DualToneMenuIcon(type: item.type),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DualToneMenuIcon extends StatelessWidget {
  const _DualToneMenuIcon({required this.type});

  final _MenuIconType type;

  static const Color _navy = Color(0xFF033172);
  static const Color _blue = Color(0xFF118CE0);
  static const Color _cyan = Color(0xFF00C2D1);

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case _MenuIconType.mutasi:
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(Icons.description_rounded, color: _navy, size: 25),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: _cyan,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.6),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 8.5),
                ),
              ),
            ],
          ),
        );
      case _MenuIconType.pinjaman:
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(Icons.account_balance_wallet_rounded, color: _navy, size: 24),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _cyan,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.attach_money_rounded, color: Colors.white, size: 8.5),
                ),
              ),
            ],
          ),
        );
      case _MenuIconType.deposito:
        return SizedBox(
          width: 26,
          height: 26,
          child: CustomPaint(
            painter: _DepositChartPainter(),
          ),
        );
      case _MenuIconType.profil:
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(
                child: Icon(Icons.account_balance_rounded, color: _navy, size: 24),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: _cyan,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _DepositChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bar1 = Paint()..color = const Color(0xFF033172);
    final bar2 = Paint()..color = const Color(0xFF0550A6);
    final bar3 = Paint()..color = const Color(0xFF118CE0);

    // 3 neat ascending rounded bars at bottom
    const barW = 4.6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, h * 0.58, barW, h * 0.34),
        const Radius.circular(1.8),
      ),
      bar1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, h * 0.44, barW, h * 0.48),
        const Radius.circular(1.8),
      ),
      bar2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w - 2 - barW, h * 0.30, barW, h * 0.62),
        const Radius.circular(1.8),
      ),
      bar3,
    );

    // Clean upward trend arrow floating clearly above the bars
    final arrowPaint = Paint()
      ..color = const Color(0xFF00C2D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final trend = Path()
      ..moveTo(2.5, h * 0.42)
      ..lineTo(w * 0.42, h * 0.25)
      ..lineTo(w * 0.60, h * 0.31)
      ..lineTo(w - 3, h * 0.08);
    canvas.drawPath(trend, arrowPaint);

    // Arrowhead
    final head = Path()
      ..moveTo(w - 7.5, h * 0.08)
      ..lineTo(w - 2.5, h * 0.08)
      ..lineTo(w - 2.5, h * 0.25);
    canvas.drawPath(head, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
