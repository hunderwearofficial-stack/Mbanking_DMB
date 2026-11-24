import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import '../../widgets/auth_ui_kit.dart';

class NotificationScreen extends StatefulWidget {
  final bool isTab;
  const NotificationScreen({super.key, this.isTab = false});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _notifications = [];
  int _selectedFilterIndex = 0; // 0: Semua, 1: Transaksi, 2: Keamanan, 3: Info & Promo

  static const Color primaryNavy = AppColors.primaryNavy;
  static const Color royalBlue = AppColors.royalBlue;
  static const Color dmbGreen = AppColors.dmbGreen;
  static const Color dmbRed = AppColors.danger;
  static const Color dmbAmber = AppColors.warning;
  static const Color titleDark = AppColors.titleDark;
  static const Color textMuted = AppColors.textMuted;
  static const Color borderLight = AppColors.borderLight;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final repo = context.read<AccountCubit>().accountRepository;
      final list = await repo.getNotifications(limit: 40);
      if (mounted) {
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ApiException.humanize(
            e,
            fallback: 'Kotak masuk notifikasi belum dapat dimuat. Silakan coba kembali.',
          );
          _isLoading = false;
        });
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
        AppToast.showSuccess(
          context,
          'Semua notifikasi ditandai telah dibaca',
          title: 'Kotak Masuk',
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
      context.read<AccountCubit>().accountRepository.markNotificationsRead();
    }
    final category = (n['category'] as String? ?? 'INFO').toUpperCase();
    final title = n['title'] as String? ?? 'Informasi Mobile DMB';
    final message = n['message'] as String? ?? '';
    final createdAt = n['created_at'] as String? ?? '';

    IconData icon = Icons.notifications_active_rounded;
    Color iconBg = AppColors.primaryLight;
    Color iconColor = royalBlue;
    String badgeLabel = 'INFORMASI';

    if (category == 'SECURITY') {
      icon = Icons.shield_rounded;
      iconBg = AppColors.dangerLight;
      iconColor = dmbRed;
      badgeLabel = 'KEAMANAN';
    } else if (category == 'TRANSACTION') {
      icon = Icons.receipt_long_rounded;
      iconBg = AppColors.successLight;
      iconColor = dmbGreen;
      badgeLabel = 'TRANSAKSI';
    } else if (category == 'PROMO') {
      icon = Icons.campaign_rounded;
      iconBg = AppColors.warningLight;
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
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AuthUiTokens.deepCobalt,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
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
    final hasUnread = _notifications.any((n) => n['is_read'] != true);

    return AuthSwooshCanvas(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: Row(
                children: [
                  if (!widget.isTab) ...[
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AuthUiTokens.inputBorder),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 17,
                            color: AuthUiTokens.deepCobalt,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      'Notifikasi',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AuthUiTokens.titleDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (hasUnread)
                    Material(
                      color: AuthUiTokens.softBlueBg,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _markAllAsRead,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.done_all_rounded,
                                size: 15,
                                color: AuthUiTokens.deepCobalt,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Tandai Dibaca',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AuthUiTokens.deepCobalt,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            _buildFilterPills(),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadNotifications,
                color: AuthUiTokens.deepCobalt,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AuthUiTokens.deepCobalt))
                    : _errorMessage != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Column(
                                  children: [
                                    const Icon(Icons.cloud_off_rounded, size: 48, color: textMuted),
                                    const SizedBox(height: 14),
                                    Text(
                                      _errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: titleDark,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: _loadNotifications,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AuthUiTokens.deepCobalt,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(150, 44),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(22),
                                        ),
                                      ),
                                      icon: const Icon(Icons.refresh_rounded, size: 18),
                                      label: const Text('Coba Lagi'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
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
                                            color: AuthUiTokens.softBlueBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.notifications_none_rounded,
                                              size: 36,
                                              color: AuthUiTokens.royalBlue,
                                            ),
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
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 32),
                                          child: Text(
                                            'Peringatan keamanan login, transaksi & info DMB akan tampil di sini.',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              color: textMuted,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final n = filtered[index];
                                  final isRead = n['is_read'] == true;
                                  final category = (n['category'] as String? ?? 'INFO').toUpperCase();
                                  final title = n['title'] as String? ?? 'Informasi Mobile DMB';
                                  final message = n['message'] as String? ?? '';
                                  final createdAt = n['created_at'] as String? ?? '';

                                  IconData icon = Icons.info_rounded;
                                  Color iconBg = AuthUiTokens.softBlueBg;
                                  Color iconColor = AuthUiTokens.royalBlue;

                                  if (category == 'SECURITY') {
                                    icon = Icons.shield_rounded;
                                    iconBg = AppColors.dangerLight;
                                    iconColor = dmbRed;
                                  } else if (category == 'TRANSACTION') {
                                    icon = Icons.check_circle_rounded;
                                    iconBg = const Color(0xFFD1FAE5);
                                    iconColor = const Color(0xFF059669);
                                  } else if (category == 'PROMO') {
                                    icon = Icons.percent_rounded;
                                    iconBg = const Color(0xFFE0F2FE);
                                    iconColor = AuthUiTokens.deepCobalt;
                                  }

                                  return Material(
                                    color: isRead ? Colors.white : const Color(0xFFF4F8FF),
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      onTap: () => _showNotificationDetail(n),
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.all(15),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: isRead
                                                ? const Color(0xFFE8EEF6)
                                                : AuthUiTokens.softBlueBorder,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AuthUiTokens.royalBlue.withOpacity(0.05),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
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
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: GoogleFonts.plusJakartaSans(
                                                            fontSize: 13.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: AuthUiTokens.titleDark,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        CurrencyFormatter.formatDateShort(createdAt),
                                                        style: GoogleFonts.plusJakartaSans(
                                                          fontSize: 11,
                                                          color: textMuted,
                                                          fontWeight: isRead
                                                              ? FontWeight.w500
                                                              : FontWeight.w700,
                                                        ),
                                                      ),
                                                      if (!isRead) ...[
                                                        const SizedBox(width: 5),
                                                        Container(
                                                          margin: const EdgeInsets.only(top: 4),
                                                          width: 7,
                                                          height: 7,
                                                          decoration: const BoxDecoration(
                                                            color: AuthUiTokens.royalBlue,
                                                            shape: BoxShape.circle,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    message,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.plusJakartaSans(
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
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPills() {
    final filters = ['Semua', 'Transaksi', 'Keamanan', 'Info & Promo'];

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilterIndex == index;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selectedFilterIndex = index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text(
                    filters[index],
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? AuthUiTokens.deepCobalt
                          : AuthUiTokens.textMuted,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2.5,
                  width: isSelected ? 42 : 0,
                  decoration: BoxDecoration(
                    color: AuthUiTokens.royalBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
