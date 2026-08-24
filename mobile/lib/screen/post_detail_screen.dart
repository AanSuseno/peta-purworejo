// lib/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/posts_service.dart';
import '../widgets/post_card_widget.dart';
import '../widgets/comment_section_widget.dart';

class PostDetailScreen extends StatefulWidget {
  final int postId;
  final int communityId;

  const PostDetailScreen({
    super.key,
    required this.postId,
    required this.communityId,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostsService _service = PostsService();
  Map<String, dynamic>? _post;
  bool _isLoading = true;
  bool _isLiking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Sesi tidak ditemukan';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final post = await _service.fetchPostById(
        token: token,
        postId: widget.postId,
      );
      if (!mounted) return;
      setState(() {
        _post = post;
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

  Future<void> _handleLike() async {
    if (_isLiking || _post == null) return;

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesi tidak ditemukan')));
      return;
    }

    setState(() => _isLiking = true);

    try {
      final result = await _service.toggleLike(
        token: token,
        postId: widget.postId,
      );

      if (!mounted) return;

      setState(() {
        _post!['is_liked'] = result['is_liked'] ?? false;
        _post!['likes_count'] = result['total_likes'] ?? 0;
        _isLiking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLiking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _handleRegister() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesi tidak ditemukan')));
      return;
    }

    try {
      await _service.registerEvent(token: token, postId: widget.postId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berhasil mendaftar event!'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadPost();
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

  Future<void> _handleCancel() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesi tidak ditemukan')));
      return;
    }

    try {
      await _service.cancelEventRegistration(
        token: token,
        postId: widget.postId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berhasil membatalkan pendaftaran'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadPost();
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
          'Detail Postingan',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : _buildPostDetail(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text('Coba Lagi', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Widget _buildPostDetail() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          PostCardWidget(
            post: _post!,
            showCommunityInfo: true,
            isLiked: _post?['is_liked'] == true,
            isLiking: _isLiking,
            onTap: () {},
            onLike: _handleLike,
            onComment: () {},
            onRegisterEvent: _handleRegister,
            onCancelEvent: _handleCancel,
          ),
          const SizedBox(height: 16),
          // Comments Section
          CommentSectionWidget(
            postId: widget.postId,
            communityId: widget.communityId,
            onCommentAdded: _loadPost,
          ),
        ],
      ),
    );
  }
}
