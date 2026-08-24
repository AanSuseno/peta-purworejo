// lib/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/posts_service.dart';
import '../widgets/post_card_widget.dart';

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
    // ... implement like
  }

  Future<void> _handleRegister() async {
    // ... implement register event
  }

  Future<void> _handleCancel() async {
    // ... implement cancel event
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PostCardWidget(
          post: _post!,
          showCommunityInfo: true,
          isLiked: _post?['is_liked'] == true,
          onTap: () {},
          onLike: _handleLike,
          onComment: () {},
          onRegisterEvent: () => _handleRegister(),
          onCancelEvent: () => _handleCancel(),
        ),
        // Comments section can be added here
      ],
    );
  }
}
