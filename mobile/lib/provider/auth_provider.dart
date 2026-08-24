import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '1040742393190-iqja9lb7fcb1p09pfh0iop1n93etpcnm.apps.googleusercontent.com',
  );
  final AuthService _authService = AuthService();
  final SecureStorageService _storage = SecureStorageService();

  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isRefreshingProfile = false;
  bool _isUpdatingProfile = false;
  bool _isUploadingPhoto = false;
  Map<String, dynamic>? _userData;
  GoogleSignInAccount? _userAccount;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isRefreshingProfile => _isRefreshingProfile;
  bool get isUpdatingProfile => _isUpdatingProfile;
  bool get isUploadingPhoto => _isUploadingPhoto;
  Map<String, dynamic>? get userData => _userData;

  String get displayName => _userData?['full_name'] ?? 'No Name';
  String get email => _userData?['email'] ?? 'No Email';
  String? get photoUrl => _userData?['profile_picture'];

  /// Token JWT yang tersimpan (dibaca dari secure storage). Dipakai layar
  /// lain (mis. CommunityScreen) yang perlu memanggil endpoint sendiri
  /// tanpa lewat method khusus di AuthProvider.
  Future<String?> getToken() => _storage.readToken();

  AuthProvider() {
    _checkLoginStatus();
  }

  // Cek apakah masih ada JWT tersimpan & masih valid di server
  Future<void> _checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();

    final token = await _storage.readToken();

    if (token == null) {
      _isLoggedIn = false;
      _userData = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Ada token tersimpan -> anggap dulu masih login supaya user langsung
    // masuk ke Home (tidak perlu login ulang tiap buka app), sambil
    // divalidasi ke server di belakang layar.
    _isLoggedIn = true;
    // Muat data user yang tersimpan lokal supaya nama/email/foto langsung
    // muncul, tidak perlu menunggu request ke server selesai.
    _userData = await _storage.readUserData();
    _isLoading = false;
    notifyListeners();

    try {
      final profile = await _authService.fetchProfile(token);
      _userData = profile;
      await _storage.saveUserData(profile);
      _isLoggedIn = true;
      notifyListeners();
    } on AuthException catch (e) {
      // Server benar-benar menolak token (401/403) -> sesi memang habis
      debugPrint('Token ditolak server, logout: $e');
      await _storage.deleteToken();
      await _storage.deleteUserData();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
      notifyListeners();
    } on SocketException catch (e) {
      // Tidak bisa connect ke server -> JANGAN logout paksa
      debugPrint('Network error saat validasi token, tetap login: $e');
    } on TimeoutException catch (e) {
      debugPrint('Timeout saat validasi token, tetap login: $e');
    } catch (e) {
      // Error tak terduga lain -> jangan langsung logout, cukup log
      debugPrint('Error tak terduga saat validasi token: $e');
    }
  }

  Future<void> refreshProfile() async {
    final token = await _storage.readToken();
    if (token == null) {
      throw AuthException('Sesi tidak ditemukan, silakan login ulang');
    }

    _isRefreshingProfile = true;
    notifyListeners();

    try {
      final profile = await _authService.fetchProfile(token);
      _userData = profile;
      await _storage.saveUserData(profile);
      notifyListeners();
    } on AuthException catch (e) {
      debugPrint('Token ditolak server saat refresh profil, logout: $e');
      await _storage.deleteToken();
      await _storage.deleteUserData();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
      notifyListeners();
      rethrow;
    } finally {
      _isRefreshingProfile = false;
      notifyListeners();
    }
  }

  /// Simpan perubahan profil (nama, no. telepon, bio, kecamatan, minat)
  /// ke server. Melempar [ValidationException] kalau ada input yang
  /// ditolak backend, supaya UI bisa tampilkan pesannya langsung.
  Future<void> updateProfile(Map<String, dynamic> updates) async {
    final token = await _storage.readToken();
    if (token == null) {
      throw AuthException('Sesi tidak ditemukan, silakan login ulang');
    }

    _isUpdatingProfile = true;
    notifyListeners();

    try {
      final profile = await _authService.updateProfile(token, updates);
      _userData = profile;
      await _storage.saveUserData(profile);
      notifyListeners();
    } on AuthException catch (e) {
      debugPrint('Token ditolak server saat update profil, logout: $e');
      await _storage.deleteToken();
      await _storage.deleteUserData();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
      notifyListeners();
      rethrow;
    } finally {
      _isUpdatingProfile = false;
      notifyListeners();
    }
  }

  /// Upload foto profil baru (file sudah di-crop di UI sebelum sampai sini).
  Future<void> uploadProfilePicture(File imageFile) async {
    final token = await _storage.readToken();
    if (token == null) {
      throw AuthException('Sesi tidak ditemukan, silakan login ulang');
    }

    _isUploadingPhoto = true;
    notifyListeners();

    try {
      final profile = await _authService.uploadProfilePicture(token, imageFile);
      _userData = profile;
      await _storage.saveUserData(profile);
      notifyListeners();
    } on AuthException catch (e) {
      debugPrint('Token ditolak server saat upload foto, logout: $e');
      await _storage.deleteToken();
      await _storage.deleteUserData();
      _isLoggedIn = false;
      _userAccount = null;
      _userData = null;
      notifyListeners();
      rethrow;
    } finally {
      _isUploadingPhoto = false;
      notifyListeners();
    }
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
      await _storage.saveUserData(_userData!);
      _isLoggedIn = true;

      debugPrint('Profile from login: $_userData');

      notifyListeners();
    } catch (e) {
      debugPrint('Login error: $e');
      await _storage.deleteToken();
      await _storage.deleteUserData();
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
      await _storage.deleteUserData();
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
