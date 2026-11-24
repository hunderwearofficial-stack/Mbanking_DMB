import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/terms_consent_store.dart';
import '../../../data/models/terms_document.dart';
import '../../../data/repositories/terms_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../widgets/app_validation_feedback.dart';
import '../splash/splash_screen.dart';
import 'login_screen.dart';

typedef TermsPdfViewBuilder = Widget Function(
  Uint8List bytes,
  void Function(int pages) onLoaded,
  void Function(Object error) onError,
  void Function(int page) onPageChanged,
);

class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({
    super.key,
    this.repository,
    this.pdfViewBuilder,
    this.onAccepted,
    this.readOnly = false,
  });

  final TermsRepository? repository;
  final TermsPdfViewBuilder? pdfViewBuilder;
  final VoidCallback? onAccepted;
  final bool readOnly;

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = true;

  late final TermsRepository _repo;
  TermsDocument? _doc;
  Uint8List? _pdfBytes;
  List<Uint8List> _renderedPages = const [];
  bool _loading = true;
  String? _error;
  bool _pdfReady = false;
  List<bool> _checks = const [];
  bool _submitting = false;

  bool get _isAllAgreed => _checks.isNotEmpty && _checks.every((c) => c);
  bool get _canProceed => _doc != null && _pdfReady && _isAllAgreed && !_submitting;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _repo = widget.repository ?? TermsRepository(apiClient: context.read<AuthCubit>().authRepository.apiClient);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pdfReady = false;
      _renderedPages = const [];
    });
    try {
      final doc = await _repo.fetchActive();
      final bytes = await _repo.fetchPdf(doc);
      final pages = <Uint8List>[];
      if (widget.pdfViewBuilder == null) {
        final pdfDoc = await PdfDocument.openData(bytes);
        try {
          for (var i = 1; i <= pdfDoc.pagesCount; i++) {
            final page = await pdfDoc.getPage(i);
            try {
              final img = await page.render(
                width: page.width * 2,
                height: page.height * 2,
                format: PdfPageImageFormat.png,
                backgroundColor: '#FFFFFF',
              );
              if (img != null) {
                pages.add(img.bytes);
              }
            } finally {
              await page.close();
            }
          }
        } finally {
          await pdfDoc.close();
        }
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _pdfBytes = bytes;
        _renderedPages = pages;
        _pdfReady = widget.pdfViewBuilder == null ? pages.isNotEmpty : false;
        _checks = List<bool>.filled(doc.consentStatements.length, false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _doc = null;
        _pdfBytes = null;
        _renderedPages = const [];
        _error = e is ApiException || e is TermsIntegrityException
            ? e.toString()
            : 'Syarat dan Ketentuan belum dapat dimuat. Periksa koneksi internet Anda lalu coba kembali.';
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    final isNearBottom = (maxScroll - currentScroll) <= 80;

    if (isNearBottom && _showScrollToBottom) {
      setState(() => _showScrollToBottom = false);
    } else if (!isNearBottom && !_showScrollToBottom) {
      setState(() => _showScrollToBottom = true);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _onProceed() async {
    if (widget.readOnly) {
      Navigator.of(context).maybePop();
      return;
    }
    final doc = _doc;
    if (!_canProceed || doc == null) return;
    setState(() => _submitting = true);
    try {
      final acceptanceId = await _repo.accept(doc);
      await TermsConsentStore.instance.persist(
        acceptanceId: acceptanceId,
        versionId: doc.versionId,
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(SplashScreen.hasSeenOnboardingKey, true);
      } catch (_) {}
      if (!mounted) return;
      if (widget.onAccepted != null) {
        setState(() => _submitting = false);
        widget.onAccepted!();
        return;
      }
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final versionChanged = e is ApiException && e.responseCode == '12';
      AppToast.showError(
        context,
        versionChanged
            ? 'Syarat dan Ketentuan telah diperbarui. Silakan baca versi terbaru.'
            : (e is ApiException ? e.message : 'Persetujuan belum dapat dicatat. Silakan coba kembali.'),
        title: 'Verifikasi S&K',
      );
      if (versionChanged) _load();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  static const _months = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _versionLine() {
    final doc = _doc;
    if (doc == null) return _loading ? 'Memuat versi dokumen...' : '-';
    final parts = <String>['Versi ${doc.versionNumber}'];
    if (doc.documentNumber != null) parts.add('No. ${doc.documentNumber}');
    if (doc.effectiveFrom != null) parts.add('Berlaku sejak ${_date(doc.effectiveFrom!)}');
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: Navigator.canPop(context)
            ? AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        body: SafeArea(
          top: !Navigator.canPop(context),
          bottom: false,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppContent.text('terms.headline'),
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: AppColors.titleDark,
                              height: 1.28,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _versionLine(),
                            key: const Key('termsVersionLine'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppContent.text('terms.instruction'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPdfArea(context),
                    if (!widget.readOnly && doc != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 1,
                              color: AppColors.borderLight,
                              margin: const EdgeInsets.only(bottom: 20),
                            ),
                            Text(
                              doc.consentHeading.isNotEmpty ? doc.consentHeading : 'Persetujuan Layanan Nasabah',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.titleDark,
                              ),
                            ),
                            if (doc.consentInstruction.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                doc.consentInstruction,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            for (var i = 0; i < doc.consentStatements.length; i++) ...[
                              _buildCheckboxItem(
                                key: Key('termsConsent$i'),
                                value: _checks[i],
                                enabled: _pdfReady && !_submitting,
                                onChanged: (val) => setState(() => _checks[i] = val ?? false),
                                text: doc.consentStatements[i],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_showScrollToBottom && !widget.readOnly)
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: GestureDetector(
                    onTap: _scrollToBottom,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF033172),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF033172).withOpacity(0.24),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_downward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                key: const Key('termsProceedButton'),
                onPressed: widget.readOnly
                    ? () => Navigator.of(context).maybePop()
                    : (_canProceed ? _onProceed : null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF033172),
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: const Color(0xFF94A3B8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        widget.readOnly ? 'Tutup Dokumen' : 'Saya Setuju',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfArea(BuildContext context) {
    if (_loading) {
      return const Padding(
        key: Key('termsLoading'),
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primaryNavy),
              SizedBox(height: 12),
              Text(
                'Memuat dokumen Syarat dan Ketentuan...',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || _pdfBytes == null) {
      return Padding(
        key: const Key('termsError'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: Color(0xFF94A3B8)),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Dokumen tidak dapat ditampilkan.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.pdfViewBuilder != null) {
      final height = (MediaQuery.of(context).size.height * 0.56).clamp(320.0, 520.0);
      return SizedBox(
        height: height,
        child: widget.pdfViewBuilder!(
          _pdfBytes!,
          (pages) {
            if (!mounted) return;
            setState(() => _pdfReady = pages > 0);
          },
          (e) {
            if (!mounted) return;
            setState(() {
              _pdfReady = false;
              _error = 'Dokumen PDF tidak dapat ditampilkan. Silakan muat ulang.';
            });
          },
          (_) {},
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _renderedPages
          .map(
            (pageBytes) => Image.memory(
              pageBytes,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true,
            ),
          )
          .toList(),
    );
  }

  Widget _buildCheckboxItem({
    Key? key,
    required bool value,
    required bool enabled,
    required ValueChanged<bool?> onChanged,
    required String text,
  }) {
    return InkWell(
      key: key,
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFEFF6FF) : const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? const Color(0xFF93C5FD) : AppColors.borderLight,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeColor: const Color(0xFF0550A6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  color: value ? AppColors.textPrimary : AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
