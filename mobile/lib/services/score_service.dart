import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// Service untuk endpoint "/scores".
///
/// Endpoint yang tersedia:
/// GET /scores/:communityId
/// GET /scores/:communityId/history
/// GET /scores/:communityId/summary
/// GET /scores/ranking/top
class ScoreService {
  static const String baseUrl = AuthService.baseUrl;
  static const String _path = '/scores';

  /// GET /scores/:communityId
  ///
  /// Mengambil total skor sebuah komunitas.
  ///
  /// Response backend:
  /// {
  ///   "success": true,
  ///   "data": {
  ///     "community_id": 1,
  ///     "total_score": 120
  ///   }
  /// }
  Future<Map<String, dynamic>> fetchCommunityScore({
    required String token,
    required int communityId,
  }) async {
    final uri = Uri.parse('$baseUrl$_path/$communityId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('📡 [Score] GET $uri');
      debugPrint('📡 [Score] Status: ${response.statusCode}');
      debugPrint('📡 [Score] Response: ${response.body}');

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(
          data['data'] as Map,
        );
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(
          data['message'] ?? 'Komunitas tidak ditemukan',
        );
      }

      throw Exception(
        data['message'] ??
            'Gagal mengambil skor komunitas (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } on FormatException {
      throw Exception('Response server tidak valid');
    }
  }

  /// GET /scores/:communityId/history
  ///
  /// Mengambil riwayat perubahan skor komunitas.
  ///
  /// Parameter:
  /// - page       : halaman pagination
  /// - limit      : jumlah data per halaman
  /// - scoreType  : filter berdasarkan jenis skor
  ///
  /// Response backend:
  /// {
  ///   "success": true,
  ///   "data": [...],
  ///   "pagination": {
  ///     "page": 1,
  ///     "limit": 20,
  ///     "total": 50,
  ///     "totalPages": 3
  ///   }
  /// }
  Future<ScoreHistoryPage> fetchScoreHistory({
    required String token,
    required int communityId,
    int page = 1,
    int limit = 20,
    String? scoreType,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (scoreType != null && scoreType.trim().isNotEmpty)
        'scoreType': scoreType.trim(),
    };

    final uri = Uri.parse('$baseUrl$_path/$communityId/history')
        .replace(queryParameters: queryParams);

    try {
      debugPrint('📡 [Score History] GET $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint(
        '📡 [Score History] Status: ${response.statusCode}',
      );
      debugPrint(
        '📡 [Score History] Response: ${response.body}',
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final rawList = data['data'] as List? ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>?;

        final history = rawList
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();

        return ScoreHistoryPage(
          history: history,
          page: pagination?['page'] ?? page,
          limit: pagination?['limit'] ?? limit,
          total: pagination?['total'] ?? history.length,
          totalPages: pagination?['totalPages'] ?? 1,
        );
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(
          data['message'] ?? 'Komunitas tidak ditemukan',
        );
      }

      throw Exception(
        data['message'] ??
            'Gagal mengambil riwayat skor (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } on FormatException {
      throw Exception('Response server tidak valid');
    }
  }

  /// GET /scores/:communityId/summary
  ///
  /// Mengambil statistik skor berdasarkan score_type.
  ///
  /// Contoh response:
  /// [
  ///   {
  ///     "scoreType": "post",
  ///     "totalScore": 30,
  ///     "totalActivities": 5
  ///   }
  /// ]
  Future<List<Map<String, dynamic>>> fetchScoreSummary({
    required String token,
    required int communityId,
  }) async {
    final uri = Uri.parse('$baseUrl$_path/$communityId/summary');

    try {
      debugPrint('📡 [Score Summary] GET $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint(
        '📡 [Score Summary] Status: ${response.statusCode}',
      );
      debugPrint(
        '📡 [Score Summary] Response: ${response.body}',
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final rawList = data['data'] as List? ?? [];

        return rawList
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(
          data['message'] ?? 'Komunitas tidak ditemukan',
        );
      }

      throw Exception(
        data['message'] ??
            'Gagal mengambil summary skor (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } on FormatException {
      throw Exception('Response server tidak valid');
    }
  }

  /// GET /scores/ranking/top
  ///
  /// Mengambil 20 komunitas aktif dengan skor tertinggi.
  ///
  /// Response backend:
  /// {
  ///   "success": true,
  ///   "data": [
  ///     {
  ///       "rank": 1,
  ///       "community_id": 1,
  ///       "community_name": "...",
  ///       "community_slug": "...",
  ///       "logo": "...",
  ///       "total_score": 100,
  ///       "total_members": 20
  ///     }
  ///   ]
  /// }
  Future<List<Map<String, dynamic>>> fetchTopCommunities({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl$_path/ranking/top');

    try {
      debugPrint('📡 [Score Ranking] GET $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint(
        '📡 [Score Ranking] Status: ${response.statusCode}',
      );
      debugPrint(
        '📡 [Score Ranking] Response: ${response.body}',
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final rawList = data['data'] as List? ?? [];

        return rawList
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(
        data['message'] ??
            'Gagal mengambil ranking komunitas (${response.statusCode})',
      );
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } on FormatException {
      throw Exception('Response server tidak valid');
    }
  }
}

/// Model pagination untuk riwayat skor.
class ScoreHistoryPage {
  final List<Map<String, dynamic>> history;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  ScoreHistoryPage({
    required this.history,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;
}
