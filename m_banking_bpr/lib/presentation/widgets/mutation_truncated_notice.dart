import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';

/// Shown when the server reports more transactions in the period than it returned
/// (`has_more`, audit MA-02), so a partial history is never mistaken for a complete one.
class MutationTruncatedNotice extends StatelessWidget {
  final int shown;
  final String message;

  const MutationTruncatedNotice({
    super.key,
    required this.shown,
    this.message = 'Masih ada transaksi lain pada periode ini. Persempit rentang tanggal untuk melihat seluruh riwayat.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFC2410C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Menampilkan $shown transaksi terbaru. $message',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.titleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
