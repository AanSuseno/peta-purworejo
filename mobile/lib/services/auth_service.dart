import 'dart:convert';

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

class AuthService {
  static const String baseUrl = 'http://192.168.1.6:3000';

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
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['user'] as Map<String, dynamic>;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AuthException('Token tidak valid atau kadaluarsa');
    }

    // Status code lain (500, dst) jangan dianggap "token invalid" ->
    // biar tidak memicu logout paksa gara-gara server lagi error.
    throw Exception('Gagal memuat profil (${response.statusCode})');
  }
}
