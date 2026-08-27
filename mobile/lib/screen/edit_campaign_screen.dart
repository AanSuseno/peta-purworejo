// lib/screens/edit_campaign_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../provider/auth_provider.dart';
import '../services/donation_service.dart';
import '../widgets/custom_text_field.dart';

class EditCampaignScreen extends StatefulWidget {
  final int campaignId;
  final int communityId;
  final Map<String, dynamic> initialData;

  const EditCampaignScreen({
    super.key,
    required this.campaignId,
    required this.communityId,
    required this.initialData,
  });

  @override
  State<EditCampaignScreen> createState() => _EditCampaignScreenState();
}

class _EditCampaignScreenState extends State<EditCampaignScreen> {
  final DonationService _service = DonationService();
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _paymentInfoController =
      TextEditingController(); // 🔥 GANTI: gabung bank & ewallet
  final _goodsDescriptionController = TextEditingController();
  final _volunteerNeedsController = TextEditingController();
  final _volunteerSlotsController = TextEditingController();

  // Dropdown selections
  String _donationType = 'money';
  bool _isSubmitting = false;
  bool _isLoading = true;
  String? _error;

  // Date ranges
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final data = widget.initialData;

    _titleController.text = data['title'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _donationType = data['donation_type'] ?? 'money';

    // Load field sesuai tipe donasi
    if (_donationType == 'money') {
      final targetAmount = data['target_amount'];
      if (targetAmount != null) {
        _targetAmountController.text = targetAmount.toString();
      }
      // 🔥 PERUBAHAN: Gunakan payment_info (bukan bank_account_info + ewallet_info)
      _paymentInfoController.text = data['payment_info'] ?? '';
    }

    if (_donationType == 'goods') {
      _goodsDescriptionController.text = data['goods_description'] ?? '';
    }

    if (_donationType == 'volunteer') {
      _volunteerNeedsController.text = data['volunteer_needs'] ?? '';
      final slots = data['volunteer_slots'];
      if (slots != null) {
        _volunteerSlotsController.text = slots.toString();
      }
    }

    // Load dates
    if (data['start_date'] != null) {
      _startDate = DateTime.parse(data['start_date']);
    }
    if (data['end_date'] != null) {
      _endDate = DateTime.parse(data['end_date']);
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetAmountController.dispose();
    _paymentInfoController.dispose(); // 🔥 GANTI
    _goodsDescriptionController.dispose();
    _volunteerNeedsController.dispose();
    _volunteerSlotsController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih tanggal mulai terlebih dahulu'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate!.add(const Duration(days: 7)),
      firstDate: _startDate!,
      lastDate: _startDate!.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validasi spesifik tipe donasi
    if (_donationType == 'money') {
      if (_targetAmountController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Target donasi wajib diisi untuk donasi uang'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final targetAmount = double.tryParse(_targetAmountController.text);
      if (targetAmount == null || targetAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Target donasi harus berupa angka positif'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validasi volunteer slots
    if (_donationType == 'volunteer') {
      if (_volunteerSlotsController.text.isNotEmpty) {
        final slots = int.tryParse(_volunteerSlotsController.text);
        if (slots == null || slots <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kuota relawan harus berupa angka positif'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi tidak ditemukan, silakan login ulang'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final targetAmount = _targetAmountController.text.isNotEmpty
          ? double.tryParse(_targetAmountController.text)
          : null;

      final volunteerSlots = _volunteerSlotsController.text.isNotEmpty
          ? int.tryParse(_volunteerSlotsController.text)
          : null;

      // 🔥 PERUBAHAN: Gunakan paymentInfo (satu field)
      final paymentInfo = _paymentInfoController.text.trim().isNotEmpty
          ? _paymentInfoController.text.trim()
          : null;

      final result = await _service.updateCampaign(
        token: token,
        campaignId: widget.campaignId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        donationType: _donationType,
        targetAmount: targetAmount,
        paymentInfo: paymentInfo, // 🔥 GANTI: kirim payment_info
        goodsDescription: _goodsDescriptionController.text.trim().isNotEmpty
            ? _goodsDescriptionController.text.trim()
            : null,
        volunteerNeeds: _volunteerNeedsController.text.trim().isNotEmpty
            ? _volunteerNeedsController.text.trim()
            : null,
        volunteerSlots: volunteerSlots,
        startDate: _startDate != null
            ? DateFormat('yyyy-MM-dd').format(_startDate!)
            : null,
        endDate: _endDate != null
            ? DateFormat('yyyy-MM-dd').format(_endDate!)
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Campaign donasi berhasil diperbarui',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      String errorMessage = e.toString().replaceFirst('Exception: ', '');

      // 🔥 Handle error spesifik
      if (errorMessage.contains('Token tidak valid')) {
        errorMessage = 'Sesi Anda kadaluarsa, silakan login ulang';
      } else if (errorMessage.contains('Anda tidak memiliki izin')) {
        errorMessage = 'Anda tidak memiliki izin untuk mengedit campaign ini';
      } else if (errorMessage.contains('Campaign tidak ditemukan')) {
        errorMessage = 'Campaign tidak ditemukan';
      } else if (errorMessage.contains('End date must be after start date')) {
        errorMessage = 'Tanggal selesai harus setelah tanggal mulai';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          'Edit Campaign Donasi',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tipe Donasi (readonly - tidak bisa diubah)
                        _fieldLabel('Tipe Donasi'),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _donationType == 'money'
                                    ? Icons.attach_money
                                    : _donationType == 'goods'
                                        ? Icons.inventory_2_outlined
                                        : Icons.handshake_outlined,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _donationType == 'money'
                                    ? 'Donasi Uang'
                                    : _donationType == 'goods'
                                        ? 'Donasi Barang'
                                        : 'Relawan',
                                style: GoogleFonts.poppins(
                                  fontSize: 13.5,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Judul
                        CustomTextField(
                          controller: _titleController,
                          hint: 'Masukkan judul',
                          label: 'Judul Campaign',
                          required: true,
                          maxLines: 1,
                          validator: (value) =>
                              value?.isEmpty ?? true ? 'Wajib diisi' : null,
                        ),
                        const SizedBox(height: 16),

                        // Deskripsi
                        CustomTextField(
                          controller: _descriptionController,
                          hint: 'Jelaskan tujuan campaign donasi ini',
                          label: 'Deskripsi',
                          required: true,
                          maxLines: 4,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Deskripsi wajib diisi'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Field spesifik donasi uang
                        if (_donationType == 'money') ...[
                          CustomTextField(
                            controller: _targetAmountController,
                            hint: 'Masukkan target donasi',
                            label: 'Target Donasi (Rp)',
                            required: true,
                            maxLines: 1,
                            keyboardType: TextInputType.number,
                            prefixText: 'Rp ',
                            validator: (value) {
                              if (value?.isEmpty ?? true) {
                                return 'Target donasi wajib diisi';
                              }
                              final amount = double.tryParse(value!);
                              if (amount == null || amount <= 0) {
                                return 'Masukkan angka yang valid';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // 🔥 PERUBAHAN: Gabung bank & ewallet menjadi satu field
                          _fieldLabel('Informasi Pembayaran (Opsional)'),
                          Text(
                            'Masukkan rekening bank dan/atau e-wallet yang dapat digunakan untuk donasi',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _textField(
                            controller: _paymentInfoController,
                            hint:
                                'Contoh: BCA 123456789 a.n. John Doe / OVO 08123456789',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Field spesifik donasi barang
                        if (_donationType == 'goods') ...[
                          _fieldLabel('Deskripsi Barang yang Dibutuhkan *'),
                          _textField(
                            controller: _goodsDescriptionController,
                            hint: 'Jelaskan barang apa saja yang dibutuhkan',
                            maxLines: 3,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Deskripsi barang wajib diisi'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Field spesifik volunteer
                        if (_donationType == 'volunteer') ...[
                          _fieldLabel('Kebutuhan Relawan *'),
                          _textField(
                            controller: _volunteerNeedsController,
                            hint: 'Jelaskan kebutuhan relawan',
                            maxLines: 3,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Kebutuhan relawan wajib diisi'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          _fieldLabel('Kuota Relawan (Opsional)'),
                          _textField(
                            controller: _volunteerSlotsController,
                            hint: 'Jumlah relawan yang dibutuhkan',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Periode Campaign
                        _fieldLabel('Periode Campaign (Opsional)'),
                        Row(
                          children: [
                            Expanded(
                              child: _DatePickerButton(
                                label: _startDate != null
                                    ? DateFormat('dd/MM/yyyy')
                                        .format(_startDate!)
                                    : 'Mulai',
                                icon: Icons.calendar_today,
                                onTap: _selectStartDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DatePickerButton(
                                label: _endDate != null
                                    ? DateFormat('dd/MM/yyyy').format(_endDate!)
                                    : 'Selesai',
                                icon: Icons.calendar_today,
                                onTap: _selectEndDate,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Info approval status
                        _buildApprovalStatus(),
                        const SizedBox(height: 16),

                        // Submit
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Perbarui Campaign',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildApprovalStatus() {
    final approvalStatus =
        widget.initialData['approval_status'] as String? ?? 'approved';
    final rejectionReason = widget.initialData['rejection_reason'] as String?;

    if (approvalStatus == 'approved') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Campaign ini sudah disetujui dan publik',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (approvalStatus == 'pending') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, color: Colors.orange.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Campaign ini menunggu persetujuan admin komunitas',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (approvalStatus == 'rejected' && rejectionReason != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cancel, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Campaign ini ditolak',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            if (rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Alasan: $rejectionReason',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.red.shade600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text('Coba Lagi', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? prefixText,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: Colors.grey.shade400,
        ),
        prefixText: prefixText,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DatePickerButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: label.contains('Mulai') || label.contains('Selesai')
                      ? Colors.grey.shade400
                      : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
