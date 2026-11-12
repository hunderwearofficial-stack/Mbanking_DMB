import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
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
  int _selectedFilterIndex = 0; // 0: Semua, 1: Transaksi, 2: Keamanan, 3: Info & Promo

  // Executive Brand Colors (Consistent with HomeScreen & MutationScreen)
  static const Color primaryNavy = Color(0xFF0B356D);
  static const Color royalBlue = Color(0xFF0062E3);
  static const Color dmbGreen = Color(0xFF16984B);
  static const Color dmbRed = Color(0xFFDC2626);
  static const Color dmbAmber = Color(0xFFD97706);
  static const Color titleDark = Color(0xFF0B2546);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color bgCanvas = Color(0xFFF8FAFC);

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

  Future<void> _markAllAsRead() async {
    try {
      final repo = context.read<AccountCubit>().accountRepository;
      await repo.markNotificationsRead();
      if (mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Semua notifikasi ditandai telah dibaca',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: dmbGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _getFilteredList() {
    if (_selectedFilterIndex == 1) {
      return _notifications.where((n) {
        final cat = (n['category'] as String? ?? '').toUpperCase();
        return cat == 'TRANSACTION';
      }).toList();
    } else if (_selectedFilterIndex == 2) {
      return _notifications.where((n) {
        final cat = (n['category'] as String? ?? '').toUpperCase();
        return cat == 'SECURITY';
      }).toList();
    } else if (_selectedFilterIndex == 3) {
      return _notifications.where((n) {
        final cat = (n['category'] as String? ?? '').toUpperCase();
        return cat == 'PROMO' || cat == 'INFO';
      }).toList();
    }
    return _notifications;
  }

  void _showNotificationDetail(Map<String, dynamic> n) {
    if (n['is_read'] != true) {
      setState(() => n['is_read'] = true);
    }
    final category = (n['category'] as String? ?? 'INFO').toUpperCase();
    final title = n['title'] as String? ?? 'Informasi Mobile DMB';
    final message = n['message'] as String? ?? '';
    final createdAt = n['created_at'] as String? ?? '';

    IconData icon = Icons.notifications_active_rounded;
    Color iconBg = const Color(0xFFEFF6FF);
    Color iconColor = royalBlue;
    String badgeLabel = 'INFORMASI';

    if (category == 'SECURITY') {
      icon = Icons.shield_rounded;
      iconBg = const Color(0xFFFEF2F2);
      iconColor = dmbRed;
      badgeLabel = 'KEAMANAN';
    } else if (category == 'TRANSACTION') {
      icon = Icons.receipt_long_rounded;
      iconBg = const Color(0xFFF0FDF4);
      iconColor = dmbGreen;
      badgeLabel = 'TRANSAKSI';
    } else if (category == 'PROMO') {
      icon = Icons.campaign_rounded;
      iconBg = const Color(0xFFFFFBEB);
      iconColor = dmbAmber;
      badgeLabel = 'PROMO & EDUKASI';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: borderLight, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                    child: Center(child: Icon(icon, color: iconColor, size: 22)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            badgeLabel,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: iconColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          CurrencyFormatter.formatDate(createdAt),
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: borderLight, height: 1),
              const SizedBox(height: 14),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: titleDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF334155),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Tutup',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredList();

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: titleDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'Kotak Masuk & Notifikasi',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleDark,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'KEAMANAN & AKTIVITAS AKUN',
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
          if (_notifications.any((n) => n['is_read'] != true))
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all_rounded, size: 16, color: royalBlue),
                label: Text(
                  'Tandai Dibaca',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: royalBlue,
                  ),
                ),
              ),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: borderLight),
        ),
      ),
      body: Column(
        children: [
          // Filter Pills Bar (Semua, Transaksi, Keamanan, Info)
          _buildFilterPills(),

          // Notifications List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadNotifications,
              color: primaryNavy,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: primaryNavy))
                  : filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 90),
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.notifications_none_rounded, size: 36, color: Color(0xFF94A3B8)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Belum Ada Notifikasi',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: titleDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Peringatan keamanan login, transaksi & info DMB akan tampil di sini.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: textMuted,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final n = filtered[index];
                            final isRead = n['is_read'] == true;
                            final category = (n['category'] as String? ?? 'INFO').toUpperCase();
                            final title = n['title'] as String? ?? 'Informasi Mobile DMB';
                            final message = n['message'] as String? ?? '';
                            final createdAt = n['created_at'] as String? ?? '';

                            IconData icon = Icons.notifications_active_rounded;
                            Color iconBg = const Color(0xFFEFF6FF);
                            Color iconColor = royalBlue;
                            String badgeLabel = 'INFO';

                            if (category == 'SECURITY') {
                              icon = Icons.shield_rounded;
                              iconBg = const Color(0xFFFEF2F2);
                              iconColor = dmbRed;
                              badgeLabel = 'KEAMANAN';
                            } else if (category == 'TRANSACTION') {
                              icon = Icons.receipt_long_rounded;
                              iconBg = const Color(0xFFF0FDF4);
                              iconColor = dmbGreen;
                              badgeLabel = 'TRANSAKSI';
                            } else if (category == 'PROMO') {
                              icon = Icons.campaign_rounded;
                              iconBg = const Color(0xFFFFFBEB);
                              iconColor = dmbAmber;
                              badgeLabel = 'PROMO';
                            }

                            return InkWell(
                              onTap: () => _showNotificationDetail(n),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: isRead ? Colors.white : const Color(0xFFF8FAFF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isRead ? borderLight : const Color(0xFF93C5FD),
                                    width: isRead ? 1 : 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Circular Category Icon
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: iconBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Icon(icon, color: iconColor, size: 20),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Content Body
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
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: iconColor,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    CurrencyFormatter.formatDateShort(createdAt),
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 11,
                                                      color: textMuted,
                                                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                                    ),
                                                  ),
                                                  if (!isRead) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      width: 7,
                                                      height: 7,
                                                      decoration: const BoxDecoration(
                                                        color: royalBlue,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 7),
                                          Text(
                                            title,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: titleDark,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            message,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              color: const Color(0xFF475569),
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FILTER PILLS ====================
  Widget _buildFilterPills() {
    final filters = ['Semua', 'Transaksi', 'Keamanan', 'Info & Promo'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(filters.length, (index) {
          final isSelected = _selectedFilterIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilterIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7.5),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  filters[index],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? royalBlue : textMuted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
