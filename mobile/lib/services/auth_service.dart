import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Dilempar khusus saat server menolak token (401/403) -> sesi memang habis.
/// Beda dengan error jaringan (SocketException/TimeoutException) yang berarti
/// server sedang tidak bisa dihubungi, padahal token belum tentu invalid.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Dilempar saat request ditolak karena validasi input (400) -> pesannya
/// diambil langsung dari backend supaya user tahu field mana yang salah.
class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static const String baseUrl = 'http://192.168.1.6:3000';

  // Router users.routes.js diasumsikan di-mount di "/users". Sesuaikan
  // ini kalau ternyata mount path-nya beda (mis. "/api/users").
  static const String _usersPath = '/users';

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/mobile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'credential': idToken, 'platform': 'android'}),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      }

      throw Exception(
        data['message'] ?? 'Login gagal (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  Future<Map<String, dynamic>> fetchProfile(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$_usersPath/me/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        // Backend kadang membungkus user di key "user" atau "data",
        // kadang langsung mengembalikan object user-nya. Ditangani
        // ketiganya supaya tidak gagal diam-diam kalau bentuk
        // response-nya sedikit berbeda dari yang diasumsikan.
        Map<String, dynamic>? userMap;
        if (decoded is Map<String, dynamic>) {
          if (decoded['user'] is Map<String, dynamic>) {
            userMap = decoded['user'] as Map<String, dynamic>;
          } else if (decoded['data'] is Map<String, dynamic>) {
            userMap = decoded['data'] as Map<String, dynamic>;
          } else if (decoded.containsKey('user_id') ||
              decoded.containsKey('email')) {
            // Response-nya langsung object user, tanpa wrapper.
            userMap = decoded;
          }
        }

        if (userMap == null) {
          debugPrint('Bentuk response profil tidak dikenali: ${response.body}');
          throw Exception('Format response profil tidak dikenali');
        }

        return userMap;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      // Status code lain (500, dst) jangan dianggap "token invalid" ->
      // biar tidak memicu logout paksa gara-gara server lagi error.
      throw Exception(
        data['message'] ?? 'Gagal memuat profil (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// PUT /users/me/profile — field yang diterima backend: full_name,
  /// phone_number, bio, kecamatan, interests. Hanya kirim field yang
  /// memang mau diubah (backend pakai `field || undefined`, jadi field
  /// kosong tidak akan menimpa nilai lama kalau tidak dikirim).
  Future<Map<String, dynamic>> updateProfile(
    String token,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$_usersPath/me/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(updates),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 400) {
        throw ValidationException(
          data['message'] ?? 'Data yang dikirim tidak valid',
        );
      }

      throw Exception(
        data['message'] ?? 'Gagal memperbarui profil (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// PUT /users/me/profile-picture/upload — kirim file foto sebagai
  /// multipart form-data dengan field name "profile_picture" (harus sama
  /// dengan nama field di multer.single(...) pada backend).
  Future<Map<String, dynamic>> uploadProfilePicture(
    String token,
    File imageFile,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl$_usersPath/me/profile-picture/upload');
      final request = http.MultipartRequest('PUT', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(
          await http.MultipartFile.fromPath('profile_picture', imageFile.path),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 400) {
        throw ValidationException(data['message'] ?? 'File foto tidak valid');
      }

      throw Exception(
        data['message'] ?? 'Gagal mengupload foto (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }
}
