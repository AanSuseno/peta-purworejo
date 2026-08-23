import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';
import 'secure_storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '1040742393190-iqja9lb7fcb1p09pfh0iop1n93etpcnm.apps.googleusercontent.com',
  );
  final AuthService _authService = AuthService();
  final SecureStorageService _storage = SecureStorageService();

  bool _isLoggedIn = false;
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  GoogleSignInAccount? _userAccount;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  Map<String, dynamic>? get userData => _userData;

  String get displayName => _userData?['full_name'] ?? 'No Name';
  String get email => _userData?['email'] ?? 'No Email';
  String? get photoUrl => _userData?['profile_picture'];

  AuthProvider() {
    _checkLoginStatus();
  }

  // Cek apakah masih ada JWT tersimpan & masih valid di server
  Future<void> _checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.readToken();

      if (token != null) {
        // Validasi token ke server, jangan asumsikan token masih valid
        final profile = await _authService.fetchProfile(token);
        _userData = profile;
        _isLoggedIn = true;
      } else {
        _isLoggedIn = false;
        _userData = null;
      }
    } catch (e) {
      // Token invalid/expired di server -> anggap logout
      debugPrint('Error checking login status: $e');
      await _storage.deleteToken();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login() async {
    _isLoading = true;
    notifyListeners();

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        throw Exception('Login dibatalkan');
      }

      _userAccount = account;

      // Ambil ID token dari Google -- INI yang dikirim ke server,
      // bukan email/name/photo mentah. Server yang akan memverifikasi
      // token ini langsung ke Google.
      final GoogleSignInAuthentication googleAuth =
          await account.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Gagal mendapatkan ID token dari Google');
      }

      final result = await _authService.loginWithGoogle(idToken);

      // Simpan JWT dari server dengan aman
      await _storage.saveToken(result['token'] as String);

      _userData = result['user'] as Map<String, dynamic>;
      _isLoggedIn = true;

      notifyListeners();
    } catch (e) {
      debugPrint('Login error: $e');
      await _storage.deleteToken();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _googleSignIn.signOut();
      await _storage.deleteToken();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
