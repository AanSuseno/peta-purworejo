import prisma from "../../lib/prisma.js";

export const getCommentsByPost = async (req, res) => {
    try {
        const { id } = req.params;
        const { page = 1, limit = 20 } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const post = await prisma.posts.findUnique({
            where: { post_id: parseInt(id) }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Postingan tidak ditemukan"
            });
        }

        const [comments, total] = await Promise.all([
            prisma.post_comments.findMany({
                where: {
                    post_id: parseInt(id)
                },
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
                skip,
                take
            }),
            prisma.post_comments.count({
                where: {
                    post_id: parseInt(id)
                }
            })
        ]);

        return res.json({
            success: true,
            data: comments,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Comments By Post Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil komentar",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const createComment = async (req, res) => {
    try {
        const { id } = req.params; // post_id
        const userId = req.user.id;
        const { content } = req.body;

        if (!content || content.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Komentar wajib diisi"
            });
        }

        const post = await prisma.posts.findUnique({
            where: { post_id: parseInt(id) }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Postingan tidak ditemukan"
            });
        }

        // Cek apakah user adalah member komunitas
        const membership = await prisma.community_members.findFirst({
            where: {
                community_id: post.community_id,
                user_id: userId,
                status: 'active'
            }
        });

        if (!membership) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi anggota komunitas untuk berkomentar"
            });
        }

        // Buat comment
        const comment = await prisma.post_comments.create({
            data: {
                post_id: parseInt(id),
                user_id: userId,
                content: content.trim(),
                created_at: new Date()
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

        // Update total_comments di post
        await prisma.posts.update({
            where: { post_id: parseInt(id) },
            data: {
                total_comments: {
                    increment: 1
                }
            }
        });

        return res.status(200).json({
            success: true,
            message: "Komentar berhasil ditambahkan",
            data: comment
        });

    } catch (error) {
        console.error("Create Comment Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menambahkan komentar",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const updateComment = async (req, res) => {
    try {
        const { id } = req.params; // comment_id
        const userId = req.user.id;
        const { content } = req.body;

        if (!content || content.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Komentar wajib diisi"
            });
        }

        const comment = await prisma.post_comments.findUnique({
            where: { comment_id: parseInt(id) },
            include: {
                posts: true
            }
        });

        if (!comment) {
            return res.status(404).json({
                success: false,
                message: "Komentar tidak ditemukan"
            });
        }

        // Cek permission: author atau admin komunitas
        const isAuthor = comment.user_id === userId;
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        let isCommunityAdmin = false;
        if (!isAuthor && !isSystemAdmin) {
            const admin = await prisma.community_admins.findFirst({
                where: {
                    community_id: comment.posts.community_id,
                    user_id: userId
                }
            });
            isCommunityAdmin = !!admin;
        }

        if (!isAuthor && !isCommunityAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate komentar ini"
            });
        }

        const updatedComment = await prisma.post_comments.update({
            where: {
                comment_id: parseInt(id)
            },
            data: {
                content: content.trim()
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

        return res.json({
            success: true,
            message: "Komentar berhasil diperbarui",
            data: updatedComment
        });

    } catch (error) {
        console.error("Update Comment Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui komentar",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const deleteComment = async (req, res) => {
    try {
        const { id } = req.params; // comment_id
        const userId = req.user.id;

        const comment = await prisma.post_comments.findUnique({
            where: { comment_id: parseInt(id) },
            include: {
                posts: true
            }
        });

        if (!comment) {
            return res.status(404).json({
                success: false,
                message: "Komentar tidak ditemukan"
            });
        }

        // Cek permission
        const isAuthor = comment.user_id === userId;
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        let isCommunityAdmin = false;
        if (!isAuthor && !isSystemAdmin) {
            const admin = await prisma.community_admins.findFirst({
                where: {
                    community_id: comment.posts.community_id,
                    user_id: userId
                }
            });
            isCommunityAdmin = !!admin;
        }

        if (!isAuthor && !isCommunityAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk menghapus komentar ini"
            });
        }

        await prisma.post_comments.delete({
            where: {
                comment_id: parseInt(id)
            }
        });

        // Update total_comments di post
        await prisma.posts.update({
            where: { post_id: comment.post_id },
            data: {
                total_comments: {
                    decrement: 1
                }
            }
        });

        return res.json({
            success: true,
            message: "Komentar berhasil dihapus"
        });

    } catch (error) {
        console.error("Delete Comment Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus komentar",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};