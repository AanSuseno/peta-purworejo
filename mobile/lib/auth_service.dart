import 'dart:convert';

import 'package:http/http.dart' as http;

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

    throw Exception('Token tidak valid atau kadaluarsa');
  }
}
