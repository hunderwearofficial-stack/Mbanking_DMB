import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/content/app_content.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/terms_document.dart';
import '../../../data/repositories/terms_repository.dart';
import '../../blocs/auth/auth_cubit.dart';
import 'login_screen.dart';
import '../../widgets/app_validation_feedback.dart';

/// Builds the PDF viewer. [onLoaded] reports the page count once the document is
/// rendered; [onError] reports a document that can not be opened (corrupt file).
typedef TermsPdfViewBuilder = Widget Function(
  Uint8List bytes,
  void Function(int pages) onLoaded,
  void Function(Object error) onError,
  void Function(int page) onPageChanged,
);

/// Syarat dan Ketentuan before login. The text is the PDF of the version published by
/// the bank (back office); consent is valid only once the backend has recorded it.
class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key, this.repository, this.pdfViewBuilder, this.onAccepted});

  /// Injected in tests; defaults to the app's API client.
  final TermsRepository? repository;

  /// Injected in tests (no native PDF renderer in widget tests); defaults to pdfx.
  final TermsPdfViewBuilder? pdfViewBuilder;

  /// Called after the backend confirmed the consent; defaults to opening the login screen.
  final VoidCallback? onAccepted;

  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = true;

  late final TermsRepository _repo;
  TermsDocument? _doc;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;
  bool _pdfReady = false;
  int _pageCount = 0;
  int _currentPage = 1;
  List<bool> _checks = const [];
  bool _submitting = false;
  PdfController? _pdfController;

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
      _pageCount = 0;
      _currentPage = 1;
    });
    try {
      final doc = await _repo.fetchActive();
      final bytes = await _repo.fetchPdf(doc);
      if (!mounted) return;
      _pdfController?.dispose();
      _pdfController = widget.pdfViewBuilder == null ? PdfController(document: PdfDocument.openData(bytes)) : null;
      setState(() {
        _doc = doc;
        _pdfBytes = bytes;
        _checks = List<bool>.filled(doc.consentStatements.length, false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _doc = null;
        _pdfBytes = null;
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

    // Hide floating down button when near the bottom
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
    final doc = _doc;
    if (!_canProceed || doc == null) return;
    setState(() => _submitting = true);
    try {
      // Checking the boxes is not consent until the backend confirms the record.
      await _repo.accept(doc);
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
    _pdfController?.dispose();
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
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 4,
                bottom: MediaQuery.of(context).padding.bottom + 36,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Headline Title
                  Text(
                    AppContent.text('terms.headline'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      height: 1.28,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Version & effective date of the published document
                  Text(
                    _versionLine(),
                    key: const Key('termsVersionLine'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF64748B),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Subtitle Instruction
                  Text(
                    AppContent.text('terms.instruction'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // PDF document (published version)
                  _buildPdfArea(context),

                  const SizedBox(height: 28),

                  // Divider Before Agreement Section
                  Container(
                    height: 1.5,
                    color: const Color(0xFFE2E8F0),
                    margin: const EdgeInsets.only(bottom: 24),
                  ),

                  if (doc != null) ...[
                    Text(
                      doc.consentHeading.isNotEmpty ? doc.consentHeading : 'Persetujuan Layanan Nasabah',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (doc.consentInstruction.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        doc.consentInstruction,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    for (var i = 0; i < doc.consentStatements.length; i++) ...[
                      _buildCheckboxItem(
                        key: Key('termsConsent$i'),
                        value: _checks[i],
                        enabled: _pdfReady && !_submitting,
                        onChanged: (val) => setState(() => _checks[i] = val ?? false),
                        text: doc.consentStatements[i],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_pdfReady)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Persetujuan dapat diberikan setelah dokumen PDF berhasil ditampilkan.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],

                  // Primary Action Button: active only when the PDF is shown, the version is
                  // valid and every statement is checked; confirmed by the backend.
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const Key('termsProceedButton'),
                      onPressed: _canProceed ? _onProceed : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16984B), // DMB Green
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        elevation: _canProceed ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_submitting)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            Icon(
                              _canProceed ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                              size: 18,
                            ),
                          const SizedBox(width: 8),
                          const Text(
                            'Setuju & Lanjutkan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Floating Scroll-to-Bottom Button (Visible only when not at bottom, to easily reach checkboxes)
            if (_showScrollToBottom)
              Positioned(
                right: 20,
                bottom: 24,
                child: GestureDetector(
                  onTap: _scrollToBottom,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.28),
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
    );
  }

  Widget _buildPdfArea(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.62;
    Widget body;
    if (_loading) {
      body = const Center(
        key: Key('termsLoading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00897B)),
            SizedBox(height: 12),
            Text('Memuat dokumen Syarat dan Ketentuan...', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
        ),
      );
    } else if (_error != null || _pdfBytes == null) {
      body = Center(
        key: const Key('termsError'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: Color(0xFF94A3B8)),
              const SizedBox(height: 10),
              Text(
                _error ?? 'Dokumen tidak dapat ditampilkan.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.4),
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
    } else {
      void onLoaded(int pages) {
        if (!mounted) return;
        setState(() {
          _pdfReady = pages > 0;
          _pageCount = pages;
        });
      }

      void onError(Object e) {
        if (!mounted) return;
        setState(() {
          _pdfReady = false;
          _error = 'Dokumen PDF tidak dapat ditampilkan. Silakan muat ulang.';
        });
      }

      void onPage(int page) {
        if (mounted) setState(() => _currentPage = page);
      }

      body = widget.pdfViewBuilder != null
          ? widget.pdfViewBuilder!(_pdfBytes!, onLoaded, onError, onPage)
          : PdfView(
              controller: _pdfController!,
              onDocumentLoaded: (d) => onLoaded(d.pagesCount),
              onDocumentError: onError,
              onPageChanged: onPage,
              backgroundDecoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
            );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _doc != null ? 'Syarat dan Ketentuan • Versi ${_doc!.versionNumber}' : 'Syarat dan Ketentuan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                ),
                if (_pdfReady)
                  Text(
                    'Halaman $_currentPage dari $_pageCount',
                    key: const Key('termsPageIndicator'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                if (_pdfReady && _pdfController != null) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _currentPage > 1
                        ? () => _pdfController!.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                        : null,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _currentPage < _pageCount
                        ? () => _pdfController!.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(height: height, child: body),
          if (_pdfReady)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Geser ke kiri/kanan untuk berpindah halaman • cubit untuk memperbesar',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
            ),
        ],
      ),
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
          color: value ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
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
                activeColor: const Color(0xFF16984B),
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
                  color: value ? const Color(0xFF0F172A) : const Color(0xFF334155),
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
