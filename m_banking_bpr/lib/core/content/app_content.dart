import 'package:flutter/widgets.dart';
import '../services/dynamic_config_service.dart';

/// Kind of a content element (mirrors internal/mobilecontent/registry.go).
enum ContentType { text, multiline, image, phone, email, flag, action }

class ContentSpec {
  final ContentType type;
  final String builtIn; // the value shipped with the app (shown before the first download)
  const ContentSpec(this.type, this.builtIn);
}

/// Content elements of existing screens that the bank manages from the back office
/// (GET /api/v1/content). Keys and built-in values are the same as the backend registry;
/// the app keeps full control over widgets, layout and navigation and only reads
/// validated plain values. An invalid or missing value is never applied: the built-in
/// value (what the app showed before) is used instead.
class AppContent {
  AppContent._();

  static const Map<String, ContentSpec> specs = {
    'app.logo': ContentSpec(ContentType.image, ''),
    'app.announcement': ContentSpec(ContentType.multiline, ''),
    'splash.background': ContentSpec(ContentType.image, ''),
    'splash.tagline': ContentSpec(ContentType.text, 'Sahabat Finansial Terpercaya Anda'),
    'splash.loading_text': ContentSpec(ContentType.text, 'Memuat layanan perbankan...'),
    'splash.disclaimer': ContentSpec(ContentType.multiline,
        'PT BPR Dana Mandiri Bogor berizin dan diawasi oleh Otoritas Jasa Keuangan (OJK) serta merupakan peserta penjaminan Lembaga Penjamin Simpanan (LPS).'),
    'onboarding.slide1_title': ContentSpec(ContentType.text, 'Jadi bestie di dunia finansial anak dengan DMB Mobile'),
    'onboarding.slide1_desc': ContentSpec(ContentType.multiline,
        'Dari uang jajan sampai target impian anak, semua bisa didampingi bersama orang tua secara transparan dan mudah.'),
    'onboarding.slide1_image': ContentSpec(ContentType.image, ''),
    'onboarding.slide2_title': ContentSpec(ContentType.text, 'Wujudkan masa depan keluarga dengan tabungan cerdas'),
    'onboarding.slide2_desc': ContentSpec(ContentType.multiline,
        'Bebas biaya transfer, bunga deposito menguntungkan, dan proteksi transaksi berlapis dalam genggaman Anda.'),
    'onboarding.slide2_image': ContentSpec(ContentType.image, ''),
    'onboarding.button_text': ContentSpec(ContentType.text, 'Mulai Sekarang'),
    'terms.headline': ContentSpec(ContentType.multiline, 'Ringkasan Informasi dan Syarat Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor'),
    'terms.instruction': ContentSpec(ContentType.multiline,
        'Baca dan setujui Ringkasan Informasi serta Syarat dan Ketentuan DMB Mobile by PT BPR Dana Mandiri Bogor.'),
    'login.background': ContentSpec(ContentType.image, ''),
    'login.title': ContentSpec(ContentType.text, 'Selamat Datang'),
    'login.subtitle': ContentSpec(ContentType.multiline, 'Login untuk melanjutkan\nke layanan DMB Mobile'),
    'login.footer': ContentSpec(ContentType.text, 'Transaksi Anda aman bersama DMB'),
    'login.help_badge': ContentSpec(ContentType.text, 'Layanan Resmi 24 Jam'),
    'login.help_title': ContentSpec(ContentType.text, 'Pusat Bantuan Bank DMB'),
    'login.help_subtitle': ContentSpec(ContentType.text, 'Butuh bantuan? Tim kami siap melayani Anda.'),
    'login.security_title': ContentSpec(ContentType.text, 'PENTING: JAGA KERAHASIAAN ANDA'),
    'login.security_text': ContentSpec(ContentType.multiline,
        'Petugas Bank DMB TIDAK PERNAH meminta Kata Sandi, PIN, atau Kode OTP Anda melalui kanal apa pun.'),
    'home.greeting_title': ContentSpec(ContentType.text, 'Selamat Datang,'),
    'home.greeting_subtitle': ContentSpec(ContentType.text, 'Semoga harimu menyenangkan!'),
    'home.banner1_visible': ContentSpec(ContentType.flag, 'true'),
    'home.banner1_title': ContentSpec(ContentType.text, 'DMB Mobile'),
    'home.banner1_subtitle': ContentSpec(ContentType.text, 'Lebih Mudah, Lebih Dekat dengan Anda'),
    'home.banner1_image': ContentSpec(ContentType.image, ''),
    'home.banner1_action': ContentSpec(ContentType.action, 'profil'),
    'home.banner2_visible': ContentSpec(ContentType.flag, 'true'),
    'home.banner2_title': ContentSpec(ContentType.text, 'Tabungan Mikro DMB'),
    'home.banner2_subtitle': ContentSpec(ContentType.text, 'Simpanan dijamin LPS sesuai ketentuan'),
    'home.banner2_image': ContentSpec(ContentType.image, ''),
    'home.banner2_action': ContentSpec(ContentType.action, 'profil'),
    'home.banner3_visible': ContentSpec(ContentType.flag, 'true'),
    'home.banner3_title': ContentSpec(ContentType.text, 'Keamanan Berlapis'),
    'home.banner3_subtitle': ContentSpec(ContentType.text, 'PIN transaksi & perangkat terdaftar'),
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
  };

  static final RegExp _upload = RegExp(r'^/admin/(uploads|images)/[A-Za-z0-9_\-]+\.(png|jpg|jpeg|webp)$');
  static final RegExp _phone = RegExp(r'^[0-9+()\- ]{3,20}$');
  static final RegExp _email = RegExp(r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$');
  static const _actions = {'profil', 'keamanan', 'none'};

  /// Whether [value] may be applied for [key] (same rules as the backend).
  static bool isValid(String key, String value) {
    final spec = specs[key];
    if (spec == null || value.length > 1000 || value.contains('<') || value.contains('>')) return false;
    switch (spec.type) {
      case ContentType.image:
        if (value.isEmpty || _upload.hasMatch(value)) return true;
        final u = Uri.tryParse(value);
        return u != null && u.scheme == 'https' && u.host.isNotEmpty;
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

  /// Text content.
  static String text(String key) => _value(key);

  /// Image content: absolute URL to load, or null to use the image bundled in the app.
  static String? imageUrl(String key) {
    final v = _value(key);
    if (v.isEmpty) return null;
    return DynamicConfigService().resolveUrl(v);
  }

  /// Visibility flags.
  static bool flag(String key) => _value(key) == 'true';
}

/// Rebuilds the visible screens when a new content version has been downloaded, so a
/// published change appears without restarting or rebuilding the app. Navigation and
/// screen state are kept (elements are rebuilt, not recreated).
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

/// Image element managed from the back office; the image bundled with the app is used
/// when no image is published or the published one can not be loaded.
class ContentImage extends StatelessWidget {
  final String contentKey;
  final String asset;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;

  const ContentImage(this.contentKey, {super.key, required this.asset, this.fit = BoxFit.cover, this.width, this.height, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    final url = AppContent.imageUrl(contentKey);
    Widget bundled() => Image.asset(asset, fit: fit, width: width, height: height, alignment: alignment);
    if (url == null) return bundled();
    return Image.network(url, fit: fit, width: width, height: height, alignment: alignment, errorBuilder: (_, __, ___) => bundled());
  }
}
