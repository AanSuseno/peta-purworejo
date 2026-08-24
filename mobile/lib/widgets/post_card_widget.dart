// lib/widgets/post_card_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:intl/intl.dart';

class PostCardWidget extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool showCommunityInfo;
  final bool isLiked;
  final bool? isLiking;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback? onRegisterEvent;
  final VoidCallback? onCancelEvent;

  const PostCardWidget({
    super.key,
    required this.post,
    this.showCommunityInfo = true,
    required this.isLiked,
    this.isLiking,
    required this.onTap,
    required this.onLike,
    required this.onComment,
    this.onRegisterEvent,
    this.onCancelEvent,
  });

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AuthService.baseUrl}$path';
  }

  bool get isEvent => post['is_event'] == true || post['post_type'] == 'event';
  bool get isParticipant => post['is_participant'] == true;
  int get registeredCount => post['event_registered_count'] ?? 0;
  int? get quota => post['event_quota'];
  bool get isFull => quota != null && registeredCount >= quota!;
  String? get eventStatus => post['event_status'];

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

  Widget _buildMediaGallery(List<dynamic> mediaList) {
    if (mediaList.isEmpty) return const SizedBox.shrink();

    final mediaUrls = mediaList
        .map((m) => _resolveUrl(m['media_url'] as String?))
        .where((url) => url != null)
        .toList();

    if (mediaUrls.isEmpty) return const SizedBox.shrink();

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

    final coverIndex = mediaItems.indexWhere((m) => m['isCover'] == 'true');
    final sortedItems = [...mediaItems];
    if (coverIndex > 0) {
      final cover = sortedItems.removeAt(coverIndex);
      sortedItems.insert(0, cover);
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        if (sortedItems.length == 1)
          _buildSingleMedia(sortedItems[0])
        else
          _buildMultipleMedia(sortedItems),
      ],
    );
  }

  Widget _buildSingleMedia(Map<String, String> media) {
    final isVideo = media['type'] == 'video';

    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
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
                : Image.network(
                    media['url']!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildMultipleMedia(List<Map<String, String>> mediaItems) {
    final count = mediaItems.length;
    final first = mediaItems[0];
    final remaining = mediaItems.sublist(1);

    return Column(
      children: [
        // First media (full width)
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                first['type'] == 'video'
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
                    : Image.network(
                        first['url']!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                if (count > 1)
                  Positioned(
                    top: 8,
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
                        '+$count',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Remaining media (grid horizontal)
        if (remaining.isNotEmpty) ...[
          const SizedBox(height: 2),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: remaining.length > 3 ? 3 : remaining.length,
              itemBuilder: (context, index) {
                final media = remaining[index];
                return Container(
                  width: 80,
                  margin: EdgeInsets.only(
                    left: index == 0 ? 0 : 2,
                    right: index == 2 ? 0 : 2,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: media['type'] == 'video'
                        ? Container(
                            color: Colors.black,
                            child: Center(
                              child: Icon(
                                Icons.play_circle_filled,
                                size: 30,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          )
                        : Image.network(
                            media['url']!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
          if (remaining.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '+${remaining.length - 3} lainnya',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = post['title'] ?? 'Tanpa Judul';
    final content = post['content'] ?? '';
    final author = post['users'] as Map<String, dynamic>?;
    final authorName = author?['full_name'] ?? 'Pengguna';
    final authorPhoto = _resolveUrl(author?['profile_picture'] as String?);
    final community = post['communities'] as Map<String, dynamic>?;
    final communityName = community?['community_name'] ?? '';
    final createdAt = post['created_at'] ?? '';
    final likesCount = post['likes_count'] ?? 0;
    final commentsCount = post['comments_count'] ?? 0;
    final mediaList = post['post_media'] as List? ?? [];

    return GestureDetector(
      onTap: onTap,
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
            // Header: author & community info
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    backgroundImage: authorPhoto != null
                        ? NetworkImage(authorPhoto)
                        : null,
                    child: authorPhoto == null
                        ? Text(
                            authorName.isNotEmpty
                                ? authorName[0].toUpperCase()
                                : '?',
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
                        if (showCommunityInfo && communityName.isNotEmpty)
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
                ],
              ),
            ),

            // Badge event
            if (isEvent) ...[
              Padding(
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
              ),
              const SizedBox(height: 6),
            ],

            // Title
            Padding(
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
            ),

            // Content preview
            if (content.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
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
              ),
            ],

            // Media Gallery
            _buildMediaGallery(mediaList),

            // Event info (if event)
            if (isEvent) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (post['event_date'] != null)
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
                              post['event_date'] as String?,
                              post['event_start_time'] as String?,
                            ),
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    if (post['event_location'] != null &&
                        post['event_location'].toString().isNotEmpty) ...[
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
                              post['event_location'] as String? ?? '',
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$registeredCount peserta',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (quota != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '/ $quota kuota',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                        if (isFull) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Penuh',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Event button
                    if (eventStatus == 'upcoming' ||
                        eventStatus == 'ongoing') ...[
                      const SizedBox(height: 8),
                      if (isParticipant) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Terdaftar',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.secondary,
                              ),
                            ),
                            if (onCancelEvent != null) ...[
                              const Spacer(),
                              TextButton(
                                onPressed: onCancelEvent,
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Batal',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ] else if (!isFull && onRegisterEvent != null) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: ElevatedButton(
                            onPressed: onRegisterEvent,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Daftar Event',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ] else if (isFull) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Kuota Penuh',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],

            // Actions: Like & Comment
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  // Like button
                  GestureDetector(
                    onTap: isLiking == true ? null : onLike,
                    child: Row(
                      children: [
                        isLiking == true
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red,
                                ),
                              )
                            : Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 18,
                                color: isLiked
                                    ? Colors.red
                                    : Colors.grey.shade500,
                              ),
                        const SizedBox(width: 4),
                        Text(
                          '$likesCount',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: isLiked ? Colors.red : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Comment button
                  GestureDetector(
                    onTap: onComment,
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
            ),
          ],
        ),
      ),
    );
  }
}
