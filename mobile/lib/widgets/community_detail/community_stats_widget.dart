// widgets/community_detail/community_stats_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommunityStatsWidget extends StatelessWidget {
  final int memberCount;
  final int postCount;
  final int? totalScore;
  final VoidCallback? onMembersTap;

  const CommunityStatsWidget({
    super.key,
    required this.memberCount,
    required this.postCount,
    this.totalScore,
    this.onMembersTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onMembersTap,
              child: _StatItem(
                label: 'Anggota',
                value: '$memberCount',
              ),
            ),
          ),
          _statDivider(),
          Expanded(
            child: _StatItem(
              label: 'Post',
              value: '$postCount',
            ),
          ),
          if (totalScore != null) ...[
            _statDivider(),
            Expanded(
              child: _StatItem(
                label: 'Skor',
                value: '$totalScore',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: Colors.grey.shade200);
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;

  const _StatItem({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: iconColor ?? Colors.grey.shade600,
              ),
              const SizedBox(width: 3),
            ],
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
