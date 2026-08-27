import prisma from "../../lib/prisma.js";

export const toggleLikePost = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const post = await prisma.posts.findUnique({
            where: { post_id: parseInt(id) }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Postingan tidak ditemukan"
            });
        }

        // Cek apakah sudah like
        const existingLike = await prisma.post_likes.findFirst({
            where: {
                post_id: parseInt(id),
                user_id: userId
            }
        });

        let isLiked = false;

        if (existingLike) {
            // Unlike
            await prisma.post_likes.delete({
                where: {
                    like_id: existingLike.like_id
                }
            });
            await prisma.posts.update({
                where: { post_id: parseInt(id) },
                data: {
                    total_likes: {
                        decrement: 1
                    }
                }
            });
            isLiked = false;
        } else {
            // Like
            await prisma.post_likes.create({
                data: {
                    post_id: parseInt(id),
                    user_id: userId,
                    created_at: new Date()
                }
            });
            await prisma.posts.update({
                where: { post_id: parseInt(id) },
                data: {
                    total_likes: {
                        increment: 1
                    }
                }
            });
            isLiked = true;
        }

        // Get updated post
        const updatedPost = await prisma.posts.findUnique({
            where: { post_id: parseInt(id) },
            select: {
                post_id: true,
                total_likes: true
            }
        });

        return res.json({
            success: true,
            message: isLiked ? "Berhasil like" : "Berhasil unlike",
            data: {
                post_id: parseInt(id),
                total_likes: updatedPost.total_likes,
                is_liked: isLiked
            }
        });

    } catch (error) {
        console.error("Toggle Like Post Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal like/unlike postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};