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

/// Langkah 2 dari alur buat komunitas: unggah logo (crop persegi) dan
/// banner (crop lebar 16:9) untuk komunitas yang baru dibuat. Dipisah dari
/// form supaya proses buat komunitas (JSON) tidak tercampur dengan upload
/// file (multipart) -- dua request yang beda bentuk ke endpoint yang beda.
class CommunityMediaUploadScreen extends StatefulWidget {
  final int communityId;
  final String communityName;

  const CommunityMediaUploadScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  State<CommunityMediaUploadScreen> createState() =>
      _CommunityMediaUploadScreenState();
}

class _CommunityMediaUploadScreenState
    extends State<CommunityMediaUploadScreen> {
  final _service = CommunitiesService();

  File? _logoFile;
  File? _bannerFile;
  String? _logoUrl;
  String? _bannerUrl;
  bool _isUploadingLogo = false;
  bool _isUploadingBanner = false;

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AuthService.baseUrl}$path';
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

    setState(() => _logoFile = File(cropped.path));
    await _uploadLogo();
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

    setState(() => _bannerFile = File(cropped.path));
    await _uploadBanner();
  }

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

  Future<void> _uploadLogo() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null || _logoFile == null) return;

    setState(() => _isUploadingLogo = true);
    try {
      final updated = await _service.uploadLogo(
        token,
        widget.communityId,
        _logoFile!,
      );
      if (!mounted) return;
      setState(() => _logoUrl = _resolveUrl(updated['logo'] as String?));
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

  Future<void> _uploadBanner() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null || _bannerFile == null) return;

    setState(() => _isUploadingBanner = true);
    try {
      final updated = await _service.uploadBanner(
        token,
        widget.communityId,
        _bannerFile!,
      );
      if (!mounted) return;
      setState(() => _bannerUrl = _resolveUrl(updated['banner'] as String?));
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

  void _finish() {
    // Pop layar ini dengan hasil `true` -- CreateCommunityScreen akan
    // menangkap ini lalu pop dirinya sendiri juga dengan `true`, jadi
    // CommunityScreen (paling awal memanggil push) tahu harus refresh list.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          'Logo & Banner',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Langkah 2 dari 2',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '"${widget.communityName}" berhasil dibuat. Tambahkan logo dan banner supaya lebih menarik (opsional, bisa dilewati).',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),

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
              child: _bannerUploadContent(),
            ),
          ),
          const SizedBox(height: 24),

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
              width: 100,
              height: 100,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _logoUploadContent(),
            ),
          ),

          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Selesai',
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _finish,
              child: Text(
                'Lewati untuk sekarang',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerUploadContent() {
    if (_isUploadingBanner) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_bannerUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(_bannerUrl!, fit: BoxFit.cover),
          Positioned(right: 8, bottom: 8, child: _editBadge()),
        ],
      );
    }
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
            'Ketuk untuk unggah banner',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _logoUploadContent() {
    if (_isUploadingLogo) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_logoUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(_logoUrl!, fit: BoxFit.cover),
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
}
