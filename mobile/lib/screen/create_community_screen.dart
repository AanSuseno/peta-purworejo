import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/communities_service.dart';
import 'community_media_upload_screen.dart';

/// Langkah 1 dari alur buat komunitas: isi data teks dulu (nama, deskripsi,
/// kategori, kecamatan, kontak). Logo & banner diupload di layar berikutnya
/// (CommunityMediaUploadScreen) karena endpoint POST /communities menerima
/// JSON biasa, bukan multipart -- jadi gambar tidak bisa ikut dikirim
/// bareng di form yang sama.
class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = CommunitiesService();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _kecamatanController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  bool _isLoadingCategories = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _kecamatanController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      setState(() => _isLoadingCategories = false);
      return;
    }
    try {
      final categories = await _service.fetchCategories(token);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (e) {
      // Kategori bersifat opsional saat buat komunitas, jadi kalau gagal
      // dimuat, form tetap bisa dipakai -- cukup tanpa pilihan kategori.
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi tidak ditemukan, silakan login ulang'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final created = await _service.createCommunity(
        token: token,
        communityName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        categoryId: _selectedCategoryId,
        kecamatan: _kecamatanController.text.trim(),
        address: _addressController.text.trim(),
        contactEmail: _emailController.text.trim(),
        contactPhone: _phoneController.text.trim(),
      );

      if (!mounted) return;

      final communityId = created['community_id'] as int;
      final communityName =
          (created['community_name'] as String?) ?? _nameController.text.trim();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Komunitas berhasil dibuat')),
      );

      // Lanjut ke layar upload logo & banner, lalu tutup form ini juga
      // begitu layar upload selesai -- jadi dari daftar komunitas cukup
      // 1x `push` yang menunggu 1 hasil akhir (true = perlu refresh list).
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CommunityMediaUploadScreen(
            communityId: communityId,
            communityName: communityName,
          ),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(result ?? true);
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
          'Buat Komunitas',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'Langkah 1 dari 2',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Lengkapi data komunitas. Logo dan banner bisa diunggah di langkah berikutnya.',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            _fieldLabel('Nama Komunitas *'),
            _textField(
              controller: _nameController,
              hint: 'Contoh: Komunitas Peduli Lingkungan',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Nama komunitas wajib diisi'
                  : null,
            ),
            const SizedBox(height: 16),
            _fieldLabel('Deskripsi'),
            _textField(
              controller: _descriptionController,
              hint: 'Ceritakan tentang komunitas ini...',
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            _fieldLabel('Kategori'),
            _categoryDropdown(),
            const SizedBox(height: 16),
            _fieldLabel('Kecamatan'),
            _textField(
              controller: _kecamatanController,
              hint: 'Contoh: Cilandak',
            ),
            const SizedBox(height: 16),
            _fieldLabel('Alamat'),
            _textField(
              controller: _addressController,
              hint: 'Alamat sekretariat / titik kumpul (opsional)',
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _fieldLabel('Email Kontak'),
            _textField(
              controller: _emailController,
              hint: 'kontak@komunitas.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _fieldLabel('No. Telepon Kontak'),
            _textField(
              controller: _phoneController,
              hint: '08xxxxxxxxxx',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmit,
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
                        'Lanjut: Unggah Logo & Banner',
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
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: Colors.grey.shade400,
        ),
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

  Widget _categoryDropdown() {
    if (_isLoadingCategories) {
      return Container(
        height: 48,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Kategori tidak tersedia (opsional, bisa dilewati)',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: Colors.grey.shade400,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<int>(
          value: _selectedCategoryId,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13.5, color: Colors.black87),
          decoration: const InputDecoration(border: InputBorder.none),
          hint: Text(
            'Pilih kategori (opsional)',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
          ),
          items: _categories
              .map(
                (c) => DropdownMenuItem<int>(
                  value: c['category_id'] as int,
                  child: Text((c['category_name'] as String?) ?? '-'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedCategoryId = value),
        ),
      ),
    );
  }
}
