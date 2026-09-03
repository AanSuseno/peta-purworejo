// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/communities_service.dart';
import '../services/donation_service.dart' hide AuthException;
import '../services/posts_service.dart';
import '../services/score_service.dart';
import '../services/secure_storage_service.dart';
import '../widgets/post_card_widget.dart';
import './event_screen.dart';
import './post_detail_screen.dart';
import './post_screen.dart';
import './community_screen.dart';
import './community/create_community_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PostsService _postsService = PostsService();
  final DonationService _donationService = DonationService();
  final CommunitiesService _communitiesService = CommunitiesService();
  final ScoreService _scoreService = ScoreService();
  final SecureStorageService _secureStorage = SecureStorageService();

  bool _bootLoading = true;
  String? _bootError;

  _SectionState<List<Map<String, dynamic>>> _posts = _SectionState.loading();
  _SectionState<List<Map<String, dynamic>>> _events = _SectionState.loading();
  _SectionState<List<Map<String, dynamic>>> _campaigns =
      _SectionState.loading();
  _SectionState<List<Map<String, dynamic>>> _categories =
      _SectionState.loading();
  _SectionState<List<Map<String, dynamic>>> _ranking = _SectionState.loading();

  // State untuk like
  Set<int> _likingPostIds = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _bootLoading = true;
      _bootError = null;
    });

    final token = await _secureStorage.readToken();

    if (token == null || token.isEmpty) {
      setState(() {
        _bootLoading = false;
        _bootError = 'Sesi tidak ditemukan. Silakan login ulang.';
      });
      return;
    }

    setState(() => _bootLoading = false);

    await Future.wait([
      _loadPosts(token),
      _loadEvents(token),
      _loadCampaigns(token),
      _loadCategories(token),
      _loadRanking(token),
    ]);
  }

  String? _resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${AuthService.baseUrl}$path';
  }

  // ==================== LOADING METHODS ====================

  Future<void> _loadPosts(String token) async {
    setState(() => _posts = _SectionState.loading());
    try {
      final page = await _postsService.fetchFeedPosts(token: token, limit: 3);
      setState(() => _posts = _SectionState.data(page.posts));
    } on AuthException {
      setState(() =>
          _posts = _SectionState.error('Sesi habis, silakan login ulang'));
    } catch (e) {
      setState(() => _posts = _SectionState.error('Gagal memuat postingan'));
    }
  }

  Future<void> _loadEvents(String token) async {
    setState(() => _events = _SectionState.loading());
    try {
      final page =
          await _postsService.fetchPublicEvents(token: token, limit: 3);
      setState(() => _events = _SectionState.data(page.posts));
    } on AuthException {
      setState(() =>
          _events = _SectionState.error('Sesi habis, silakan login ulang'));
    } catch (e) {
      setState(() => _events = _SectionState.error('Gagal memuat event'));
    }
  }

  Future<void> _loadCampaigns(String token) async {
    setState(() => _campaigns = _SectionState.loading());
    try {
      final page =
          await _donationService.fetchCampaigns(token: token, limit: 5);
      setState(() => _campaigns = _SectionState.data(page.campaigns));
    } catch (e) {
      setState(() => _campaigns = _SectionState.error('Gagal memuat donasi'));
    }
  }

  Future<void> _loadCategories(String token) async {
    setState(() => _categories = _SectionState.loading());
    try {
      final list = await _communitiesService.fetchCategories(token);
      if (list.isNotEmpty) {
        debugPrint('🔍 Contoh data kategori mentah: ${list.first}');
      }
      setState(() => _categories = _SectionState.data(list));
    } catch (e) {
      setState(
          () => _categories = _SectionState.error('Gagal memuat kategori'));
    }
  }

  Future<void> _loadRanking(String token) async {
    setState(() => _ranking = _SectionState.loading());
    try {
      final list = await _scoreService.fetchTopCommunities(token: token);
      setState(() => _ranking = _SectionState.data(list.take(5).toList()));
    } on AuthException {
      setState(() =>
          _ranking = _SectionState.error('Sesi habis, silakan login ulang'));
    } catch (e) {
      setState(() => _ranking = _SectionState.error('Gagal memuat ranking'));
    }
  }

  Future<void> _retrySection(Future<void> Function(String token) loader) async {
    final token = await _secureStorage.readToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _bootError = 'Sesi tidak ditemukan. Silakan login ulang.';
      });
      return;
    }
    await loader(token);
  }

  // ==================== LIKE HANDLER ====================

  Future<void> _handleLikePost(Map<String, dynamic> post) async {
    final postId = post['post_id'] as int?;
    if (postId == null) return;
    if (_likingPostIds.contains(postId)) return;

    final token = await _secureStorage.readToken();
    if (token == null) return;

    setState(() => _likingPostIds.add(postId));

    try {
      final result = await _postsService.toggleLike(
        token: token,
        postId: postId,
      );

      if (!mounted) return;

      // Update state di posts dan events
      setState(() {
        _updatePostLike(
            postId, result['is_liked'] ?? false, result['total_likes'] ?? 0);
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

  void _updatePostLike(int postId, bool isLiked, int likesCount) {
    // Update posts
    if (_posts.data != null) {
      final index = _posts.data!.indexWhere((p) => p['post_id'] == postId);
      if (index != -1) {
        _posts.data![index]['is_liked'] = isLiked;
        _posts.data![index]['likes_count'] = likesCount;
      }
    }
    // Update events
    if (_events.data != null) {
      final index = _events.data!.indexWhere((p) => p['post_id'] == postId);
      if (index != -1) {
        _events.data![index]['is_liked'] = isLiked;
        _events.data![index]['likes_count'] = likesCount;
      }
    }
  }

  // ==================== NAVIGATION ====================

  void _navigateToPostDetail(Map<String, dynamic> post) {
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

  void _navigateToEditPost(Map<String, dynamic> post) {
    // TODO: Implement edit navigation
  }

  Future<void> _handleDeletePost(Map<String, dynamic> post) async {
    // TODO: Implement delete
  }

  bool _isCurrentUserAuthor(Map<String, dynamic> post) {
    // TODO: Implement with actual user ID
    return false;
  }

  bool _isCurrentUserAdmin() {
    // TODO: Implement with actual admin check
    return false;
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    if (_bootLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_bootError != null) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildHeader(auth),

            // Ranking Section - dengan Bar Chart style
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: _buildRankingSection(),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _CreateCommunityBanner(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateCommunityScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Text(
                  'Gabung komunitas berdasarkan minat Anda:',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),

            // Categories
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCategoriesSection(),
              ),
            ),

            // Posts
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                title: 'Postingan Terbaru',
                topPadding: 4,
                onSeeAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PostScreen()),
                  );
                },
              ),
            ),
            _buildPostsSection(),

            // Events
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                title: 'Event Terbaru',
                onSeeAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const EventScreen()),
                  );
                },
              ),
            ),
            _buildEventsSection(),

            // Campaigns
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                title: 'Donasi Terbaru',
              ),
            ),
            SliverToBoxAdapter(child: _buildCampaignsSection()),

            SliverToBoxAdapter(
              child: SizedBox(
                  height: 24 + MediaQuery.of(context).padding.bottom + 70),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ERROR SCREEN ====================

  Widget _buildErrorScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                _bootError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== HEADER ====================

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'Selamat pagi,';
    if (hour < 15) return 'Selamat siang,';
    if (hour < 18) return 'Selamat sore,';
    return 'Selamat malam,';
  }

  Widget _buildHeader(AuthProvider auth) {
    final imageUrl = _resolveImageUrl(auth.photoUrl); // 🔥 resolve dulu

    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: AppColors.primary,
      automaticallyImplyLeading: false,
      expandedHeight: 100,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primary.withOpacity(0.85)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white,
                      backgroundImage:
                          imageUrl != null ? NetworkImage(imageUrl) : null,
                      onBackgroundImageError: imageUrl != null
                          ? (exception, stackTrace) {
                              debugPrint(
                                'Gagal load foto header ($imageUrl): $exception',
                              );
                            }
                          : null,
                      child: imageUrl == null
                          ? Icon(Icons.person, color: AppColors.primary)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ==================== SECTION HEADER ====================

  Widget _buildSectionHeader({
    required String title,
    VoidCallback? onSeeAll,
    double topPadding = 20, // 🔥 baru, default tetap 20 buat section lain
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Lihat Semua'),
            ),
        ],
      ),
    );
  }
  // ==================== RANKING SECTION - BAR CHART STYLE ====================

  Widget _buildRankingSection() {
    if (_ranking.isLoading) {
      return _buildRankingSkeleton();
    }
    if (_ranking.hasError) {
      return _InlineErrorCard(
        message: _ranking.error!,
        onRetry: () => _retrySection(_loadRanking),
      );
    }
    if (_ranking.data!.isEmpty) {
      return const _EmptyHint(text: 'Belum ada data ranking');
    }

    final List<Map<String, dynamic>> rankings = _ranking.data!;
    final maxScore = rankings.fold<num>(0, (max, item) {
      final score = _pickNum(item, ['total_score']);
      return score > max ? score : max;
    }).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Peringkat Komunitas',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...rankings.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final name = _pick(item, ['community_name'], 'Komunitas');
            final score = _pickNum(item, ['total_score']).toDouble();
            final percentage = maxScore > 0 ? (score / maxScore) : 0.0;
            final rank = index + 1;

            return _RankingBarTile(
              rank: rank,
              name: name,
              score: score,
              percentage: percentage,
              isTop: rank <= 3,
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRankingSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SkeletonBox(width: 20, height: 20, radius: 10),
              const SizedBox(width: 8),
              const _SkeletonBox(width: 150, height: 16, radius: 4),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(5, (index) => _RankingBarSkeleton()),
        ],
      ),
    );
  }

  // ==================== CATEGORIES ====================

  Widget _buildCategoriesSection() {
    if (_categories.isLoading) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - (8 * 3)) / 4;
          return Wrap(
            spacing: 8,
            runSpacing: 14,
            children: List.generate(
              8,
              (_) => SizedBox(
                width: itemWidth,
                child: const _CategoryGridSkeleton(),
              ),
            ),
          );
        },
      );
    }
    if (_categories.hasError) {
      return _InlineErrorText(
        message: _categories.error!,
        onRetry: () => _retrySection(_loadCategories),
      );
    }
    if (_categories.data!.isEmpty) {
      return const _EmptyHint(text: 'Belum ada kategori');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - (8 * 3)) / 4; // 🔥 4 per baris

        return Wrap(
          spacing: 8,
          runSpacing: 7, // 🔥 jarak antar baris, sekarang bisa dikontrol pasti
          children: _categories.data!.asMap().entries.map((entry) {
            final index = entry.key;
            final cat = entry.value;
            final name =
                _pick(cat, ['name', 'category_name', 'title'], 'Kategori');
            final iconName =
                _pick(cat, ['icon', 'icon_name', 'category_icon', 'iconName']);
            final communityCount = _pickCommunityCount(cat);
            final colors = _categoryPalette[index % _categoryPalette.length];

            return SizedBox(
              width: itemWidth,
              child: _CategoryGridItem(
                icon: _categoryIconData(iconName.isEmpty ? null : iconName),
                label: name,
                count: communityCount,
                background: colors.background,
                foreground: colors.foreground,
                onTap: () {
                  final categoryId = _pickCategoryId(cat);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CommunityScreen(
                        initialCategoryId: categoryId,
                        initialCategoryName: name,
                      ),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static final List<_CategoryPalette> _categoryPalette = [
    _CategoryPalette(AppColors.primary.withOpacity(0.12), AppColors.primary),
    _CategoryPalette(
        AppColors.secondary.withOpacity(0.15), AppColors.secondary),
    _CategoryPalette(Colors.orange.withOpacity(0.12), Colors.orange.shade800),
    _CategoryPalette(Colors.purple.withOpacity(0.12), Colors.purple.shade700),
    _CategoryPalette(Colors.teal.withOpacity(0.12), Colors.teal.shade700),
  ];

  // ==================== POSTS ====================

  Widget _buildPostsSection() {
    if (_posts.isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.separated(
          itemCount: 2,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => const _PostSkeleton(),
        ),
      );
    }
    if (_posts.hasError) {
      return SliverToBoxAdapter(
        child: _InlineErrorCard(
          message: _posts.error!,
          onRetry: () => _retrySection(_loadPosts),
        ),
      );
    }
    if (_posts.data!.isEmpty) {
      return const SliverToBoxAdapter(
        child: _EmptyHint(text: 'Belum ada postingan publik'),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: _posts.data!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final post = _posts.data![index];
          final postId = post['post_id'] as int;
          final isLiking = _likingPostIds.contains(postId);

          return PostCardWidget(
            post: post,
            showCommunityInfo: true,
            isLiked: post['is_liked'] ?? false,
            isLiking: isLiking,
            isAuthor: _isCurrentUserAuthor(post),
            isAdmin: _isCurrentUserAdmin(),
            onTap: () => _navigateToPostDetail(post),
            onLike: () => _handleLikePost(post),
            onComment: () => _navigateToPostDetail(post),
            onEdit: _isCurrentUserAuthor(post)
                ? () => _navigateToEditPost(post)
                : null,
            onDelete: (_isCurrentUserAuthor(post) || _isCurrentUserAdmin())
                ? () => _handleDeletePost(post)
                : null,
          );
        },
      ),
    );
  }

  // ==================== EVENTS ====================

  Widget _buildEventsSection() {
    if (_events.isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.separated(
          itemCount: 2,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => const _PostSkeleton(),
        ),
      );
    }
    if (_events.hasError) {
      return SliverToBoxAdapter(
        child: _InlineErrorCard(
          message: _events.error!,
          onRetry: () => _retrySection(_loadEvents),
        ),
      );
    }
    if (_events.data!.isEmpty) {
      return const SliverToBoxAdapter(
        child: _EmptyHint(text: 'Belum ada event publik'),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: _events.data!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final event = _events.data![index];
          final postId = event['post_id'] as int;
          final isLiking = _likingPostIds.contains(postId);

          return PostCardWidget(
            post: event,
            showCommunityInfo: true,
            isLiked: event['is_liked'] ?? false,
            isLiking: isLiking,
            isAuthor: _isCurrentUserAuthor(event),
            isAdmin: _isCurrentUserAdmin(),
            onTap: () => _navigateToPostDetail(event),
            onLike: () => _handleLikePost(event),
            onComment: () => _navigateToPostDetail(event),
            onEdit: _isCurrentUserAuthor(event)
                ? () => _navigateToEditPost(event)
                : null,
            onDelete: (_isCurrentUserAuthor(event) || _isCurrentUserAdmin())
                ? () => _handleDeletePost(event)
                : null,
          );
        },
      ),
    );
  }

  // ==================== CAMPAIGNS ====================

  Widget _buildCampaignsSection() {
    if (_campaigns.isLoading) {
      return SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => const _CardSkeleton(),
        ),
      );
    }
    if (_campaigns.hasError) {
      return _InlineErrorCard(
        message: _campaigns.error!,
        onRetry: () => _retrySection(_loadCampaigns),
      );
    }
    if (_campaigns.data!.isEmpty) {
      return const _EmptyHint(text: 'Belum ada donasi aktif');
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _campaigns.data!.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            _CampaignCard(campaign: _campaigns.data![index]),
      ),
    );
  }
}

// ==================== SECTION STATE ====================

class _SectionState<T> {
  final T? data;
  final String? error;
  final bool isLoading;

  _SectionState._({this.data, this.error, required this.isLoading});

  factory _SectionState.loading() => _SectionState._(isLoading: true);
  factory _SectionState.data(T value) =>
      _SectionState._(data: value, isLoading: false);
  factory _SectionState.error(String message) =>
      _SectionState._(error: message, isLoading: false);

  bool get hasError => error != null;
}

// ==================== CATEGORY PALETTE ====================

class _CategoryPalette {
  final Color background;
  final Color foreground;
  const _CategoryPalette(this.background, this.foreground);
}

class _CategoryGridItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count; // 🔥 baru
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  const _CategoryGridItem({
    required this.icon,
    required this.label,
    required this.count, // 🔥 baru
    required this.background,
    required this.foreground,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: foreground, size: 26),
              ),
              // 🔥 Badge jumlah komunitas, hanya muncul kalau > 0
              if (count > 0)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: foreground,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGridSkeleton extends StatelessWidget {
  const _CategoryGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 44,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== RANKING BAR TILE ====================

class _RankingBarTile extends StatelessWidget {
  final int rank;
  final String name;
  final double score;
  final double percentage;
  final bool isTop;

  const _RankingBarTile({
    required this.rank,
    required this.name,
    required this.score,
    required this.percentage,
    required this.isTop,
  });

  Color get _rankColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFC107);
      case 2:
        return const Color(0xFFB0BEC5);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    final barColor =
        isTop ? AppColors.primary : AppColors.primary.withOpacity(0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Rank
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _rankColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name
          SizedBox(
            width: 80,
            child: Text(
              name,
              style: TextStyle(
                fontWeight: isTop ? FontWeight.w600 : FontWeight.w400,
                fontSize: 12,
                color: isTop ? Colors.black87 : Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percentage.clamp(0.0, 1.0),
                minHeight: 24,
                backgroundColor: Colors.grey.shade100,
                color: barColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Score
          SizedBox(
            width: 50,
            child: Text(
              '${score.toInt()} pts',
              style: TextStyle(
                fontWeight: isTop ? FontWeight.bold : FontWeight.w400,
                fontSize: 12,
                color: isTop ? AppColors.primary : Colors.grey.shade600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingBarSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _Shimmer(
        child: Row(
          children: [
            const _SkeletonBox(width: 28, height: 28, radius: 14),
            const SizedBox(width: 12),
            const _SkeletonBox(width: 80, height: 12, radius: 4),
            const SizedBox(width: 8),
            Expanded(
              child: const _SkeletonBox(height: 24, radius: 8),
            ),
            const SizedBox(width: 8),
            const _SkeletonBox(width: 50, height: 12, radius: 4),
          ],
        ),
      ),
    );
  }
}

// ==================== SHIMMER / SKELETON ====================

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = _controller.value * 3 - 1.5;
            return LinearGradient(
              colors: [
                Colors.grey.shade300,
                Colors.grey.shade100,
                Colors.grey.shade300,
              ],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(dx - 1, 0),
              end: Alignment(dx + 1, 0),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const _SkeletonBox({
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _SkeletonBox(width: 32, height: 32, radius: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBox(width: 100, height: 10),
                      SizedBox(height: 6),
                      _SkeletonBox(width: 70, height: 8),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _SkeletonBox(width: 160, height: 12),
            const SizedBox(height: 8),
            const _SkeletonBox(height: 10),
            const SizedBox(height: 6),
            const _SkeletonBox(width: 220, height: 10),
          ],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SkeletonBox(height: 90, radius: 16),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBox(width: 130, height: 12),
                  SizedBox(height: 8),
                  _SkeletonBox(width: 90, height: 10),
                  SizedBox(height: 6),
                  _SkeletonBox(width: 70, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== SHARED UI ====================

class _InlineErrorText extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _InlineErrorText({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(message,
              style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRetry,
            child: Icon(Icons.refresh, size: 16, color: Colors.red.shade400),
          ),
        ],
      ],
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _InlineErrorCard({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade400,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Coba Lagi'),
            ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.inbox_outlined, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ],
    );
  }
}

// ==================== CAMPAIGN CARD ====================

class _CampaignCard extends StatelessWidget {
  final Map<String, dynamic> campaign;
  const _CampaignCard({required this.campaign});

  IconData _typeIcon(String type) {
    switch (type) {
      case 'money':
        return Icons.volunteer_activism_rounded;
      case 'goods':
        return Icons.inventory_2_rounded;
      default:
        return Icons.handshake_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'money':
        return 'Uang';
      case 'goods':
        return 'Barang';
      default:
        return 'Volunteer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _pick(campaign, ['title'], 'Campaign Donasi');
    final target = _pickNum(campaign, ['target_amount']);
    final current = _pickNum(campaign, ['current_amount', 'collected_amount']);
    final progress =
        target > 0 ? (current / target).clamp(0, 1).toDouble() : 0.0;
    final communityName = _pickNested(
        campaign, 'community', ['name', 'community_name'], ['community_name']);
    final donationType = _pick(campaign, ['donation_type'], 'money');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ikon tipe donasi dalam badge bulat + label tipe
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      _typeIcon(donationType),
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _typeLabel(donationType),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Judul campaign
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // 🔥 Nama komunitas, selalu ditampilkan kalau ada
              if (communityName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.groups_rounded,
                        size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        communityName,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const Spacer(),

              // Progress hanya untuk tipe uang, tipe lain cukup badge di atas
              if (donationType == 'money' && target > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade100,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Rp${_formatCurrency(current)}',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
// ==================== HELPER FUNCTIONS ====================

String _pick(Map<String, dynamic> map, List<String> keys,
    [String fallback = '']) {
  for (final k in keys) {
    final v = map[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return fallback;
}

num _pickNum(Map<String, dynamic> map, List<String> keys, [num fallback = 0]) {
  for (final k in keys) {
    final v = map[k];
    if (v is num) return v;
    if (v is String) {
      final parsed = num.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  return fallback;
}

int _pickCommunityCount(Map<String, dynamic> cat) {
  final countMap = cat['_count'];
  if (countMap is Map) {
    final v = countMap['communities'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
  }
  return 0;
}

int? _pickCategoryId(Map<String, dynamic> cat) {
  final v = cat['category_id'] ?? cat['id'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

IconData _categoryIconData(String? iconName) {
  final key = iconName?.trim().toLowerCase();

  switch (key) {
    case 'volunteer_activism':
      return Icons.volunteer_activism;
    case 'eco':
      return Icons.eco;
    case 'school':
      return Icons.school;
    case 'sports_soccer':
      return Icons.sports_soccer;
    case 'palette':
      return Icons.palette;
    case 'storefront':
      return Icons.storefront;
    case 'mosque':
      return Icons.mosque;
    case 'interests':
      return Icons.interests;
    case 'category':
      return Icons.category;
    default:
      // 🔥 kalau ini yang muncul di console, berarti field/nama icon-nya
      // beda dari yang diasumsikan di switch di atas
      debugPrint('⚠️ Icon kategori tidak dikenali: "$iconName"');
      return Icons.category;
  }
}

// ==================== BANNER BUAT KOMUNITAS ====================

class _CreateCommunityBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateCommunityBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gambar banner
              Image.asset(
                'assets/images/banner-create-community.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withOpacity(0.7)
                      ],
                    ),
                  ),
                ),
              ),
              // Gradient overlay biar teks tetap kebaca di atas gambar
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.65),
                      Colors.black.withOpacity(0.35),
                      Colors.black.withOpacity(0.10),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              // Konten teks + CTA
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.auto_awesome_rounded,
                              size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Mulai Sekarang',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Punya komunitas?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Daftarkan komunitas kamu atau buat komunitas baru dan ajak orang-orang bergabung',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Buat Komunitas',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 14, color: Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _pickNested(
  Map<String, dynamic> map,
  String nestedKey,
  List<String> nestedFieldKeys,
  List<String> flatFieldKeys,
) {
  final nested = map[nestedKey];
  if (nested is Map) {
    final value = _pick(Map<String, dynamic>.from(nested), nestedFieldKeys);
    if (value.isNotEmpty) return value;
  }
  return _pick(map, flatFieldKeys);
}

String _formatCurrency(num value) {
  final str = value.toInt().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    final posFromEnd = str.length - i;
    buffer.write(str[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}
