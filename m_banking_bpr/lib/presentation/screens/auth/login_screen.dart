import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
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
  String _uploadedLogoUrl = '';

  // DMB Green Color Palette
  static const Color dmbGreen = Color(0xFF16984B); // Vibrant DMB Green
  static const Color dmbGreenDark = Color(0xFF0E6832); // Deep Bank Green
  static const Color dmbMint = Color(0xFFF0FDF4); // Mint Accent Tint
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderColor = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _loadSavedPhone();
    _loadBankLogoConfig();
  }

  Future<void> _loadSavedPhone() async {
    try {
      final savedPhone = await context.read<AuthCubit>().authRepository.secureStorage.getPhoneNumber();
      if (mounted && savedPhone != null && savedPhone.isNotEmpty && _phoneController.text.isEmpty) {
        setState(() {
          _phoneController.text = savedPhone;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBankLogoConfig() async {
    try {
      final apiClient = context.read<AuthCubit>().authRepository.apiClient;
      final res = await apiClient.get('/api/v1/config');
      if (mounted && res is Map<String, dynamic>) {
        final logo = (res['logo_url'] as String?) ?? '';
        if (logo.isNotEmpty) {
          setState(() => _uploadedLogoUrl = logo);
        }
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
      _showWarning('Kata sandi wajib diisi');
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

  void _showHelpdeskModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dmbMint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: dmbGreen, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pusat Bantuan & CS Bank DMB',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark),
                        ),
                        Text(
                          'Layanan resmi pengaduan nasabah Mobile Banking',
                          style: TextStyle(fontSize: 12, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildHelpRow(Icons.phone_in_talk_rounded, 'Call Center Resmi', '(0251) 832-1234'),
              const SizedBox(height: 10),
              _buildHelpRow(Icons.chat_bubble_rounded, 'WhatsApp Customer Service', '0811-9988-7766'),
              const SizedBox(height: 10),
              _buildHelpRow(Icons.mail_outline_rounded, 'Email Pengaduan', 'layanan@bprdanamandiribogor.co.id'),
              const SizedBox(height: 10),
              _buildHelpRow(Icons.schedule_rounded, 'Jam Operasional Kantor', 'Senin - Jumat (08.00 - 15.00 WIB)'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dmbGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup Bantuan', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: dmbGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: textMuted)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textDark),
                ),
              ],
            ),
          ),
        ],
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
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Clean Top Header: Official Bank Logo + Divider + Institution + Help
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Official Bank Logo + Entity Name
                        Row(
                          children: [
                            _uploadedLogoUrl.isNotEmpty
                                ? Image.network(
                                    _uploadedLogoUrl.startsWith('http')
                                        ? _uploadedLogoUrl
                                        : '${ApiEndpoints.baseUrl}$_uploadedLogoUrl',
                                    height: 38,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Image.asset(
                                      'assets/images/bank_logo.png',
                                      height: 38,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : Image.asset(
                                    'assets/images/bank_logo.png',
                                    height: 38,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: dmbMint,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'DMB',
                                          style: TextStyle(
                                            color: dmbGreenDark,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            const SizedBox(width: 10),
                            Container(width: 1.2, height: 26, color: const Color(0xFFCBD5E1)),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BANK DMB',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: dmbGreenDark,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'PT BPR DANA MANDIRI BOGOR',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: dmbGreen,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Right: Minimal "Bantuan" button
                        InkWell(
                          onTap: _showHelpdeskModal,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: dmbMint,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.headset_mic_rounded, color: dmbGreen, size: 15),
                                SizedBox(width: 5),
                                Text(
                                  'Bantuan',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: dmbGreenDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 36),

                    // 2. Direct Clean Title & Subtitle (No stacked AI banners)
                    const Text(
                      'Masuk',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: textDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Silakan masukkan nomor handphone dan kata sandi akun Mobile Banking Anda.',
                      style: TextStyle(
                        fontSize: 13,
                        color: textMuted,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // 3. Form Input 1: Nomor Handphone
                    const Text(
                      'Nomor Handphone',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Contoh: 081234567890',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, fontWeight: FontWeight.normal),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: dmbGreen, width: 1.6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          prefixIcon: const Icon(Icons.phone_android_rounded, color: dmbGreen, size: 20),
                          suffixIcon: _phoneController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.cancel_rounded, color: Color(0xFF94A3B8), size: 18),
                                  onPressed: () => setState(() => _phoneController.clear()),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 4. Form Input 2: Kata Sandi
                    const Text(
                      'Kata Sandi',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Masukkan kata sandi',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, fontWeight: FontWeight.normal),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: dmbGreen, width: 1.6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: dmbGreen, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 5. Utility Row: Remember Me & Forgot Password
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _rememberMe = !_rememberMe),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: dmbGreen,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) => setState(() => _rememberMe = val ?? false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Ingat nomor HP',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: textMuted,
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
                              'Lupa kata sandi?',
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

                    const SizedBox(height: 24),

                    // 6. Solid DMB Green Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: dmbGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isLoading ? null : _onLogin,
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text(
                                'Masuk',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 7. Clean Secondary Link: Aktivasi M-Banking (Simple inline text, NOT a big box)
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Belum memiliki akun Mobile Banking? ',
                            style: TextStyle(fontSize: 12.5, color: textMuted),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ActivationScreen()),
                              );
                            },
                            child: const Text(
                              'Aktivasi Sekarang',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: dmbGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 8. Subtle Single Device Security Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_outlined, color: dmbGreen, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Proteksi Single Active Device: Akun terikat aman pada satu smartphone aktif.',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF475569),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // 9. Regulatory Compliance Footer (matching Backoffice)
                    Container(
                      height: 1,
                      color: const Color(0xFFF1F5F9),
                      margin: const EdgeInsets.only(bottom: 14),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Terdaftar & Diawasi:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/images/logo_ojk.svg',
                          height: 24,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 14),
                        Container(width: 1, height: 16, color: const Color(0xFFE2E8F0)),
                        const SizedBox(width: 14),
                        const Text(
                          'Peserta:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/images/logo_lps.svg',
                          height: 22,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'PT BPR Dana Mandiri Bogor berizin & diawasi oleh OJK\nserta merupakan peserta penjaminan LPS.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF94A3B8),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
