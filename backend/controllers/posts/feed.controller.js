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

        // Cek apakah user adalah member
        const userId = req.user?.id;
        let isMember = false;

        if (userId) {
            const membership = await prisma.community_members.findFirst({
                where: {
                    community_id: parseInt(id),
                    user_id: userId,
                    status: 'active'
                }
            });
            isMember = !!membership;
        }

        // Build filter
        const where = {
            community_id: parseInt(id),
            status: 'active'
        };

        // Jika bukan member, hanya tampilkan postingan public
        if (!isMember) {
            where.visibility = 'public';
        } else if (visibility) {
            // Jika member dan ada filter visibility
            where.visibility = visibility;
        }

        if (post_type) {
            where.post_type = post_type;
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
            is_liked: false,
            is_participant: false,
            event_start_time: post.event_start_time,
            event_end_time: post.event_end_time,
            is_public: post.visibility === 'public', // Tambahkan info visibility
            _count: undefined
        }));

        return res.json({
            success: true,
            data: formattedPosts,
            isMember: isMember, // Kirim status member ke frontend
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
        const { 
            page = 1, 
            limit = 10, 
            post_type, 
            search, 
            category_id 
        } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {
            status: 'active',
            visibility: 'public'
        };

        if (post_type) {
            where.post_type = post_type;
        }

        if (category_id) {
            const categoryIdInt = parseInt(category_id);

            if (!isNaN(categoryIdInt)) {
                where.communities = {
                    category_id: categoryIdInt
                };
            }
        }

        if (search) {
            where.OR = [
                {
                    title: {
                        contains: search,
                        mode: 'insensitive'
                    }
                },
                {
                    content: {
                        contains: search,
                        mode: 'insensitive'
                    }
                }
            ];
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
                            logo: true,
                            category_id: true
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

            prisma.posts.count({
                where
            })
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

            is_public: post.visibility === 'public',

            _count: undefined
        }));

        return res.json({
            success: true,
            data: formattedPosts,

            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(
                    total / parseInt(limit)
                )
            }
        });

    } catch (error) {
        console.error("Get Feed Posts Error:", error);

        return res.status(500).json({
            success: false,
            message: "Gagal mengambil feed",
            error:
                process.env.NODE_ENV === 'development'
                    ? error.message
                    : undefined
        });
    }
};