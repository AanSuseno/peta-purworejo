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

  Future<Map<String, dynamic>> createCampaign({
    required String token,
    required String title,
    required String description,
    required String donationType, // 'money', 'goods', 'volunteer'
    int? communityId, // 🔥 Ubah menjadi nullable (opsional)
    double? targetAmount,
    String? bankAccountInfo,
    String? ewalletInfo,
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
    if (bankAccountInfo != null && bankAccountInfo.isNotEmpty) {
      body['bank_account_info'] = bankAccountInfo.trim();
    }
    if (ewalletInfo != null && ewalletInfo.isNotEmpty) {
      body['ewallet_info'] = ewalletInfo.trim();
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

  // ==================== DONATION ENDPOINTS ====================

  Future<Map<String, dynamic>> donateMoney({
    required String token,
    required int campaignId,
    required double amount,
    required String paymentMethod,
    required String donorName,
    required String donorPhone,
    required String donorEmail,
    int? communityId,
    String? donationPurpose,
    int? representativeId,
    bool isAnonymous = false,
    File? proofImage,
  }) async {
    const tag = 'donateMoney';
    _debugLog(tag, 'Donating money to campaign: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/donate');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['donation_type'] = 'money'
        ..fields['amount'] = amount.toString()
        ..fields['payment_method'] = paymentMethod
        ..fields['donor_name'] = donorName.trim()
        ..fields['donor_phone'] = donorPhone.trim()
        ..fields['donor_email'] = donorEmail.trim()
        ..fields['is_anonymous'] = isAnonymous ? 'true' : 'false';

      if (communityId != null) {
        request.fields['community_id'] = communityId.toString();
      }
      if (donationPurpose != null && donationPurpose.isNotEmpty) {
        request.fields['donation_purpose'] = donationPurpose.trim();
      }
      if (representativeId != null) {
        request.fields['representative_id'] = representativeId.toString();
      }

      // 🔥 PERBAIKAN: Field name harus 'proof_image' sesuai backend
      if (proofImage != null) {
        final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
        request.files.add(
          await http.MultipartFile.fromPath(
            'proof_image', // 🔥 Ubah dari 'proof' menjadi 'proof_image'
            proofImage.path,
            filename: fileName,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        _debugLog(tag, 'Proof image attached: $fileName');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _debugLog(tag, 'Response status: ${response.statusCode}');

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Donation created successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data donasi tidak valid');
      }

      throw Exception(data['message'] ?? 'Gagal membuat donasi');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
    }
  }

  /// POST /donations/campaigns/:id/donate-goods - Donasi barang
  Future<Map<String, dynamic>> donateGoods({
    required String token,
    required int campaignId,
    required String goodsType,
    required String goodsName,
    required double goodsQuantity,
    required String goodsUnit,
    required String deliveryMethod,
    required String donorName,
    required String donorPhone,
    required String donorEmail,
    String? deliveryAddress,
    int? communityId,
    String? donationPurpose,
    int? representativeId,
    bool isAnonymous = false,
    File? goodsPhoto,
  }) async {
    const tag = 'donateGoods';
    _debugLog(tag, 'Donating goods to campaign: $campaignId');

    final uri =
        Uri.parse('$baseUrl/donations/campaigns/$campaignId/donate-goods');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['donation_type'] = 'goods'
        ..fields['goods_type'] = goodsType
        ..fields['goods_name'] = goodsName.trim()
        ..fields['goods_quantity'] = goodsQuantity.toString()
        ..fields['goods_unit'] = goodsUnit
        ..fields['delivery_method'] = deliveryMethod
        ..fields['donor_name'] = donorName.trim()
        ..fields['donor_phone'] = donorPhone.trim()
        ..fields['donor_email'] = donorEmail.trim()
        ..fields['is_anonymous'] = isAnonymous ? 'true' : 'false';

      if (deliveryAddress != null && deliveryAddress.isNotEmpty) {
        request.fields['delivery_address'] = deliveryAddress.trim();
      }
      if (communityId != null) {
        request.fields['community_id'] = communityId.toString();
      }
      if (donationPurpose != null && donationPurpose.isNotEmpty) {
        request.fields['donation_purpose'] = donationPurpose.trim();
      }
      if (representativeId != null) {
        request.fields['representative_id'] = representativeId.toString();
      }

      // 🔥 PERBAIKAN: Field name harus 'goods_photo' sesuai backend
      if (goodsPhoto != null) {
        final fileName = 'goods_${DateTime.now().millisecondsSinceEpoch}.jpg';
        request.files.add(
          await http.MultipartFile.fromPath(
            'goods_photo', // 🔥 Sudah benar
            goodsPhoto.path,
            filename: fileName,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        _debugLog(tag, 'Goods photo attached: $fileName');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final data = _parseResponse(tag, response);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _debugLog(tag, '✅ Goods donation created successfully');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data donasi tidak valid');
      }

      throw Exception(data['message'] ?? 'Gagal membuat donasi barang');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
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
    _debugLog(tag, 'Registering as volunteer for campaign: $campaignId');

    final uri = Uri.parse('$baseUrl/donations/campaigns/$campaignId/volunteer');

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

      final data = _parseResponse(tag, response);

      if (response.statusCode == 200) {
        _debugLog(tag, '✅ Volunteer registration successful');
        return data['data'] as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        throw AuthException('Token tidak valid atau kadaluarsa');
      }

      if (response.statusCode == 400) {
        throw Exception(data['message'] ?? 'Data pendaftaran tidak valid');
      }

      throw Exception(data['message'] ?? 'Gagal mendaftar sebagai volunteer');
    } on http.ClientException {
      throw Exception('Gagal terhubung ke server');
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

  Future<Map<String, dynamic>> updateCampaign({
    required String token,
    required int campaignId,
    required String title,
    required String description,
    required String donationType,
    double? targetAmount,
    String? bankAccountInfo,
    String? ewalletInfo,
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
    if (bankAccountInfo != null && bankAccountInfo.isNotEmpty) {
      body['bank_account_info'] = bankAccountInfo.trim();
    }
    if (ewalletInfo != null && ewalletInfo.isNotEmpty) {
      body['ewallet_info'] = ewalletInfo.trim();
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
}
