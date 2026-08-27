// lib/screens/create_campaign_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../provider/auth_provider.dart';
import '../services/donation_service.dart';
import '../widgets/custom_text_field.dart';

class CreateCampaignScreen extends StatefulWidget {
  final int? communityId; // 🔥 Ubah menjadi nullable

  const CreateCampaignScreen({
    super.key,
    this.communityId, // 🔥 Tidak lagi required
  });

  @override
  State<CreateCampaignScreen> createState() => _CreateCampaignScreenState();
}

class _CreateCampaignScreenState extends State<CreateCampaignScreen> {
  final DonationService _service = DonationService();
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _ewalletController = TextEditingController();
  final _goodsDescriptionController = TextEditingController();
  final _volunteerNeedsController = TextEditingController();
  final _volunteerSlotsController = TextEditingController();

  // Dropdown selections
  String _donationType = 'money'; // 'money', 'goods', 'volunteer'
  bool _isSubmitting = false;

  // Date ranges
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _targetAmountController.dispose();
    _bankAccountController.dispose();
    _ewalletController.dispose();
    _goodsDescriptionController.dispose();
    _volunteerNeedsController.dispose();
    _volunteerSlotsController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
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
      initialDate: _startDate!.add(const Duration(days: 7)),
      firstDate: _startDate!,
      lastDate: _startDate!.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // 🔥 Validasi spesifik tipe donasi
    if (_donationType == 'money') {
      // Validasi target amount untuk donasi uang
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

    // 🔥 Validasi untuk volunteer slots
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

      // 🔥 Perbaikan: Gunakan parameter yang benar
      final result = await _service.createCampaign(
        token: token,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        donationType: _donationType,
        communityId: widget.communityId, // Bisa null untuk campaign personal
        targetAmount: targetAmount,
        bankAccountInfo: _bankAccountController.text.trim().isNotEmpty
            ? _bankAccountController.text.trim()
            : null,
        ewalletInfo: _ewalletController.text.trim().isNotEmpty
            ? _ewalletController.text.trim()
            : null,
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

      // 🔥 Tampilkan pesan sukses
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Campaign berhasil dibuat! Menunggu persetujuan admin.',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // Kirim balik data campaign yang baru dibuat
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;

      // 🔥 Tampilkan pesan error yang lebih jelas
      String errorMessage = e.toString().replaceFirst('Exception: ', '');

      // 🔥 Handle error spesifik
      if (errorMessage.contains('member of this community')) {
        errorMessage = 'Anda harus menjadi member komunitas ini untuk membuat campaign';
      } else if (errorMessage.contains('Maximum 5 active campaigns')) {
        errorMessage = 'Maksimal 5 campaign aktif per komunitas';
      } else if (errorMessage.contains('Token tidak valid')) {
        errorMessage = 'Sesi Anda kadaluarsa, silakan login ulang';
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
          widget.communityId != null ? 'Buat Campaign Donasi' : 'Buat Campaign Personal',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 Informasi komunitas (jika ada)
              if (widget.communityId != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Campaign ini akan dibuat di dalam komunitas dan membutuhkan persetujuan admin.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Tipe Donasi
              _fieldLabel('Tipe Donasi *'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _donationType,
                    isExpanded: true,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: Colors.black87,
                    ),
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: const [
                      DropdownMenuItem(
                        value: 'money',
                        child: Row(
                          children: [
                            Icon(Icons.attach_money, size: 18),
                            SizedBox(width: 8),
                            Text('Donasi Uang'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'goods',
                        child: Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Donasi Barang'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'volunteer',
                        child: Row(
                          children: [
                            Icon(Icons.handshake_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Relawan'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _donationType = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Judul
              CustomTextField(
                controller: _titleController,
                hint: 'Masukkan judul campaign',
                label: 'Judul Campaign',
                required: true,
                maxLines: 1,
                validator: (value) =>
                value?.isEmpty ?? true ? 'Judul wajib diisi' : null,
              ),
              const SizedBox(height: 16),

              // Deskripsi
              CustomTextField(
                controller: _descriptionController,
                hint: 'Jelaskan tujuan campaign donasi ini',
                label: 'Deskripsi',
                required: true,
                maxLines: 4,
                validator: (value) =>
                value?.isEmpty ?? true ? 'Deskripsi wajib diisi' : null,
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
                _fieldLabel('Informasi Rekening (Opsional)'),
                _textField(
                  controller: _bankAccountController,
                  hint: 'Contoh: BCA 123456789 a.n. John Doe',
                ),
                const SizedBox(height: 8),
                _fieldLabel('Informasi E-Wallet (Opsional)'),
                _textField(
                  controller: _ewalletController,
                  hint: 'Contoh: OVO 08123456789',
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
                          ? DateFormat('dd/MM/yyyy').format(_startDate!)
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
                    'Buat Campaign',
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              Text(
                widget.communityId != null
                    ? 'Campaign yang dibuat oleh member akan membutuhkan persetujuan admin/founder komunitas terlebih dahulu.'
                    : 'Campaign personal akan langsung aktif setelah dibuat.',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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