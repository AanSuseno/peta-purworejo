// lib/screens/campaign_list_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../provider/auth_provider.dart';
import '../services/donation_service.dart';
import 'create_campaign_screen.dart';
import 'campaign_detail_screen.dart';

/// Halaman penuh untuk menampilkan seluruh campaign donasi milik satu
/// komunitas. Sebelumnya daftar ini ditampilkan langsung (inline) di
/// community_detail_screen, sekarang dipisah menjadi halaman sendiri agar
/// halaman detail komunitas lebih ringkas dan fokus ke postingan.
class CampaignListScreen extends StatefulWidget {
  final int communityId;
  final String? communityName;
  final bool isMember;
  final bool canManage; // admin/founder

  const CampaignListScreen({
    super.key,
    required this.communityId,
    this.communityName,
    required this.isMember,
    this.canManage = false,
  });

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  final DonationService _service = DonationService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _campaigns = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  bool _hasMore = true;

  // Filter. 'pending' hanya relevan/berguna untuk admin/founder yang perlu
  // meninjau campaign yang menunggu persetujuan.
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadCampaigns(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      _loadCampaigns();
    }
  }

  Future<void> _loadCampaigns({bool reset = false}) async {
    final token = await context.read<AuthProvider>().getToken();
    if (token == null) return;

    setState(() {
      if (reset) {
        _isLoading = true;
        _error = null;
      } else {
        _isLoadingMore = true;
      }
    });

    final nextPage = reset ? 1 : _page + 1;
    String? statusFilter;
    bool showPending = false;

    switch (_selectedFilter) {
      case 'all':
        statusFilter = null;
        showPending = false;
        break;
      case 'active':
        statusFilter = 'active';
        showPending = false;
        break;
      case 'pending_approval':
        // ✅ Untuk menampilkan campaign yang menunggu persetujuan
        statusFilter = null; // Tidak filter status campaign
        showPending = true; // Tampilkan semua approval_status termasuk pending
        break;
      case 'completed':
        statusFilter = 'completed';
        showPending = false;
        break;
      case 'cancelled':
        statusFilter = 'cancelled';
        showPending = false;
        break;
      default:
        statusFilter = null;
        showPending = false;
    }

    try {
      final result = await _service.fetchCampaigns(
        token: token,
        page: nextPage,
        limit: 10,
        communityId: widget.communityId,
        status: statusFilter,
        showPending: showPending,
      );

      if (!mounted) return;

      setState(() {
        if (reset) _campaigns.clear();
        _campaigns.addAll(result.campaigns);
        _page = result.page;
        _totalPages = result.totalPages;
        _hasMore = result.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (reset) {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      });
    }
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
      // `result` bisa berupa `true` (fallback lama) atau Map berisi data
      // campaign yang baru dibuat. Kalau berupa data campaign, langsung kita
      // selipkan ke daftar lokal supaya pembuat campaign LANGSUNG melihat
      // campaign-nya, tanpa menunggu approval admin/founder mempengaruhi
      // apakah campaign itu ikut kembali dari server saat filter "Semua".
      if (result is Map<String, dynamic>) {
        setState(() {
          _campaigns.removeWhere(
            (c) => c['campaign_id'] == result['campaign_id'],
          );
          _campaigns.insert(0, result);
        });
      } else if (result == true) {
        _loadCampaigns(reset: true);
      }
    });
  }

  void _openCampaignDetail(Map<String, dynamic> campaign) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => CampaignDetailScreen(
          campaignId: campaign['campaign_id'] as int,
          communityId: widget.communityId,
        ),
      ),
    )
        .then((result) {
      if (result == true) {
        _loadCampaigns(reset: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          'Campaign Donasi',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: widget.isMember
          ? FloatingActionButton.extended(
              onPressed: _openCreateCampaign,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Buat Campaign',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _loadCampaigns(reset: true),
        child: _isLoading
            ? _buildShimmerLoading()
            : CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Semua',
                              selected: _selectedFilter == 'all',
                              onTap: () {
                                setState(() => _selectedFilter = 'all');
                                _loadCampaigns(reset: true);
                              },
                            ),
                            _FilterChip(
                              label: 'Aktif',
                              selected: _selectedFilter == 'active',
                              onTap: () {
                                setState(() => _selectedFilter = 'active');
                                _loadCampaigns(reset: true);
                              },
                            ),
                            if (widget.canManage)
                              _FilterChip(
                                label: 'Menunggu Persetujuan',
                                selected: _selectedFilter == 'pending_approval',
                                onTap: () {
                                  setState(() =>
                                      _selectedFilter = 'pending_approval');
                                  _loadCampaigns(reset: true);
                                },
                              ),
                            _FilterChip(
                              label: 'Selesai',
                              selected: _selectedFilter == 'completed',
                              onTap: () {
                                setState(() => _selectedFilter = 'completed');
                                _loadCampaigns(reset: true);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    SliverToBoxAdapter(child: _buildErrorState())
                  else if (_campaigns.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index >= _campaigns.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            return _CampaignCard(
                              campaign: _campaigns[index],
                              onTap: () =>
                                  _openCampaignDetail(_campaigns[index]),
                            );
                          },
                          childCount: _campaigns.length + (_hasMore ? 1 : 0),
                        ),
                      ),
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
                ],
              ),
      ),
    );
  }

  // ============ SHIMMER LOADING ============
  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      enabled: true,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            sliver: SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildShimmerFilterChip(width: 70),
                    const SizedBox(width: 6),
                    _buildShimmerFilterChip(width: 60),
                    const SizedBox(width: 6),
                    _buildShimmerFilterChip(width: 120),
                    const SizedBox(width: 6),
                    _buildShimmerFilterChip(width: 70),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildShimmerCampaignCard(),
                  );
                },
                childCount: 4,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildShimmerFilterChip({required double width}) {
    return Container(
      height: 32,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildShimmerCampaignCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badges
            Row(
              children: [
                _buildShimmerBadge(width: 90),
                const SizedBox(width: 6),
                _buildShimmerBadge(width: 60),
                const SizedBox(width: 6),
                _buildShimmerBadge(width: 70),
              ],
            ),
            const SizedBox(height: 8),
            // Title
            Container(
              height: 18,
              width: double.infinity,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 4),
            // Description
            Container(
              height: 14,
              width: double.infinity,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 4),
            Container(
              height: 14,
              width: 200,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 10),
            // Progress bar (money type)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      height: 16,
                      width: 80,
                      color: Colors.grey.shade300,
                    ),
                    Container(
                      height: 14,
                      width: 40,
                      color: Colors.grey.shade300,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 4,
                  width: double.infinity,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 2),
                Container(
                  height: 12,
                  width: 100,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Stats
            Row(
              children: [
                _buildShimmerStatChip(width: 100),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerBadge({required double width}) {
    return Container(
      height: 22,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildShimmerStatChip({required double width}) {
    return Container(
      height: 26,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  // ============ ERROR & EMPTY STATE ============
  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _loadCampaigns(reset: true),
              child: Text(
                'Coba Lagi',
                style: GoogleFonts.poppins(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.favorite_border, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              widget.isMember
                  ? 'Belum ada campaign donasi di komunitas ini'
                  : 'Gabung komunitas untuk membuat campaign donasi',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.isMember) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _openCreateCampaign,
                icon: Icon(Icons.add, size: 16, color: AppColors.primary),
                label: Text(
                  'Buat Campaign Donasi',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Parse angka dari dynamic dengan aman. Backend kadang mengirim field
/// numerik (mis. target_amount, collected_amount, progress) sebagai String
/// (umum terjadi pada tipe Decimal), jadi jangan pernah hard-cast `as double`.
double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

class _CampaignCard extends StatelessWidget {
  final Map<String, dynamic> campaign;
  final VoidCallback onTap;

  const _CampaignCard({
    required this.campaign,
    required this.onTap,
  });

  String _getApprovalStatusLabel(String? approvalStatus) {
    switch (approvalStatus) {
      case 'pending':
        return '⏳ Menunggu Persetujuan';
      case 'approved':
        return '✅ Disetujui';
      case 'rejected':
        return '❌ Ditolak';
      default:
        return '';
    }
  }

  Color _getApprovalStatusColor(String? approvalStatus) {
    switch (approvalStatus) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'active':
        return 'Aktif';
      case 'pending':
        return 'Menunggu Persetujuan';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
      case 'rejected':
        return 'Dibatalkan';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getDonationTypeLabel(String? type) {
    switch (type) {
      case 'money':
        return '💰 Uang';
      case 'goods':
        return '📦 Barang';
      case 'volunteer':
        return '🤝 Relawan';
      default:
        return type ?? 'Unknown';
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final title = campaign['title'] as String? ?? 'Tanpa Judul';
    final description = campaign['description'] as String?;
    final donationType = campaign['donation_type'] as String?;
    final status = campaign['status'] as String?;
    final targetAmount = _parseDouble(campaign['target_amount']);
    final collectedAmount = _parseDouble(campaign['collected_amount']) ?? 0;
    final progress = _parseDouble(campaign['progress']) ?? 0;
    final totalDonors = _parseInt(campaign['total_donors']) ?? 0;
    final totalVolunteers = _parseInt(campaign['total_volunteers']) ?? 0;
    final approvalStatus = campaign['approval_status'] as String? ?? 'approved';
    final isPending = approvalStatus == 'pending';
    final isRejected = approvalStatus == 'rejected';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // ✅ Tampilkan status approval jika pending atau rejected
                  if (isPending || isRejected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _getApprovalStatusColor(approvalStatus)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getApprovalStatusLabel(approvalStatus),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getApprovalStatusColor(approvalStatus),
                        ),
                      ),
                    ),
                  if (isPending || isRejected) const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getStatusLabel(status),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getDonationTypeLabel(donationType),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),

              // Progress
              if (donationType == 'money' && targetAmount != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatCurrency(collectedAmount),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          '${progress.round()}%',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (progress / 100).clamp(0, 1).toDouble(),
                        backgroundColor: Colors.grey.shade200,
                        color: AppColors.primary,
                        minHeight: 4,
                      ),
                    ),
                    Text(
                      'Target: ${_formatCurrency(targetAmount)}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],

              // Stats
              const SizedBox(height: 10),
              Row(
                children: [
                  if (donationType == 'money' || donationType == 'goods')
                    _StatChip(
                      icon: Icons.people_outline,
                      label: '$totalDonors Donatur',
                    ),
                  if (donationType == 'volunteer')
                    _StatChip(
                      icon: Icons.handshake_outlined,
                      label: '$totalVolunteers Relawan',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
