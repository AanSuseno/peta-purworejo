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
import 'community_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh profil begitu layar ini dibuka, jangan andalkan cache lama
    // atau nunggu user pull-to-refresh manual. Pakai addPostFrameCallback
    // supaya tidak trigger notifyListeners() di tengah proses build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().refreshProfile().catchError((e) {
        debugPrint('Gagal refresh profil saat buka layar: $e');
      });
    });
  }

  // profile_picture dari backend bisa berupa path relatif (mis.
  // "/uploads/profiles/xxx.jpg") atau URL lengkap. Kalau relatif,
  // gabungkan dengan baseUrl supaya NetworkImage bisa memuatnya.
  String? _resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${AuthService.baseUrl}$path';
  }

  // interests dari backend bisa berupa null, String, atau List
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

  // Ubah ISO date string ke format tanggal yang enak dibaca
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

  // Ambil komunitas yang dijoin dari community_members
  List<Map<String, dynamic>> _getJoinedCommunities(Map<String, dynamic> user) {
    final List<Map<String, dynamic>> joinedCommunities = [];

    final members = user['community_members'] as List? ?? [];
    for (var member in members) {
      if (member is Map) {
        final communityData = member['communities'] as Map?;
        if (communityData != null) {
          joinedCommunities.add({
            ...communityData,
            'join_date': member['join_date'],
            'status': member['status'],
          });
        }
      }
    }

    return joinedCommunities;
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

          // Belum ada data sama sekali
          if (user == null) {
            if (auth.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildEmptyState(context, auth);
          }

          final fullName =
              (user['full_name'] as String?)?.trim() ?? 'Tanpa Nama';
          final emailText = (user['email'] as String?)?.trim() ?? '';
          final phone = (user['phone_number'] as String?)?.trim();
          final bio = (user['bio'] as String?)?.trim();
          final kecamatan = (user['kecamatan'] as String?)?.trim();
          final interests = _formatInterests(user['interests']);
          final imageUrl = _resolveImageUrl(user['profile_picture'] as String?);
          final joinedAt = _formatDate(user['created_at'] as String?);
          final lastLogin = _formatDate(
            user['last_login'] as String?,
            withTime: true,
          );
          final isVerified = user['is_verified'] == true;
          final isActive = user['is_active'] == true;
          final roleName =
              (user['user_roles'] as Map?)?.containsKey('role_name') == true
                  ? (user['user_roles'] as Map)['role_name'] as String?
                  : null;

          // Ambil komunitas yang dijoin
          final joinedCommunities = _getJoinedCommunities(user);

          // Statistik dari _count
          final countData = user['_count'] as Map? ?? {};
          final totalCommunities = countData['communities'] ?? 0;
          final totalPosts = countData['posts'] ?? 0;
          final totalEvents = countData['event_participants'] ?? 0;

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
                // Header gradient
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
                              onBackgroundImageError: imageUrl != null
                                  ? (exception, stackTrace) {
                                      debugPrint(
                                        'Gagal load foto profil ($imageUrl): $exception',
                                      );
                                    }
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              fullName,
                              style: GoogleFonts.poppins(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified, size: 18, color: Colors.white),
                          ],
                        ],
                      ),
                      if (roleName != null && roleName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              roleName,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      if (emailText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            emailText,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                        ),
                      if (!isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Akun Tidak Aktif',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // Statistik Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(
                                Icons.groups_outlined,
                                totalCommunities.toString(),
                                'Komunitas',
                              ),
                              _buildStatItem(
                                Icons.article_outlined,
                                totalPosts.toString(),
                                'Postingan',
                              ),
                              _buildStatItem(
                                Icons.event_available_outlined,
                                totalEvents.toString(),
                                'Event',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Info Pribadi
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
                              _divider(),
                              _InfoTile(
                                icon: Icons.calendar_today_outlined,
                                label: 'Bergabung Sejak',
                                value: joinedAt,
                              ),
                              if (lastLogin != null) ...[
                                _divider(),
                                _InfoTile(
                                  icon: Icons.history_outlined,
                                  label: 'Login Terakhir',
                                  value: lastLogin,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Minat
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

                        // Komunitas yang dijoin
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
                                    'Komunitas yang Diikuti',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(
                                        0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      joinedCommunities.length.toString(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              joinedCommunities.isEmpty
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
                                        for (var i = 0;
                                            i < joinedCommunities.length;
                                            i++) ...[
                                          if (i > 0) const SizedBox(height: 10),
                                          _CommunityTile(
                                            community: joinedCommunities[i],
                                            onTap: () {
                                              final communityId =
                                                  joinedCommunities[i]
                                                      ['community_id'] as int?;
                                              final communityName =
                                                  joinedCommunities[i]
                                                          ['community_name']
                                                      as String?;
                                              if (communityId != null) {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        CommunityDetailScreen(
                                                      communityId: communityId,
                                                      communityName:
                                                          communityName,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Tombol Edit Profil
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

                        // Tombol Logout
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

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 24, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _divider() =>
      Divider(height: 1, indent: 56, color: Colors.grey.shade100);

  // Bottom sheet pilih sumber foto
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
      if (picked == null) return;

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
      if (cropped == null) return;

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
  final VoidCallback? onTap; // Tambahkan parameter onTap

  const _CommunityTile({
    required this.community,
    this.onTap,
  });

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

    return InkWell(
      onTap: onTap, // Panggil onTap saat diklik
      child: Container(
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
                        Icon(Icons.verified,
                            size: 14, color: AppColors.primary),
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
            // Tambahkan icon panah untuk indikasi bisa diklik
            Icon(
              Icons.chevron_right,
              size: 20,
              color: Colors.grey.shade400,
            ),
          ],
        ),
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
