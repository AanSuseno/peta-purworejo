import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/communities_service.dart';
import 'edit_community_screen.dart';

/// Layar detail 1 komunitas. Dibuka dari kartu di [CommunityScreen].
///
/// CATATAN: endpoint buat post & buat event di komunitas belum ada di
/// backend, jadi kedua tombol itu untuk sekarang cuma mengarah ke layar
/// placeholder ([_ComingSoonScreen]) supaya UI-nya sudah siap dan tinggal
/// disambungkan begitu endpoint-nya jadi. Tombol "Edit Komunitas" sudah
/// disambungkan ke [EditCommunityScreen] (PUT /communities/:id +
/// upload logo/banner).
class CommunityDetailScreen extends StatefulWidget {
  final int communityId;

  /// Nama komunitas dari list (opsional), dipakai sebagai judul AppBar
  /// sementara sambil data lengkap masih dimuat -- supaya tidak blank.
  final String? communityName;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    this.communityName,
  });

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final _service = CommunitiesService();

  Map<String, dynamic>? _community;
  bool _isLoading = true;
  bool _isJoinLeavePending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
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
      final community = await _service.fetchCommunityById(
        token,
        widget.communityId,
      );
      if (!mounted) return;
      setState(() {
        _community = community;
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

  Map<String, dynamic> get _userAccess =>
      (_community?['user_access'] as Map<String, dynamic>?) ?? {};

  bool get _isMember => _userAccess['is_member'] == true;
  bool get _isAdmin => _userAccess['is_admin'] == true;
  bool get _isFounder => _userAccess['is_founder'] == true;
  bool get _canManage => _isAdmin || _isFounder;

  /// Tombol "Buat Post" & "Buat Event" cuma untuk anggota komunitas
  /// (termasuk admin/founder, yang otomatis anggota juga) -- bukan
  /// pengunjung yang belum gabung.
  bool get _canPostOrEvent => _isMember || _canManage;

  Future<void> _handleJoin() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    setState(() => _isJoinLeavePending = true);
    try {
      await _service.joinCommunity(token, widget.communityId);
      if (!mounted) return;
      setState(() {
        _community = {
          ..._community!,
          'user_access': {..._userAccess, 'is_member': true},
          'member_count': ((_community!['member_count'] ?? 0) as num) + 1,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil bergabung dengan komunitas')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isJoinLeavePending = false);
    }
  }

  Future<void> _handleLeave() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    setState(() => _isJoinLeavePending = true);
    try {
      await _service.leaveCommunity(token, widget.communityId);
      if (!mounted) return;
      setState(() {
        _community = {
          ..._community!,
          'user_access': {..._userAccess, 'is_member': false},
          'member_count': (((_community!['member_count'] ?? 1) as num) - 1)
              .clamp(0, 1 << 30),
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil keluar dari komunitas')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isJoinLeavePending = false);
    }
  }

  void _openCreatePost() {
    final name =
        (_community?['community_name'] as String?) ??
        widget.communityName ??
        'komunitas ini';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ComingSoonScreen(
          title: 'Buat Post',
          icon: Icons.post_add,
          message:
              'Fitur buat post untuk "$name" belum tersedia.\nEndpoint di backend belum ada, jadi tombol ini masih placeholder.',
        ),
      ),
    );
  }

  void _openCreateEvent() {
    final name =
        (_community?['community_name'] as String?) ??
        widget.communityName ??
        'komunitas ini';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ComingSoonScreen(
          title: 'Buat Event',
          icon: Icons.event_available_outlined,
          message:
              'Fitur buat event untuk "$name" belum tersedia.\nEndpoint di backend belum ada, jadi tombol ini masih placeholder.',
        ),
      ),
    );
  }

  Future<void> _openEditCommunity() async {
    if (_community == null) return;

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => EditCommunityScreen(community: _community!),
      ),
    );

    // EditCommunityScreen pop dengan data komunitas terbaru kalau berhasil
    // simpan -- langsung dipakai di sini tanpa perlu fetch ulang. Kalau
    // user cuma ganti logo/banner lalu back tanpa tekan "Simpan", tetap
    // aman: layar ini akan reload karena RefreshIndicator/pop biasa tidak
    // otomatis refresh, jadi panggil _loadDetail supaya logo/banner baru
    // (yang sudah tersimpan di server) ikut termuat.
    if (!mounted) return;
    if (result != null) {
      setState(() => _community = result);
    } else {
      _loadDetail();
    }
  }

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AuthService.baseUrl}$path';
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          (_community?['community_name'] as String?) ??
              widget.communityName ??
              'Detail Komunitas',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'Edit Komunitas',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEditCommunity,
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadDetail,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null) {
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

    final community = _community!;
    final name =
        (community['community_name'] as String?)?.trim() ?? 'Tanpa Nama';
    final description = (community['description'] as String?)?.trim();
    final kecamatan = (community['kecamatan'] as String?)?.trim();
    final address = (community['address'] as String?)?.trim();
    final contactEmail = (community['contact_email'] as String?)?.trim();
    final contactPhone = (community['contact_phone'] as String?)?.trim();
    final isVerified = community['is_verified'] == true;
    final memberCount = community['member_count'] ?? 0;
    final postCount = community['post_count'] ?? 0;
    final eventCount = community['event_count'] ?? 0;
    final logoUrl = _resolveUrl(community['logo'] as String?);
    final bannerUrl = _resolveUrl(community['banner'] as String?);
    final category = community['categories'] as Map<String, dynamic>?;
    final categoryName = (category?['category_name'] as String?)?.trim();
    final founder = community['users'] as Map<String, dynamic>?;
    final founderName = (founder?['full_name'] as String?)?.trim();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Banner + logo
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: bannerUrl != null
                  ? Image.network(
                      bannerUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _bannerFallback(),
                    )
                  : _bannerFallback(),
            ),
            Positioned(
              left: 20,
              bottom: -28,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  backgroundImage: logoUrl != null
                      ? NetworkImage(logoUrl)
                      : null,
                  child: logoUrl == null
                      ? Text(
                          _initials(name),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (founderName != null && founderName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Didirikan oleh $founderName',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (categoryName != null && categoryName.isNotEmpty)
                    _Tag(icon: Icons.category_outlined, label: categoryName),
                  if (kecamatan != null && kecamatan.isNotEmpty)
                    _Tag(icon: Icons.location_on_outlined, label: kecamatan),
                  if (_isFounder)
                    _Tag(icon: Icons.star_outline, label: 'Founder')
                  else if (_isAdmin)
                    _Tag(icon: Icons.shield_outlined, label: 'Admin'),
                ],
              ),
              const SizedBox(height: 18),

              // Statistik
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatItem(label: 'Anggota', value: '$memberCount'),
                    ),
                    _statDivider(),
                    Expanded(
                      child: _StatItem(label: 'Post', value: '$postCount'),
                    ),
                    _statDivider(),
                    Expanded(
                      child: _StatItem(label: 'Event', value: '$eventCount'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (description != null && description.isNotEmpty) ...[
                _SectionTitle('Tentang Komunitas'),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if ((address != null && address.isNotEmpty) ||
                  (contactEmail != null && contactEmail.isNotEmpty) ||
                  (contactPhone != null && contactPhone.isNotEmpty)) ...[
                _SectionTitle('Kontak'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (address != null && address.isNotEmpty)
                        _ContactRow(
                          icon: Icons.location_on_outlined,
                          text: address,
                        ),
                      if (contactEmail != null && contactEmail.isNotEmpty)
                        _ContactRow(
                          icon: Icons.email_outlined,
                          text: contactEmail,
                        ),
                      if (contactPhone != null && contactPhone.isNotEmpty)
                        _ContactRow(
                          icon: Icons.phone_outlined,
                          text: contactPhone,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Tombol gabung / keluar
              if (!_isMember) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isJoinLeavePending ? null : _handleJoin,
                    icon: _isJoinLeavePending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add, size: 16),
                    label: Text(
                      _isJoinLeavePending ? 'Memproses...' : 'Gabung Komunitas',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
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
                const SizedBox(height: 20),
              ] else ...[
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 15,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Kamu sudah bergabung',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                    const Spacer(),
                    if (!_isFounder)
                      GestureDetector(
                        onTap: _isJoinLeavePending ? null : _handleLeave,
                        child: Text(
                          _isJoinLeavePending ? 'Memproses...' : 'Keluar',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.grey.shade400,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // Aksi komunitas: buat post & buat event (masih placeholder,
              // menunggu endpoint backend-nya siap). Hanya ditampilkan
              // untuk anggota komunitas (termasuk admin/founder) -- bukan
              // pengunjung yang belum gabung.
              if (_canPostOrEvent) ...[
                _SectionTitle('Aksi Komunitas'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.post_add,
                        label: 'Buat Post',
                        onTap: _openCreatePost,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.event_available_outlined,
                        label: 'Buat Event',
                        onTap: _openCreateEvent,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: Colors.grey.shade200);

  Widget _bannerFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Tag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade500),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder generik untuk fitur yang tombolnya sudah ada tapi backend
/// / form-nya belum jadi (buat post, buat event, edit komunitas). Ganti
/// isi layar ini kalau endpoint-nya sudah tersedia.
class _ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;

  const _ComingSoonScreen({
    required this.title,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Segera Hadir',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
