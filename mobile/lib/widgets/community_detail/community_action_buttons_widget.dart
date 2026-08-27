// widgets/community_detail/community_action_buttons_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:mobile/widgets/swipe_join_button.dart';

class CommunityActionButtonsWidget extends StatelessWidget {
  final bool isMember;
  final bool isFounder;
  final bool isJoinLeavePending;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  const CommunityActionButtonsWidget({
    super.key,
    required this.isMember,
    required this.isFounder,
    required this.isJoinLeavePending,
    required this.onJoin,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    if (!isMember) {
      return Column(
        children: [
          SwipeJoinButton(
            isPending: isJoinLeavePending,
            onSwipeComplete: onJoin,
          ),
          const SizedBox(height: 20),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle,
              size: 15,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Kamu sudah bergabung',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
            const Spacer(),
            if (!isFounder)
              GestureDetector(
                onTap: isJoinLeavePending ? null : onLeave,
                child: Text(
                  isJoinLeavePending ? 'Memproses...' : 'Keluar',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.grey.shade400,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}