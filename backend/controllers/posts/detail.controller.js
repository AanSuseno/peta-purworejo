import prisma from "../../lib/prisma.js";


export const getPostById = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const post = await prisma.posts.findUnique({
            where: {
                post_id: parseInt(id)
            },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        profile_picture: true,
                        email: true
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
                post_likes: {
                    where: {
                        user_id: userId
                    },
                    select: {
                        user_id: true
                    }
                },
                post_comments: {
                    include: {
                        users: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true
                            }
                        }
                    },
                    orderBy: {
                        created_at: 'desc'
                    },
                    take: 5
                },
                event_participants: {
                    where: {
                        user_id: userId
                    },
                    select: {
                        participant_id: true,
                        status: true
                    }
                },
                _count: {
                    select: {
                        post_likes: true,
                        post_comments: true,
                        event_participants: true
                    }
                }
            }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Postingan tidak ditemukan"
            });
        }

        // Cek apakah user sudah like
        const isLiked = post.post_likes.length > 0;
        const isParticipant = post.event_participants.length > 0;
        const participantStatus = isParticipant ? post.event_participants[0].status : null;

        const formattedPost = {
            ...post,
            likes_count: post._count.post_likes,
            comments_count: post._count.post_comments,
            participants_count: post._count.event_participants,
            is_liked: isLiked,
            is_participant: isParticipant,
            participant_status: participantStatus,
            is_event: post.post_type === 'event',
            event_start_time: post.event_start_time,
            event_end_time: post.event_end_time,
            _count: undefined,
            post_likes: undefined,
            event_participants: undefined
        };

        return res.json({
            success: true,
            data: formattedPost
        });

    } catch (error) {
        console.error("Get Post By ID Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};