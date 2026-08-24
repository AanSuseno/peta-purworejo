// lib/services/posts_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_service.dart';

/// Hasil satu halaman daftar post
class PostPage {
  final List<Map<String, dynamic>> posts;
  final int page;
  final int totalPages;
  final int total;

  PostPage({
    required this.posts,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  bool get hasMore => page < totalPages;
}

class PostsService {
  static const String baseUrl = AuthService.baseUrl;

  /// Helper untuk debug logging
  void _debugLog(String tag, String message) {
    if (kDebugMode) {
      debugPrint('📝 [$tag] $message');
    }
  }

  void _debugError(String tag, dynamic error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('❌ [$tag] Error: $error');
      if (stackTrace != null) {
        debugPrint('📚 [$tag] StackTrace: $stackTrace');
      }
    }
  }

  void _debugResponse(String tag, http.Response response) {
    if (kDebugMode) {
      final bodyPreview = response.body.length > 500
          ? '${response.body.substring(0, 500)}...'
          : response.body;
      debugPrint('📡 [$tag] Status: ${response.statusCode}');
      debugPrint('📡 [$tag] Body preview: $bodyPreview');
    }
  }

  /// Cek apakah response adalah HTML
  bool _isHtmlResponse(String body) {
    return body.trim().startsWith('<!DOCTYPE') ||
        body.trim().startsWith('<html') ||
        body.trim().startsWith('<?xml');
  }

  /// Parse response dengan handling HTML
  dynamic _parseResponse(String tag, http.Response response) {
    final body = response.body;

    // Cek jika response adalah HTML
    if (_isHtmlResponse(body)) {
      _debugLog(tag, '⚠️ Server returned HTML instead of JSON');
      _debugLog(tag, '⚠️ This usually means:');
      _debugLog(tag, '⚠️ 1. Endpoint URL is wrong');
      _debugLog(tag, '⚠️ 2. Server is not configured properly');
      _debugLog(tag, '⚠️ 3. Missing /posts/ prefix or wrong base URL');

      // Coba ekstrak info dari HTML
      if (body.contains('404')) {
        throw Exception(
          'Endpoint tidak ditemukan (404). Periksa URL endpoint.',
        );
      } else if (body.contains('500')) {
        throw Exception('Server error (500). Periksa backend.');
      } else if (body.contains('Method Not Allowed')) {
        throw Exception('Method tidak diizinkan. Periksa method HTTP.');
      } else {
        throw Exception(
          'Server mengembalikan HTML bukan JSON. Periksa konfigurasi endpoint.',
        );
      }
    }

    try {
      return jsonDecode(body);
    } catch (e) {
      _debugError(tag, 'Failed to parse JSON: $e');
      _debugLog(
        tag,
        'Raw response: ${body.substring(0, body.length > 200 ? 200 : body.length)}',
      );
      throw Exception('Response tidak valid: ${e.toString()}');
    }
  }

  /// GET /posts/communities/:id/posts
  Future<PostPage> fetchCommunityPosts({
    required String token,
    required int communityId,
    int page = 1,
    int limit = 10,
    String? postType,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  }) async {
    const tag = 'fetchCommunityPosts';
    _debugLog(tag, 'Fetching posts for communityId: $communityId, page: $page');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'sort_by': sortBy,
      'sort_order': sortOrder,
      if (postType != null && postType.isNotEmpty) 'post_type': postType,
    };

    final uri = Uri.parse('$baseUrl/posts/communities/$communityId/posts')
        .replace(queryParameters: queryParams);

    _debugLog(tag, 'URI: $uri');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      // Handle HTML response
      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        final rawList = (data['data'] as List?) ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>?;

        return PostPage(
          posts: rawList
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList(),
          page: pagination?['page'] ?? page,
          totalPages: pagination?['totalPages'] ?? 1,
          total: pagination?['total'] ?? 0,
        );
      }

      if (response.statusCode == 401) {
        _debugLog(tag, 'Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, 'Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, 'Komunitas tidak ditemukan');
        throw Exception(data['message'] ?? 'Komunitas tidak ditemukan');
      }

      _debugError(
        tag,
        'Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal memuat postingan (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, 'ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// GET /posts/posts/feed
  Future<PostPage> fetchFeedPosts({
    required String token,
    int page = 1,
    int limit = 10,
    String? postType,
  }) async {
    const tag = 'fetchFeedPosts';
    _debugLog(tag, 'Fetching feed posts, page: $page');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (postType != null && postType.isNotEmpty) 'post_type': postType,
    };

    final uri = Uri.parse('$baseUrl/posts/posts/feed')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        final rawList = (data['data'] as List?) ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>?;

        return PostPage(
          posts: rawList
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList(),
          page: pagination?['page'] ?? page,
          totalPages: pagination?['totalPages'] ?? 1,
          total: pagination?['total'] ?? 0,
        );
      }

      if (response.statusCode == 401) {
        _debugLog(tag, 'Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      _debugError(
        tag,
        'Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal memuat feed (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, 'ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// GET /posts/posts/:id
  Future<Map<String, dynamic>> fetchPostById({
    required String token,
    required int postId,
  }) async {
    const tag = 'fetchPostById';
    _debugLog(tag, 'Fetching post by ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, 'Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, 'Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, 'Postingan tidak ditemukan');
        throw Exception(data['message'] ?? 'Postingan tidak ditemukan');
      }

      _debugError(
        tag,
        'Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal memuat postingan (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, 'ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// POST /posts/communities/:id/posts - Buat post (text only)
  Future<Map<String, dynamic>> createPost({
    required String token,
    required int communityId,
    required String title,
    String? content,
    required String postType,
    String visibility = 'public',
    // Event fields
    String? eventDate,
    String? eventStartTime,
    String? eventEndTime,
    String? eventLocation,
    double? eventLatitude,
    double? eventLongitude,
    int? eventQuota,
    String? eventRegistrationLink,
  }) async {
    const tag = 'createPost';
    _debugLog(tag, '=== START CREATE POST ===');
    _debugLog(tag, 'communityId: $communityId');
    _debugLog(tag, 'Title: "$title"');
    _debugLog(tag, 'postType: "$postType"');
    _debugLog(tag, 'visibility: "$visibility"');
    _debugLog(tag, 'isEvent: ${postType == "event"}');

    // CEK BASE URL
    _debugLog(tag, '⚠️ BASE_URL: $baseUrl');
    _debugLog(tag, '⚠️ Pastikan baseUrl di AuthService sudah benar!');
    _debugLog(
      tag,
      '⚠️ Seharusnya: http://10.0.2.2:3000 atau http://localhost:3000',
    );
    _debugLog(tag, '⚠️ JANGAN menggunakan https untuk development!');

    final uri = Uri.parse('$baseUrl/posts/communities/$communityId/posts');
    _debugLog(tag, '⚠️ FULL URI: $uri');
    _debugLog(tag, '⚠️ Periksa:');
    _debugLog(tag, '⚠️ 1. Apakah server berjalan?');
    _debugLog(tag, '⚠️ 2. Apakah port benar?');
    _debugLog(tag, '⚠️ 3. Apakah ada /posts/ di URL?');
    _debugLog(tag, '⚠️ 4. Apakah endpoint /posts/communities/:id/posts ada?');

    final body = <String, dynamic>{
      'title': title.trim(),
      'post_type': postType,
      'visibility': visibility,
    };

    if (content != null && content.isNotEmpty) {
      body['content'] = content.trim();
      _debugLog(tag, 'Content length: ${content.length}');
    }

    // Event fields
    if (postType == 'event') {
      _debugLog(tag, 'Adding event fields...');
      if (eventDate != null && eventDate.isNotEmpty) {
        body['event_date'] = eventDate;
        _debugLog(tag, 'event_date: $eventDate');
      } else {
        _debugError(
          tag,
          'eventDate is required for event type but is null or empty!',
        );
        throw Exception('Tanggal event wajib diisi untuk postingan event');
      }
      if (eventStartTime != null && eventStartTime.isNotEmpty) {
        body['event_start_time'] = eventStartTime;
        _debugLog(tag, 'event_start_time: $eventStartTime');
      }
      if (eventEndTime != null && eventEndTime.isNotEmpty) {
        body['event_end_time'] = eventEndTime;
        _debugLog(tag, 'event_end_time: $eventEndTime');
      }
      if (eventLocation != null && eventLocation.isNotEmpty) {
        body['event_location'] = eventLocation;
        _debugLog(tag, 'event_location: $eventLocation');
      }
      if (eventLatitude != null) {
        body['event_latitude'] = eventLatitude;
        _debugLog(tag, 'event_latitude: $eventLatitude');
      }
      if (eventLongitude != null) {
        body['event_longitude'] = eventLongitude;
        _debugLog(tag, 'event_longitude: $eventLongitude');
      }
      if (eventQuota != null && eventQuota > 0) {
        body['event_quota'] = eventQuota;
        _debugLog(tag, 'event_quota: $eventQuota');
      }
      if (eventRegistrationLink != null && eventRegistrationLink.isNotEmpty) {
        body['event_registration_link'] = eventRegistrationLink;
        _debugLog(tag, 'event_registration_link: $eventRegistrationLink');
      }
    }

    final jsonBody = jsonEncode(body);
    _debugLog(tag, 'Request body: $jsonBody');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonBody,
      );

      _debugResponse(tag, response);

      // Cek HTML response
      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ SERVER RETURNED HTML!');
        _debugError(tag, '❌ This is a CRITICAL error!');
        _debugError(tag, '❌ Response status: ${response.statusCode}');
        _debugError(
          tag,
          '❌ This means the endpoint is WRONG or SERVER is DOWN',
        );
        _debugError(tag, '❌ Check:');
        _debugError(tag, '❌ 1. BaseUrl: $baseUrl');
        _debugError(tag, '❌ 2. Full URI: $uri');
        _debugError(tag, '❌ 3. Does the endpoint exist?');
        _debugError(tag, '❌ 4. Is the server running?');

        // Extract error from HTML
        if (response.body.contains('404')) {
          throw Exception(
            '❌ Endpoint tidak ditemukan (404): $uri\nPeriksa URL endpoint di backend.',
          );
        } else if (response.body.contains('500')) {
          throw Exception(
            '❌ Server error (500): $uri\nPeriksa backend server.',
          );
        } else {
          throw Exception(
            '❌ Server mengembalikan HTML, bukan JSON.\nURL: $uri\nPastikan endpoint backend benar.',
          );
        }
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Post created successfully!');
        return data['data'] as Map<String, dynamic>;
      }

      // Error handling
      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        if (data['errors'] != null) {
          final errors = data['errors'] as Map<String, dynamic>;
          final errorMessages = errors.values
              .map((e) => e.toString())
              .join(', ');
          _debugLog(tag, 'Validation errors: $errorMessages');
          throw Exception(
            '${data['message'] ?? 'Validasi gagal'}: $errorMessages',
          );
        }
        throw Exception(data['message'] ?? 'Data yang dikirim tidak valid');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Komunitas tidak ditemukan');
        throw Exception(data['message'] ?? 'Komunitas tidak ditemukan');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal membuat postingan (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      _debugError(tag, '❌ Connection failed to: $uri');
      _debugError(tag, '❌ Periksa:');
      _debugError(tag, '❌ 1. Server running?');
      _debugError(tag, '❌ 2. BaseUrl correct?');
      _debugError(tag, '❌ 3. Firewall blocking?');
      throw Exception('❌ Gagal terhubung ke server: ${e.message}\nURL: $uri');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    } finally {
      _debugLog(tag, '=== END CREATE POST ===');
    }
  }

  /// POST /posts/communities/:id/posts/media - Buat post dengan media
  Future<Map<String, dynamic>> createPostWithMedia({
    required String token,
    required int communityId,
    required String title,
    String? content,
    required String postType,
    String visibility = 'public',
    bool isPinned = false,
    List<File>? files,
    // Event fields
    String? eventDate,
    String? eventStartTime,
    String? eventEndTime,
    String? eventLocation,
    double? eventLatitude,
    double? eventLongitude,
    int? eventQuota,
    String? eventRegistrationLink,
  }) async {
    const tag = 'createPostWithMedia';
    _debugLog(tag, '=== START CREATE POST WITH MEDIA ===');
    _debugLog(tag, 'communityId: $communityId');
    _debugLog(tag, 'Title: "$title"');
    _debugLog(tag, 'postType: "$postType"');
    _debugLog(tag, 'visibility: "$visibility"');
    _debugLog(tag, 'Files count: ${files?.length ?? 0}');
    _debugLog(tag, 'isEvent: ${postType == "event"}');

    _debugLog(tag, '⚠️ BASE_URL: $baseUrl');

    final uri = Uri.parse(
      '$baseUrl/posts/communities/$communityId/posts/media',
    );
    _debugLog(tag, '⚠️ FULL URI: $uri');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['title'] = title.trim()
        ..fields['post_type'] = postType
        ..fields['visibility'] = visibility
        ..fields['is_pinned'] = isPinned ? 'true' : 'false';

      if (content != null && content.isNotEmpty) {
        request.fields['content'] = content.trim();
        _debugLog(tag, 'Content length: ${content.length}');
      }

      // Event fields
      if (postType == 'event') {
        _debugLog(tag, 'Adding event fields...');
        if (eventDate != null && eventDate.isNotEmpty) {
          request.fields['event_date'] = eventDate;
          _debugLog(tag, 'event_date: $eventDate');
        } else {
          _debugError(
            tag,
            'eventDate is required for event type but is null or empty!',
          );
          throw Exception('Tanggal event wajib diisi untuk postingan event');
        }
        if (eventStartTime != null && eventStartTime.isNotEmpty) {
          request.fields['event_start_time'] = eventStartTime;
          _debugLog(tag, 'event_start_time: $eventStartTime');
        }
        if (eventEndTime != null && eventEndTime.isNotEmpty) {
          request.fields['event_end_time'] = eventEndTime;
          _debugLog(tag, 'event_end_time: $eventEndTime');
        }
        if (eventLocation != null && eventLocation.isNotEmpty) {
          request.fields['event_location'] = eventLocation;
          _debugLog(tag, 'event_location: $eventLocation');
        }
        if (eventLatitude != null) {
          request.fields['event_latitude'] = eventLatitude.toString();
          _debugLog(tag, 'event_latitude: $eventLatitude');
        }
        if (eventLongitude != null) {
          request.fields['event_longitude'] = eventLongitude.toString();
          _debugLog(tag, 'event_longitude: $eventLongitude');
        }
        if (eventQuota != null && eventQuota > 0) {
          request.fields['event_quota'] = eventQuota.toString();
          _debugLog(tag, 'event_quota: $eventQuota');
        }
        if (eventRegistrationLink != null && eventRegistrationLink.isNotEmpty) {
          request.fields['event_registration_link'] = eventRegistrationLink;
          _debugLog(tag, 'event_registration_link: $eventRegistrationLink');
        }
      }

      // Tambahkan file
      if (files != null && files.isNotEmpty) {
        _debugLog(tag, 'Adding ${files.length} files...');
        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          final extension = file.path.split('.').last.toLowerCase();
          final contentType = extension == 'mp4' || extension == 'webm'
              ? MediaType('video', extension)
              : MediaType('image', 'jpeg');
          final fileName =
              'post_${DateTime.now().millisecondsSinceEpoch}_$i.$extension';

          _debugLog(tag, 'File $i: ${file.path}, type: $contentType');

          request.files.add(
            await http.MultipartFile.fromPath(
              'media',
              file.path,
              filename: fileName,
              contentType: contentType,
            ),
          );
        }
      }

      _debugLog(tag, 'Sending multipart request...');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _debugLog(tag, 'Response status: ${response.statusCode}');
      _debugLog(
        tag,
        'Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
      );

      // Cek HTML response
      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ SERVER RETURNED HTML!');
        _debugError(tag, '❌ Response status: ${response.statusCode}');
        _debugError(tag, '❌ URL: $uri');
        throw Exception('❌ Server mengembalikan HTML, bukan JSON.\nURL: $uri');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Post with media created successfully!');
        return data['data'] as Map<String, dynamic>;
      }

      // Error handling
      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        if (data['errors'] != null) {
          final errors = data['errors'] as Map<String, dynamic>;
          final errorMessages = errors.values
              .map((e) => e.toString())
              .join(', ');
          _debugLog(tag, 'Validation errors: $errorMessages');
          throw Exception(
            '${data['message'] ?? 'Validasi gagal'}: $errorMessages',
          );
        }
        throw Exception(data['message'] ?? 'Data yang dikirim tidak valid');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Komunitas tidak ditemukan');
        throw Exception(data['message'] ?? 'Komunitas tidak ditemukan');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal membuat postingan (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      _debugError(tag, '❌ Connection failed to: $uri');
      throw Exception('❌ Gagal terhubung ke server: ${e.message}\nURL: $uri');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    } finally {
      _debugLog(tag, '=== END CREATE POST WITH MEDIA ===');
    }
  }

  /// PUT /posts/posts/:id - Update post
  Future<Map<String, dynamic>> updatePost({
    required String token,
    required int postId,
    String? title,
    String? content,
    String? postType,
    String? visibility,
    bool? isPinned,
    // Event fields
    String? eventDate,
    String? eventStartTime,
    String? eventEndTime,
    String? eventLocation,
    double? eventLatitude,
    double? eventLongitude,
    int? eventQuota,
    String? eventRegistrationLink,
    String? eventStatus,
  }) async {
    const tag = 'updatePost';
    _debugLog(tag, 'Updating post ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId');

    final body = <String, dynamic>{};
    if (title != null && title.isNotEmpty) body['title'] = title.trim();
    if (content != null)
      body['content'] = content.trim().isEmpty ? null : content.trim();
    if (postType != null && postType.isNotEmpty) body['post_type'] = postType;
    if (visibility != null && visibility.isNotEmpty)
      body['visibility'] = visibility;
    if (isPinned != null) body['is_pinned'] = isPinned;

    // Event fields
    if (eventDate != null)
      body['event_date'] = eventDate.isEmpty ? null : eventDate;
    if (eventStartTime != null)
      body['event_start_time'] = eventStartTime.isEmpty ? null : eventStartTime;
    if (eventEndTime != null)
      body['event_end_time'] = eventEndTime.isEmpty ? null : eventEndTime;
    if (eventLocation != null)
      body['event_location'] = eventLocation.isEmpty ? null : eventLocation;
    if (eventLatitude != null) body['event_latitude'] = eventLatitude;
    if (eventLongitude != null) body['event_longitude'] = eventLongitude;
    if (eventQuota != null) body['event_quota'] = eventQuota;
    if (eventRegistrationLink != null)
      body['event_registration_link'] = eventRegistrationLink.isEmpty
          ? null
          : eventRegistrationLink;
    if (eventStatus != null && eventStatus.isNotEmpty)
      body['event_status'] = eventStatus;

    _debugLog(tag, 'Request body: ${jsonEncode(body)}');

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Post updated successfully!');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Postingan tidak ditemukan');
        throw Exception(data['message'] ?? 'Postingan tidak ditemukan');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        throw Exception(data['message'] ?? 'Data yang dikirim tidak valid');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ??
            'Gagal memperbarui postingan (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// POST /posts/posts/:id/like
  Future<Map<String, dynamic>> toggleLike({
    required String token,
    required int postId,
  }) async {
    const tag = 'toggleLike';
    _debugLog(tag, 'Toggling like for post ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/like');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Like toggled successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Postingan tidak ditemukan');
        throw Exception(data['message'] ?? 'Postingan tidak ditemukan');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal like/unlike (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// GET /posts/posts/:id/comments
  Future<Map<String, dynamic>> fetchComments({
    required String token,
    required int postId,
    int page = 1,
    int limit = 20,
  }) async {
    const tag = 'fetchComments';
    _debugLog(tag, 'Fetching comments for post ID: $postId, page: $page');

    final queryParams = <String, String>{'page': '$page', 'limit': '$limit'};

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/comments')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal memuat komentar (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// POST /posts/posts/:id/comments
  Future<Map<String, dynamic>> createComment({
    required String token,
    required int postId,
    required String content,
  }) async {
    const tag = 'createComment';
    _debugLog(tag, 'Creating comment for post ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/comments');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'content': content.trim()}),
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Comment created successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        throw Exception(data['message'] ?? 'Komentar wajib diisi');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ??
            'Gagal menambahkan komentar (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// PUT /posts/comments/:id
  Future<Map<String, dynamic>> updateComment({
    required String token,
    required int commentId,
    required String content,
  }) async {
    const tag = 'updateComment';
    _debugLog(tag, 'Updating comment ID: $commentId');

    final uri = Uri.parse('$baseUrl/posts/comments/$commentId');

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'content': content.trim()}),
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Comment updated successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Komentar tidak ditemukan');
        throw Exception(data['message'] ?? 'Komentar tidak ditemukan');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ??
            'Gagal memperbarui komentar (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// DELETE /posts/comments/:id
  Future<void> deleteComment({
    required String token,
    required int commentId,
  }) async {
    const tag = 'deleteComment';
    _debugLog(tag, 'Deleting comment ID: $commentId');

    final uri = Uri.parse('$baseUrl/posts/comments/$commentId');

    try {
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Comment deleted successfully');
        return;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Komentar tidak ditemukan');
        throw Exception(data['message'] ?? 'Komentar tidak ditemukan');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal menghapus komentar (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  // ============ EVENT SPECIFIC ENDPOINTS ============

  /// POST /posts/posts/:id/event/register
  Future<Map<String, dynamic>> registerEvent({
    required String token,
    required int postId,
  }) async {
    const tag = 'registerEvent';
    _debugLog(tag, 'Registering for event post ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/event/register');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Event registration successful');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        throw Exception(data['message'] ?? 'Gagal mendaftar event');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal mendaftar event (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// DELETE /posts/posts/:id/event/cancel
  Future<void> cancelEventRegistration({
    required String token,
    required int postId,
  }) async {
    const tag = 'cancelEventRegistration';
    _debugLog(tag, 'Canceling event registration for post ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/event/cancel');

    try {
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Event registration cancelled successfully');
        return;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        throw Exception(data['message'] ?? 'Gagal membatalkan pendaftaran');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ??
            'Gagal membatalkan pendaftaran (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// GET /posts/posts/:id/event/participants
  Future<Map<String, dynamic>> fetchEventParticipants({
    required String token,
    required int postId,
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    const tag = 'fetchEventParticipants';
    _debugLog(tag, 'Fetching event participants for post ID: $postId');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status != null && status.isNotEmpty) 'status': status,
    };

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/event/participants')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal memuat peserta (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  Future<void> deletePost({required String token, required int postId}) async {
    const tag = 'deletePost';
    _debugLog(tag, 'Deleting post ID: $postId');

    final uri = Uri.parse('$baseUrl/posts/posts/$postId');

    try {
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Post deleted successfully!');
        return;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 404) {
        _debugLog(tag, '❌ Postingan tidak ditemukan');
        throw Exception(data['message'] ?? 'Postingan tidak ditemukan');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal menghapus postingan (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }

  /// PUT /posts/posts/:id/event/participants
  Future<void> updateParticipantStatus({
    required String token,
    required int postId,
    required int participantId,
    required String status,
  }) async {
    const tag = 'updateParticipantStatus';
    _debugLog(
      tag,
      'Updating participant $participantId status to "$status" for post $postId',
    );

    final uri = Uri.parse('$baseUrl/posts/posts/$postId/event/participants');

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'participant_id': participantId, 'status': status}),
      );

      _debugResponse(tag, response);

      if (_isHtmlResponse(response.body)) {
        _debugError(tag, '❌ Server returned HTML!');
        throw Exception('Server mengembalikan HTML bukan JSON.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Participant status updated successfully');
        return;
      }

      if (response.statusCode == 401) {
        _debugLog(tag, '❌ Token tidak valid atau kadaluarsa');
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        _debugLog(tag, '❌ Akses ditolak: ${data['message']}');
        throw Exception(data['message'] ?? 'Anda tidak memiliki akses');
      }

      if (response.statusCode == 400) {
        _debugLog(tag, '❌ Bad Request: ${data['message']}');
        throw Exception(data['message'] ?? 'Gagal update status peserta');
      }

      _debugError(
        tag,
        '❌ Status code: ${response.statusCode}, message: ${data['message']}',
      );
      throw Exception(
        data['message'] ?? 'Gagal update status (${response.statusCode})',
      );
    } on http.ClientException catch (e) {
      _debugError(tag, '❌ ClientException: $e');
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, '❌ Error: $e');
      rethrow;
    }
  }
}
