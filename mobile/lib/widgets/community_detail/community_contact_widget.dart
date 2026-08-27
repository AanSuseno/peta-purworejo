// widgets/community_detail/community_contact_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';

class CommunityContactWidget extends StatelessWidget {
  final String? address;
  final String? contactEmail;
  final String? contactPhone;

  const CommunityContactWidget({
    super.key,
    this.address,
    this.contactEmail,
    this.contactPhone,
  });

  bool get hasContactInfo =>
      (address != null && address!.isNotEmpty) ||
          (contactEmail != null && contactEmail!.isNotEmpty) ||
          (contactPhone != null && contactPhone!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!hasContactInfo) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Kontak'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (address != null && address!.isNotEmpty)
                _ContactRow(
                  icon: Icons.location_on_outlined,
                  text: address!,
                ),
              if (contactEmail != null && contactEmail!.isNotEmpty)
                _ContactRow(
                  icon: Icons.email_outlined,
                  text: contactEmail!,
                ),
              if (contactPhone != null && contactPhone!.isNotEmpty)
                _ContactRow(
                  icon: Icons.phone_outlined,
                  text: contactPhone!,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}