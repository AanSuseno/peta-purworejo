import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // profile_picture dari backend berupa path relatif (mis. "/uploads/xxx.jpg"),
  // jadi perlu digabung dengan base URL server untuk jadi URL gambar yang valid.
  String? _resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${AuthService.baseUrl}$path';
  }

  // interests dari backend bisa berupa List atau String tergantung data,
  // jadi ditangani dua-duanya biar tidak crash.
  List<String> _formatInterests(dynamic interests) {
    if (interests == null) return [];
    if (interests is List) {
      return interests
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final text = interests.toString().trim();
    if (text.isEmpty) return [];
    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // Ubah ISO date string dari backend (mis. "2026-08-21T12:13:59.312Z")
  // jadi format tanggal yang enak dibaca. withTime=true buat nampilin jam
  // juga (dipakai di "Login Terakhir").
  String? _formatDate(String? iso, {bool withTime = false}) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final date = DateTime.parse(iso).toLocal();
      const months = [
        '',
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember',
      ];
      final base = '${date.day} ${months[date.month]} ${date.year}';
      if (!withTime) return base;
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      return '$base, $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  // Daftar komunitas user dari field "communities" pada response profil.
  List<Map<String, dynamic>> _formatCommunities(dynamic communities) {
    if (communities is! List) return [];
    return communities
        .whereType<Map>()
        .map((e) => e.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Profil',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, auth, child) {
          final user = auth.userData;

          // Belum ada data sama sekali (baru login / belum sempat di-fetch)
          if (user == null) {
            if (auth.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildEmptyState(context, auth);
          }

          final fullName = (user['full_name'] as String?)?.trim();
          final emailText = (user['email'] as String?)?.trim();
          final phone = (user['phone_number'] as String?)?.trim();
          final bio = (user['bio'] as String?)?.trim();
          final kecamatan = (user['kecamatan'] as String?)?.trim();
          final interests = _formatInterests(user['interests']);
          final imageUrl = _resolveImageUrl(user['profile_picture'] as String?);
          final joinedAt = _formatDate(user['created_at'] as String?);
          final communities = _formatCommunities(user['communities']);

          final topInset = MediaQuery.of(context).padding.top;

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              try {
                await auth.refreshProfile();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal memuat ulang profil: $e')),
                  );
                }
              }
            },
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Header gradient yang "naik" sampai ke belakang status bar,
                // karena AppBar-nya transparan (extendBodyBehindAppBar: true).
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    topInset + kToolbarHeight + 4,
                    20,
                    44,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                  ),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 44,
                              backgroundColor: Colors.white,
                              backgroundImage: imageUrl != null
                                  ? NetworkImage(imageUrl)
                                  : null,
                              child: imageUrl == null
                                  ? Icon(
                                      Icons.person,
                                      size: 44,
                                      color: AppColors.primary,
                                    )
                                  : null,
                            ),
                          ),
                          // Overlay loading pas lagi upload foto baru
                          if (auth.isUploadingPhoto)
                            Positioned.fill(
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black45,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Ikon pensil buat ganti foto profil
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: GestureDetector(
                              onTap: auth.isUploadingPhoto
                                  ? null
                                  : () => _handleChangePhoto(context),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        (fullName == null || fullName.isEmpty)
                            ? 'Tanpa Nama'
                            : fullName,
                        style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (emailText != null && emailText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            emailText,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.primary.withOpacity(0.15),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Transform.translate(
                  // Card ditarik naik supaya "menimpa" bagian bawah header
                  // gradient, kesannya lebih menyatu (floating card style).
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _InfoTile(
                                icon: Icons.phone_outlined,
                                label: 'No. Telepon',
                                value: phone,
                              ),
                              _divider(),
                              _InfoTile(
                                icon: Icons.location_on_outlined,
                                label: 'Kecamatan',
                                value: kecamatan,
                              ),
                              _divider(),
                              _InfoTile(
                                icon: Icons.info_outline,
                                label: 'Bio',
                                value: bio,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.interests_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Minat',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              interests.isEmpty
                                  ? Text(
                                      'Belum diisi',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey.shade400,
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: interests
                                          .map(
                                            (tag) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                tag,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 12.5,
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _InfoTile(
                                icon: Icons.calendar_today_outlined,
                                label: 'Bergabung Sejak',
                                value: joinedAt,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.groups_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Komunitas',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              communities.isEmpty
                                  ? Text(
                                      'Belum bergabung dengan komunitas',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey.shade400,
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < communities.length;
                                          i++
                                        ) ...[
                                          if (i > 0) const SizedBox(height: 10),
                                          _CommunityTile(
                                            community: communities[i],
                                          ),
                                        ],
                                      ],
                                    ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const EditProfileScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit_outlined, size: 19),
                            label: Text(
                              'Edit Profil',
                              style: GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await auth.logout();
                            },
                            icon: const Icon(Icons.logout, color: Colors.red),
                            label: Text(
                              'Keluar',
                              style: GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 90 + MediaQuery.of(context).padding.bottom,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, indent: 56, color: Colors.grey.shade100);

  // Bottom sheet pilih sumber foto (kamera / galeri), lalu crop bulat,
  // baru upload ke server. Loading state-nya ambil dari
  // AuthProvider.isUploadingPhoto (bukan setState lokal) supaya UI avatar
  // otomatis update lewat Consumer di atas.
  Future<void> _handleChangePhoto(BuildContext context) async {
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
                'Ganti Foto Profil',
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

    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return; // user batal

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Sesuaikan Foto',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Sesuaikan Foto',
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      if (cropped == null) return; // user batal di layar crop

      if (!context.mounted) return;
      await context.read<AuthProvider>().uploadProfilePicture(
        File(cropped.path),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto profil berhasil diperbarui')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengganti foto: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context, AuthProvider auth) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text('Data profil belum tersedia', style: GoogleFonts.poppins()),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                try {
                  await auth.refreshProfile();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal memuat profil: $e')),
                    );
                  }
                }
              },
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityTile extends StatelessWidget {
  final Map<String, dynamic> community;

  const _CommunityTile({required this.community});

  String? _resolveLogoUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${AuthService.baseUrl}$path';
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (community['community_name'] as String?)?.trim() ?? 'Tanpa Nama';
    final totalMembers = community['total_members'];
    final isVerified = community['is_verified'] == true;
    final logoUrl = _resolveLogoUrl(community['logo'] as String?);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
            child: logoUrl == null
                ? Icon(Icons.groups, size: 18, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  totalMembers != null
                      ? '$totalMembers anggota'
                      : 'Jumlah anggota tidak diketahui',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasValue ? value! : 'Belum diisi',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: hasValue ? Colors.black87 : Colors.grey.shade400,
                    fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
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
