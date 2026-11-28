import 'package:flutter/material.dart';
import '../../account/balance_summary_screen.dart';
import '../../deposit/deposit_application_bottom_sheet.dart';
import '../../deposit/deposit_screen.dart';
import '../../loan/loan_application_bottom_sheet.dart';
import '../../loan/loan_schedule_list_screen.dart';
import '../../loan/loan_screen.dart';
import '../../mutation/mutation_screen.dart';
import '../../product/application_status_screen.dart';
import '../../product/apply_hub_screen.dart';
import '../../product/product_catalog_screen.dart';

/// 4-column clean banking quick menu grid with duotone fintech icons
/// matching Bank DMB brand palette.
enum _DmbMenuIconType {
  balance,
  mutation,
  deposit,
  credit,
  schedule,
  applyCredit,
  applyDeposit,
  status,
  attendance,
  catalog,
}

class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

  static const Color _navy = Color(0xFF033172);
  static const Color _skyFill = Color(0xFF7DD3FC);

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        label: 'Informasi\nSaldo',
        iconType: _DmbMenuIconType.balance,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BalanceSummaryScreen()),
        ),
      ),
      (
        label: 'Mutasi',
        iconType: _DmbMenuIconType.mutation,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MutationScreen()),
        ),
      ),
      (
        label: 'Deposito',
        iconType: _DmbMenuIconType.deposit,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DepositScreen()),
        ),
      ),
      (
        label: 'Kredit',
        iconType: _DmbMenuIconType.credit,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoanSubMenuScreen()),
        ),
      ),
      (
        label: 'Jadwal\nAngsuran',
        iconType: _DmbMenuIconType.schedule,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoanScheduleListScreen()),
        ),
      ),
      (
        label: 'Ajukan\nKredit',
        iconType: _DmbMenuIconType.applyCredit,
        onTap: () => LoanApplicationBottomSheet.show(context),
      ),
      (
        label: 'Ajukan\nDeposito',
        iconType: _DmbMenuIconType.applyDeposit,
        onTap: () => DepositApplicationBottomSheet.show(context),
      ),
      (
        label: 'Status\nPengajuan',
        iconType: _DmbMenuIconType.status,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApplicationStatusScreen()),
        ),
      ),
      (
        label: 'Kehadiran\nKelompok',
        iconType: _DmbMenuIconType.attendance,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LoanScreen(
              categoryFilter: 'KKM',
              openAttendanceDirect: true,
            ),
          ),
        ),
      ),
      (
        label: 'Katalog\nProduk',
        iconType: _DmbMenuIconType.catalog,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        mainAxisExtent: 88,
      ),
      itemBuilder: (_, index) {
        final item = items[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFCFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEBF1F8)),
                  boxShadow: [
                    BoxShadow(
                      color: _navy.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CustomPaint(
                      painter: _DuotoneMenuIconPainter(
                        type: item.iconType,
                        strokeColor: _navy,
                        fillColor: _skyFill,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                  height: 1.18,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DuotoneMenuIconPainter extends CustomPainter {
  const _DuotoneMenuIconPainter({
    required this.type,
    required this.strokeColor,
    required this.fillColor,
  });

  final _DmbMenuIconType type;
  final Color strokeColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = fillColor.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case _DmbMenuIconType.balance:
        // Document sheet with folded corner (like Informasi Saldo in reference)
        final doc = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.20, h * 0.12, w * 0.60, h * 0.76),
          const Radius.circular(3.5),
        );
        canvas.drawRRect(doc, fill);
        canvas.drawRRect(doc, stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.36), Offset(w * 0.66, h * 0.36), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.52), Offset(w * 0.66, h * 0.52), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.68), Offset(w * 0.52, h * 0.68), stroke);
        break;

      case _DmbMenuIconType.mutation:
        // Clock circle with soft sky fill & hands (like Mutasi Rekening in reference)
        final center = Offset(w * 0.50, h * 0.50);
        canvas.drawCircle(center, w * 0.36, fill);
        canvas.drawCircle(center, w * 0.36, stroke);
        canvas.drawLine(center, Offset(w * 0.50, h * 0.30), stroke);
        canvas.drawLine(center, Offset(w * 0.64, h * 0.56), stroke);
        break;

      case _DmbMenuIconType.deposit:
        // Piggy bank + coin (like Deposito in reference)
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.16, h * 0.32, w * 0.64, h * 0.44),
          const Radius.circular(10),
        );
        canvas.drawRRect(body, fill);
        canvas.drawRRect(body, stroke);
        // Coin on top
        canvas.drawCircle(Offset(w * 0.48, h * 0.18), w * 0.10, fill);
        canvas.drawCircle(Offset(w * 0.48, h * 0.18), w * 0.10, stroke);
        // Legs
        canvas.drawLine(Offset(w * 0.30, h * 0.76), Offset(w * 0.30, h * 0.86), stroke);
        canvas.drawLine(Offset(w * 0.64, h * 0.76), Offset(w * 0.64, h * 0.86), stroke);
        // Snout
        canvas.drawLine(Offset(w * 0.80, h * 0.48), Offset(w * 0.88, h * 0.48), stroke);
        canvas.drawLine(Offset(w * 0.80, h * 0.58), Offset(w * 0.88, h * 0.58), stroke);
        break;

      case _DmbMenuIconType.credit:
        // Bank card with sky-blue fill & magnetic band (like Kartu Debit in reference)
        final card = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.12, h * 0.24, w * 0.76, h * 0.52),
          const Radius.circular(4),
        );
        canvas.drawRRect(card, fill);
        canvas.drawRRect(card, stroke);
        canvas.drawLine(Offset(w * 0.12, h * 0.42), Offset(w * 0.88, h * 0.42), stroke);
        canvas.drawLine(Offset(w * 0.24, h * 0.60), Offset(w * 0.44, h * 0.60), stroke);
        break;

      case _DmbMenuIconType.schedule:
        // Calendar with sky-blue header & date dots
        final cal = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.14, h * 0.20, w * 0.72, h * 0.66),
          const Radius.circular(4),
        );
        final header = RRect.fromRectAndCorners(
          Rect.fromLTWH(w * 0.14, h * 0.20, w * 0.72, h * 0.20),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(header, fill);
        canvas.drawRRect(cal, stroke);
        canvas.drawLine(Offset(w * 0.14, h * 0.40), Offset(w * 0.86, h * 0.40), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.12), Offset(w * 0.34, h * 0.24), stroke);
        canvas.drawLine(Offset(w * 0.66, h * 0.12), Offset(w * 0.66, h * 0.24), stroke);
        canvas.drawLine(Offset(w * 0.34, h * 0.56), Offset(w * 0.46, h * 0.68), stroke);
        canvas.drawLine(Offset(w * 0.46, h * 0.68), Offset(w * 0.66, h * 0.50), stroke);
        break;

      case _DmbMenuIconType.applyCredit:
        // Rising chart bars + arrow (like Investasi in reference)
        final b1 = Rect.fromLTWH(w * 0.18, h * 0.56, w * 0.14, h * 0.26);
        final b2 = Rect.fromLTWH(w * 0.43, h * 0.44, w * 0.14, h * 0.38);
        final b3 = Rect.fromLTWH(w * 0.68, h * 0.30, w * 0.14, h * 0.52);
        canvas.drawRect(b1, fill);
        canvas.drawRect(b2, fill);
        canvas.drawRect(b3, fill);
        canvas.drawRect(b1, stroke);
        canvas.drawRect(b2, stroke);
        canvas.drawRect(b3, stroke);
        final trend = Path()
          ..moveTo(w * 0.18, h * 0.38)
          ..lineTo(w * 0.46, h * 0.24)
          ..lineTo(w * 0.76, h * 0.14);
        canvas.drawPath(trend, stroke);
        break;

      case _DmbMenuIconType.applyDeposit:
        // Smartphone + plus badge (like Top Up in reference)
        final phone = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.22, h * 0.12, w * 0.46, h * 0.74),
          const Radius.circular(4),
        );
        canvas.drawRRect(phone, fill);
        canvas.drawRRect(phone, stroke);
        final plusCenter = Offset(w * 0.72, h * 0.68);
        canvas.drawCircle(plusCenter, w * 0.17, Paint()..color = Colors.white);
        canvas.drawCircle(plusCenter, w * 0.17, fill);
        canvas.drawCircle(plusCenter, w * 0.17, stroke);
        canvas.drawLine(Offset(w * 0.72, h * 0.59), Offset(w * 0.72, h * 0.77), stroke);
        canvas.drawLine(Offset(w * 0.63, h * 0.68), Offset(w * 0.81, h * 0.68), stroke);
        break;

      case _DmbMenuIconType.status:
        // Shield with check (like Keamanan in reference)
        final shield = Path()
          ..moveTo(w * 0.50, h * 0.12)
          ..lineTo(w * 0.82, h * 0.24)
          ..lineTo(w * 0.82, h * 0.50)
          ..quadraticBezierTo(w * 0.82, h * 0.76, w * 0.50, h * 0.88)
          ..quadraticBezierTo(w * 0.18, h * 0.76, w * 0.18, h * 0.50)
          ..lineTo(w * 0.18, h * 0.24)
          ..close();
        canvas.drawPath(shield, fill);
        canvas.drawPath(shield, stroke);
        canvas.drawLine(Offset(w * 0.36, h * 0.50), Offset(w * 0.46, h * 0.60), stroke);
        canvas.drawLine(Offset(w * 0.46, h * 0.60), Offset(w * 0.65, h * 0.40), stroke);
        break;

      case _DmbMenuIconType.attendance:
        // Two people duotone
        canvas.drawCircle(Offset(w * 0.38, h * 0.32), w * 0.13, fill);
        canvas.drawCircle(Offset(w * 0.38, h * 0.32), w * 0.13, stroke);
        final arc1 = Path()
          ..moveTo(w * 0.14, h * 0.78)
          ..quadraticBezierTo(w * 0.14, h * 0.54, w * 0.38, h * 0.54)
          ..quadraticBezierTo(w * 0.62, h * 0.54, w * 0.62, h * 0.78)
          ..close();
        canvas.drawPath(arc1, fill);
        canvas.drawPath(arc1, stroke);
        canvas.drawCircle(Offset(w * 0.68, h * 0.36), w * 0.10, stroke);
        final arc2 = Path()
          ..moveTo(w * 0.64, h * 0.56)
          ..quadraticBezierTo(w * 0.86, h * 0.56, w * 0.86, h * 0.78);
        canvas.drawPath(arc2, stroke);
        break;

      case _DmbMenuIconType.catalog:
        // 2x2 rounded grid (like Katalog / Lainnya duotone)
        final r1 = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.16, w * 0.28, h * 0.28), const Radius.circular(3.5));
        final r2 = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.56, h * 0.16, w * 0.28, h * 0.28), const Radius.circular(3.5));
        final r3 = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.56, w * 0.28, h * 0.28), const Radius.circular(3.5));
        final r4 = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.56, h * 0.56, w * 0.28, h * 0.28), const Radius.circular(3.5));
        canvas.drawRRect(r1, fill);
        canvas.drawRRect(r2, fill);
        canvas.drawRRect(r3, fill);
        canvas.drawRRect(r4, fill);
        canvas.drawRRect(r1, stroke);
        canvas.drawRRect(r2, stroke);
        canvas.drawRRect(r3, stroke);
        canvas.drawRRect(r4, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DuotoneMenuIconPainter oldDelegate) =>
      oldDelegate.type != type;
}
