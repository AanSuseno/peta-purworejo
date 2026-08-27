// screens/community_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../../provider/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/communities_service.dart';
import '../../services/posts_service.dart';
import '../../widgets/post_card_widget.dart';
import '../../widgets/community_detail/community_header_widget.dart';
import '../../widgets/community_detail/community_stats_widget.dart';
import '../../widgets/community_detail/community_tags_widget.dart';
import '../../widgets/community_detail/community_contact_widget.dart';
import '../../widgets/community_detail/community_action_buttons_widget.dart';
import '../../widgets/community_detail/community_shimmer_widget.dart';
import 'edit_community_screen.dart';
import '../create_post_screen.dart';
import '../post_detail_screen.dart';
import '../edit_post_screen.dart';
import 'community_members_screen.dart';
import 'community_manage_admins_screen.dart';

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

  final Set<int> _likedPostIds = {};

  // ============ GETTERS ============
  Map<String, dynamic> get _userAccess =>
      (_community?['user_access'] as Map<String, dynamic>?) ?? {};

  bool get _isMember => _userAccess['is_member'] == true;
  bool get _isAdmin => _userAccess['is_admin'] == true;
  bool get _isFounder => _userAccess['is_founder'] == true;
  bool get _canManage => _isAdmin || _isFounder;
  bool get _canPost => _isMember || _canManage;

  String get _communityName =>
      (_community?['community_name'] as String?)?.trim() ??
          widget.communityName ??
          'Detail Komunitas';

  // ============ LIFECYCLE ============
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

  // ============ NAVIGATION ============
  void _openMembersList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityMembersScreen(
          communityId: widget.communityId,
          communityName: _communityName,
        ),
      ),
    );
  }

  void _openManageAdmins() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityManageAdminsScreen(
          communityId: widget.communityId,
          communityName: _communityName,
        ),
      ),
    );
  }

  void _openCreatePost() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          communityId: widget.communityId,
          communityName: _communityName,
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

  Future<void> _handleEditPost(Map<String, dynamic> post) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditPostScreen(
          post: post,
          communityId: widget.communityId,
          communityName: _communityName,
        ),
      ),
    );
    if (result != null) {
      await _loadPosts(reset: true);
    }
  }

  // ============ DATA LOADING ============
  Future<void> _loadDetail() async {
    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getToken();
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
        final filteredPosts = _isMember
            ? result.posts
            : result.posts.where((p) => p['visibility'] == 'public' || p['visibility'] == null).toList();
        _posts.addAll(filteredPosts);
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

  // ============ ACTIONS ============
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

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AuthService.baseUrl}$path';
  }

  // ============ BUILD ============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          _communityName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isFounder)
            IconButton(
              tooltip: 'Kelola Admin',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: _openManageAdmins,
            ),
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
        child: _isLoading ? const CommunityShimmerWidget() : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _buildErrorState();
    }

    final community = _community!;
    final name = (community['community_name'] as String?)?.trim() ?? 'Tanpa Nama';
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
              // HEADER
              CommunityHeaderWidget(
                name: name,
                logoUrl: logoUrl,
                bannerUrl: bannerUrl,
                isVerified: isVerified,
                founderName: founderName,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Verified
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

                    // TAGS
                    CommunityTagsWidget(
                      categoryName: categoryName,
                      kecamatan: kecamatan,
                      isFounder: _isFounder,
                      isAdmin: _isAdmin,
                    ),
                    const SizedBox(height: 18),

                    // STATS
                    CommunityStatsWidget(
                      memberCount: memberCount,
                      postCount: postCount,
                      eventCount: eventCount,
                      onMembersTap: _isMember ? _openMembersList : null,
                    ),
                    const SizedBox(height: 20),

                    // DESCRIPTION
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

                    // CONTACT
                    CommunityContactWidget(
                      address: address,
                      contactEmail: contactEmail,
                      contactPhone: contactPhone,
                    ),

                    // ACTION BUTTONS
                    CommunityActionButtonsWidget(
                      isMember: _isMember,
                      isFounder: _isFounder,
                      isJoinLeavePending: _isJoinLeavePending,
                      onJoin: _handleJoin,
                      onLeave: _handleLeave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // POSTS SECTION
        _buildPostsSection(),
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  Widget _buildPostsSection() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
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
                if (_canPost)
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
                if (!_isMember)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Menampilkan postingan publik',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 8, thickness: 1),

            // Posts List
            if (_isLoadingPosts && _posts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_posts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _isMember
                        ? 'Belum ada postingan di komunitas ini'
                        : 'Belum ada postingan publik. Bergabunglah untuk melihat semua postingan!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ..._posts.asMap().entries.map((entry) {
                final index = entry.key;
                final post = entry.value;
                final postId = post['post_id'] as int;
                final isPublic = post['visibility'] == 'public' || post['visibility'] == null;
                final bool canInteract = _isMember && isPublic;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: PostCardWidget(
                    post: post,
                    showCommunityInfo: false,
                    isLiked: _likedPostIds.contains(postId),
                    isAuthor: post['author_id'] == _userId,
                    isAdmin: _canManage,
                    onTap: () => _openPostDetail(post),
                    onLike: canInteract ? () => _handleLike(postId) : () {},
                    onComment: canInteract ? () => _openPostDetail(post) : () {},
                    onEdit: canInteract ? () => _handleEditPost(post) : null,
                    onDelete: canInteract ? () => _handleDeletePost(postId) : null,
                    onRegisterEvent: null,
                    onCancelEvent: null,
                  ),
                );
              }),

            // Loading more indicator
            if (_hasMorePosts && _posts.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
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
}

// Helper Widget
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