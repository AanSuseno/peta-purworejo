import 'package:flutter/material.dart';
import 'package:flutter_swipe_button/flutter_swipe_button.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';

/// Tombol swipe-to-join yang dipakai di list komunitas & detail komunitas.
class SwipeJoinButton extends StatefulWidget {
  final bool isPending;
  final VoidCallback onSwipeComplete;
  final double height;
  final String label;
  final String subtitle;
  final String pendingLabel;
  final String successLabel;

  const SwipeJoinButton({
    super.key,
    required this.isPending,
    required this.onSwipeComplete,
    this.height = 64,
    this.label = 'Geser untuk bergabung',
    this.subtitle = 'Gabung komunitas & ikut kegiatan bersama',
    this.pendingLabel = 'Sedang bergabung...',
    this.successLabel = 'Berhasil bergabung!',
  });

  @override
  State<SwipeJoinButton> createState() => _SwipeJoinButtonState();
}

class _SwipeJoinButtonState extends State<SwipeJoinButton> {
  bool _isCompleted = false;

  void _handleSwipe() {
    if (_isCompleted || widget.isPending) return;

    setState(() => _isCompleted = true);
    widget.onSwipeComplete();

    // Biarkan state sukses terlihat sebentar sebelum reset lagi.
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _isCompleted = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPending) {
      return _buildStatusButton(
        icon: const SizedBox(
          width: 19,
          height: 19,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        label: widget.pendingLabel,
      );
    }

    if (_isCompleted) {
      return _buildStatusButton(
        icon: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
        label: widget.successLabel,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwipeButton(
        width: double.infinity,
        height: widget.height,
        borderRadius: BorderRadius.circular(18),
        thumbPadding: const EdgeInsets.all(5),
        elevationThumb: 2,
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withOpacity(0.14),
        thumb: const Icon(
          Icons.chevron_right_rounded,
          size: 23,
          color: Colors.white,
        ),
        onSwipe: _handleSwipe,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.double_arrow_rounded,
                  size: 17,
                  color: AppColors.primary.withOpacity(0.7),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              widget.subtitle,
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton({
    required Widget icon,
    required String label,
  }) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
