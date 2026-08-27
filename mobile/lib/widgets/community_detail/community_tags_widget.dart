// widgets/community_detail/community_tags_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';

class CommunityTagsWidget extends StatelessWidget {
  final String? categoryName;
  final String? kecamatan;
  final bool isFounder;
  final bool isAdmin;

  const CommunityTagsWidget({
    super.key,
    this.categoryName,
    this.kecamatan,
    this.isFounder = false,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> tags = [];

    if (categoryName != null && categoryName!.isNotEmpty) {
      tags.add(_Tag(
        icon: Icons.category_outlined,
        label: categoryName!,
      ));
    }

    if (kecamatan != null && kecamatan!.isNotEmpty) {
      tags.add(_Tag(
        icon: Icons.location_on_outlined,
        label: kecamatan!,
      ));
    }

    if (isFounder) {
      tags.add(_Tag(icon: Icons.star_outline, label: 'Founder'));
    } else if (isAdmin) {
      tags.add(_Tag(icon: Icons.shield_outlined, label: 'Admin'));
    }

    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags,
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Tag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade500),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}