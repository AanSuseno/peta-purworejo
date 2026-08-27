// widgets/community_detail/community_header_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';

class CommunityHeaderWidget extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final String? bannerUrl;
  final bool isVerified;
  final String? founderName;

  const CommunityHeaderWidget({
    super.key,
    required this.name,
    this.logoUrl,
    this.bannerUrl,
    this.isVerified = false,
    this.founderName,
  });

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: bannerUrl != null
              ? Image.network(
            bannerUrl!,
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
              backgroundImage: logoUrl != null ? NetworkImage(logoUrl!) : null,
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
    );
  }

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