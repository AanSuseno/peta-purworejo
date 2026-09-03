// lib/widgets/post_card_widget.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:intl/intl.dart';

class PostCardWidget extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool showCommunityInfo;
  final bool isLiked;
  final bool? isLiking;
  final bool isAuthor;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRegisterEvent;
  final VoidCallback? onCancelEvent;

  const PostCardWidget({
    super.key,
    required this.post,
    this.showCommunityInfo = true,
    required this.isLiked,
    this.isLiking,
    this.isAuthor = false,
    this.isAdmin = false,
    required this.onTap,
    required this.onLike,
    required this.onComment,
    this.onEdit,
    this.onDelete,
    this.onRegisterEvent,
    this.onCancelEvent,
  });

  @override
  State<PostCardWidget> createState() => _PostCardWidgetState();
}

class _PostCardWidgetState extends State<PostCardWidget>
    with SingleTickerProviderStateMixin {
  // Image loading states
  final Map<int, bool> _imageLoadingStates = {};
  final Map<int, bool> _imageErrorStates = {};
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AuthService.baseUrl}$path';
  }

  bool get isEvent =>
      widget.post['is_event'] == true || widget.post['post_type'] == 'event';
  String? get eventStatus => widget.post['event_status'];

  String getEventStatusLabel() {
    final status = eventStatus ?? '';
    switch (status) {
      case 'upcoming':
        return 'Akan Datang';
      case 'ongoing':
        return 'Berlangsung';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return '';
    }
  }

  Color getEventStatusColor() {
    final status = eventStatus ?? '';
    switch (status) {
      case 'upcoming':
        return Colors.blue;
      case 'ongoing':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String formatDateTime(String? date, String? time) {
    if (date == null) return '';
    try {
      final parsedDate = DateTime.parse(date);
      final formattedDate = DateFormat('dd MMM yyyy').format(parsedDate);
      if (time != null && time.isNotEmpty) {
        final timeParts = time.split(':');
        if (timeParts.length >= 2) {
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          final period = hour >= 12 ? 'PM' : 'AM';
          final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
          return '$formattedDate, $displayHour:${minute.toString().padLeft(2, '0')} $period';
        }
      }
      return formattedDate;
    } catch (_) {
      return date;
    }
  }

  String timeAgo(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return DateFormat('dd MMM yyyy').format(dateTime);
      } else if (difference.inDays > 0) {
        return '${difference.inDays} hari lalu';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} jam lalu';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} menit lalu';
      } else {
        return 'Baru saja';
      }
    } catch (_) {
      return dateTimeStr;
    }
  }

  void _onImageLoaded(int index) {
    if (mounted) {
      setState(() {
        _imageLoadingStates[index] = false;
      });
    }
  }

  void _onImageError(int index) {
    if (mounted) {
      setState(() {
        _imageLoadingStates[index] = false;
        _imageErrorStates[index] = true;
      });
    }
  }

  void _showFullScreenGallery(
    BuildContext context,
    List<Map<String, String>> mediaItems,
    int initialIndex,
  ) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullScreenGallery(
          mediaItems: mediaItems,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  // ==================== SHIMMER WIDGET ====================

  Widget _buildShimmerPlaceholder() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = _shimmerController.value * 3 - 1.5;
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
          child: Container(
            color: Colors.grey.shade300,
          ),
        );
      },
    );
  }

  // ==================== MEDIA GALLERY ====================

  Widget _buildMediaGallery(List<dynamic> mediaList) {
    if (mediaList.isEmpty) return const SizedBox.shrink();

    final List<Map<String, String>> mediaItems = [];
    for (int i = 0; i < mediaList.length; i++) {
      final m = mediaList[i];
      final url = _resolveUrl(m['media_url'] as String?);
      if (url != null) {
        final type = (m['media_type'] as String? ?? 'image').toLowerCase();
        mediaItems.add({
          'url': url,
          'type': type,
          'isCover': m['is_cover'] == true ? 'true' : 'false',
        });
      }
    }

    if (mediaItems.isEmpty) return const SizedBox.shrink();

    // Inisialisasi loading states untuk semua media
    for (int i = 0; i < mediaItems.length; i++) {
      _imageLoadingStates.putIfAbsent(i, () => true);
      _imageErrorStates.putIfAbsent(i, () => false);
    }

    final coverIndex = mediaItems.indexWhere((m) => m['isCover'] == 'true');
    final sortedItems = [...mediaItems];
    if (coverIndex > 0) {
      final cover = sortedItems.removeAt(coverIndex);
      sortedItems.insert(0, cover);
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        // Hanya tampilkan 1 gambar (gambar pertama/cover)
        _buildSingleMedia(sortedItems[0], 0),
      ],
    );
  }

  Widget _buildSingleMedia(Map<String, String> media, int index) {
    final isVideo = media['type'] == 'video';
    final isLoading = _imageLoadingStates[index] ?? true;
    final hasError = _imageErrorStates[index] ?? false;

    return GestureDetector(
      onTap: () {
        final allMedia = widget.post['post_media'] as List? ?? [];
        final List<Map<String, String>> allItems = [];
        for (int i = 0; i < allMedia.length; i++) {
          final m = allMedia[i];
          final url = _resolveUrl(m['media_url'] as String?);
          if (url != null) {
            allItems.add({
              'url': url,
              'type': (m['media_type'] as String? ?? 'image').toLowerCase(),
              'isCover': m['is_cover'] == true ? 'true' : 'false',
            });
          }
        }
        _showFullScreenGallery(context, allItems, 0);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media content with shimmer
              isVideo
                  ? Container(
                      color: Colors.black,
                      child: Center(
                        child: Icon(
                          Icons.play_circle_filled,
                          size: 60,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    )
                  : _buildNetworkImageWithShimmer(
                      url: media['url']!,
                      index: index,
                      isLoading: isLoading,
                      hasError: hasError,
                      onLoaded: () => _onImageLoaded(index),
                      onError: () => _onImageError(index),
                    ),

              // Video badge
              if (isVideo)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Video',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              // Total media count badge (hanya jika lebih dari 1 media)
              if (widget.post['post_media'] != null &&
                  (widget.post['post_media'] as List).length > 1)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+${(widget.post['post_media'] as List).length - 1}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== IMAGE WITH SHIMMER ====================

  Widget _buildNetworkImageWithShimmer({
    required String url,
    required int index,
    required bool isLoading,
    required bool hasError,
    required VoidCallback onLoaded,
    required VoidCallback onError,
  }) {
    if (hasError) {
      return Container(
        color: Colors.grey.shade200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text('Gagal memuat',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null && isLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onError());
            return const SizedBox.shrink();
          },
        ),
        if (isLoading) _buildShimmerPlaceholder(),
      ],
    );
  }
  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final title = widget.post['title'] ?? 'Tanpa Judul';
    final content = widget.post['content'] ?? '';
    final author = widget.post['users'] as Map<String, dynamic>?;
    final authorName = author?['full_name'] ?? 'Pengguna';
    final authorPhoto = _resolveUrl(author?['profile_picture'] as String?);
    final community = widget.post['communities'] as Map<String, dynamic>?;
    final communityName = community?['community_name'] ?? '';
    final createdAt = widget.post['created_at'] ?? '';
    final likesCount = widget.post['likes_count'] ?? 0;
    final commentsCount = widget.post['comments_count'] ?? 0;
    final mediaList = widget.post['post_media'] as List? ?? [];

    final postAuthorId = widget.post['author_id'] as int?;
    final isAuthorBool = widget.isAuthor;
    final isAdminBool = widget.isAdmin;

    final canManage = isAuthorBool || isAdminBool;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(
              authorName: authorName,
              authorPhoto: authorPhoto,
              communityName: communityName,
              createdAt: createdAt,
              canManage: canManage,
            ),

            // Event Badge
            if (isEvent) _buildEventBadge(),

            // Title
            _buildTitle(title),

            // Content
            if (content.isNotEmpty) _buildContent(content),

            // Media Gallery
            _buildMediaGallery(mediaList),

            // Event Info
            if (isEvent) _buildEventInfo(),

            // Actions
            _buildActions(
              likesCount: likesCount,
              commentsCount: commentsCount,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SUB-WIDGETS ====================

  Widget _buildHeader({
    required String authorName,
    required String? authorPhoto,
    required String communityName,
    required String createdAt,
    required bool canManage,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            backgroundImage:
                authorPhoto != null ? NetworkImage(authorPhoto) : null,
            child: authorPhoto == null
                ? Text(
                    authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (widget.showCommunityInfo && communityName.isNotEmpty)
                  Text(
                    communityName,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            timeAgo(createdAt),
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.grey.shade400,
            ),
          ),
          if (canManage) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: Colors.grey.shade500,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  widget.onEdit?.call();
                } else if (value == 'delete') {
                  widget.onDelete?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Hapus',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventBadge() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event,
                  size: 12,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'EVENT',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: getEventStatusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  getEventStatusLabel(),
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: getEventStatusColor(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildContent(String content) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Text(
        content,
        style: GoogleFonts.poppins(
          fontSize: 12.5,
          color: Colors.grey.shade600,
          height: 1.4,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildEventInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.post['event_date'] != null)
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  formatDateTime(
                    widget.post['event_date'] as String?,
                    widget.post['event_start_time'] as String?,
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          if (widget.post['event_location'] != null &&
              widget.post['event_location'].toString().isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 13,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.post['event_location'] as String? ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions({
    required int likesCount,
    required int commentsCount,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.isLiking == true ? null : widget.onLike,
            child: Row(
              children: [
                widget.isLiking == true
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red,
                        ),
                      )
                    : Icon(
                        widget.isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color:
                            widget.isLiked ? Colors.red : Colors.grey.shade500,
                      ),
                const SizedBox(width: 4),
                Text(
                  '$likesCount',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: widget.isLiked ? Colors.red : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onComment,
            child: Row(
              children: [
                Icon(
                  Icons.comment_outlined,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  '$commentsCount',
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

// ==================== FULLSCREEN GALLERY ====================

class _FullScreenGallery extends StatefulWidget {
  final List<Map<String, String>> mediaItems;
  final int initialIndex;

  const _FullScreenGallery({
    required this.mediaItems,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late AnimationController _shimmerController;

  // Loading states per image in fullscreen
  final Map<int, bool> _fullscreenLoadingStates = {};
  final Map<int, bool> _fullscreenErrorStates = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Initialize loading states
    for (int i = 0; i < widget.mediaItems.length; i++) {
      _fullscreenLoadingStates[i] = true;
      _fullscreenErrorStates[i] = false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onFullscreenImageLoaded(int index) {
    if (mounted) {
      setState(() {
        _fullscreenLoadingStates[index] = false;
      });
    }
  }

  void _onFullscreenImageError(int index) {
    if (mounted) {
      setState(() {
        _fullscreenLoadingStates[index] = false;
        _fullscreenErrorStates[index] = true;
      });
    }
  }

  Widget _buildFullscreenShimmer() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = _shimmerController.value * 3 - 1.5;
            return LinearGradient(
              colors: [
                Colors.grey.shade800,
                Colors.grey.shade600,
                Colors.grey.shade800,
              ],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(dx - 1, 0),
              end: Alignment(dx + 1, 0),
            ).createShader(bounds);
          },
          child: Container(
            color: Colors.grey.shade800,
          ),
        );
      },
    );
  }

  Widget _buildFullscreenImage(String url, int index) {
    final isLoading = _fullscreenLoadingStates[index] ?? true;
    final hasError = _fullscreenErrorStates[index] ?? false;

    if (hasError) {
      return Container(
        color: Colors.grey.shade800,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 60, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text('Gagal memuat gambar',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null && isLoading) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _onFullscreenImageLoaded(index),
                );
              }
              return child;
            },
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _onFullscreenImageError(index),
              );
              return const SizedBox.shrink();
            },
          ),
          if (isLoading) _buildFullscreenShimmer(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PageView untuk swipe antar gambar
          PageView.builder(
            controller: _pageController,
            itemCount: widget.mediaItems.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final media = widget.mediaItems[index];
              final isVideo = media['type'] == 'video';

              return Center(
                child: isVideo
                    ? Container(
                        color: Colors.black,
                        child: Center(
                          child: Icon(
                            Icons.play_circle_filled,
                            size: 80,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      )
                    : _buildFullscreenImage(media['url']!, index),
              );
            },
          ),

          // Indikator jumlah gambar
          if (widget.mediaItems.length > 1)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.mediaItems.length}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          // Tombol close
          Positioned(
            top: 60,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
