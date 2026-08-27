import prisma from "../../lib/prisma.js";

export const getCommunityPosts = async (req, res) => {
    try {
        const { id } = req.params;
        const {
            page = 1,
            limit = 10,
            post_type,
            visibility,
            sort_by = 'created_at',
            sort_order = 'desc'
        } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        // Cek community exists
        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        // Build filter
        const where = {
            community_id: parseInt(id),
            status: 'active'
        };

        if (post_type) {
            where.post_type = post_type;
        }

        if (visibility) {
            where.visibility = visibility;
        }

        // Build sorting
        let orderBy = {};
        if (['created_at', 'total_likes', 'total_comments', 'event_date'].includes(sort_by)) {
            orderBy[sort_by] = sort_order;
        } else {
            orderBy = { created_at: 'desc' };
        }

        const [posts, total] = await Promise.all([
            prisma.posts.findMany({
                where,
                include: {
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            profile_picture: true
                        }
                    },
                    communities: {
                        select: {
                            community_id: true,
                            community_name: true,
                            community_slug: true,
                            logo: true
                        }
                    },
                    post_media: {
                        orderBy: {
                            sort_order: 'asc'
                        }
                    },
                    _count: {
                        select: {
                            post_likes: true,
                            post_comments: true,
                            event_participants: true
                        }
                    }
                },
                orderBy,
                skip,
                take
            }),
            prisma.posts.count({ where })
        ]);

        // Format response
        const formattedPosts = posts.map(post => ({
            ...post,
            likes_count: post._count.post_likes,
            comments_count: post._count.post_comments,
            participants_count: post._count.event_participants,
            is_event: post.post_type === 'event',
            is_liked: false, // Default untuk list
            is_participant: false, // Default untuk list
            event_start_time: post.event_start_time, // Sudah string dari database
            event_end_time: post.event_end_time, // Sudah string dari database
            _count: undefined
        }));

        return res.json({
            success: true,
            data: formattedPosts,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Community Posts Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const getFeedPosts = async (req, res) => {
    try {
        const userId = req.user.id;
        const { page = 1, limit = 10, post_type } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        // Dapatkan komunitas yang diikuti user
        const userCommunities = await prisma.community_members.findMany({
            where: {
                user_id: userId,
                status: 'active'
            },
            select: {
                community_id: true
            }
        });

        const communityIds = userCommunities.map(m => m.community_id);

        if (communityIds.length === 0) {
            return res.json({
                success: true,
                data: [],
                message: "Anda belum bergabung dengan komunitas manapun",
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total: 0,
                    totalPages: 0
                }
            });
        }

        const where = {
            community_id: { in: communityIds },
            status: 'active',
            visibility: 'public'
        };

        if (post_type) {
            where.post_type = post_type;
        }

        const [posts, total] = await Promise.all([
            prisma.posts.findMany({
                where,
                include: {
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            profile_picture: true
                        }
                    },
                    communities: {
                        select: {
                            community_id: true,
                            community_name: true,
                            community_slug: true,
                            logo: true
                        }
                    },
                    post_media: {
                        orderBy: {
                            sort_order: 'asc'
                        }
                    },
                    _count: {
                        select: {
                            post_likes: true,
                            post_comments: true,
                            event_participants: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'desc'
                },
                skip,
                take
            }),
            prisma.posts.count({ where })
        ]);

        const formattedPosts = posts.map(post => ({
            ...post,
            likes_count: post._count.post_likes,
            comments_count: post._count.post_comments,
            participants_count: post._count.event_participants,
            is_event: post.post_type === 'event',
            is_liked: false,
            is_participant: false,
            event_start_time: post.event_start_time,
            event_end_time: post.event_end_time,
            _count: undefined
        }));

        return res.json({
            success: true,
            data: formattedPosts,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Feed Posts Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil feed",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};