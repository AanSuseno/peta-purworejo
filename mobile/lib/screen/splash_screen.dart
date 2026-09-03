import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import './home_screen.dart';
import './login_screen.dart';

/// Splash screen sekaligus gerbang konektivitas.
///
/// Alurnya SENGAJA tidak langsung pindah halaman: harus berhasil cek
/// koneksi ke backend (GET /health) dulu. Kalau gagal, tetap di sini
/// dan user diminta coba lagi -- tidak lanjut ke Home ataupun Login,
/// supaya tidak muncul error yang membingungkan di layar berikutnya
/// gara-gara server memang belum bisa diakses.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  bool _isConnecting = true;
  bool _hasError = false;
  bool _isConnected = false;
  String _statusText = 'Menghubungkan ke server...';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    _connectAndProceed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connectAndProceed() async {
    setState(() {
      _isConnecting = true;
      _hasError = false;
      _isConnected = false;
      _statusText = 'Menghubungkan ke server...';
    });

    // Biar tulisan "Menghubungkan..." sempat terbaca, bukan cuma kedip.
    final connectingDelay = Future.delayed(const Duration(milliseconds: 1100));
    final isConnected = await _checkBackendConnection();
    await connectingDelay;

    if (!mounted) return;

    if (!isConnected) {
      setState(() {
        _isConnecting = false;
        _hasError = true;
        _statusText = 'Tidak dapat terhubung ke server';
      });
      return; // 🔥 berhenti di sini, tidak pindah halaman apa pun
    }

    // Tampilkan status "Terhubung!" sejenak sebelum lanjut, biar user
    // sadar prosesnya berhasil -- tapi tidak dibuat lama-lama.
    setState(() {
      _isConnected = true;
      _statusText = 'Terhubung!';
    });
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    setState(() {
      _statusText = 'Memeriksa sesi login...';
    });
    await Future.delayed(const Duration(milliseconds: 500));

    await _navigateBasedOnSession();
  }

  Future<bool> _checkBackendConnection() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _navigateBasedOnSession() async {
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    String? token;
    try {
      token = await auth.getToken();
    } catch (e) {
      token = null;
    }

    if (!mounted) return;

    final hasSession = token != null && token.isNotEmpty;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => hasSession ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

          // Overlay gradient supaya konten tetap kebaca di atas gambar
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryDark.withOpacity(0.75),
                  AppColors.primary.withOpacity(0.55),
                  AppColors.primaryDark.withOpacity(0.85),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  // Logo dengan animasi fade + scale
                  // Logo dengan animasi fade + scale
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 110,
                        height: 110,
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
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        // 🔥 Padding kecil biar logo tidak mepet ke tepi lingkaran
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/icon-app.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.groups_rounded,
                                size: 54,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      'Komunitas',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      'Terhubung, berbagi, dan tumbuh bersama',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Status koneksi
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _hasError
                        ? _buildErrorState()
                        : _buildConnectingState(),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingState() {
    return Column(
      key: ValueKey(_isConnected ? 'connected' : 'connecting'),
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isConnected
              ? Container(
                  key: const ValueKey('check'),
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 18, color: Colors.white),
                )
              : const SizedBox(
                  key: ValueKey('spinner'),
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _statusText,
            key: ValueKey(_statusText),
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      key: const ValueKey('error'),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Periksa koneksi internet kamu, lalu coba lagi',
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _connectAndProceed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text(
              'Coba Lagi',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
