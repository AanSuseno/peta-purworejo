// widgets/community_detail/community_shimmer_widget.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class CommunityShimmerWidget extends StatelessWidget {
  final int postCount;

  const CommunityShimmerWidget({super.key, this.postCount = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      enabled: true,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Banner shimmer
                Container(
                  height: 160,
                  width: double.infinity,
                  color: Colors.grey.shade300,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      // Nama komunitas
                      Container(
                        height: 22,
                        width: 180,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 6),
                      // Founder
                      Container(
                        height: 14,
                        width: 140,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 14),
                      // Tags
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildShimmerTag(width: 80),
                          _buildShimmerTag(width: 100),
                          _buildShimmerTag(width: 70),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Statistik
                      Container(
                        height: 70,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Deskripsi
                      Container(
                        height: 18,
                        width: 120,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 12,
                        width: double.infinity,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 12,
                        width: 200,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 24),
                      // Kontak
                      Container(
                        height: 18,
                        width: 80,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 100,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Tombol swipe
                      Container(
                        height: 52,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Shimmer untuk postingan
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Container(
                    height: 20,
                    width: 140,
                    color: Colors.grey.shade300,
                  ),
                  const Spacer(),
                  Container(
                    height: 16,
                    width: 80,
                    color: Colors.grey.shade300,
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Divider(height: 12, thickness: 1),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildShimmerPostCard(),
                  );
                },
                childCount: postCount,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildShimmerTag({required double width}) {
    return Container(
      height: 24,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildShimmerPostCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 120,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 10,
                        width: 80,
                        color: Colors.grey.shade300,
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 10,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 16,
              width: double.infinity,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 16,
              width: 200,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            width: double.infinity,
            color: Colors.grey.shade300,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  height: 14,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
                const Spacer(),
                Container(
                  height: 14,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(width: 16),
                Container(
                  height: 14,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Shimmer untuk hanya menampilkan postingan (saat detail sudah dimuat)
class CommunityPostsShimmerWidget extends StatelessWidget {
  final int postCount;

  const CommunityPostsShimmerWidget({super.key, this.postCount = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      enabled: true,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Container(
                    height: 20,
                    width: 140,
                    color: Colors.grey.shade300,
                  ),
                  const Spacer(),
                  Container(
                    height: 16,
                    width: 80,
                    color: Colors.grey.shade300,
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Divider(height: 8, thickness: 1),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildShimmerPostCard(),
                  );
                },
                childCount: postCount,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildShimmerPostCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 120,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 10,
                        width: 80,
                        color: Colors.grey.shade300,
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 10,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 16,
              width: double.infinity,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 16,
              width: 200,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            width: double.infinity,
            color: Colors.grey.shade300,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  height: 14,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
                const Spacer(),
                Container(
                  height: 14,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(width: 16),
                Container(
                  height: 14,
                  width: 60,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}