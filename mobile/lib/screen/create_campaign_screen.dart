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

class CreateCampaignScreen extends StatefulWidget {
  final int communityId;

  const CreateCampaignScreen({
    super.key,
    required this.communityId,
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

    // Validasi spesifik tipe donasi
    if (_donationType == 'money' && _targetAmountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Target donasi wajib diisi untuk donasi uang'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sesi tidak ditemukan, silakan login ulang')),
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

      final result = await _service.createCampaign(
        token: token,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        donationType: _donationType,
        communityId: widget.communityId,
        targetAmount: targetAmount,
        bankAccountInfo: _bankAccountController.text.trim(),
        ewalletInfo: _ewalletController.text.trim(),
        goodsDescription: _goodsDescriptionController.text.trim(),
        volunteerNeeds: _volunteerNeedsController.text.trim(),
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
            result['message'] ?? 'Campaign donasi berhasil dibuat',
          ),
        ),
      );
      // Kirim balik data campaign yang baru dibuat (bukan cuma `true`),
      // supaya layar sebelumnya bisa langsung menampilkannya tanpa harus
      // menunggu approval admin/founder membuatnya muncul lagi dari server.
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
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
          'Buat Campaign Donasi',
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
              _fieldLabel('Judul Campaign *'),
              _textField(
                controller: _titleController,
                hint: 'Masukkan judul campaign donasi',
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Judul wajib diisi'
                    : null,
              ),
              const SizedBox(height: 16),

              // Deskripsi
              _fieldLabel('Deskripsi *'),
              _textField(
                controller: _descriptionController,
                hint: 'Jelaskan tujuan campaign donasi ini',
                maxLines: 4,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Deskripsi wajib diisi'
                    : null,
              ),
              const SizedBox(height: 16),

              // Field spesifik donasi uang
              if (_donationType == 'money') ...[
                _fieldLabel('Target Donasi (Rp) *'),
                _textField(
                  controller: _targetAmountController,
                  hint: 'Masukkan target donasi',
                  keyboardType: TextInputType.number,
                  prefixText: 'Rp ',
                ),
                const SizedBox(height: 12),
                _fieldLabel('Informasi Rekening (Opsional)'),
                _textField(
                  controller: _bankAccountController,
                  hint: 'Masukkan info rekening bank',
                ),
                const SizedBox(height: 8),
                _fieldLabel('Informasi E-Wallet (Opsional)'),
                _textField(
                  controller: _ewalletController,
                  hint: 'Masukkan info e-wallet',
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
                _fieldLabel('Kuota Relawan'),
                _textField(
                  controller: _volunteerSlotsController,
                  hint: 'Jumlah relawan yang dibutuhkan',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
              ],

              // Periode Campaign
              _fieldLabel('Periode Campaign'),
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
                'Campaign yang dibuat oleh member akan membutuhkan persetujuan admin/founder komunitas terlebih dahulu.',
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
