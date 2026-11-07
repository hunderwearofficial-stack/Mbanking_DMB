import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class PinInputDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final Function(String pin) onPinComplete;

  const PinInputDialog({
    super.key,
    this.title = 'Masukkan PIN Transaksi',
    this.subtitle = 'Konfirmasi otorisasi dengan 6 digit PIN Anda',
    required this.onPinComplete,
  });

  static Future<String?> show(BuildContext context, {String? title, String? subtitle}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PinInputDialog(
        title: title ?? 'Masukkan PIN Transaksi',
        subtitle: subtitle ?? 'Konfirmasi otorisasi dengan 6 digit PIN Anda',
        onPinComplete: (pin) => Navigator.of(context).pop(pin),
      ),
    );
  }

  @override
  State<PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends State<PinInputDialog> {
  String _pin = '';

  void _onKeyTap(String val) {
    if (_pin.length < 6) {
      setState(() {
        _pin += val;
      });
      if (_pin.length == 6) {
        widget.onPinComplete(_pin);
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 32, left: 24, right: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.lock_outline_rounded, size: 36, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            widget.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),

          // 6 PIN Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              final isFilled = index < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isFilled ? AppColors.primary : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 36),

          // Custom Keypad
          _buildKeypad(),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 72);
              }
              if (key == 'delete') {
                return SizedBox(
                  width: 72,
                  height: 72,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(36),
                    onTap: _onDelete,
                    child: const Center(
                      child: Icon(Icons.backspace_outlined, color: AppColors.textPrimary, size: 24),
                    ),
                  ),
                );
              }
              return SizedBox(
                width: 72,
                height: 72,
                child: InkWell(
                  borderRadius: BorderRadius.circular(36),
                  onTap: () => _onKeyTap(key),
                  child: Center(
                    child: Text(
                      key,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

