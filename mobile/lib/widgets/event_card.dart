import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile/constants/colors.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/screen/post_detail_screen.dart';

class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final int communityId;

  const EventCard({
    super.key,
    required this.event,
    required this.communityId,
  });

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${AuthService.baseUrl}$path';
  }

  String _getCountdown(DateTime eventDate) {
    final now = DateTime.now();
    final difference = eventDate.difference(now);

    if (difference.isNegative) {
      return 'Sudah lewat';
    }

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;

    if (days > 30) {
      final months = (days / 30).floor();
      return '$months bulan lagi';
    } else if (days > 0) {
      if (days == 1) return '1 hari lagi';
      return '$days hari lagi';
    } else if (hours > 0) {
      if (hours == 1) return '1 jam lagi';
      return '$hours jam lagi';
    } else if (minutes > 0) {
      if (minutes == 1) return '1 menit lagi';
      return '$minutes menit lagi';
    } else {
      return 'Sebentar lagi';
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Tanggal belum ditentukan';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';
    try {
      final time = DateFormat.Hm().parse(timeString);
      return DateFormat('HH:mm').format(time);
    } catch (e) {
      return timeString;
    }
  }

  String _getStatusBadge(String? status) {
    switch (status) {
      case 'upcoming':
        return 'Akan Datang';
      case 'ongoing':
        return 'Berlangsung';
      case 'past':
        return 'Selesai';
      default:
        return 'Event';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'upcoming':
        return Colors.blue.shade600;
      case 'ongoing':
        return Colors.green.shade600;
      case 'past':
        return Colors.grey.shade600;
      default:
        return AppColors.primary;
    }
  }

  void _navigateToDetail(BuildContext context) {
    final postId = event['post_id'] as int;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(
          postId: postId,
          communityId: communityId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = event['communities']['community_name'] +
            " >> " +
            event['title'] as String? ??
        'Tanpa Judul';
    final eventDate = event['event_date'] as String?;
    final eventStartTime = event['event_start_time'] as String?;
    final eventEndTime = event['event_end_time'] as String?;
    final eventLocation = event['event_location'] as String?;
    final media = event['post_media'] as List? ?? [];
    final coverImage =
        media.isNotEmpty ? media.first['media_url'] as String? : null;
    final status = event['event_status'] as String?;
    final isFull = event['is_full'] == true;

    DateTime? parsedDate;
    if (eventDate != null) {
      try {
        parsedDate = DateTime.parse(eventDate);
        if (eventStartTime != null) {
          final timeParts = eventStartTime.split(':');
          if (timeParts.length >= 2) {
            parsedDate = DateTime(
              parsedDate.year,
              parsedDate.month,
              parsedDate.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
          }
        }
      } catch (e) {
        // Ignore parsing errors
      }
    }

    final showCountdown = parsedDate != null && status != 'past';
    final countdownText = showCountdown ? _getCountdown(parsedDate!) : null;
    final isCountdownInDays =
        showCountdown && parsedDate!.difference(DateTime.now()).inDays > 0;
    final isCountdownInHours = showCountdown &&
        parsedDate!.difference(DateTime.now()).inDays == 0 &&
        parsedDate!.difference(DateTime.now()).inHours > 0;

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
          onTap: () => _navigateToDetail(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: coverImage != null
                        ? Image.network(
                            _resolveUrl(coverImage)!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _coverFallback(),
                          )
                        : _coverFallback(),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _getStatusBadge(status),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (isFull)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'Penuh',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (showCountdown && status != 'past')
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCountdownInHours ||
                                      (!isCountdownInDays &&
                                          !isCountdownInHours)
                                  ? Icons.access_time
                                  : Icons.calendar_today,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              countdownText!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (showCountdown && status != 'past') ...[
                      Row(
                        children: [
                          Icon(
                            isCountdownInHours ||
                                    (!isCountdownInDays && !isCountdownInHours)
                                ? Icons.access_time
                                : Icons.calendar_today,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              countdownText!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (eventDate != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formatDate(eventDate),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (eventStartTime != null &&
                        (status == 'past' || eventDate == null))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_formatTime(eventStartTime)}${eventEndTime != null ? ' - ${_formatTime(eventEndTime)}' : ''}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (eventLocation != null && eventLocation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                eventLocation,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Tap untuk detail',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
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

  Widget _coverFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.event,
          size: 40,
          color: Colors.white.withOpacity(0.4),
        ),
      ),
    );
  }
}
