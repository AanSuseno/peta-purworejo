import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../provider/auth_provider.dart';
import '../services/posts_service.dart';
import '../widgets/post_card_widget.dart';
import 'post_detail_screen.dart';

/// Halaman daftar postingan publik: cari, scroll (infinite load),
/// like, dan buka detail postingan.
class PostScreen extends StatefulWidget {
  final int? initialCategoryId; // 🔥 baru
  final String? initialCategoryName; // 🔥 baru, buat label chip filter

  const PostScreen({
    super.key,
    this.initialCategoryId,
    this.initialCategoryName,
  });

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final PostsService _service = PostsService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _posts = [];
  final Set<int> _likingPostIds = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  String _query = '';
  int? _userId;

  int? _categoryId; // 🔥 baru
  String? _categoryName;

  @override
  void initState() {
    super.initState();
    _userId = context.read<AuthProvider>().userData?['user_id'] as int?;
    _categoryId = widget.initialCategoryId; // 🔥 baru
    _categoryName = widget.initialCategoryName;
    _loadPosts(reset: true);
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
      _loadPosts();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value;
      _loadPosts(reset: true);
    });
  }

  void _clearCategoryFilter() {
    setState(() {
      _categoryId = null;
      _categoryName = null;
    });
    _loadPosts(reset: true);
  }

  Future<void> _loadPosts({bool reset = false}) async {
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
      final result = await _service.fetchFeedPosts(
        token: token,
        limit: 10,
        page: nextPage,
        postType: 'regular',
        search: _query.isNotEmpty ? _query : null,
        categoryId: _categoryId, // 🔥 baru
      );

      if (!mounted) return;

      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(result.posts);
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

  Future<void> _handleLike(Map<String, dynamic> post) async {
    final postId = post['post_id'] as int?;
    if (postId == null) return;
    if (_likingPostIds.contains(postId)) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    setState(() => _likingPostIds.add(postId));

    try {
      final result = await _service.toggleLike(token: token, postId: postId);
      if (!mounted) return;
      setState(() {
        final idx = _posts.indexWhere((p) => p['post_id'] == postId);
        if (idx != -1) {
          _posts[idx] = {
            ..._posts[idx],
            'is_liked': result['is_liked'] ?? false,
            'likes_count': result['total_likes'] ?? 0,
          };
        }
        _likingPostIds.remove(postId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _likingPostIds.remove(postId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Gagal menyukai: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  void _openPostDetail(Map<String, dynamic> post) {
    final postId = post['post_id'] as int?;
    final communityId = post['community_id'] as int?;
    if (postId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          postId: postId,
          communityId: communityId ?? 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Postingan',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _loadPosts(reset: true),
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
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lihat semua cerita dari komunitas',
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
                hintText: 'Cari postingan...',
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
                          _loadPosts(reset: true);
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
          // 🔥 Chip filter kategori aktif, cuma muncul kalau ada filter
          if (_categoryId != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_rounded,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _categoryName ?? 'Kategori terpilih',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _clearCategoryFilter,
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildShimmerLoading();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_posts.isEmpty) {
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
      itemCount: _posts.length + (_page < _totalPages ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index >= _posts.length) {
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

        final post = _posts[index];
        final postId = post['post_id'] as int?;
        final isLiking = postId != null && _likingPostIds.contains(postId);

        return PostCardWidget(
          post: post,
          showCommunityInfo: true,
          isLiked: post['is_liked'] ?? false,
          isLiking: isLiking,
          isAuthor: post['author_id'] == _userId,
          isAdmin: false,
          onTap: () => _openPostDetail(post),
          onLike: () => _handleLike(post),
          onComment: () => _openPostDetail(post),
          onEdit: null,
          onDelete: null,
          onRegisterEvent: null,
          onCancelEvent: null,
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
        _buildShimmerCard(),
        const SizedBox(height: 14),
        _buildShimmerCard(longDescription: true),
        const SizedBox(height: 14),
        _buildShimmerCard(noDescription: true),
      ],
    );
  }

  Widget _buildShimmerCard({
    bool longDescription = false,
    bool noDescription = false,
  }) {
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 12,
                            width: 120,
                            color: Colors.grey.shade300),
                        const SizedBox(height: 6),
                        Container(
                            height: 10, width: 80, color: Colors.grey.shade300),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 14,
                width: 180 + (longDescription ? 40 : 0),
                color: Colors.grey.shade300,
              ),
              if (!noDescription) ...[
                const SizedBox(height: 10),
                Container(
                    height: 12,
                    width: double.infinity,
                    color: Colors.grey.shade300),
                const SizedBox(height: 4),
                Container(
                  height: 12,
                  width: longDescription ? 260 : 150,
                  color: Colors.grey.shade300,
                ),
              ],
            ],
          ),
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
            _error ?? 'Terjadi kesalahan',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: () => _loadPosts(reset: true),
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
    final hasCategoryFilter = _categoryId != null;
    final hasSearchQuery = _query.isNotEmpty;

    String message;
    if (hasSearchQuery) {
      message = 'Tidak ada postingan untuk "$_query"';
    } else if (hasCategoryFilter) {
      message = 'Belum ada postingan di kategori ${_categoryName ?? 'ini'}';
    } else {
      message = 'Belum ada postingan tersedia';
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.article_outlined,
          size: 48,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
