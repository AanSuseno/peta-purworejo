import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_service.dart';

/// Hasil satu halaman daftar komunitas: data + info pagination dari backend
/// (dipakai untuk infinite scroll / tombol "muat lagi").
class CommunityPage {
  final List<Map<String, dynamic>> communities;
  final int page;
  final int totalPages;

  CommunityPage({
    required this.communities,
    required this.page,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;
}

/// Service untuk endpoint "/communities". Mengikuti pola AuthService:
/// exception khusus untuk 401/403 supaya bisa dibedakan dari error jaringan.
class CommunitiesService {
  static const String baseUrl = AuthService.baseUrl;
  static const String _path = '/communities';

  /// GET /communities?page=&limit=&search=
  /// Query 'search' dipakai baik untuk pencarian nama maupun deskripsi
  /// komunitas (langsung ditangani backend lewat parameter yang sama).
  Future<CommunityPage> fetchCommunities({
    required String token,
    int page = 1,
    int limit = 10,
    String? search,
  }) async {
    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };

    final uri = Uri.parse('$baseUrl$_path')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        // Backend sekarang menyertakan "is_member" per komunitas (status join
        // user yang sedang login), jadi UI tidak perlu menebak sendiri.
        final rawList = (data['data'] as List?) ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>?;

        return CommunityPage(
          communities: rawList
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList(),
          page: pagination?['page'] ?? page,
          totalPages: pagination?['totalPages'] ?? 1,
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(
        data['message'] ?? 'Gagal memuat komunitas (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// GET /communities/:id — detail lengkap 1 komunitas (dipakai
  /// CommunityDetailScreen). Backend menyertakan "user_access" berisi
  /// is_member / is_admin / is_founder untuk user yang sedang login, jadi
  /// UI tidak perlu menebak sendiri siapa yang boleh melihat tombol edit.
  Future<Map<String, dynamic>> fetchCommunityById(
    String token,
    int communityId,
  ) async {
    final uri = Uri.parse('$baseUrl$_path/$communityId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Komunitas tidak ditemukan');
      }

      throw Exception(
        data['message'] ??
            'Gagal memuat detail komunitas (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } on FormatException {
      throw Exception('Response server tidak valid');
    }
  }

  /// POST /communities/:id/join
  Future<void> joinCommunity(String token, int communityId) async {
    final uri = Uri.parse('$baseUrl$_path/$communityId/join');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) return;

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      // 400 dipakai backend juga untuk "sudah jadi anggota" -> pesannya
      // dari backend langsung dilempar biar bisa dibedakan di UI kalau perlu.
      throw Exception(data['message'] ?? 'Gagal bergabung dengan komunitas');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// POST /communities/:id/leave
  Future<void> leaveCommunity(String token, int communityId) async {
    final uri = Uri.parse('$baseUrl$_path/$communityId/leave');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) return;

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(data['message'] ?? 'Gagal keluar dari komunitas');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// GET /categories — dipakai untuk dropdown kategori di form buat
  /// komunitas. Menangani beberapa kemungkinan bentuk response (dibungkus
  /// "data" atau langsung berupa list) supaya tidak gagal diam-diam kalau
  /// bentuknya sedikit beda dari yang diasumsikan.
  Future<List<Map<String, dynamic>>> fetchCategories(String token) async {
    final uri = Uri.parse('$baseUrl/categories');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Gagal memuat kategori (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      List<dynamic> rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map && decoded['data'] is List) {
        rawList = decoded['data'] as List;
      } else {
        rawList = [];
      }

      return rawList
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// POST /communities — buat komunitas baru (data teks saja; logo/banner
  /// diupload terpisah lewat uploadLogo/uploadBanner karena endpoint ini
  /// menerima JSON, bukan multipart).
  Future<Map<String, dynamic>> createCommunity({
    required String token,
    required String communityName,
    String? description,
    int? categoryId,
    String? kecamatan,
    String? address,
    String? contactEmail,
    String? contactPhone,
  }) async {
    final uri = Uri.parse('$baseUrl$_path');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'community_name': communityName,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (categoryId != null) 'category_id': categoryId,
          if (kecamatan != null && kecamatan.isNotEmpty) 'kecamatan': kecamatan,
          if (address != null && address.isNotEmpty) 'address': address,
          if (contactEmail != null && contactEmail.isNotEmpty)
            'contact_email': contactEmail,
          if (contactPhone != null && contactPhone.isNotEmpty)
            'contact_phone': contactPhone,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201 || response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 409) {
        throw Exception(data['message'] ?? 'Nama komunitas sudah dipakai');
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data yang dikirim tidak valid');
      }

      throw Exception(
        data['message'] ?? 'Gagal membuat komunitas (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// PATCH internal helper: upload file (logo/banner) lewat multipart ke
  /// "/communities/:id/logo" atau "/communities/:id/banner".
  ///
  /// CATATAN: nama field multipart diasumsikan "logo" / "banner" (sesuai
  /// nama endpoint-nya), mengikuti middleware upload.middleware.js kamu.
  /// Kalau ternyata field name-nya beda, sesuaikan parameter [fieldName].
  Future<Map<String, dynamic>> _uploadCommunityImage({
    required String token,
    required int communityId,
    required File imageFile,
    required String endpoint,
    required String fieldName,
  }) async {
    final uri = Uri.parse('$baseUrl$_path/$communityId/$endpoint');
    final fileName = '${endpoint}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            imageFile.path,
            filename: fileName,
            contentType: MediaType('image', 'jpeg'),
          ),
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

      throw Exception(
        data['message'] ?? 'Gagal mengupload gambar (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } on FormatException {
      throw Exception('Response server tidak valid');
    }
  }

  /// POST /communities/:id/logo (multipart, field "logo")
  Future<Map<String, dynamic>> uploadLogo(
    String token,
    int communityId,
    File imageFile,
  ) {
    return _uploadCommunityImage(
      token: token,
      communityId: communityId,
      imageFile: imageFile,
      endpoint: 'logo',
      fieldName: 'logo',
    );
  }

  /// POST /communities/:id/banner (multipart, field "banner")
  Future<Map<String, dynamic>> uploadBanner(
    String token,
    int communityId,
    File imageFile,
  ) {
    return _uploadCommunityImage(
      token: token,
      communityId: communityId,
      imageFile: imageFile,
      endpoint: 'banner',
      fieldName: 'banner',
    );
  }
}
