import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/communities_service.dart';

/// Form edit komunitas yang sudah ada. Dibuka dari [CommunityDetailScreen]
/// lewat tombol "Edit Komunitas" (hanya terlihat untuk admin/founder).
///
/// Beda dengan alur buat komunitas (2 langkah terpisah karena POST
/// /communities cuma terima JSON), di sini logo & banner bisa langsung
/// diganti di layar yang sama -- komunitasnya sudah ada duluan, jadi
/// upload logo/banner (PATCH via multipart ke /communities/:id/logo dan
/// /banner) bisa langsung jalan begitu gambar dipilih, terpisah dari
/// submit form teks (PUT /communities/:id).
class EditCommunityScreen extends StatefulWidget {
  /// Data komunitas lengkap (hasil GET /communities/:id) dari layar detail,
  /// dipakai untuk mengisi form supaya tidak perlu fetch ulang.
  final Map<String, dynamic> community;

  const EditCommunityScreen({super.key, required this.community});

  @override
  State<EditCommunityScreen> createState() => _EditCommunityScreenState();
}

class _EditCommunityScreenState extends State<EditCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = CommunitiesService();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _kecamatanController;
  late final TextEditingController _addressController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  bool _isLoadingCategories = true;
  bool _isSubmitting = false;

  String? _logoUrl;
  String? _bannerUrl;
  bool _isUploadingLogo = false;
  bool _isUploadingBanner = false;

  /// Community record terbaru -- dimutakhirkan tiap kali logo/banner
  /// selesai diupload, supaya kalau user tekan "Simpan" setelahnya, hasil
  /// akhir yang dikembalikan ke layar detail sudah menyertakan gambar baru.
  late Map<String, dynamic> _community;

  int get _communityId => widget.community['community_id'] as int;

  @override
  void initState() {
    super.initState();
    _community = widget.community;

    _nameController = TextEditingController(
      text: (widget.community['community_name'] as String?) ?? '',
    );
    _descriptionController = TextEditingController(
      text: (widget.community['description'] as String?) ?? '',
    );
    _kecamatanController = TextEditingController(
      text: (widget.community['kecamatan'] as String?) ?? '',
    );
    _addressController = TextEditingController(
      text: (widget.community['address'] as String?) ?? '',
    );
    _emailController = TextEditingController(
      text: (widget.community['contact_email'] as String?) ?? '',
    );
    _phoneController = TextEditingController(
      text: (widget.community['contact_phone'] as String?) ?? '',
    );

    final category = widget.community['categories'] as Map<String, dynamic>?;
    _selectedCategoryId =
        (category?['category_id'] as int?) ??
        (widget.community['category_id'] as int?);

    _logoUrl = _resolveUrl(widget.community['logo'] as String?);
    _bannerUrl = _resolveUrl(widget.community['banner'] as String?);

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

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AuthService.baseUrl}$path';
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
        // Kalau kategori komunitas saat ini ternyata sudah tidak ada di
        // daftar (mis. dihapus), jangan paksa dropdown menampilkan value
        // yang tidak valid -- biarkan kosong daripada error.
        if (_selectedCategoryId != null &&
            !_categories.any((c) => c['category_id'] == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }
      });
    } catch (e) {
      // Kategori opsional -- kalau gagal dimuat, form tetap bisa dipakai
      // (dropdown cuma tidak akan muncul).
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    }
  }

  // ---------------------------------------------------------------------
  // Logo & banner: pilih -> crop -> langsung upload (tidak menunggu tombol
  // "Simpan"), sama seperti alur di CommunityMediaUploadScreen.
  // ---------------------------------------------------------------------

  Future<XFile?> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Pilih Sumber Gambar',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: AppColors.primary,
              ),
              title: Text('Ambil Foto', style: GoogleFonts.poppins()),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: Text('Pilih dari Galeri', style: GoogleFonts.poppins()),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return ImagePicker().pickImage(source: source, imageQuality: 90);
  }

  Future<void> _pickAndCropLogo() async {
    final picked = await _pickImage();
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Sesuaikan Logo',
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Sesuaikan Logo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped == null) return;

    await _uploadLogo(File(cropped.path));
  }

  Future<void> _pickAndCropBanner() async {
    final picked = await _pickImage();
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Sesuaikan Banner',
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Sesuaikan Banner', aspectRatioLockEnabled: true),
      ],
    );
    if (cropped == null) return;

    await _uploadBanner(File(cropped.path));
  }

  Future<void> _uploadLogo(File file) async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    setState(() => _isUploadingLogo = true);
    try {
      final updated = await _service.uploadLogo(token, _communityId, file);
      if (!mounted) return;
      setState(() {
        _community = {..._community, ...updated};
        _logoUrl = _resolveUrl(updated['logo'] as String?);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal mengunggah logo: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<void> _uploadBanner(File file) async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    setState(() => _isUploadingBanner = true);
    try {
      final updated = await _service.uploadBanner(token, _communityId, file);
      if (!mounted) return;
      setState(() {
        _community = {..._community, ...updated};
        _bannerUrl = _resolveUrl(updated['banner'] as String?);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal mengunggah banner: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingBanner = false);
    }
  }

  // ---------------------------------------------------------------------
  // Simpan perubahan field teks
  // ---------------------------------------------------------------------

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
      final updated = await _service.updateCommunity(
        token: token,
        communityId: _communityId,
        communityName: _nameController.text,
        description: _descriptionController.text,
        categoryId: _selectedCategoryId,
        kecamatan: _kecamatanController.text,
        address: _addressController.text,
        contactEmail: _emailController.text,
        contactPhone: _phoneController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Komunitas berhasil diperbarui')),
      );
      // Kembalikan data terbaru ke CommunityDetailScreen supaya bisa
      // langsung dipakai tanpa fetch ulang.
      Navigator.of(context).pop({..._community, ...updated});
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
          'Edit Komunitas',
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
              'Banner',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _isUploadingBanner ? null : _pickAndCropBanner,
              child: Container(
                height: 140,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _bannerContent(),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Logo',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _isUploadingLogo ? null : _pickAndCropLogo,
              child: Container(
                width: 88,
                height: 88,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _logoContent(),
              ),
            ),
            const SizedBox(height: 24),

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
                        'Simpan Perubahan',
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

  Widget _bannerContent() {
    if (_isUploadingBanner) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_bannerUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _bannerUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _bannerPlaceholder(),
          ),
          Positioned(right: 8, bottom: 8, child: _editBadge()),
        ],
      );
    }
    return _bannerPlaceholder();
  }

  Widget _bannerPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary.withOpacity(0.15), Colors.indigo.shade50],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(height: 6),
          Text(
            'Ketuk untuk ganti banner',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _logoContent() {
    if (_isUploadingLogo) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_logoUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _logoUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.primary.withOpacity(0.15),
              alignment: Alignment.center,
              child: Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),
          Positioned(right: 0, bottom: 0, child: _editBadge()),
        ],
      );
    }
    return Container(
      color: AppColors.primary.withOpacity(0.15),
      alignment: Alignment.center,
      child: Icon(
        Icons.add_a_photo_outlined,
        color: AppColors.primary,
        size: 22,
      ),
    );
  }

  Widget _editBadge() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Icon(Icons.edit, size: 11, color: Colors.white),
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
