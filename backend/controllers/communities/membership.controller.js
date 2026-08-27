import prisma from "../../lib/prisma.js";

export const getCommunityMembers = async (req, res) => {
    try {
        const { id } = req.params;
        const { page = 1, limit = 20, status = 'active' } = req.query;

        // Pastikan page dan limit adalah integer
        const pageNum = Math.max(1, parseInt(page) || 1);
        const limitNum = Math.min(100, parseInt(limit) || 20);
        const skip = (pageNum - 1) * limitNum;

        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        const [members, total] = await Promise.all([
            prisma.community_members.findMany({
                where: {
                    community_id: parseInt(id),
                    status: status
                },
                include: {
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            profile_picture: true,
                            email: true,
                            bio: true,
                            kecamatan: true,
                            is_verified: true
                        }
                    }
                },
                orderBy: {
                    join_date: 'desc'
                },
                skip: skip,
                take: limitNum
            }),
            prisma.community_members.count({
                where: {
                    community_id: parseInt(id),
                    status: status
                }
            })
        ]);

        return res.json({
            success: true,
            data: members.map(m => ({
                ...m,
                user: m.users // Alias users ke user untuk konsistensi
            })),
            pagination: {
                page: pageNum,
                limit: limitNum,
                total: total,
                totalPages: Math.ceil(total / limitNum)
            }
        });

    } catch (error) {
        console.error("❌ Get Community Members Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil anggota komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const joinCommunity = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        if (!community.is_active) {
            return res.status(400).json({
                success: false,
                message: "Komunitas tidak aktif"
            });
        }

        const existingMember = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });

        if (existingMember) {
            if (existingMember.status === 'active') {
                return res.status(400).json({
                    success: false,
                    message: "Anda sudah menjadi anggota komunitas ini"
                });
            }
            if (existingMember.status === 'pending') {
                return res.status(400).json({
                    success: false,
                    message: "Permintaan bergabung Anda sedang diproses"
                });
            }
        }

        const membership = await prisma.community_members.create({
            data: {
                community_id: parseInt(id),
                user_id: userId,
                status: 'active',
                join_date: new Date()
            },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        profile_picture: true
                    }
                }
            }
        });

        await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                total_members: {
                    increment: 1
                },
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Berhasil bergabung dengan komunitas",
            data: membership
        });

    } catch (error) {
        console.error("Join Community Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal bergabung dengan komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const leaveCommunity = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        if (community.founder_id === userId) {
            return res.status(400).json({
                success: false,
                message: "Anda adalah founder komunitas. Transfer kepemilikan terlebih dahulu sebelum keluar."
            });
        }

        const membership = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId,
                status: 'active'
            }
        });

        if (!membership) {
            return res.status(400).json({
                success: false,
                message: "Anda bukan anggota aktif komunitas ini"
            });
        }

        await prisma.community_members.delete({
            where: {
                member_id: membership.member_id
            }
        });

        await prisma.community_admins.deleteMany({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });

        await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                total_members: {
                    decrement: 1
                },
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Berhasil keluar dari komunitas"
        });

    } catch (error) {
        console.error("Leave Community Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal keluar dari komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};