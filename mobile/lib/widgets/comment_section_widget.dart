// lib/widgets/comment_section_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/posts_service.dart';

class CommentSectionWidget extends StatefulWidget {
  final int postId;
  final int communityId;
  final VoidCallback? onCommentAdded;

  const CommentSectionWidget({
    super.key,
    required this.postId,
    required this.communityId,
    this.onCommentAdded,
  });

  @override
  State<CommentSectionWidget> createState() => _CommentSectionWidgetState();
}

class _CommentSectionWidgetState extends State<CommentSectionWidget> {
  final PostsService _service = PostsService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore && !_hasMore) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Sesi tidak ditemukan';
      });
      return;
    }

    setState(() {
      if (!loadMore) {
        _isLoading = true;
        _comments = [];
        _currentPage = 1;
      }
      _error = null;
    });

    try {
      final result = await _service.fetchComments(
        token: token,
        postId: widget.postId,
        page: loadMore ? _currentPage + 1 : 1,
        limit: 20,
      );

      if (!mounted) return;

      final newComments =
          (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final pagination = result['pagination'] as Map<String, dynamic>?;

      setState(() {
        if (loadMore) {
          _comments.addAll(newComments);
        } else {
          _comments = newComments;
        }
        _currentPage = pagination?['page'] ?? 1;
        _totalPages = pagination?['totalPages'] ?? 1;
        _hasMore = _currentPage < _totalPages;
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

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesi tidak ditemukan')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final newComment = await _service.createComment(
        token: token,
        postId: widget.postId,
        content: content,
      );

      if (!mounted) return;

      setState(() {
        _comments.insert(0, newComment);
        _commentController.clear();
        _isSubmitting = false;
      });

      widget.onCommentAdded?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Komentar berhasil ditambahkan'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _deleteComment(int commentId) async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus Komentar', style: GoogleFonts.poppins()),
        content: Text(
          'Apakah Anda yakin ingin menghapus komentar ini?',
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

    try {
      await _service.deleteComment(token: token, commentId: commentId);

      if (!mounted) return;

      setState(() {
        _comments.removeWhere((c) => c['comment_id'] == commentId);
      });

      widget.onCommentAdded?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Komentar berhasil dihapus'),
          backgroundColor: Colors.orange,
        ),
      );
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

  String? _resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${PostsService.baseUrl}$path';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'Komentar (${_comments.length})',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),

        // Comment Input
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Tulis komentar...',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSubmitting ? null : _submitComment,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Comments List
        if (_isLoading && _comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 32,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadComments,
                    child: Text(
                      'Coba Lagi',
                      style: GoogleFonts.poppins(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 32,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Belum ada komentar',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Jadilah yang pertama berkomentar',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            controller: _scrollController,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _comments.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _comments.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: TextButton(
                      onPressed: () => _loadComments(loadMore: true),
                      child: Text(
                        'Muat lebih banyak',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final comment = _comments[index];
              final user = comment['users'] as Map<String, dynamic>?;
              final userName = user?['full_name'] ?? 'Pengguna';
              final userPhoto = _resolveUrl(
                user?['profile_picture'] as String?,
              );
              final content = comment['content'] ?? '';
              final createdAt = comment['created_at'] ?? '';
              final commentId = comment['comment_id'] ?? 0;
              final isAuthor = false; // Bisa diimplementasikan dengan userId dari AuthProvider

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      backgroundImage: userPhoto != null
                          ? NetworkImage(userPhoto)
                          : null,
                      child: userPhoto == null
                          ? Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  userName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                timeAgo(createdAt),
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            content,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Colors.grey.shade700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Delete button (hanya untuk author)
                    GestureDetector(
                      onTap: () => _deleteComment(commentId),
                      child: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
