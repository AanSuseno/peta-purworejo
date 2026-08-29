export async function addCommunityScore(
  prisma,
  {
    communityId,
    score,
    scoreType,
    description = null,
    referenceId = null,
  }
) {
  if (!communityId) {
    throw new Error('communityId wajib diisi');
  }

  if (!Number.isInteger(score) || score === 0) {
    throw new Error('score harus berupa integer dan tidak boleh 0');
  }

  if (!scoreType) {
    throw new Error('scoreType wajib diisi');
  }

  return prisma.$transaction(async (tx) => {
    // Pastikan komunitas ada
    const community = await tx.communities.findUnique({
      where: {
        community_id: communityId,
      },
      select: {
        community_id: true,
        total_score: true,
      },
    });

    if (!community) {
      throw new Error('Komunitas tidak ditemukan');
    }

    // Simpan histori perubahan skor
    const scoreHistory = await tx.community_scores.create({
      data: {
        community_id: communityId,
        score,
        score_type: scoreType,
        description,
        reference_id: referenceId,
      },
    });

    // Update total score
    const updatedCommunity = await tx.communities.update({
      where: {
        community_id: communityId,
      },
      data: {
        total_score: {
          increment: score,
        },
      },
      select: {
        community_id: true,
        total_score: true,
      },
    });

    return {
      scoreHistory,
      community: updatedCommunity,
    };
  });
}

/**
 * Mengambil total skor komunitas.
 */
export async function getCommunityScore(prisma, communityId) {
  const community = await prisma.communities.findUnique({
    where: {
      community_id: communityId,
    },
    select: {
      community_id: true,
      total_score: true,
    },
  });

  if (!community) {
    throw new Error('Komunitas tidak ditemukan');
  }

  return community.total_score;
}

/**
 * Mengambil riwayat skor komunitas.
 */
export async function getCommunityScoreHistory(
  prisma,
  communityId,
  {
    page = 1,
    limit = 20,
    scoreType = null,
  } = {}
) {
  const safePage = Math.max(1, Number(page) || 1);
  const safeLimit = Math.min(
    100,
    Math.max(1, Number(limit) || 20)
  );

  const skip = (safePage - 1) * safeLimit;

  const where = {
    community_id: communityId,
  };

  if (scoreType) {
    where.score_type = scoreType;
  }

  const [data, total] = await prisma.$transaction([
    prisma.community_scores.findMany({
      where,
      orderBy: {
        created_at: 'desc',
      },
      skip,
      take: safeLimit,
    }),

    prisma.community_scores.count({
      where,
    }),
  ]);

  return {
    data,
    pagination: {
      page: safePage,
      limit: safeLimit,
      total,
      totalPages: Math.ceil(total / safeLimit),
    },
  };
}

/**
 * Mengambil statistik skor berdasarkan jenis aktivitas.
 */
export async function getCommunityScoreSummary(prisma, communityId) {
  const summary = await prisma.community_scores.groupBy({
    by: ['score_type'],
    where: {
      community_id: communityId,
    },
    _sum: {
      score: true,
    },
    _count: {
      score_id: true,
    },
  });

  return summary.map((item) => ({
    scoreType: item.score_type,
    totalScore: item._sum.score || 0,
    totalActivities: item._count.score_id,
  }));
}

export async function getTopCommunitiesByScore(prisma) {
  const communities = await prisma.communities.findMany({
    where: {
      is_active: true,
    },
    select: {
      community_id: true,
      community_name: true,
      community_slug: true,
      logo: true,
      total_score: true,
      total_members: true,
    },
    orderBy: {
      total_score: 'desc',
    },
    take: 20,
  });

  return communities.map((community, index) => ({
    rank: index + 1,
    ...community,
  }));
}