// lib/screens/campaign_detail_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/donation_service.dart';

class CampaignDetailScreen extends StatefulWidget {
  final int campaignId;
  final int communityId;

  const CampaignDetailScreen({
    super.key,
    required this.campaignId,
    required this.communityId,
  });

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

/// Parse angka dari dynamic dengan aman. Backend kadang mengirim field
/// numerik (mis. target_amount, collected_amount, progress, amount) sebagai
/// String (umum terjadi pada tipe Decimal), jadi jangan pernah hard-cast
/// `as double`.
double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  final DonationService _service = DonationService();
  final TextEditingController _donorNameController = TextEditingController();
  final TextEditingController _donorPhoneController = TextEditingController();
  final TextEditingController _donorEmailController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  Map<String, dynamic>? _campaign;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _donations = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isDonating = false;
  bool _isVolunteer = false;
  bool _isProcessingApproval = false;
  String? _error;

  // Donation type
  String _donationType = 'money'; // 'money', 'goods', 'volunteer'

  // Goods fields
  String _goodsType = 'food';
  String _goodsName = '';
  double _goodsQuantity = 0;
  String _goodsUnit = 'kg';
  String _deliveryMethod = 'dropoff';
  String _deliveryAddress = '';
  File? _goodsPhoto;
  File? _proofImage;

  // Volunteer fields
  String _volunteerAvailability = '';
  String _volunteerSkills = '';
  String _volunteerExperience = '';
  String _volunteerNotes = '';

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _donorNameController.dispose();
    _donorPhoneController.dispose();
    _donorEmailController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Sesi tidak ditemukan, silakan login ulang';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final campaign = await _service.fetchCampaignById(
        token: token,
        campaignId: widget.campaignId,
      );

      final summary = await _service.getCampaignSummary(
        token: token,
        campaignId: widget.campaignId,
      );

      final donations = await _service.getCampaignDonations(
        token: token,
        campaignId: widget.campaignId,
        limit: 20,
      );

      if (!mounted) return;

      setState(() {
        _campaign = campaign;
        _summary = summary;
        _donations = (donations['data'] as List?)
                ?.whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList() ??
            [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'active':
        return 'Aktif';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getDonationTypeLabel(String? type) {
    switch (type) {
      case 'money':
        return 'Donasi Uang';
      case 'goods':
        return 'Donasi Barang';
      case 'volunteer':
        return 'Relawan';
      default:
        return type ?? 'Unknown';
    }
  }

  String _getDonationTypeIcon(String? type) {
    switch (type) {
      case 'money':
        return '💰';
      case 'goods':
        return '📦';
      case 'volunteer':
        return '🤝';
      default:
        return '🎯';
    }
  }

  Future<void> _pickImage(ImageSource source, bool isGoods) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() {
        if (isGoods) {
          _goodsPhoto = File(picked.path);
        } else {
          _proofImage = File(picked.path);
        }
      });
    }
  }

  Future<void> _submitDonation() async {
    if (_donationType == 'money') {
      await _submitMoneyDonation();
    } else if (_donationType == 'goods') {
      await _submitGoodsDonation();
    } else {
      await _submitVolunteerRegistration();
    }
  }

  Future<void> _submitMoneyDonation() async {
    // Validasi
    if (_donorNameController.text.trim().isEmpty) {
      _showError('Nama donatur wajib diisi');
      return;
    }
    if (_donorPhoneController.text.trim().isEmpty) {
      _showError('Nomor HP donatur wajib diisi');
      return;
    }
    if (_donorEmailController.text.trim().isEmpty ||
        !_donorEmailController.text.contains('@')) {
      _showError('Email donatur wajib diisi dan valid');
      return;
    }
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showError('Jumlah donasi harus diisi dan lebih dari 0');
      return;
    }
    if (_proofImage == null) {
      _showError('Bukti transfer wajib diupload');
      return;
    }

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      _showError('Sesi tidak ditemukan, silakan login ulang');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.donateMoney(
        token: token,
        campaignId: widget.campaignId,
        amount: amount,
        paymentMethod: 'bank_transfer',
        donorName: _donorNameController.text.trim(),
        donorPhone: _donorPhoneController.text.trim(),
        donorEmail: _donorEmailController.text.trim(),
        communityId: widget.communityId,
        proofImage: _proofImage,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Donasi berhasil dibuat, menunggu verifikasi'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitGoodsDonation() async {
    // Validasi
    if (_donorNameController.text.trim().isEmpty) {
      _showError('Nama donatur wajib diisi');
      return;
    }
    if (_donorPhoneController.text.trim().isEmpty) {
      _showError('Nomor HP donatur wajib diisi');
      return;
    }
    if (_donorEmailController.text.trim().isEmpty ||
        !_donorEmailController.text.contains('@')) {
      _showError('Email donatur wajib diisi dan valid');
      return;
    }
    if (_goodsName.trim().isEmpty) {
      _showError('Nama barang wajib diisi');
      return;
    }
    if (_goodsQuantity <= 0) {
      _showError('Jumlah barang harus lebih dari 0');
      return;
    }

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      _showError('Sesi tidak ditemukan, silakan login ulang');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.donateGoods(
        token: token,
        campaignId: widget.campaignId,
        goodsType: _goodsType,
        goodsName: _goodsName.trim(),
        goodsQuantity: _goodsQuantity,
        goodsUnit: _goodsUnit,
        deliveryMethod: _deliveryMethod,
        donorName: _donorNameController.text.trim(),
        donorPhone: _donorPhoneController.text.trim(),
        donorEmail: _donorEmailController.text.trim(),
        deliveryAddress: _deliveryAddress.trim(),
        communityId: widget.communityId,
        goodsPhoto: _goodsPhoto,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Donasi barang berhasil dibuat, menunggu verifikasi'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitVolunteerRegistration() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      _showError('Sesi tidak ditemukan, silakan login ulang');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.registerVolunteer(
        token: token,
        campaignId: widget.campaignId,
        availability: _volunteerAvailability.trim(),
        skills: _volunteerSkills.trim(),
        experience: _volunteerExperience.trim(),
        notes: _volunteerNotes.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Berhasil mendaftar sebagai volunteer, menunggu konfirmasi'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  Future<void> _approveCampaign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Setujui Campaign',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Campaign ini akan langsung tampil publik dan bisa menerima donasi. Lanjutkan?',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Setujui', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      _showError('Sesi tidak ditemukan, silakan login ulang');
      return;
    }

    setState(() => _isProcessingApproval = true);

    try {
      await _service.approveCampaign(
          token: token, campaignId: widget.campaignId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign berhasil disetujui')),
      );
      await _loadDetail();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isProcessingApproval = false);
    }
  }

  Future<void> _showRejectDialog() async {
    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tolak Campaign',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Tuliskan alasan penolakan...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tolak', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    reasonController.dispose();

    if (reason == null || reason.isEmpty) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      _showError('Sesi tidak ditemukan, silakan login ulang');
      return;
    }

    setState(() => _isProcessingApproval = true);

    try {
      await _service.rejectCampaign(
        token: token,
        campaignId: widget.campaignId,
        rejectionReason: reason,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign ditolak')),
      );
      await _loadDetail();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isProcessingApproval = false);
    }
  }

  /// Panel aksi approve/reject, tampil jika campaign belum disetujui.
  /// Backend tetap memvalidasi hak akses (403 jika bukan admin komunitas/
  /// founder/system admin), jadi non-admin yang menekan tombol ini akan
  /// melihat pesan error dari server.
  Widget _buildApprovalActions() {
    final approvalStatus =
        _campaign?['approval_status'] as String? ?? 'approved';
    if (approvalStatus == 'approved') return const SizedBox.shrink();

    final rejectionReason = _campaign?['rejection_reason'] as String?;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: approvalStatus == 'rejected'
            ? Colors.red.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: approvalStatus == 'rejected'
              ? Colors.red.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approvalStatus == 'rejected'
                    ? Icons.cancel_outlined
                    : Icons.hourglass_top_rounded,
                size: 18,
                color: approvalStatus == 'rejected'
                    ? Colors.red.shade700
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  approvalStatus == 'rejected'
                      ? 'Campaign ini ditolak'
                      : 'Campaign ini menunggu persetujuan admin komunitas',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: approvalStatus == 'rejected'
                        ? Colors.red.shade700
                        : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          if (approvalStatus == 'rejected' &&
              rejectionReason != null &&
              rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Alasan: $rejectionReason',
              style:
                  GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade600),
            ),
          ],
          const SizedBox(height: 12),
          if (_isProcessingApproval)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _showRejectDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _approveCampaign,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Setujui'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showDonationDialog() {
    _donationType = _campaign?['donation_type'] ?? 'money';
    _donorNameController.clear();
    _donorPhoneController.clear();
    _donorEmailController.clear();
    _amountController.clear();
    _goodsName = '';
    _goodsQuantity = 0;
    _deliveryAddress = '';
    _goodsPhoto = null;
    _proofImage = null;
    _volunteerAvailability = '';
    _volunteerSkills = '';
    _volunteerExperience = '';
    _volunteerNotes = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _donationType == 'money'
                    ? 'Donasi Uang'
                    : _donationType == 'goods'
                        ? 'Donasi Barang'
                        : 'Daftar Relawan',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _campaign?['title'] ?? '',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: _buildDonationForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDonationForm() {
    if (_donationType == 'money') {
      return _buildMoneyDonationForm();
    } else if (_donationType == 'goods') {
      return _buildGoodsDonationForm();
    } else {
      return _buildVolunteerForm();
    }
  }

  Widget _buildMoneyDonationForm() {
    return Column(
      children: [
        _formField('Nama Donatur *', _donorNameController),
        const SizedBox(height: 12),
        _formField('Nomor HP *', _donorPhoneController,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _formField('Email *', _donorEmailController,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _formField('Jumlah Donasi (Rp) *', _amountController,
            keyboardType: TextInputType.number, prefixText: 'Rp '),
        const SizedBox(height: 12),
        _buildImagePicker(
          label: 'Upload Bukti Transfer *',
          imageFile: _proofImage,
          onPick: () => _pickImage(ImageSource.gallery, false),
          onCamera: () => _pickImage(ImageSource.camera, false),
        ),
        const SizedBox(height: 20),
        _buildSubmitButton('Kirim Donasi'),
      ],
    );
  }

  Widget _buildGoodsDonationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formField('Nama Donatur *', _donorNameController),
        const SizedBox(height: 12),
        _formField('Nomor HP *', _donorPhoneController,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _formField('Email *', _donorEmailController,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _fieldLabel('Tipe Barang *'),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              value: _goodsType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'food', child: Text('Makanan')),
                DropdownMenuItem(value: 'clothing', child: Text('Pakaian')),
                DropdownMenuItem(value: 'medicine', child: Text('Obat-obatan')),
                DropdownMenuItem(value: 'other', child: Text('Lainnya')),
              ],
              onChanged: (v) => setState(() => _goodsType = v!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Nama Barang *'),
        TextFormField(
          initialValue: _goodsName,
          onChanged: (v) => setState(() => _goodsName = v),
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _inputDecoration('Masukkan nama barang'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Jumlah *'),
                  TextFormField(
                    initialValue:
                        _goodsQuantity > 0 ? _goodsQuantity.toString() : '',
                    onChanged: (v) => setState(() {
                      _goodsQuantity = double.tryParse(v) ?? 0;
                    }),
                    style: GoogleFonts.poppins(fontSize: 13.5),
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Jumlah'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Satuan *'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButtonFormField<String>(
                        value: _goodsUnit,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                          DropdownMenuItem(
                              value: 'liter', child: Text('liter')),
                          DropdownMenuItem(value: 'unit', child: Text('unit')),
                        ],
                        onChanged: (v) => setState(() => _goodsUnit = v!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _fieldLabel('Metode Pengiriman *'),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              value: _deliveryMethod,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'pickup', child: Text('Diambil')),
                DropdownMenuItem(
                    value: 'dropoff', child: Text('Antar ke Lokasi')),
                DropdownMenuItem(value: 'courier', child: Text('Kurir')),
              ],
              onChanged: (v) => setState(() => _deliveryMethod = v!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Alamat Pengiriman'),
        TextFormField(
          initialValue: _deliveryAddress,
          onChanged: (v) => setState(() => _deliveryAddress = v),
          maxLines: 2,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _inputDecoration('Masukkan alamat pengiriman'),
        ),
        const SizedBox(height: 12),
        _buildImagePicker(
          label: 'Upload Foto Barang (Opsional)',
          imageFile: _goodsPhoto,
          onPick: () => _pickImage(ImageSource.gallery, true),
          onCamera: () => _pickImage(ImageSource.camera, true),
        ),
        const SizedBox(height: 20),
        _buildSubmitButton('Kirim Donasi Barang'),
      ],
    );
  }

  Widget _buildVolunteerForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Ketersediaan Waktu'),
        TextFormField(
          initialValue: _volunteerAvailability,
          onChanged: (v) => setState(() => _volunteerAvailability = v),
          maxLines: 2,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _inputDecoration('Kapan Anda tersedia?'),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Keahlian'),
        TextFormField(
          initialValue: _volunteerSkills,
          onChanged: (v) => setState(() => _volunteerSkills = v),
          maxLines: 2,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _inputDecoration('Keahlian yang dimiliki'),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Pengalaman'),
        TextFormField(
          initialValue: _volunteerExperience,
          onChanged: (v) => setState(() => _volunteerExperience = v),
          maxLines: 3,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _inputDecoration('Pengalaman sebagai relawan'),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Catatan Tambahan'),
        TextFormField(
          initialValue: _volunteerNotes,
          onChanged: (v) => setState(() => _volunteerNotes = v),
          maxLines: 2,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration: _inputDecoration('Catatan tambahan'),
        ),
        const SizedBox(height: 20),
        _buildSubmitButton('Daftar Relawan'),
      ],
    );
  }

  Widget _formField(String label, TextEditingController controller,
      {TextInputType? keyboardType, String? prefixText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(fontSize: 13.5),
          decoration:
              _inputDecoration('Masukkan $label', prefixText: prefixText),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      );

  InputDecoration _inputDecoration(String hint, {String? prefixText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
      prefixText: prefixText,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary),
      ),
    );
  }

  Widget _buildImagePicker({
    required String label,
    required File? imageFile,
    required VoidCallback onPick,
    required VoidCallback onCamera,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        GestureDetector(
          onTap: onPick,
          child: Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: imageFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      imageFile,
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 28, color: Colors.grey.shade400),
                      const SizedBox(height: 4),
                      Text(
                        'Tap untuk pilih gambar',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: onPick,
                            icon: const Icon(Icons.photo_library, size: 16),
                            label: const Text('Galeri'),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: onCamera,
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text('Kamera'),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(String label) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitDonation,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          _campaign?['title'] ?? 'Detail Campaign',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      bottomSheet: _campaign?['status'] == 'active' && !_isLoading
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _showDonationDialog,
                    icon: Icon(
                      _campaign?['donation_type'] == 'money'
                          ? Icons.attach_money
                          : _campaign?['donation_type'] == 'goods'
                              ? Icons.inventory_2_outlined
                              : Icons.handshake_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _campaign?['donation_type'] == 'money'
                          ? 'Donasi Sekarang'
                          : _campaign?['donation_type'] == 'goods'
                              ? 'Donasi Barang'
                              : 'Daftar Relawan',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final campaign = _campaign!;
    final summary = _summary!;
    final donationType = campaign['donation_type'] as String? ?? 'money';
    final status = campaign['status'] as String?;
    final targetAmount = _parseDouble(campaign['target_amount']);
    final collectedAmount = _parseDouble(campaign['collected_amount']) ?? 0;
    final progress = _parseDouble(campaign['progress']) ?? 0;
    final totalDonors = _parseInt(campaign['total_donors']) ?? 0;
    final totalVolunteers = _parseInt(campaign['total_volunteers']) ?? 0;
    final community = campaign['communities'] as Map<String, dynamic>?;
    final communityName = community?['community_name'] as String?;
    final creator = campaign['users'] as Map<String, dynamic>?;
    final creatorName = creator?['full_name'] as String?;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadDetail,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: 80 + MediaQuery.of(context).padding.bottom,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusLabel(status),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(status),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_getDonationTypeIcon(donationType)} ${_getDonationTypeLabel(donationType)}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    campaign['title'] ?? 'Tanpa Judul',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  if (communityName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Komunitas: $communityName',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  if (creatorName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Dibuat oleh: $creatorName',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    campaign['description'] ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Panel approve/reject campaign (hanya tampil jika belum approved)
            _buildApprovalActions(),

            // Progress
            if (donationType == 'money' && targetAmount != null) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Terkumpul',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            Text(
                              _formatCurrency(collectedAmount),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Target',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            Text(
                              _formatCurrency(targetAmount),
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.grey.shade200,
                        color: AppColors.primary,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${progress.round()}% terkumpul',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '$totalDonors donatur',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Volunteer stats
            if (donationType == 'volunteer') ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          label: 'Relawan Terdaftar',
                          value: '$totalVolunteers',
                          icon: Icons.handshake_outlined,
                        ),
                        _StatItem(
                          label: 'Dibutuhkan',
                          value: '${campaign['volunteer_slots'] ?? '∞'}',
                          icon: Icons.people_outline,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Detail info
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informasi Tambahan',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (campaign['bank_account_info'] != null &&
                      (campaign['bank_account_info'] as String).isNotEmpty)
                    _InfoRow(
                      icon: Icons.account_balance_outlined,
                      label: 'Rekening',
                      value: campaign['bank_account_info'],
                    ),
                  if (campaign['ewallet_info'] != null &&
                      (campaign['ewallet_info'] as String).isNotEmpty)
                    _InfoRow(
                      icon: Icons.wallet_outlined,
                      label: 'E-Wallet',
                      value: campaign['ewallet_info'],
                    ),
                  if (campaign['start_date'] != null)
                    _InfoRow(
                      icon: Icons.event_available_outlined,
                      label: 'Mulai',
                      value: DateFormat('dd/MM/yyyy')
                          .format(DateTime.parse(campaign['start_date'])),
                    ),
                  if (campaign['end_date'] != null)
                    _InfoRow(
                      icon: Icons.event_busy_outlined,
                      label: 'Selesai',
                      value: DateFormat('dd/MM/yyyy')
                          .format(DateTime.parse(campaign['end_date'])),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Recent donations
            if (_donations.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donasi Terbaru',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._donations.take(5).map((donation) {
                      final isAnonymous = donation['is_anonymous'] == true;
                      final donorName = isAnonymous
                          ? 'Anonim'
                          : (donation['donor_name'] as String? ?? 'Unknown');
                      final amount = _parseDouble(donation['amount']);
                      final status = donation['status'] as String?;
                      final createdAt = donation['created_at'] as String?;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  AppColors.primary.withOpacity(0.1),
                              child: Text(
                                donorName.isNotEmpty ? donorName[0] : '?',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    donorName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  if (createdAt != null)
                                    Text(
                                      DateFormat('dd/MM/yyyy HH:mm')
                                          .format(DateTime.parse(createdAt)),
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (amount != null)
                              Text(
                                _formatCurrency(amount),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'confirmed'
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status == 'confirmed'
                                    ? '✓'
                                    : status == 'pending'
                                        ? '⏳'
                                        : '✗',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: status == 'confirmed'
                                      ? Colors.green
                                      : status == 'pending'
                                          ? Colors.orange
                                          : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: _loadDetail,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Coba Lagi', style: GoogleFonts.poppins()),
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
