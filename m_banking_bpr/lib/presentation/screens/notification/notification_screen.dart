import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<AccountCubit>().accountRepository;
      final list = await repo.getNotifications(limit: 40);
      await repo.markNotificationsRead();
      if (mounted) {
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          children: [
            Text(
              'Kotak Masuk & Notifikasi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            Text(
              'KEAMANAN & AKTIVITAS TRANSAKSI',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        color: AppColors.primary,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _notifications.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 60, color: AppColors.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'Belum ada notifikasi baru',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Peringatan keamanan login & bukti transaksi akan tampil di sini.',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      final category = (n['category'] as String? ?? 'INFO').toUpperCase();
                      final title = n['title'] as String? ?? 'Informasi Mobile DMB';
                      final message = n['message'] as String? ?? '';
                      final createdAt = n['created_at'] as String? ?? '';

                      IconData icon = Icons.notifications_active_rounded;
                      Color iconBg = AppColors.primaryLight;
                      Color iconColor = AppColors.primary;
                      String badgeLabel = 'INFO';

                      if (category == 'SECURITY') {
                        icon = Icons.shield_rounded;
                        iconBg = const Color(0xFFFFF1F2);
                        iconColor = AppColors.danger;
                        badgeLabel = 'KEAMANAN';
                      } else if (category == 'TRANSACTION') {
                        icon = Icons.receipt_long_rounded;
                        iconBg = const Color(0xFFF0FDF4);
                        iconColor = AppColors.primary;
                        badgeLabel = 'TRANSAKSI';
                      } else if (category == 'PROMO') {
                        icon = Icons.campaign_rounded;
                        iconBg = const Color(0xFFFEF3C7);
                        iconColor = const Color(0xFFD97706);
                        badgeLabel = 'PROMO & INFO';
                      }

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: iconBg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: iconColor, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: iconBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          badgeLabel,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: iconColor,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        CurrencyFormatter.formatDateShort(createdAt),
                                        style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    message,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

