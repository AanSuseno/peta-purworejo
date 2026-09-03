// lib/services/donation_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'auth_service.dart';

/// Response untuk campaign
class CampaignPage {
  final List<Map<String, dynamic>> campaigns;
  final int page;
  final int totalPages;
  final int total;

  CampaignPage({
    required this.campaigns,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  bool get hasMore => page < totalPages;
}

class DonationService {
  static const String baseUrl = AuthService.baseUrl;

  void _debugLog(String tag, String message) {
    if (kDebugMode) {
      debugPrint('📝 [$tag] $message');
    }
  }

  void _debugError(String tag, dynamic error) {
    if (kDebugMode) {
      debugPrint('❌ [$tag] Error: $error');
    }
  }

  bool _isHtmlResponse(String body) {
    return body.trim().startsWith('<!DOCTYPE') ||
        body.trim().startsWith('<html') ||
        body.trim().startsWith('<?xml');
  }

  dynamic _parseResponse(String tag, http.Response response) {
    final body = response.body;

    if (_isHtmlResponse(body)) {
      if (body.contains('404')) {
        throw Exception('Endpoint tidak ditemukan (404)');
      } else if (body.contains('500')) {
        throw Exception('Server error (500)');
      } else {
        throw Exception('Server mengembalikan HTML bukan JSON');
      }
    }

    try {
      return jsonDecode(body);
    } catch (e) {
      throw Exception('Response tidak valid: ${e.toString()}');
    }
  }

  // ==================== CAMPAIGN ENDPOINTS ====================

  /// GET /donations/campaigns - Daftar campaign dengan filter
  Future<CampaignPage> fetchCampaigns({
    required String token,
    int page = 1,
    int limit = 10,
    String? status,
    String? donationType,
    int? communityId,
    String? search,
    bool showPending = false,
  }) async {
    const tag = 'fetchCampaigns';
    _debugLog(tag, 'Fetching campaigns, page: $page');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status != null && status.isNotEmpty) 'status': status,
      if (donationType != null && donationType.isNotEmpty)
        'donation_type': donationType,
      if (communityId != null) 'community_id': '$communityId',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (showPending) 'show_pending': 'true',
    };

    final uri = Uri.parse('$baseUrl/donations/campaigns')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        final rawList = (data['data'] as List?) ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>?;

        return CampaignPage(
          campaigns: rawList
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList(),
          page: pagination?['page'] ?? page,
          totalPages: pagination?['totalPages'] ?? 1,
          total: pagination?['total'] ?? 0,
        );
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(data['message'] ?? 'Gagal memuat campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// GET /donations/campaigns/:id - Detail campaign
  Future<Map<String, dynamic>> fetchCampaignById({
    required String token,
    required int campaignId,
  }) async {
    const tag = 'fetchCampaignById';
    _debugLog(tag, 'Fetching campaign ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Campaign tidak ditemukan');
      }

      throw Exception(data['message'] ?? 'Gagal memuat detail campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// PUT /donations/campaigns/:id/approve - Setujui campaign (admin komunitas/founder/system admin)
  Future<Map<String, dynamic>> approveCampaign({
    required String token,
    required int campaignId,
  }) async {
    const tag = 'approveCampaign';
    _debugLog(tag, 'Approving campaign ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/approve');

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Campaign approved successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
            data['message'] ?? 'Anda tidak berhak menyetujui campaign ini');
      }

      if (response.statusCode == 400 || response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Gagal menyetujui campaign');
      }

      throw Exception(data['message'] ?? 'Gagal menyetujui campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// PUT /donations/campaigns/:id/reject - Tolak campaign (admin komunitas/founder/system admin)
  Future<Map<String, dynamic>> rejectCampaign({
    required String token,
    required int campaignId,
    required String rejectionReason,
  }) async {
    const tag = 'rejectCampaign';
    _debugLog(tag, 'Rejecting campaign ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/reject');

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'rejection_reason': rejectionReason.trim()}),
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Campaign rejected successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
            data['message'] ?? 'Anda tidak berhak menolak campaign ini');
      }

      if (response.statusCode == 400 || response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Gagal menolak campaign');
      }

      throw Exception(data['message'] ?? 'Gagal menolak campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// GET /donations/campaigns/:id/stats - Statistik campaign
  Future<Map<String, dynamic>> fetchCampaignStats({
    required String token,
    required int campaignId,
  }) async {
    const tag = 'fetchCampaignStats';
    _debugLog(tag, 'Fetching campaign stats ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/stats');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      throw Exception(data['message'] ?? 'Gagal memuat statistik campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// POST /donations/campaigns - Create campaign
  Future<Map<String, dynamic>> createCampaign({
    required String token,
    required String title,
    required String description,
    required String donationType, // 'money', 'goods', 'volunteer'
    int? communityId,
    double? targetAmount,
    String?
        paymentInfo, // 🔥 GABUNG: bank_account_info + ewallet_info → payment_info
    String? goodsDescription,
    String? volunteerNeeds,
    int? volunteerSlots,
    String? startDate,
    String? endDate,
  }) async {
    const tag = 'createCampaign';
    _debugLog(tag, 'Creating campaign: "$title"');

    final uri = Uri.parse('$baseUrl/donations/campaigns');

    final body = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'donation_type': donationType,
    };

    // 🔥 Hanya tambahkan community_id jika ada (tidak null)
    if (communityId != null) {
      body['community_id'] = communityId;
    }

    if (targetAmount != null && targetAmount > 0) {
      body['target_amount'] = targetAmount;
    }

    // 🔥 PERUBAHAN: Gunakan payment_info (satu field) bukan bank_account_info + ewallet_info
    if (paymentInfo != null && paymentInfo.isNotEmpty) {
      body['payment_info'] = paymentInfo.trim();
    }

    if (goodsDescription != null && goodsDescription.isNotEmpty) {
      body['goods_description'] = goodsDescription.trim();
    }
    if (volunteerNeeds != null && volunteerNeeds.isNotEmpty) {
      body['volunteer_needs'] = volunteerNeeds.trim();
    }
    if (volunteerSlots != null && volunteerSlots > 0) {
      body['volunteer_slots'] = volunteerSlots;
    }
    if (startDate != null && startDate.isNotEmpty) {
      body['start_date'] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      body['end_date'] = endDate;
    }

    // ❌ HAPUS: volunteer_registered (tidak ada di DB)
    // ❌ HAPUS: bank_account_info (diganti payment_info)
    // ❌ HAPUS: ewallet_info (diganti payment_info)

    _debugLog(tag, 'Request body: ${jsonEncode(body)}');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Campaign created successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(data['message'] ?? 'Anda tidak memiliki izin');
      }

      if (response.statusCode == 400) {
        // 🔥 Tampilkan pesan error lebih detail
        final message = data['message'] ?? 'Data yang dikirim tidak valid';
        throw Exception(message);
      }

      throw Exception(data['message'] ?? 'Gagal membuat campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// PUT /donations/campaigns/:id - Update campaign
  Future<Map<String, dynamic>> updateCampaign({
    required String token,
    required int campaignId,
    required String title,
    required String description,
    required String donationType,
    double? targetAmount,
    String?
        paymentInfo, // 🔥 GABUNG: bank_account_info + ewallet_info → payment_info
    String? goodsDescription,
    String? volunteerNeeds,
    int? volunteerSlots,
    String? startDate,
    String? endDate,
  }) async {
    const tag = 'updateCampaign';
    _debugLog(tag, 'Updating campaign ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId');

    final body = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'donation_type': donationType,
    };

    if (targetAmount != null && targetAmount > 0) {
      body['target_amount'] = targetAmount;
    }

    // 🔥 PERUBAHAN: Gunakan payment_info (satu field)
    if (paymentInfo != null && paymentInfo.isNotEmpty) {
      body['payment_info'] = paymentInfo.trim();
    }

    if (goodsDescription != null && goodsDescription.isNotEmpty) {
      body['goods_description'] = goodsDescription.trim();
    }
    if (volunteerNeeds != null && volunteerNeeds.isNotEmpty) {
      body['volunteer_needs'] = volunteerNeeds.trim();
    }
    if (volunteerSlots != null && volunteerSlots > 0) {
      body['volunteer_slots'] = volunteerSlots;
    }
    if (startDate != null && startDate.isNotEmpty) {
      body['start_date'] = startDate;
    }
    if (endDate != null && endDate.isNotEmpty) {
      body['end_date'] = endDate;
    }

    // ❌ HAPUS: bank_account_info (diganti payment_info)
    // ❌ HAPUS: ewallet_info (diganti payment_info)

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

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Campaign updated successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(data['message'] ??
            'Anda tidak memiliki izin untuk mengupdate campaign ini');
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data yang dikirim tidak valid');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Campaign tidak ditemukan');
      }

      throw Exception(data['message'] ?? 'Gagal mengupdate campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// DELETE /donations/campaigns/:id - Delete campaign
  Future<void> deleteCampaign({
    required String token,
    required int campaignId,
  }) async {
    const tag = 'deleteCampaign';
    _debugLog(tag, 'Deleting campaign ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId');

    try {
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Campaign deleted successfully');
        return;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
            data['message'] ?? 'Anda tidak berhak menghapus campaign ini');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Campaign tidak ditemukan');
      }

      throw Exception(data['message'] ?? 'Gagal menghapus campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  // ==================== DONATION ENDPOINTS ====================

  /// POST /donations/campaigns/:id/donate - Donasi uang
  Future<Map<String, dynamic>> donateMoney({
    required String token,
    required int campaignId,
    required double amount,
    required String donorName,
    required String donorPhone,
    required String donorEmail,
    int? communityId,
    bool isAnonymous = false,
    File? proofImage,
  }) async {
    const tag = 'donateMoney';

    _debugLog(tag, 'Donating money to campaign: $campaignId');

    final uri = Uri.parse(
      '$baseUrl/donations/campaigns/$campaignId/donate',
    );

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['donation_type'] = 'money'
        ..fields['amount'] = amount.toString()
        ..fields['donor_name'] = donorName.trim()
        ..fields['donor_phone'] = donorPhone.trim()
        ..fields['donor_email'] = donorEmail.trim()
        ..fields['is_anonymous'] = isAnonymous ? 'true' : 'false';

      if (communityId != null) {
        request.fields['community_id'] = communityId.toString();
      }

      if (proofImage != null) {
        final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';

        request.files.add(
          await http.MultipartFile.fromPath(
            'proof_image',
            proofImage.path,
            filename: fileName,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

        _debugLog(tag, 'Proof image attached: $fileName');
      }

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      _debugLog(
        tag,
        'Response status: ${response.statusCode}',
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(
          tag,
          '✅ Donation created successfully',
        );

        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException(
          'Token tidak valid atau kadaluarsa',
        );
      }

      if (response.statusCode == 400) {
        throw Exception(
          data['message'] ?? 'Data donasi tidak valid',
        );
      }

      throw Exception(
        data['message'] ?? 'Gagal membuat donasi',
      );
    } on http.ClientException {
      throw Exception(
        'Gagal terhubung ke server',
      );
    }
  }

  /// POST /donations/campaigns/:id/donate-goods - Donasi barang
  Future<Map<String, dynamic>> donateGoods({
    required String token,
    required int campaignId,
    required String goodsName,
    required double goodsQuantity,
    required String goodsUnit,
    required String donorName,
    required String donorPhone,
    required String donorEmail,
    String? deliveryNotes,
    int? communityId,
    bool isAnonymous = false,
  }) async {
    const tag = 'donateGoods';

    _debugLog(
      tag,
      'Donating goods to campaign: $campaignId',
    );

    final uri = Uri.parse(
      '$baseUrl/donations/campaigns/$campaignId/donate-goods',
    );

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['donation_type'] = 'goods'
        ..fields['goods_name'] = goodsName.trim()
        ..fields['goods_quantity'] = goodsQuantity.toString()
        ..fields['goods_unit'] = goodsUnit
        ..fields['donor_name'] = donorName.trim()
        ..fields['donor_phone'] = donorPhone.trim()
        ..fields['donor_email'] = donorEmail.trim()
        ..fields['is_anonymous'] = isAnonymous ? 'true' : 'false';

      if (deliveryNotes != null && deliveryNotes.isNotEmpty) {
        request.fields['delivery_notes'] = deliveryNotes.trim();
      }

      if (communityId != null) {
        request.fields['community_id'] = communityId.toString();
      }

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      _debugLog(
        tag,
        'Response status: ${response.statusCode}',
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(
          tag,
          '✅ Goods donation created successfully',
        );

        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException(
          'Token tidak valid atau kadaluarsa',
        );
      }

      if (response.statusCode == 400) {
        throw Exception(
          data['message'] ?? 'Data donasi tidak valid',
        );
      }

      throw Exception(
        data['message'] ?? 'Gagal membuat donasi barang',
      );
    } on http.ClientException {
      throw Exception(
        'Gagal terhubung ke server',
      );
    }
  }

  /// POST /donations/campaigns/:id/volunteer - Daftar sebagai volunteer
  Future<Map<String, dynamic>> registerVolunteer({
    required String token,
    required int campaignId,
    String? availability,
    String? skills,
    String? experience,
    String? notes,
  }) async {
    const tag = 'registerVolunteer';

    _debugLog(
      tag,
      'Registering as volunteer for campaign: $campaignId',
    );

    final uri = Uri.parse(
      '$baseUrl/donations/campaigns/$campaignId/volunteer',
    );

    final body = <String, dynamic>{};

    if (availability != null && availability.isNotEmpty) {
      body['availability'] = availability.trim();
    }

    if (skills != null && skills.isNotEmpty) {
      body['skills'] = skills.trim();
    }

    if (experience != null && experience.isNotEmpty) {
      body['experience'] = experience.trim();
    }

    if (notes != null && notes.isNotEmpty) {
      body['notes'] = notes.trim();
    }

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      _debugLog(
        tag,
        'Response status: ${response.statusCode}',
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _debugLog(
          tag,
          '✅ Volunteer registration successful',
        );

        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException(
          'Token tidak valid atau kadaluarsa',
        );
      }

      if (response.statusCode == 400) {
        throw Exception(
          data['message'] ?? 'Data pendaftaran tidak valid',
        );
      }

      throw Exception(
        data['message'] ?? 'Gagal mendaftar sebagai volunteer',
      );
    } on http.ClientException {
      throw Exception(
        'Gagal terhubung ke server',
      );
    }
  }

  /// GET /donations/donations/me - Donasi saya
  Future<Map<String, dynamic>> getMyDonations({
    required String token,
    int page = 1,
    int limit = 10,
    String? status,
    String? donationType,
  }) async {
    const tag = 'getMyDonations';
    _debugLog(tag, 'Fetching my donations, page: $page');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status != null && status.isNotEmpty) 'status': status,
      if (donationType != null && donationType.isNotEmpty)
        'donation_type': donationType,
    };

    final uri = Uri.parse('$baseUrl/donations/donations/me')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(data['message'] ?? 'Gagal memuat donasi saya');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// GET /donations/campaigns/:id/donations - Donasi campaign
  Future<Map<String, dynamic>> getCampaignDonations({
    required String token,
    required int campaignId,
    int page = 1,
    int limit = 20,
    String? status,
    String? donationType,
  }) async {
    const tag = 'getCampaignDonations';
    _debugLog(tag, 'Fetching donations for campaign: $campaignId');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status != null && status.isNotEmpty) 'status': status,
      if (donationType != null && donationType.isNotEmpty)
        'donation_type': donationType,
    };

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/donations')
        .replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(data['message'] ?? 'Gagal memuat donasi campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// GET /donations/campaigns/:id/summary - Ringkasan donasi campaign
  Future<Map<String, dynamic>> getCampaignSummary({
    required String token,
    required int campaignId,
  }) async {
    const tag = 'getCampaignSummary';
    _debugLog(tag, 'Fetching summary for campaign: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/summary');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      throw Exception(data['message'] ?? 'Gagal memuat ringkasan campaign');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  // ==================== DISTRIBUTION ENDPOINTS ====================

  /// GET /donations/campaigns/:id/distributions - Daftar distribusi campaign
  Future<Map<String, dynamic>> getCampaignDistributions({
    required String token,
    required int campaignId,
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    const tag = 'getCampaignDistributions';
    _debugLog(tag, 'Fetching distributions for campaign: $campaignId');

    final queryParams = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (status != null && status.isNotEmpty) 'status': status,
    };

    final uri = Uri.parse(
      '$baseUrl/donations/campaigns/$campaignId/distributions',
    ).replace(queryParameters: queryParams);

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      throw Exception(data['message'] ?? 'Gagal memuat daftar distribusi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// GET /donations/distributions/:id - Detail distribusi
  Future<Map<String, dynamic>> fetchDistributionById({
    required String token,
    required int distributionId,
  }) async {
    const tag = 'fetchDistributionById';
    _debugLog(tag, 'Fetching distribution ID: $distributionId');

    final uri = Uri.parse('$baseUrl/donations/distributions/$distributionId');

    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Distribusi tidak ditemukan');
      }

      throw Exception(data['message'] ?? 'Gagal memuat detail distribusi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// POST /donations/campaigns/:id/distributions - Buat distribusi baru (dengan bukti/evidence)
  Future<Map<String, dynamic>> createDistribution({
    required String token,
    required int campaignId,
    required String recipientName,
    required double amount,
    String? recipientPhone,
    String? recipientAddress,
    String? description,
    List<File>? evidenceImages,
  }) async {
    const tag = 'createDistribution';
    _debugLog(tag, 'Creating distribution for campaign: $campaignId');

    final uri = Uri.parse(
      '$baseUrl/donations/campaigns/$campaignId/distributions',
    );

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['recipient_name'] = recipientName.trim()
        ..fields['amount'] = amount.toString();

      if (recipientPhone != null && recipientPhone.isNotEmpty) {
        request.fields['recipient_phone'] = recipientPhone.trim();
      }
      if (recipientAddress != null && recipientAddress.isNotEmpty) {
        request.fields['recipient_address'] = recipientAddress.trim();
      }
      if (description != null && description.isNotEmpty) {
        request.fields['description'] = description.trim();
      }

      if (evidenceImages != null && evidenceImages.isNotEmpty) {
        for (final image in evidenceImages) {
          final fileName =
              'evidence_${DateTime.now().millisecondsSinceEpoch}_${evidenceImages.indexOf(image)}.jpg';

          request.files.add(
            await http.MultipartFile.fromPath(
              'evidence_images',
              image.path,
              filename: fileName,
              contentType: MediaType('image', 'jpeg'),
            ),
          );
        }
        _debugLog(tag, '${evidenceImages.length} evidence image(s) attached');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _debugLog(tag, 'Response status: ${response.statusCode}');

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Distribution created successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
          data['message'] ?? 'Anda tidak berhak membuat distribusi',
        );
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data distribusi tidak valid');
      }

      throw Exception(data['message'] ?? 'Gagal membuat distribusi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// POST /donations/distributions/:id/evidence - Tambah bukti ke distribusi yang sudah ada
  Future<List<Map<String, dynamic>>> addDistributionEvidence({
    required String token,
    required int distributionId,
    required List<File> evidenceImages,
  }) async {
    const tag = 'addDistributionEvidence';
    _debugLog(tag, 'Adding evidence to distribution: $distributionId');

    final uri = Uri.parse(
      '$baseUrl/donations/distributions/$distributionId/evidence',
    );

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token';

      for (final image in evidenceImages) {
        final fileName =
            'evidence_${DateTime.now().millisecondsSinceEpoch}_${evidenceImages.indexOf(image)}.jpg';

        request.files.add(
          await http.MultipartFile.fromPath(
            'evidence_images',
            image.path,
            filename: fileName,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _debugLog(tag, 'Response status: ${response.statusCode}');

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Evidence added successfully');
        final rawList = (data['data'] as List?) ?? [];
        return rawList
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
          data['message'] ?? 'Anda tidak berhak menambahkan bukti',
        );
      }

      throw Exception(data['message'] ?? 'Gagal menambahkan bukti distribusi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// PUT /donations/distributions/:id - Update status/data distribusi
  Future<Map<String, dynamic>> updateDistributionStatus({
    required String token,
    required int distributionId,
    String? status, // 'pending', 'distributed', 'cancelled'
    String? recipientName,
    String? recipientPhone,
    String? recipientAddress,
    double? amount,
    String? description,
  }) async {
    const tag = 'updateDistributionStatus';
    _debugLog(tag, 'Updating distribution ID: $distributionId');

    final uri = Uri.parse('$baseUrl/donations/distributions/$distributionId');

    final body = <String, dynamic>{};

    if (status != null && status.isNotEmpty) body['status'] = status;
    if (recipientName != null && recipientName.isNotEmpty) {
      body['recipient_name'] = recipientName.trim();
    }
    if (recipientPhone != null) body['recipient_phone'] = recipientPhone.trim();
    if (recipientAddress != null) {
      body['recipient_address'] = recipientAddress.trim();
    }
    if (amount != null) body['amount'] = amount;
    if (description != null) body['description'] = description.trim();

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      _debugLog(tag, 'Response status: ${response.statusCode}');

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Distribution updated successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
          data['message'] ?? 'Anda tidak berhak mengubah distribusi ini',
        );
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data yang dikirim tidak valid');
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Distribusi tidak ditemukan');
      }

      throw Exception(data['message'] ?? 'Gagal memperbarui distribusi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// DELETE /donations/distributions/:id - Hapus distribusi
  Future<void> deleteDistribution({
    required String token,
    required int distributionId,
  }) async {
    const tag = 'deleteDistribution';
    _debugLog(tag, 'Deleting distribution ID: $distributionId');

    final uri = Uri.parse('$baseUrl/donations/distributions/$distributionId');

    try {
      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Distribution deleted successfully');
        return;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(
          data['message'] ?? 'Anda tidak berhak menghapus distribusi ini',
        );
      }

      if (response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Distribusi tidak ditemukan');
      }

      throw Exception(data['message'] ?? 'Gagal menghapus distribusi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }

  /// PUT /donations/campaigns/:id/complete - Tandai campaign selesai (admin komunitas/founder/creator)
  Future<Map<String, dynamic>> completeCampaign({
    required String token,
    required int campaignId,
  }) async {
    const tag = 'completeCampaign';
    _debugLog(tag, 'Completing campaign ID: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/complete');

    try {
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Campaign marked as completed');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 403) {
        throw Exception(data['message'] ??
            'Anda tidak berhak menandai campaign ini selesai');
      }

      if (response.statusCode == 400 || response.statusCode == 404) {
        throw Exception(data['message'] ?? 'Gagal menandai campaign selesai');
      }

      throw Exception(data['message'] ?? 'Gagal menandai campaign selesai');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    } catch (e) {
      _debugError(tag, e);
      rethrow;
    }
  }
}

// AuthException untuk error autentikasi
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
