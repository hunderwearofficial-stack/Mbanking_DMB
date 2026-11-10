import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/auth/auth_state.dart';
import '../home/home_screen.dart';
import 'activation_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  // Colors aligned with DMB Mobile Executive Design
  static const Color primaryNavy = Color(0xFF0B356D); // Official Deep Navy Blue
  static const Color dmbGreen = Color(0xFF16984B); // Vibrant DMB Green Accent
  static const Color titleDark = Color(0xFF0B2546); // Executive Headline Navy
  static const Color textMuted = Color(0xFF64748B); // Slate Muted
  static const Color borderColor = Color(0xFFE2E8F0); // Subtle Border

  @override
  void initState() {
    super.initState();
    _loadSavedPhone();
  }

  Future<void> _loadSavedPhone() async {
    try {
      final savedPhone =
          await context.read<AuthCubit>().authRepository.secureStorage.getPhoneNumber();
      if (mounted && savedPhone != null && savedPhone.isNotEmpty && _phoneController.text.isEmpty) {
        setState(() {
          _phoneController.text = savedPhone;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (phone.isEmpty) {
      _showWarning('Nomor handphone wajib diisi');
      return;
    }

    if (password.isEmpty) {
      _showWarning('PIN / Password wajib diisi');
      return;
    }

    context.read<AuthCubit>().login(
          identifier: phone,
          password: password,
        );
  }

  void _showWarning(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: dmbGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Refactored Executive Pusat Bantuan Sheet
  void _showHelpdeskModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.only(left: 22, right: 22, top: 12, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Executive Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: dmbGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Layanan Resmi 24 Jam',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: dmbGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pusat Bantuan Bank DMB',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: titleDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Butuh bantuan? Tim kami siap melayani Anda.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // 1. Call Center Card
              _buildHelpContactCard(
                icon: Icons.phone_in_talk_rounded,
                iconColor: primaryNavy,
                title: 'Call Center Bank DMB',
                subtitle: '(0251) 832-1234 • Bebas Pulsa',
                badgeText: 'Telepon →',
                badgeColor: primaryNavy,
                badgeBg: const Color(0xFFF1F5F9),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '(0251) 832-1234'));
                  Navigator.pop(ctx);
                  _showToast('Nomor Call Center disalin: (0251) 832-1234');
                },
              ),

              // 2. WhatsApp Card
              _buildHelpContactCard(
                icon: Icons.chat_bubble_rounded,
                iconColor: const Color(0xFF16984B),
                title: 'WhatsApp Customer Care',
                subtitle: '0811-9988-7766 • Terverifikasi',
                badgeText: 'Chat WA →',
                badgeColor: const Color(0xFF16984B),
                badgeBg: const Color(0xFFF0FDF4),
                isVerified: true,
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '081199887766'));
                  Navigator.pop(ctx);
                  _showToast('Nomor WhatsApp disalin: 0811-9988-7766');
                },
              ),

              // 3. Email Card (clean, no awkward wrap)
              _buildHelpContactCard(
                icon: Icons.mail_rounded,
                iconColor: const Color(0xFF0D9488),
                title: 'Email Layanan Nasabah',
                subtitle: 'layanan@bprdanamandiri.co.id',
                badgeText: 'Kirim Email →',
                badgeColor: const Color(0xFF0D9488),
                badgeBg: const Color(0xFFF0FDFA),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'layanan@bprdanamandiri.co.id'));
                  Navigator.pop(ctx);
                  _showToast('Alamat email disalin: layanan@bprdanamandiri.co.id');
                },
              ),

              // 4. Kantor Operasional Card
              _buildHelpContactCard(
                icon: Icons.account_balance_rounded,
                iconColor: const Color(0xFF475569),
                title: 'Kantor Pusat Operasional',
                subtitle: 'Jl. Pajajaran No. 88, Bogor • 08.00–15.00',
                badgeText: null,
                badgeColor: Colors.transparent,
                badgeBg: Colors.transparent,
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'Jl. Pajajaran No. 88, Bogor'));
                  Navigator.pop(ctx);
                  _showToast('Alamat kantor disalin');
                },
              ),

              const SizedBox(height: 10),

              // Security Warning Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFFDC2626), size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PENTING: JAGA KERAHASIAAN ANDA',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF991B1B),
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Petugas Bank DMB TIDAK PERNAH meminta Kata Sandi, PIN, atau Kode OTP Anda melalui kanal apa pun.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFFB91C1C),
                              height: 1.35,
                            ),
                          ),
                        ],
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
  }

  Widget _buildHelpContactCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String? badgeText,
    required Color badgeColor,
    required Color badgeBg,
    bool isVerified = false,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: titleDark,
                              ),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded, size: 14, color: dmbGreen),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeText != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: badgeColor.withOpacity(0.2)),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const HomeScreen(),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 350),
              ),
            );
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(state.message)),
                  ],
                ),
                backgroundColor: const Color(0xFFDC2626),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;

          return Scaffold(
            backgroundColor: Colors.white,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Background Mount Salak & Tugu Kujang Artwork
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/splash_artwork.jpg',
                    fit: BoxFit.cover,
                  ),
                ),

                // 2. White Soft Wash Gradient to ensure form contrast & readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.20, 0.32, 0.85, 1.0],
                        colors: [
                          Colors.white.withOpacity(0.08),
                          Colors.white.withOpacity(0.40),
                          Colors.white.withOpacity(0.95),
                          Colors.white.withOpacity(0.98),
                          Colors.white.withOpacity(0.20),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Foreground Form Layer
                SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Right Helpdesk Icon
                        Align(
                          alignment: Alignment.topRight,
                          child: InkWell(
                            onTap: _showHelpdeskModal,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.headset_mic_outlined,
                                color: primaryNavy,
                                size: 18,
                              ),
                            ),
                          ),
                        ),

                        // Center Official DMB Mobile Logo
                        Center(
                          child: Image.asset(
                            'assets/images/bank_logo.png',
                            height: 64,
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Title: Selamat Datang
                        const Text(
                          'Selamat Datang',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: titleDark,
                            letterSpacing: -0.4,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Subtitle: Login untuk melanjutkan ke layanan DMB Mobile
                        const Text(
                          'Login untuk melanjutkan\nke layanan DMB Mobile',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w400,
                            color: textMuted,
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Form Input 1: Nomor Handphone
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Nomor Handphone',
                              hintStyle: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                color: Color(0xFF4A607A),
                                size: 22,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Form Input 2: PIN / Password
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: 'PIN / Password',
                              hintStyle: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: Color(0xFF4A607A),
                                size: 22,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF64748B),
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Options Row: Ingat Saya (Circle) & Lupa PIN?
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => setState(() => _rememberMe = !_rememberMe),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _rememberMe
                                              ? dmbGreen
                                              : const Color(0xFF94A3B8),
                                          width: 1.5,
                                        ),
                                        color:
                                            _rememberMe ? dmbGreen : Colors.transparent,
                                      ),
                                      child: _rememberMe
                                          ? const Icon(Icons.check,
                                              size: 11, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Ingat Saya',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                child: Text(
                                  'Lupa PIN?',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: dmbGreen,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // Primary Action Button: Login →
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _onLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryNavy,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shadowColor: primaryNavy.withOpacity(0.35),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Login',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward_rounded, size: 18),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Divider: atau
                        const Row(
                          children: [
                            Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'atau',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Secondary Action Button: + Daftar Akun
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ActivationScreen()),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: primaryNavy,
                              side: const BorderSide(color: primaryNavy, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_alt_1_rounded, size: 19),
                                SizedBox(width: 8),
                                Text(
                                  'Daftar Akun',
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

                        const SizedBox(height: 24),

                        // Bottom Security Notice
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.shield_outlined, size: 16, color: primaryNavy),
                              SizedBox(width: 6),
                              Text(
                                'Transaksi Anda aman bersama DMB',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
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
