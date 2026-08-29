import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../provider/auth_provider.dart';
import '../services/posts_service.dart';
import '../widgets/event_card.dart';

/// Halaman daftar event publik: cari, filter, scroll (infinite load),
/// daftar event, lihat detail event.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  final PostsService _service = PostsService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _events = [];
  final Set<int> _registeredEventIds = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  String _query = '';
  String? _statusFilter;

  final List<String> _statusOptions = ['all', 'upcoming', 'ongoing', 'past'];

  @override
  void initState() {
    super.initState();
    _loadEvents(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || _isLoading) return;
    if (_page >= _totalPages) return;

    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      _loadEvents();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value;
      _loadEvents(reset: true);
    });
  }

  Future<void> _loadEvents({bool reset = false}) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getToken();

    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Sesi tidak ditemukan, silakan login ulang';
      });
      return;
    }

    setState(() {
      if (reset) {
        _isLoading = true;
        _error = null;
      } else {
        _isLoadingMore = true;
      }
    });

    final nextPage = reset ? 1 : _page + 1;

    try {
      final result = await _service.fetchPublicEvents(
        token: token,
        page: nextPage,
        search: _query.isNotEmpty ? _query : null,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );

      if (!mounted) return;

      // Update registered event IDs from the events data
      final registeredIds = result.posts
          .where((e) => e['is_registered'] == true)
          .map((e) => e['post_id'] as int)
          .toSet();

      setState(() {
        if (reset) _events.clear();
        _events.addAll(result.posts);
        _page = result.page;
        _totalPages = result.totalPages;
        _registeredEventIds.addAll(registeredIds);
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (reset) _error = e.toString().replaceFirst('Exception: ', '');
      });
      if (!reset) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat lebih banyak: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _handleRegister(int eventId) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getToken();
    if (token == null) return;

    // Optimistic update
    setState(() {
      _registeredEventIds.add(eventId);
      _updateEventRegistration(eventId, true);
    });

    try {
      await _service.registerEvent(
        token: token,
        postId: eventId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berhasil mendaftar event'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Rollback on error
      setState(() {
        _registeredEventIds.remove(eventId);
        _updateEventRegistration(eventId, false);
      });
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelRegistration(int eventId) async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getToken();
    if (token == null) return;

    // Optimistic update
    setState(() {
      _registeredEventIds.remove(eventId);
      _updateEventRegistration(eventId, false);
    });

    try {
      await _service.cancelEventRegistration(
        token: token,
        postId: eventId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Berhasil membatalkan pendaftaran'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      // Rollback on error
      setState(() {
        _registeredEventIds.add(eventId);
        _updateEventRegistration(eventId, true);
      });
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _updateEventRegistration(int eventId, bool isRegistered) {
    final idx = _events.indexWhere((e) => e['post_id'] == eventId);
    if (idx != -1) {
      _events[idx] = {..._events[idx], 'is_registered': isRegistered};
      // Update participant count
      final current = _events[idx]['participants_count'] ?? 0;
      _events[idx] = {
        ..._events[idx],
        'participants_count': isRegistered ? current + 1 : current - 1,
      };
    }
  }

  bool _isRegistered(int eventId) {
    return _registeredEventIds.contains(eventId);
  }

  void _openEventDetail(Map<String, dynamic> event) {
    // Navigate to event detail screen
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (_) => EventDetailScreen(eventId: event['post_id'] as int),
    //   ),
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Event',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Filter button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _buildFilterDropdown(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _loadEvents(reset: true),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + kToolbarHeight + 4, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temukan event menarik di sekitarmu',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: GoogleFonts.poppins(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Cari nama atau lokasi event...',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade400,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.primary,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey.shade500,
                        onPressed: () {
                          _searchController.clear();
                          _query = '';
                          _loadEvents(reset: true);
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildShimmerLoading();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_events.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: _events.length + (_page < _totalPages ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index >= _events.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        return EventCard(
            event: _events[index],
            communityId: _events[index]['communities']['community_id']);
      },
    );
  }

  Widget _buildShimmerLoading() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        _buildShimmerCard(),
        const SizedBox(height: 14),
        _buildShimmerCard(longDescription: true),
        const SizedBox(height: 14),
        _buildShimmerCard(noDescription: true),
      ],
    );
  }

  Widget _buildShimmerCard({
    bool longDescription = false,
    bool noDescription = false,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      enabled: true,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              width: double.infinity,
              color: Colors.grey.shade300,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    children: [
                      Container(
                        height: 18,
                        width: 160 + (longDescription ? 30 : 0),
                        color: Colors.grey.shade300,
                      ),
                      const Spacer(),
                      Container(
                        height: 24,
                        width: 70,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Date & time
                  Container(
                    height: 12,
                    width: 120,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 12,
                    width: 100,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 8),
                  // Location
                  Container(
                    height: 12,
                    width: 140,
                    color: Colors.grey.shade300,
                  ),
                  if (!noDescription) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12,
                      width: longDescription ? 250 : 150,
                      color: Colors.grey.shade300,
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Button
                  Container(
                    height: 40,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _error ?? 'Terjadi kesalahan',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: () => _loadEvents(reset: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Coba Lagi', style: GoogleFonts.poppins()),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.event_busy_outlined,
          size: 48,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _query.isEmpty
                ? 'Belum ada event tersedia'
                : 'Tidak ada event untuk "$_query"',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ),
        if (_statusFilter != null && _statusFilter != 'all')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Status filter: ${_statusFilter}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
