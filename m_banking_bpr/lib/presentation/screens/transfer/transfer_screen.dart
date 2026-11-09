import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../blocs/account/account_cubit.dart';
import '../../blocs/account/account_state.dart';
import '../../blocs/transfer/transfer_cubit.dart';
import '../../blocs/transfer/transfer_state.dart';
import '../../widgets/banking_app_bar.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/pin_input_dialog.dart';
import 'transfer_receipt_screen.dart';

class BankOption {
  final String code;
  final String name;
  const BankOption(this.code, this.name);
}

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _toAccountController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final List<BankOption> _banks = const [
    BankOption('BPR', 'Bank DMB Internal - Overbooking CBS (Bebas Biaya)'),
    BankOption('014', 'BCA (Bank Central Asia)'),
    BankOption('008', 'Bank Mandiri'),
    BankOption('002', 'Bank Rakyat Indonesia (BRI)'),
    BankOption('009', 'Bank Negara Indonesia (BNI)'),
  ];

  late BankOption _selectedBank;
  String _recipientName = '';
  bool _isCheckingRecipient = false;

  // Nominal cepat disesuaikan untuk saldo test CBS OpenAPI & transaksi harian
  final List<double> _quickAmounts = [10, 50, 100, 500, 1000, 5000];

  @override
  void initState() {
    super.initState();
    _selectedBank = _banks.first;
  }

  @override
  void dispose() {
    _toAccountController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _checkRecipientName() async {
    final accNo = _toAccountController.text.trim();
    if (accNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan ketik nomor rekening tujuan')),
      );
      return;
    }

    setState(() {
      _isCheckingRecipient = true;
      _recipientName = '';
    });

    try {
      final accountRepo = context.read<AccountCubit>().accountRepository;
      final res = await accountRepo.inquiryAccount(accNo);
      if (mounted) {
        final holderName = (res['holder_name'] as String?) ?? '';
        setState(() {
          _isCheckingRecipient = false;
          _recipientName = holderName.isNotEmpty ? holderName : 'Nasabah Terdaftar ($accNo)';
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isCheckingRecipient = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingRecipient = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memverifikasi rekening tujuan: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _onProceedTransfer(String fromAccount) async {
    final toAccount = _toAccountController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final note = _noteController.text.trim();

    if (toAccount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor rekening tujuan wajib diisi')),
      );
      return;
    }

    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal transfer wajib diisi')),
      );
      return;
    }

    final amount = double.tryParse(amountText) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal transfer harus lebih besar dari 0')),
      );
      return;
    }

    final recipient = _recipientName.isNotEmpty ? _recipientName : 'Penerima BPR';

    // Show 6-digit PIN confirmation dialog
    final pin = await PinInputDialog.show(
      context,
      title: 'Otorisasi Transfer',
      subtitle: 'Transfer ke $recipient sebesar ${CurrencyFormatter.formatRupiah(amount)}',
    );

    if (pin != null && pin.length == 6) {
      if (!mounted) return;
      context.read<TransferCubit>().submitTransfer(
            fromAccount: fromAccount,
            toBankCode: _selectedBank.code,
            toAccount: toAccount,
            toAccountName: recipient,
            amount: amount,
            note: note,
            pin: pin,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TransferCubit, TransferState>(
      listener: (context, state) {
        if (state is TransferSuccess) {
          // Refresh account balance
          context.read<AccountCubit>().refresh();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TransferReceiptScreen(receipt: state.response),
            ),
          );
        } else if (state is TransferError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is TransferLoading;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: const BankingAppBar(title: 'Transfer Dana'),
          body: BlocBuilder<AccountCubit, AccountState>(
            builder: (context, accState) {
              String fromAccount = '-';
              double currentBalance = 0.0;
              if (accState is AccountLoaded) {
                fromAccount = accState.account.accountNumber;
                currentBalance = accState.account.balance;
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender Account Card (Prominent & Clear)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Rekening Sumber (Tabungan Utama)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  fromAccount,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sisa Saldo: ${CurrencyFormatter.formatRupiah(currentBalance)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Destination Bank Dropdown
                    const Text(
                      'Pilih Bank Tujuan',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border, width: 1.2),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<BankOption>(
                          isExpanded: true,
                          value: _selectedBank,
                          icon: const Icon(Icons.arrow_drop_down_rounded, size: 30, color: AppColors.primary),
                          items: _banks.map((b) {
                            return DropdownMenuItem(
                              value: b,
                              child: Text(
                                b.name,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedBank = val;
                                _recipientName = '';
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Destination Account Number + Check Button
                    const Text(
                      'Nomor Rekening Tujuan',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _toAccountController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Masukkan Nomor Rekening Tujuan',
                              prefixIcon: Icon(Icons.credit_card_rounded, color: AppColors.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size(88, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isCheckingRecipient ? null : _checkRecipientName,
                          child: _isCheckingRecipient
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Text('Periksa', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ],
                    ),

                    // Verified Recipient Name Card (Prominent & Clear)
                    if (_recipientName.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.success.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
                            const SizedBox(width: 10),
                            const Text(
                              'Penerima: ',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            ),
                            Expanded(
                              child: Text(
                                _recipientName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Amount Input
                    const Text(
                      'Nominal Transfer (Rp)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '0',
                        prefixText: 'Rp  ',
                        prefixStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Nominal Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _quickAmounts.map((q) {
                        return ActionChip(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.border, width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          label: Text(
                            CurrencyFormatter.formatRupiah(q),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          onPressed: () {
                            setState(() {
                              _amountController.text = q.toInt().toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Note Input (Optional)
                    const Text(
                      'Catatan Transfer (Opsional)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Contoh: Pembayaran belanja / titipan',
                        prefixIcon: Icon(Icons.note_alt_outlined, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Submit Button (Bank DMB Deep Royal Blue, 56px height)
                    CustomButton(
                      text: 'LANJUTKAN TRANSFER',
                      icon: Icons.send_rounded,
                      height: 56,
                      backgroundColor: AppColors.primary,
                      isLoading: isLoading,
                      onPressed: () => _onProceedTransfer(fromAccount),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
