import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
  static const String baseUrl = 'https://uk6npnwu311q.shares.zrok.io';

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
    final uri = Uri.parse('$baseUrl$_usersPath/me/profile-picture/upload');

    // Log sebelum request dikirim, biar kelihatan URL & file yang dipakai
    // kalau ternyata request-nya sendiri tidak pernah sampai ke server.
    debugPrint('[uploadProfilePicture] URL: $uri');
    debugPrint('[uploadProfilePicture] File path: ${imageFile.path}');
    debugPrint(
      '[uploadProfilePicture] File exists: ${await imageFile.exists()}, '
      'size: ${await imageFile.exists() ? await imageFile.length() : 'N/A'} bytes',
    );

    try {
      // Paksa filename & content-type secara eksplisit, JANGAN andalkan
      // tebakan otomatis dari path.basename(imageFile.path). Kalau path
      // hasil crop tidak punya ekstensi yang jelas, backend (multer
      // fileFilter) akan nolak dengan "Hanya file gambar yang diizinkan"
      // walaupun isi filenya beneran gambar -- karena dia cek ekstensi
      // dari nama file yang dikirim, bukan isi filenya.
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(
          await http.MultipartFile.fromPath(
            'profile_picture',
            imageFile.path,
            filename: fileName,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      debugPrint('[uploadProfilePicture] Sending as filename: $fileName');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Log status code + raw body SEBELUM di-parse, supaya kalau body-nya
      // bukan JSON valid (mis. server balas HTML error / kosong), kita
      // masih bisa lihat isinya di sini alih-alih cuma dapat FormatException.
      debugPrint('[uploadProfilePicture] Status: ${response.statusCode}');
      debugPrint('[uploadProfilePicture] Raw body: ${response.body}');

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
    } on http.ClientException catch (e) {
      debugPrint('[uploadProfilePicture] ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } on SocketException catch (e) {
      // Device tidak bisa connect ke baseUrl sama sekali (beda jaringan,
      // server mati, firewall, dsb).
      debugPrint('[uploadProfilePicture] SocketException: $e');
      throw Exception('Tidak bisa terhubung ke server ($baseUrl)');
    } on TimeoutException catch (e) {
      debugPrint('[uploadProfilePicture] TimeoutException: $e');
      throw Exception('Server tidak merespon (timeout)');
    } on FormatException catch (e) {
      // response.body bukan JSON valid -> biasanya server balas HTML/teks
      // polos (mis. halaman error 404/500 bawaan Express, bukan JSON).
      debugPrint(
        '[uploadProfilePicture] FormatException (body bukan JSON): $e',
      );
      throw Exception('Response server tidak valid, cek log body di atas');
    } catch (e, stackTrace) {
      // Tangkapan terakhir supaya error apa pun (mis. file tidak ditemukan,
      // AuthException/ValidationException yang dilempar di atas) tetap
      // ke-log sebelum di-rethrow, tapi tanpa dobel-bungkus pesannya.
      debugPrint('[uploadProfilePicture] Unexpected error: $e');
      debugPrint('[uploadProfilePicture] Stack trace: $stackTrace');
      rethrow;
    }
  }

// Tambahkan method ini di AuthService

  /// GET /users/:id/profile — ambil profil user lain berdasarkan ID
  Future<Map<String, dynamic>> fetchUserProfile(
      String token, int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$_usersPath/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("hasil $response");

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        Map<String, dynamic>? userMap;
        if (decoded is Map<String, dynamic>) {
          if (decoded['user'] is Map<String, dynamic>) {
            userMap = decoded['user'] as Map<String, dynamic>;
          } else if (decoded['data'] is Map<String, dynamic>) {
            userMap = decoded['data'] as Map<String, dynamic>;
          } else if (decoded.containsKey('user_id') ||
              decoded.containsKey('email')) {
            userMap = decoded;
          }
        }

        if (userMap == null) {
          throw Exception('Format response profil tidak dikenali');
        }

        return userMap;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'User tidak ditemukan');
      }

      throw Exception(
        data['message'] ?? 'Gagal memuat profil user (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }
}
