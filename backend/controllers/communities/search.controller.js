import prisma from "../../lib/prisma.js";

export const searchCommunities = async (req, res) => {
    try {
        const userId = req.user.id;
        const { q, category_id, kecamatan } = req.query;

        if (!q || q.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Parameter pencarian 'q' wajib diisi"
            });
        }

        const where = {
            is_active: true,
            OR: [
                { community_name: { contains: q.trim(), mode: 'insensitive' } },
                { description: { contains: q.trim(), mode: 'insensitive' } }
            ]
        };

        if (category_id) {
            where.category_id = parseInt(category_id);
        }

        if (kecamatan) {
            where.kecamatan = { contains: kecamatan, mode: 'insensitive' };
        }

        const communities = await prisma.communities.findMany({
            where,
            include: {
                categories: {
                    select: {
                        category_id: true,
                        category_name: true,
                        category_icon: true
                    }
                },
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        profile_picture: true
                    }
                },
                _count: {
                    select: {
                        community_members: {
                            where: { status: 'active' }
                        }
                    }
                }
            },
            orderBy: {
                total_members: 'desc'
            }
        });

        const communityIds = communities.map(c => c.community_id);
        const myMemberships = communityIds.length > 0
            ? await prisma.community_members.findMany({
                where: {
                    community_id: { in: communityIds },
                    user_id: userId,
                    status: 'active'
                },
                select: { community_id: true }
            })
            : [];
        const joinedIds = new Set(myMemberships.map(m => m.community_id));

        const formattedCommunities = communities.map(community => ({
            ...community,
            member_count: community._count.community_members,
            _count: undefined,
            is_member: joinedIds.has(community.community_id),
            is_founder: community.founder_id === userId
        }));

        return res.json({
            success: true,
            data: formattedCommunities,
            total: formattedCommunities.length,
            query: q.trim()
        });

    } catch (error) {
        console.error("Search Communities Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mencari komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const searchCommunityMembers = async (req, res) => {
    try {
        const { id } = req.params;
        const { q } = req.query;
        
        if (!q || q.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Parameter pencarian 'q' wajib diisi"
            });
        }

        // Cek komunitas ada
        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        // Cari member yang aktif dengan nama/email mengandung query
        const members = await prisma.community_members.findMany({
            where: {
                community_id: parseInt(id),
                status: 'active',
                OR: [
                    { users: { full_name: { contains: q.trim(), mode: 'insensitive' } } },
                    { users: { email: { contains: q.trim(), mode: 'insensitive' } } }
                ]
            },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true,
                        is_verified: true
                    }
                }
            },
            take: 20
        });

        return res.json({
            success: true,
            data: members.map(m => ({
                ...m.users,
                member_id: m.member_id,
                join_date: m.join_date
            })),
            total: members.length
        });
    } catch (error) {
        console.error("Search Community Members Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mencari member komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};