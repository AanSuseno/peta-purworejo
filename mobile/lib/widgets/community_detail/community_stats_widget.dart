// widgets/community_detail/community_stats_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';

class CommunityStatsWidget extends StatelessWidget {
  final int memberCount;
  final int postCount;
  final int eventCount;
  final VoidCallback? onMembersTap;

  const CommunityStatsWidget({
    super.key,
    required this.memberCount,
    required this.postCount,
    required this.eventCount,
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
          _statDivider(),
          Expanded(
            child: _StatItem(
              label: 'Event',
              value: '$eventCount',
            ),
          ),
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
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
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