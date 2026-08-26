// lib/screens/community_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/communities_service.dart';
import '../services/posts_service.dart';
import '../widgets/post_card_widget.dart';
import 'edit_community_screen.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'edit_post_screen.dart';
import '../widgets/community_donation_widget.dart';
import '../widgets/swipe_join_button.dart';

class CommunityDetailScreen extends StatefulWidget {
  final int communityId;
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
  final CommunitiesService _service = CommunitiesService();
  final PostsService _postsService = PostsService();

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isLoadingPosts = false;
  bool _isJoinLeavePending = false;
  String? _error;
  int? _userId;

  int _postPage = 1;
  int _postTotalPages = 1;
  bool _hasMorePosts = true;
  final ScrollController _scrollController = ScrollController();

  // Track liked posts
  final Set<int> _likedPostIds = {};

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingPosts || !_hasMorePosts) return;
    final threshold = _scrollController.position.maxScrollExtent - 300;
    if (_scrollController.position.pixels >= threshold) {
      _loadPosts();
    }
  }

  Future<void> _loadDetail() async {
    final authProvider = context.read<AuthProvider>();
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
      final userData = authProvider.userData;
      print('🔍 Current user ID: ${userData?['user_id']}'); // Debug

      setState(() {
        _userId = userData?['user_id'] as int?;
      });

      final community = await _service.fetchCommunityById(
        token,
        widget.communityId,
      );
      if (!mounted) return;
      setState(() {
        _community = community;
        _isLoading = false;
      });
      await _loadPosts(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadPosts({bool reset = false}) async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null || _community == null) return;

    setState(() {
      if (reset) {
        _isLoadingPosts = true;
        _posts.clear();
        _postPage = 1;
        _hasMorePosts = true;
      } else {
        _isLoadingPosts = true;
      }
    });

    final nextPage = reset ? 1 : _postPage + 1;

    try {
      final result = await _postsService.fetchCommunityPosts(
        token: token,
        communityId: widget.communityId,
        page: nextPage,
        limit: 10,
        sortBy: 'created_at',
        sortOrder: 'desc',
      );

      if (!mounted) return;

      for (final post in result.posts) {
        final postId = post['post_id'] as int?;
        if (postId != null && post['is_liked'] == true) {
          _likedPostIds.add(postId);
        }
      }

      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(result.posts);
        _postPage = result.page;
        _postTotalPages = result.totalPages;
        _hasMorePosts = result.page < result.totalPages;
        _isLoadingPosts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPosts = false;
      });
      debugPrint('Error loading posts: $e');
    }
  }

  Map<String, dynamic> get _userAccess =>
      (_community?['user_access'] as Map<String, dynamic>?) ?? {};

  bool get _isMember => _userAccess['is_member'] == true;
  bool get _isAdmin => _userAccess['is_admin'] == true;
  bool get _isFounder => _userAccess['is_founder'] == true;
  bool get _canManage => _isAdmin || _isFounder;
  bool get _canPost => _isMember || _canManage;

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

  Future<void> _handleLike(int postId) async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    final isCurrentlyLiked = _likedPostIds.contains(postId);
    setState(() {
      if (isCurrentlyLiked) {
        _likedPostIds.remove(postId);
      } else {
        _likedPostIds.add(postId);
      }
      final idx = _posts.indexWhere((p) => p['post_id'] == postId);
      if (idx != -1) {
        final current = _posts[idx]['likes_count'] ?? 0;
        _posts[idx] = {
          ..._posts[idx],
          'likes_count': current + (isCurrentlyLiked ? -1 : 1),
          'is_liked': !isCurrentlyLiked,
        };
      }
    });

    try {
      await _postsService.toggleLike(token: token, postId: postId);
    } catch (e) {
      setState(() {
        if (isCurrentlyLiked) {
          _likedPostIds.add(postId);
        } else {
          _likedPostIds.remove(postId);
        }
        final idx = _posts.indexWhere((p) => p['post_id'] == postId);
        if (idx != -1) {
          final current = _posts[idx]['likes_count'] ?? 0;
          _posts[idx] = {
            ..._posts[idx],
            'likes_count': current + (isCurrentlyLiked ? 1 : -1),
            'is_liked': isCurrentlyLiked,
          };
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _openCreatePost() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          communityId: widget.communityId,
          communityName: _community?['community_name'] ??
              widget.communityName ??
              'Komunitas',
        ),
      ),
    )
        .then((result) {
      if (result == true) {
        _loadPosts(reset: true);
      }
    });
  }

  void _openPostDetail(Map<String, dynamic> post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          postId: post['post_id'] as int,
          communityId: widget.communityId,
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

  Future<void> _handleEditPost(Map<String, dynamic> post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditPostScreen(
          post: post,
          communityId: widget.communityId,
          communityName: _community?['community_name'] ?? 'Komunitas',
        ),
      ),
    );
    if (result != null) {
      // Refresh posts setelah edit
      await _loadPosts(reset: true);
    }
  }

  Future<void> _handleDeletePost(int postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Hapus Postingan',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus postingan ini?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Hapus', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesi tidak ditemukan')));
      return;
    }

    try {
      await _postsService.deletePost(token: token, postId: postId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Postingan berhasil dihapus'),
          backgroundColor: Colors.orange,
        ),
      );
      // Refresh posts
      await _loadPosts(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
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
      floatingActionButton: _canPost
          ? FloatingActionButton(
              onPressed: _openCreatePost,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadDetail,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
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

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
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
                        backgroundImage:
                            logoUrl != null ? NetworkImage(logoUrl) : null,
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
                          _Tag(
                            icon: Icons.category_outlined,
                            label: categoryName,
                          ),
                        if (kecamatan != null && kecamatan.isNotEmpty)
                          _Tag(
                            icon: Icons.location_on_outlined,
                            label: kecamatan,
                          ),
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
                            child: _StatItem(
                              label: 'Anggota',
                              value: '$memberCount',
                            ),
                          ),
                          _statDivider(),
                          Expanded(
                            child: _StatItem(
                              label: 'Post',
                              value: '$postCount',
                            ),
                          ),
                          _statDivider(),
                          Expanded(
                            child: _StatItem(
                              label: 'Event',
                              value: '$eventCount',
                            ),
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
                      SwipeJoinButton(
                        isPending: _isJoinLeavePending,
                        onSwipeComplete: () => _handleJoin(),
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
                  ],
                ),
              ),
            ],
          ),
        ),
        // Donasi & Campaign — ditampilkan sebagai banner ringkas di atas
        // postingan, bukan daftar campaign penuh, supaya postingan tetap
        // jadi konten utama yang langsung terlihat.
        if (_isMember) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            sliver: SliverToBoxAdapter(
              child: CommunityDonationWidget(
                communityId: widget.communityId,
                communityName: _community?['community_name'] as String? ??
                    widget.communityName,
                isMember: _isMember,
                canManage: _canManage,
              ),
            ),
          ),

          // Posts section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Postingan Terbaru',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openCreatePost,
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Buat Post',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: Divider(height: 8, thickness: 1)),
          ),
          if (_isLoadingPosts && _posts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_posts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('Belum ada postingan')),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index >= _posts.length) {
                    if (_hasMorePosts) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  final post = _posts[index];
                  final postId = post['post_id'] as int;

                  return PostCardWidget(
                    post: post,
                    showCommunityInfo: false,
                    isLiked: _likedPostIds.contains(postId),
                    isAuthor: post['author_id'] ==
                        _userId, // Anda perlu mendapatkan userId dari AuthProvider
                    isAdmin: _canManage, // _isAdmin || _isFounder
                    onTap: () => _openPostDetail(post),
                    onLike: () => _handleLike(postId),
                    onComment: () => _openPostDetail(post),
                    onEdit: () => _handleEditPost(post),
                    onDelete: () => _handleDeletePost(postId),
                    onRegisterEvent: null,
                    onCancelEvent: null,
                  );
                }, childCount: _posts.length + (_hasMorePosts ? 1 : 0)),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ],
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
