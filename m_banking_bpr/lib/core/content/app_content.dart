import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../config/app_environment.dart';
import '../network/api_client.dart';
import '../services/dynamic_config_service.dart';

enum ContentType { text, multiline, image, phone, email, flag, action }

class ContentSpec {
  final ContentType type;
  final String builtIn; // the value shipped with the app (shown before the first download)
  const ContentSpec(this.type, this.builtIn);
}

class AppContent {
  AppContent._();

  static const Map<String, ContentSpec> specs = {
    'app.logo': ContentSpec(ContentType.image, ''),
    'app.announcement': ContentSpec(ContentType.multiline, ''),
    'app.footer': ContentSpec(ContentType.multiline,
        'Bank DMB berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS).'),
    'splash.tagline': ContentSpec(ContentType.text, 'Sahabat Finansial Terpercaya Anda'),
    'onboarding.background': ContentSpec(ContentType.image, '/admin/uploads/onboarding_hero.jpg'),
    'onboarding.title': ContentSpec(ContentType.text,
        'Selamat datang di Bank DMB'),
    'onboarding.subtitle': ContentSpec(ContentType.multiline,
        'Pantau saldo tabungan, mutasi rekening, deposito, dan pinjaman Anda secara aman dan real-time.'),
    'onboarding.button_text': ContentSpec(ContentType.text, 'Masuk Sekarang'),
    'terms.headline': ContentSpec(ContentType.multiline, 'Ringkasan Informasi dan Syarat Ketentuan Bank DMB'),
    'terms.instruction': ContentSpec(ContentType.multiline,
        'Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan Bank DMB.'),
    'login.hero_slide1_badge': ContentSpec(ContentType.text, 'TABUNGAN DANA MANDIRI'),
    'login.hero_slide1_title': ContentSpec(ContentType.text, 'Menabung aman, usaha makin lancar'),
    'login.hero_slide2_badge': ContentSpec(ContentType.text, 'DEPOSITO BERJANGKA'),
    'login.hero_slide2_title': ContentSpec(ContentType.text, 'Imbal hasil kompetitif, dijamin LPS'),
    'login.hero_slide3_badge': ContentSpec(ContentType.text, 'LAYANAN DIGITAL'),
    'login.hero_slide3_title': ContentSpec(ContentType.text, 'Pantau saldo dan mutasi kapan saja'),
    'login.title': ContentSpec(ContentType.text, 'Selamat datang'),
    'login.subtitle': ContentSpec(ContentType.multiline, 'Masuk ke akun DMB Anda'),
    'home.greeting_title': ContentSpec(ContentType.text, 'Selamat datang,'),
    'home.greeting_subtitle': ContentSpec(ContentType.text, 'Semoga harimu lancar.'),
    'home.greeting_note': ContentSpec(ContentType.text, 'Pantau saldo dan transaksi Anda dengan aman.'),
    'home.info_section_title': ContentSpec(ContentType.text, 'Info untuk Anda'),
    'home.banner1_visible': ContentSpec(ContentType.flag, 'true'),
    'home.banner1_tag': ContentSpec(ContentType.text, 'UNTUK ANDA'),
    'home.banner1_title': ContentSpec(ContentType.text, 'DMB Mobile'),
    'home.banner1_subtitle': ContentSpec(ContentType.text, 'Lebih Mudah, Lebih Dekat dengan Anda'),
    'home.banner1_image': ContentSpec(ContentType.image, '/admin/uploads/home_promo_plant.jpg'),
    'home.banner1_action': ContentSpec(ContentType.action, 'profil'),
    'home.banner2_visible': ContentSpec(ContentType.flag, 'true'),
    'home.banner2_tag': ContentSpec(ContentType.text, 'INFO PRODUK'),
    'home.banner2_title': ContentSpec(ContentType.text, 'Tabungan & Deposito DMB'),
    'home.banner2_subtitle': ContentSpec(ContentType.text, 'Simpanan dijamin LPS sesuai ketentuan'),
    'home.banner2_image': ContentSpec(ContentType.image, ''),
    'home.banner2_action': ContentSpec(ContentType.action, 'profil'),
    'home.banner3_visible': ContentSpec(ContentType.flag, 'true'),
    'home.banner3_tag': ContentSpec(ContentType.text, 'KEAMANAN'),
    'home.banner3_title': ContentSpec(ContentType.text, 'Keamanan Berlapis'),
    'home.banner3_subtitle': ContentSpec(ContentType.text, 'PIN & perangkat terdaftar terlindungi'),
    'home.banner3_image': ContentSpec(ContentType.image, ''),
    'home.banner3_action': ContentSpec(ContentType.action, 'keamanan'),
    'helpdesk.intro_title': ContentSpec(ContentType.text, 'Butuh Bantuan?'),
    'helpdesk.intro_text': ContentSpec(ContentType.multiline,
        'Tim Customer Care Bank DMB siap melayani Anda melalui kanal komunikasi resmi.'),
    'helpdesk.call_center_desc': ContentSpec(ContentType.text, 'Layanan bebas pulsa untuk nasabah aktif'),
    'helpdesk.whatsapp_desc': ContentSpec(ContentType.text, 'Akun bisnis resmi terverifikasi dengan centang hijau'),
    'helpdesk.email_desc': ContentSpec(ContentType.text, 'Dukungan surat elektronik resmi Bank DMB'),
    'contact.call_center_display': ContentSpec(ContentType.text, '(0251) 832-1234'),
    'contact.call_center_dial': ContentSpec(ContentType.phone, '02518321234'),
    'contact.whatsapp_display': ContentSpec(ContentType.text, '0811-9988-7766'),
    'contact.whatsapp_dial': ContentSpec(ContentType.phone, '081199887766'),
    'contact.email': ContentSpec(ContentType.email, 'layanan@bprdanamandiri.co.id'),
    'contact.office_short': ContentSpec(ContentType.text, 'Jl. Pajajaran No. 88, Bogor'),
    'contact.office_address': ContentSpec(ContentType.multiline, 'Jl. Pajajaran No. 88, Kota Bogor, Jawa Barat 16128'),
    'contact.office_hours': ContentSpec(ContentType.text, 'Senin - Jumat (08.00 - 15.30 WIB)'),
    'company.hero_image': ContentSpec(ContentType.image, ''),
    'company.hero_title': ContentSpec(ContentType.text, 'Mitra Keuangan UMKM Bogor Sejak 1989'),
    'company.established_year': ContentSpec(ContentType.text, '1989'),
    'company.branches': ContentSpec(ContentType.multiline,
        'Kantor Pusat Bogor | Jl Raya Puncak Ciawi No 402, Kel. Bendungan Kec. Ciawi Kab. Bogor, Jawa Barat 16720\nKantor Pusat Sukabumi | Jl. Raya Cikukulu RT. 019 RW. 005 Desa Cisande, Kec. Cicantayan Kab. Sukabumi, Jawa Barat 43155\nKantor Pusat Cianjur | Jl. Raya Cianjur - Bandung RT. 001 RW. 006 No. 7 - 8, Desa Babakancaringin Kec. Karangtengah Kab. Cianjur, Jawa Barat 43281\nKantor Pusat Tangerang Selatan | Ruko Harvest Bintaro Residence No. 27-28, Jl. Merpati Raya Ciputat, Tangerang Selatan, Banten 15413'),
    'company.about_description': ContentSpec(ContentType.multiline,
        'Bank DMB berawal di Bogor sebagai BPR yang melayani pedagang pasar dan pengusaha mikro. Fokus kami tetap sama hingga kini: Akses modal usaha yang mudah dan simpanan yang aman, diawasi OJK dan dijamin LPS.'),
    'company.vision': ContentSpec(ContentType.multiline,
        'Menjadi penyedia layanan keuangan mikro yang terpercaya bagi bangsa, menjadikan kehidupan dan masa depan yang lebih baik.'),
    'company.mission': ContentSpec(ContentType.multiline,
        'Menjadi mitra pilihan bagi micro-productive segmen yang menjunjung nilai-nilai organisasi dalam memberikan kualitas pelayanan yang handal dan secara bersama menciptakan kesempatan tumbuh dan berkembang.'),
    'company.lps_guarantee_text': ContentSpec(ContentType.multiline,
        'Seluruh simpanan dana nasabah (Tabungan & Deposito) dijamin oleh LPS hingga Rp 2 Miliar per nasabah sesuai syarat dan ketentuan berlaku.'),
    'product.deposito_rate_bps': ContentSpec(ContentType.text, '625'),
    'product.deposito_rate_label': ContentSpec(ContentType.text, '6.25% p.a. (ilustrasi)'),
    'product.deposito_min_amount': ContentSpec(ContentType.text, '1000000'),
    'product.deposito_max_amount': ContentSpec(ContentType.text, '2000000000'),
    'product.deposito_tax_threshold': ContentSpec(ContentType.text, '7500000'),
    'product.deposito_tax_percent': ContentSpec(ContentType.text, '20'),
    'product.loan_rate_bps': ContentSpec(ContentType.text, '1500'),
    'product.loan_rate_label': ContentSpec(ContentType.text, '1.25% flat/bln (ilustrasi)'),
    'product.loan_min_amount': ContentSpec(ContentType.text, '5000000'),
    'product.loan_max_amount': ContentSpec(ContentType.text, '500000000'),
  };

  static final RegExp _upload = RegExp(r'^/admin/(uploads|images)/[A-Za-z0-9_\-]+\.(png|jpg|jpeg|webp)$');
  static final RegExp _phone = RegExp(r'^[0-9+()\- ]{3,20}$');
  static final RegExp _email = RegExp(r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$');
  static const _actions = {'profil', 'keamanan', 'none'};

  static bool isValid(String key, String value) {
    final spec = specs[key];
    if (spec == null || value.length > 1000 || value.contains('<') || value.contains('>')) return false;
    switch (spec.type) {
      case ContentType.image:
        if (value.isEmpty || _upload.hasMatch(value)) return true;
        final u = Uri.tryParse(value);
        if (u == null || u.host.isEmpty) return false;
        if (u.scheme == 'https') return true;
        if (u.scheme == 'http' && !AppEnvironment.isProduction) {
          final apiUri = Uri.tryParse(AppEnvironment.apiBaseUrl);
          if (apiUri != null && apiUri.host.isNotEmpty && apiUri.host.toLowerCase() == u.host.toLowerCase()) {
            return true;
          }
        }
        return false;
      case ContentType.phone:
        return _phone.hasMatch(value);
      case ContentType.email:
        return _email.hasMatch(value);
      case ContentType.flag:
        return value == 'true' || value == 'false';
      case ContentType.action:
        return _actions.contains(value);
      case ContentType.text:
        return value.trim().isNotEmpty && !value.contains('\n');
      case ContentType.multiline:
        return true;
    }
  }

  static String _value(String key) {
    final v = DynamicConfigService().contentItem(key);
    if (v != null && isValid(key, v)) return v;
    return specs[key]?.builtIn ?? '';
  }

  static String text(String key) => _value(key);

  static int intValue(String key, int defaultValue) {
    final raw = _value(key).trim();
    return int.tryParse(raw) ?? defaultValue;
  }

  static String? imageUrl(String key) {
    final v = _value(key);
    if (v.isEmpty) return null;
    return DynamicConfigService().resolveUrl(v);
  }

  static bool flag(String key) => _value(key) == 'true';

  static Color color(String key, Color fallback) {
    var raw = _value(key).trim().replaceFirst('#', '');
    if (raw.length == 6) {
      raw = 'FF$raw';
    }
    if (raw.length != 8) return fallback;
    final parsed = int.tryParse(raw, radix: 16);
    return parsed != null ? Color(parsed) : fallback;
  }
}

class ContentRefreshScope extends StatefulWidget {
  final Widget child;
  const ContentRefreshScope({super.key, required this.child});

  @override
  State<ContentRefreshScope> createState() => _ContentRefreshScopeState();
}

class _ContentRefreshScopeState extends State<ContentRefreshScope> {
  int _version = DynamicConfigService().contentVersion;

  @override
  void initState() {
    super.initState();
    DynamicConfigService().addListener(_onChange);
  }

  @override
  void dispose() {
    DynamicConfigService().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final v = DynamicConfigService().contentVersion;
    if (v == _version || !mounted) return;
    _version = v;
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class RemoteImageCache {
  RemoteImageCache._();

  static final Map<String, Uint8List> _memCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};
  static Dio? _dio;

  static const List<String> _imageKeys = [
    'app.logo',
    'onboarding.background',
    'home.banner1_image',
    'home.banner2_image',
    'home.banner3_image',
    'company.hero_image',
  ];

  static Dio _client() => _dio ??= ApiClient.createSecureDio(baseUrl: '');

  static File _diskFile(String url) {
    final hash = sha256.convert(utf8.encode(url)).toString();
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}dmb_img_cache');
    return File('${dir.path}${Platform.pathSeparator}$hash.bin');
  }

  static Uint8List? getCachedSync(String url) => _memCache[url];

  static Future<void> preloadStartupImages() async {
    for (final key in _imageKeys) {
      final url = AppContent.imageUrl(key);
      if (url == null || _memCache.containsKey(url)) continue;
      try {
        final file = _diskFile(url);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _memCache[url] = bytes;
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> warmUpAllContentImages() async {
    final urls = <String>{};
    for (final key in _imageKeys) {
      final url = AppContent.imageUrl(key);
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
    }
    if (urls.isEmpty) return;
    try {
      await Future.wait(urls.map(getOrFetch)).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Never block app startup if an optional remote image is slow.
    }
  }

  static Future<Uint8List?> getOrFetch(String url) {
    final cached = _memCache[url];
    if (cached != null) return Future<Uint8List?>.value(cached);
    return _inflight.putIfAbsent(url, () async {
      try {
        final file = _diskFile(url);
        if (await file.exists()) {
          final diskBytes = await file.readAsBytes();
          if (diskBytes.isNotEmpty) {
            _memCache[url] = diskBytes;
            return diskBytes;
          }
        }
        final resp = await _client().get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        final data = resp.data;
        if (data != null && data.isNotEmpty) {
          final bytes = Uint8List.fromList(data);
          _memCache[url] = bytes;
          try {
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
          } catch (_) {}
          return bytes;
        }
      } catch (_) {
      } finally {
        _inflight.remove(url);
      }
      return null;
    });
  }
}

class ContentImage extends StatefulWidget {
  final String contentKey;
  final String asset;
  final Widget? placeholder;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;

  const ContentImage(
    this.contentKey, {
    super.key,
    this.asset = '',
    this.placeholder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
  });

  @override
  State<ContentImage> createState() => _ContentImageState();
}

class _ContentImageState extends State<ContentImage> {
  String? _fetchingUrl;

  void _ensureFetched(String url) {
    if (_fetchingUrl == url || RemoteImageCache.getCachedSync(url) != null) return;
    _fetchingUrl = url;
    RemoteImageCache.getOrFetch(url).then((bytes) {
      if (bytes != null && mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = AppContent.imageUrl(widget.contentKey);
    Widget fallback() {
      if (widget.placeholder != null) return widget.placeholder!;
      if (widget.asset.isNotEmpty) {
        return Image.asset(
          widget.asset,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          alignment: widget.alignment,
        );
      }
      return const SizedBox.shrink();
    }
    if (url == null) return fallback();

    final cachedBytes = RemoteImageCache.getCachedSync(url);
    if (cachedBytes != null) {
      return Image.memory(
        cachedBytes,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    _ensureFetched(url);
    return fallback();
  }
}
