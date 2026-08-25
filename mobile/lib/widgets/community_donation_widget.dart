// lib/widgets/community_donation_widget.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/donation_service.dart';
import '../screen/create_campaign_screen.dart';
import '../screen/campaign_list_screen.dart';

/// Banner ringkas untuk komunitas. Sebelumnya widget ini me-render seluruh
/// daftar campaign secara inline (auto-load semua), sekarang hanya
/// menampilkan ringkasan + tombol menuju halaman daftar campaign
/// (CampaignListScreen), supaya konten utama komunitas (postingan) tidak
/// tenggelam di bawah daftar campaign yang panjang.
class CommunityDonationWidget extends StatefulWidget {
  final int communityId;
  final String? communityName;
  final bool isMember;
  final bool canManage; // admin/founder

  const CommunityDonationWidget({
    super.key,
    required this.communityId,
    this.communityName,
    required this.isMember,
    this.canManage = false,
  });

  @override
  State<CommunityDonationWidget> createState() =>
      _CommunityDonationWidgetState();
}

class _CommunityDonationWidgetState extends State<CommunityDonationWidget> {
  final DonationService _service = DonationService();

  bool _isLoading = true;
  int _activeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final result = await _service.fetchCampaigns(
        token: token,
        page: 1,
        limit: 1,
        communityId: widget.communityId,
        status: 'active',
      );
      if (!mounted) return;
      setState(() {
        _activeCount = result.total;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _openCampaignList() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CampaignListScreen(
          communityId: widget.communityId,
          communityName: widget.communityName,
          isMember: widget.isMember,
          canManage: widget.canManage,
        ),
      ),
    )
        .then((_) {
      // Refresh ringkasan setiap kali balik dari halaman daftar campaign,
      // siapa tahu ada campaign baru yang dibuat/berubah status.
      _loadSummary();
    });
  }

  void _openCreateCampaign() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CreateCampaignScreen(
          communityId: widget.communityId,
        ),
      ),
    )
        .then((result) {
      if (result != null) {
        _loadSummary();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: _openCampaignList,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.favorite,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donasi & Campaign',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isLoading
                          ? 'Memuat...'
                          : _activeCount > 0
                              ? '$_activeCount campaign aktif di komunitas ini'
                              : 'Belum ada campaign aktif',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isMember)
                IconButton(
                  tooltip: 'Buat Campaign',
                  onPressed: _openCreateCampaign,
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: AppColors.primary,
                  ),
                ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
