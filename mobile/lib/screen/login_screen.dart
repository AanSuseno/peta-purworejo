import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import './main_navigation_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  String _errorMessage = '';
  bool _isChecking = true;
  bool _isBackendConnected = false;

  // ==================== STATE UNTUK PROSES LOGIN + POLLING ====================
  bool _isProcessingLogin =
      false; // true selama tombol ditekan sampai berhasil masuk
  bool _isRetrying =
      false; // true khusus saat sedang menunggu jeda 3 detik ulang cek
  int _retryCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();

    _checkBackendConnection();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkBackendConnection() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (mounted) {
        setState(() {
          _isBackendConnected = response.statusCode == 200;
          _isChecking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBackendConnected = false;
          _isChecking = false;
        });
      }
    }
  }

  // ==================== ALUR LOGIN + POLLING TIAP 3 DETIK ====================

  Future<void> _handleLoginButtonTap(AuthProvider auth) async {
    if (_isProcessingLogin) return; // cegah tap dobel saat proses berjalan

    if (!mounted) return;
    setState(() {
      _errorMessage = '';
      _isProcessingLogin = true;
      _isRetrying = false;
      _retryCount = 0;
    });

    try {
      // Jalankan proses Google Sign-In sekali (buka picker akun Google).
      await auth.login();
    } catch (e) {
      // Login gagal total (mis. dibatalkan user, atau error dari server) ->
      // hentikan proses, tampilkan pesan error, biarkan user coba tap lagi.
      if (mounted) {
        setState(() {
          _isProcessingLogin = false;
          _isRetrying = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }

    if (!mounted) return;

    // login() sudah selesai tanpa exception. Sekarang mulai cek status
    // auth.isLoggedIn tiap 3 detik -- kalau ternyata belum true (mis. state
    // belum sempat ke-update / delay propagasi), terus diulang sampai bisa.
    _startPollingLoginStatus(auth);
  }

  void _startPollingLoginStatus(AuthProvider auth) {
    _pollTimer?.cancel();

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (auth.isLoggedIn) {
        timer.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
        return;
      }

      // Belum juga login -> tampilkan status "mencoba lagi" dan lanjut
      // menunggu 3 detik berikutnya (timer.periodic otomatis mengulang).
      setState(() {
        _isRetrying = true;
        _retryCount += 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // Jaga-jaga: kalau auth.isLoggedIn ternyata sudah true duluan (mis.
    // ke-update di luar siklus polling), langsung arahkan juga di sini.
    if (auth.isLoggedIn && _pollTimer == null && !_isProcessingLogin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          );
        }
      });
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background banner
          Image.asset(
            'assets/images/splashscreen-banner.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryDark,
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),

          // Overlay gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryDark.withOpacity(0.75),
                  AppColors.primary.withOpacity(0.55),
                  AppColors.primaryDark.withOpacity(0.9),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/icon-app.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.person_rounded,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      'Selamat Datang!',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      'Masuk dengan Google untuk melanjutkan',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Status koneksi backend
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isChecking
                        ? const SizedBox(
                            key: ValueKey('checking'),
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Container(
                            key: const ValueKey('status'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _isBackendConnected
                                  ? Colors.greenAccent.withOpacity(0.18)
                                  : Colors.red.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isBackendConnected
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isBackendConnected
                                      ? Icons.check_circle_rounded
                                      : Icons.error_outline_rounded,
                                  color: _isBackendConnected
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isBackendConnected
                                      ? 'Server terhubung'
                                      : 'Server tidak dapat diakses',
                                  style: TextStyle(
                                    color: _isBackendConnected
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  const Spacer(flex: 3),

                  // Status polling / retry
                  if (_isProcessingLogin && _isRetrying)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.amber.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Mencoba lagi... (percobaan ke-$_retryCount)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Pesan error
                  if (_errorMessage.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Tombol Google Sign-In
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: (_isProcessingLogin)
                          ? null
                          : () => _handleLoginButtonTap(auth),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        disabledBackgroundColor: Colors.white.withOpacity(0.7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 3,
                      ),
                      icon: _isProcessingLogin
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.black54),
                              ),
                            )
                          : const Icon(
                              Icons.g_mobiledata_rounded,
                              color: Colors.red,
                              size: 28,
                            ),
                      label: Text(
                        _isProcessingLogin
                            ? (_isRetrying ? 'Mencoba lagi...' : 'Memproses...')
                            : 'Masuk dengan Google',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      'Dengan masuk, kamu menyetujui Syarat & Ketentuan yang berlaku',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
