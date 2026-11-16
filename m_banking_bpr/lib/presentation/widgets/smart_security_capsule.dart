import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/dynamic_config_service.dart';
import '../../core/constants/bank_contact.dart';

/// Smart Security Capsule - Bank DMB Executive Status Indicator.
/// Exceeds BCA Mobile's legacy circular dot with an intelligent capsule pill
/// featuring dual-state connectivity, animated heartbeat indicator,
/// and interactive Emergency Assistance BottomSheet for offline reassurance.
class SmartSecurityCapsule extends StatefulWidget {
  final String? customerName;
  final String? accountNumber;
  final String? cif;

  const SmartSecurityCapsule({
    super.key,
    this.customerName,
    this.accountNumber,
    this.cif,
  });

  @override
  State<SmartSecurityCapsule> createState() => _SmartSecurityCapsuleState();
}

class _SmartSecurityCapsuleState extends State<SmartSecurityCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showOfflineEmergencySheet(BuildContext context, bool isConnected) {
    HapticFeedback.lightImpact();
    final config = DynamicConfigService().config;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final liveConnected = DynamicConfigService().isServerConnected;

            return SafeArea(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    Container(
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Header Status
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: liveConnected
                                ? const Color(0xFFE6F4EA)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: liveConnected
                                  ? const Color(0xFFA8DAB5)
                                  : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Icon(
                            liveConnected
                                ? Icons.verified_user_rounded
                                : Icons.cloud_off_rounded,
                            color: liveConnected
                                ? const Color(0xFF137333)
                                : const Color(0xFFB45309),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                liveConnected
                                    ? 'Sistem Terhubung & Aman'
                                    : 'Aplikasi dalam Mode Offline',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                liveConnected
                                    ? 'Koneksi real-time aktif ke Core Banking Bank DMB'
                                    : 'Koneksi internet terputus • Data lokal terenkripsi',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Security Card & Offline Account Info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0A3B66), Color(0xFF062440)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A3B66).withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                config.bankShortName,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'KARTU DARURAT OFFLINE',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.tealAccent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (widget.customerName != null &&
                              widget.customerName!.isNotEmpty) ...[
                            Text(
                              widget.customerName!,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (widget.accountNumber != null &&
                              widget.accountNumber!.isNotEmpty) ...[
                            Text(
                              'No. Rekening Utama: ${widget.accountNumber}',
                              style: GoogleFonts.sourceCodePro(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Gunakan nomor rekening ini untuk transaksi tunai di Teller / ATM Bersama saat jaringan seluler tidak stabil.',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Quick Contact Support Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final num = BankContact.callCenterDisplay;
                              Clipboard.setData(ClipboardData(text: num));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Nomor Call Center disalin: $num'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.phone_in_talk, size: 16),
                            label: Text(
                              'Call Center',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0A3B66),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final num = BankContact.whatsAppDisplay;
                              Clipboard.setData(ClipboardData(text: num));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Nomor WhatsApp CS disalin: $num'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline,
                                size: 16, color: Color(0xFF16984B)),
                            label: Text(
                              'WhatsApp CS',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF16984B)),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFBBF7D0)),
                              backgroundColor: const Color(0xFFF0FDF4),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Check Connectivity Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final ok =
                              await DynamicConfigService().checkHealth();
                          setModalState(() {});
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Berhasil terhubung ke server Bank DMB!'
                                      : 'Server belum terjangkau. Periksa koneksi internet Anda.',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                                ),
                                backgroundColor: ok
                                    ? const Color(0xFF16984B)
                                    : const Color(0xFFDC2626),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.sync_rounded, size: 17),
                        label: Text(
                          'Cek Ulang Koneksi Server',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DynamicConfigService(),
      builder: (context, _) {
        final isConnected = DynamicConfigService().isServerConnected;

        final bgColor = isConnected
            ? const Color(0xFFE6F4EA)
            : const Color(0xFFFEF3C7);
        final borderColor = isConnected
            ? const Color(0xFFA8DAB5)
            : const Color(0xFFFDE68A);
        final textColor = isConnected
            ? const Color(0xFF137333)
            : const Color(0xFFB45309);
        final pulseColor = isConnected
            ? const Color(0xFF34A853)
            : const Color(0xFFF59E0B);

        return InkWell(
          onTap: () => _showOfflineEmergencySheet(context, isConnected),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: isConnected
                      ? const Color(0xFF34A853).withOpacity(0.12)
                      : const Color(0xFFF59E0B).withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live Heartbeat Pulse Indicator
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: pulseColor.withOpacity(_pulseAnimation.value),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: pulseColor.withOpacity(0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'Aman • Terhubung' : 'Mode Offline',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isConnected ? Icons.shield_rounded : Icons.info_outline_rounded,
                  size: 13,
                  color: textColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
