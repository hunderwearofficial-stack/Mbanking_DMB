import 'package:flutter/material.dart';
import '../../account/balance_summary_screen.dart';
import '../../deposit/deposit_screen.dart';
import '../../loan/loan_schedule_list_screen.dart';
import '../../loan/loan_screen.dart';
import '../../mutation/mutation_screen.dart';
import '../../product/application_status_screen.dart';
import '../../product/apply_hub_screen.dart';

/// 4-column clean banking quick menu grid matching Bank DMB brand palette.
class FigmaMenuGrid extends StatelessWidget {
  const FigmaMenuGrid({super.key});

  static const Color _navy = Color(0xFF033172);

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        label: 'Informasi\nSaldo',
        icon: Icons.account_balance_wallet_outlined,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BalanceSummaryScreen()),
        ),
      ),
      (
        label: 'Mutasi',
        icon: Icons.swap_horiz_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MutationScreen()),
        ),
      ),
      (
        label: 'Deposito',
        icon: Icons.savings_outlined,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DepositScreen()),
        ),
      ),
      (
        label: 'Kredit',
        icon: Icons.credit_card_outlined,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoanSubMenuScreen()),
        ),
      ),
      (
        label: 'Jadwal\nAngsuran',
        icon: Icons.calendar_today_outlined,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoanScheduleListScreen()),
        ),
      ),
      (
        label: 'Ajukan\nKredit',
        icon: Icons.description_outlined,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoanCategoryApplyScreen()),
        ),
      ),
      (
        label: 'Ajukan\nDeposito',
        icon: Icons.add_circle_outline_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DepositTenorApplyScreen()),
        ),
      ),
      (
        label: 'Status\nPengajuan',
        icon: Icons.assignment_outlined,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApplicationStatusScreen()),
        ),
      ),
      (
        label: 'Kehadiran\nKelompok',
        icon: Icons.people_outline_rounded,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LoanScreen(
              categoryFilter: 'KKM',
              openAttendanceDirect: true,
            ),
          ),
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
        mainAxisSpacing: 10,
        crossAxisSpacing: 6,
        mainAxisExtent: 84,
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF033172).withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  item.icon,
                  color: _navy,
                  size: 23,
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
