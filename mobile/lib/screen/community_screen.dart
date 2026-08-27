import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/communities_service.dart';
import 'community/community_detail_screen.dart';
import 'community/create_community_screen.dart';
import '../widgets/swipe_join_button.dart';

/// Halaman daftar komunitas: cari, scroll (infinite load), gabung/keluar.
/// Status "sudah gabung atau belum" per komunitas diambil dari field
/// `is_member` yang dikirim backend (lihat communities.controller.js),
/// bukan diingat sendiri di HP — jadi tetap benar walau di-refresh atau
/// dibuka lagi di sesi lain.
///
/// CATATAN: layar ini mengambil token lewat `context.read<AuthProvider>().getToken()`.
/// AuthProvider kamu tidak mengekspos token sebagai getter (disimpan lewat
/// SecureStorageService), jadi perlu tambahan method kecil di AuthProvider:
///
///   Future<String?> getToken() => _storage.readToken();
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final CommunitiesService _service = CommunitiesService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _communities = [];
  final Set<int> _pendingActionIds = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCommunities(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || _isLoading) return;
    if (_page >= _totalPages) return;

    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      _loadCommunities();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value;
      _loadCommunities(reset: true);
    });
  }

  Future<void> _loadCommunities({bool reset = false}) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getToken();

    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Sesi tidak ditemukan, silakan login ulang';
      });
      return;
    }

    setState(() {
      if (reset) {
        _isLoading = true;
        _error = null;
      } else {
        _isLoadingMore = true;
      }
    });

    final nextPage = reset ? 1 : _page + 1;

    try {
      final result = await _service.fetchCommunities(
        token: token,
        page: nextPage,
        search: _query,
      );

      if (!mounted) return;
      setState(() {
        if (reset) _communities.clear();
        _communities.addAll(result.communities);
        _page = result.page;
        _totalPages = result.totalPages;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (reset) _error = e.toString().replaceFirst('Exception: ', '');
      });
      if (!reset) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat lebih banyak: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _handleJoin(int communityId) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getToken();
    if (token == null) return;

    setState(() => _pendingActionIds.add(communityId));
    try {
      await _service.joinCommunity(token, communityId);
      if (!mounted) return;
      setState(() {
        _setMembership(communityId, true);
        _bumpMemberCount(communityId, 1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil bergabung dengan komunitas')),
      );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      // Backend juga balas error kalau ternyata user sudah jadi anggota;
      // di kasus ini cukup sinkronkan status lokal tanpa nampilkan error.
      if (message.contains('sudah menjadi anggota')) {
        if (!mounted) return;
        setState(() => _setMembership(communityId, true));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingActionIds.remove(communityId));
    }
  }

  Future<void> _handleLeave(int communityId) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getToken();
    if (token == null) return;

    setState(() => _pendingActionIds.add(communityId));
    try {
      await _service.leaveCommunity(token, communityId);
      if (!mounted) return;
      setState(() {
        _setMembership(communityId, false);
        _bumpMemberCount(communityId, -1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil keluar dari komunitas')),
      );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingActionIds.remove(communityId));
    }
  }

  // Set status "is_member" pada data komunitas di list lokal setelah
  // join/leave sukses, supaya kartu langsung berubah tanpa perlu reload,
  // dan status ini ikut benar kalau nanti list di-refresh dari server
  // (server sekarang mengirim "is_member" apa adanya).
  void _setMembership(int communityId, bool isMember) {
    final idx = _communities.indexWhere(
      (c) => c['community_id'] == communityId,
    );
    if (idx == -1) return;
    _communities[idx] = {..._communities[idx], 'is_member': isMember};
  }

  // Update angka anggota di kartu secara optimis, biar tidak perlu
  // fetch ulang seluruh daftar cuma buat 1 angka.
  void _bumpMemberCount(int communityId, int delta) {
    final idx = _communities.indexWhere(
      (c) => c['community_id'] == communityId,
    );
    if (idx == -1) return;
    final current = _communities[idx]['member_count'] ?? 0;
    _communities[idx] = {
      ..._communities[idx],
      'member_count': (current as num).toInt() + delta,
    };
  }

  void _openCommunityDetail(Map<String, dynamic> community) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(
          communityId: community['community_id'] as int,
          communityName: community['community_name'] as String?,
        ),
      ),
    );
  }

  Future<void> _openCreateCommunity() async {
    final result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CreateCommunityScreen()));
    if (result == true) {
      _loadCommunities(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Komunitas',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: _openCreateCommunity,
                icon: const Icon(Icons.add, size: 18, color: Colors.white),
                label: Text(
                  'Buat',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _loadCommunities(reset: true),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + kToolbarHeight + 4, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temukan komunitas di sekitarmu',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: GoogleFonts.poppins(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Cari nama atau deskripsi komunitas...',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.primary,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey.shade500,
                        onPressed: () {
                          _searchController.clear();
                          _query = '';
                          _loadCommunities(reset: true);
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // 🔥 TIPU USER: Tampilkan shimmer kalo lagi loading
    if (_isLoading) {
      return _buildShimmerLoading();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_communities.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: _communities.length + (_page < _totalPages ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index >= _communities.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        return _CommunityCard(
          community: _communities[index],
          isJoined: _communities[index]['is_member'] == true,
          isPending: _pendingActionIds.contains(
            _communities[index]['community_id'],
          ),
          onJoin: () => _handleJoin(_communities[index]['community_id'] as int),
          onLeave: () =>
              _handleLeave(_communities[index]['community_id'] as int),
          onTap: () => _openCommunityDetail(_communities[index]),
        );
      },
    );
  }

  Widget _buildShimmerLoading() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // Kartu 1: full
        _buildShimmerCard(),
        const SizedBox(height: 14),
        // Kartu 2: dengan deskripsi panjang
        _buildShimmerCard(longDescription: true),
        const SizedBox(height: 14),
        // Kartu 3: tanpa deskripsi
        _buildShimmerCard(noDescription: true),
      ],
    );
  }

  Widget _buildShimmerCard(
      {bool longDescription = false, bool noDescription = false}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      enabled: true,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 96,
              width: double.infinity,
              color: Colors.grey.shade300,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nama + verified badge
                  Row(
                    children: [
                      Container(
                        height: 18,
                        width: 120 + (longDescription ? 30 : 0),
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(width: 4),
                      Container(
                        height: 15,
                        width: 15,
                        decoration: const BoxDecoration(
                          color: Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Tags
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildShimmerTag(width: 80),
                      _buildShimmerTag(width: 90),
                      _buildShimmerTag(width: 70),
                    ],
                  ),
                  if (!noDescription) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12,
                      width: longDescription ? 250 : 150,
                      color: Colors.grey.shade300,
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Tombol swipe
                  Container(
                    height: 44,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTag({required double width}) {
    return Container(
      height: 20,
      width: width,
      color: Colors.grey.shade300,
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
            _error ?? 'Terjadi kesalahan',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: () => _loadCommunities(reset: true),
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

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _query.isEmpty
                ? 'Belum ada komunitas tersedia'
                : 'Tidak ada komunitas untuk "$_query"',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final Map<String, dynamic> community;
  final bool isJoined;
  final bool isPending;
  final VoidCallback onJoin;
  final VoidCallback
      onLeave; // Tetap ada untuk keperluan internal tapi tidak ditampilkan
  final VoidCallback onTap;

  const _CommunityCard({
    required this.community,
    required this.isJoined,
    required this.isPending,
    required this.onJoin,
    required this.onLeave,
    required this.onTap,
  });

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
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
    final name =
        (community['community_name'] as String?)?.trim() ?? 'Tanpa Nama';
    final description = (community['description'] as String?)?.trim();
    final kecamatan = (community['kecamatan'] as String?)?.trim();
    final isVerified = community['is_verified'] == true;
    final memberCount = community['member_count'] ?? community['total_members'];
    final logoUrl = _resolveUrl(community['logo'] as String?);
    final bannerUrl = _resolveUrl(community['banner'] as String?);
    final category = community['categories'] as Map<String, dynamic>?;
    final categoryName = (category?['category_name'] as String?)?.trim();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    height: 96,
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
                    left: 16,
                    bottom: -24,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 27,
                        backgroundColor: Colors.white.withOpacity(0.9),
                        backgroundImage:
                            logoUrl != null ? NetworkImage(logoUrl) : null,
                        child: logoUrl == null
                            ? Text(
                                _initials(name),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
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
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  size: 15,
                                  color: AppColors.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isJoined) _JoinedLabel(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (categoryName != null && categoryName.isNotEmpty)
                          _Tag(
                            icon: Icons.category_outlined,
                            label: categoryName,
                          ),
                        if (kecamatan != null && kecamatan.isNotEmpty)
                          _Tag(
                            icon: Icons.location_on_outlined,
                            label: kecamatan,
                          ),
                        _Tag(
                          icon: Icons.people_outline,
                          label: '${memberCount ?? 0} anggota',
                        ),
                      ],
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                    // Tombol Gabung hanya muncul kalau belum bergabung
                    if (!isJoined) ...[
                      const SizedBox(height: 14),
                      SwipeJoinButton(
                        isPending: isPending,
                        onSwipeComplete: onJoin,
                      )
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

class _JoinedLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 11, color: AppColors.secondary),
          const SizedBox(width: 3),
          Text(
            'Sudah bergabung',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.grey.shade500),
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
