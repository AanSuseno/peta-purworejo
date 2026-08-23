// controllers/posts.controller.js
import prisma from "../lib/prisma.js";
import fs from "fs";
import path from "path";

export const getCommunityPosts = async (req, res) => {
    try {
        const { id } = req.params;
        const { 
            page = 1, 
            limit = 10, 
            post_type,
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

        // Build sorting
        let orderBy = {};
        if (sort_by === 'created_at' || sort_by === 'total_likes' || sort_by === 'total_comments') {
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
                    post_media: {
                        orderBy: {
                            sort_order: 'asc'
                        }
                    },
                    _count: {
                        select: {
                            post_likes: true,
                            post_comments: true
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
        const { page = 1, limit = 10 } = req.query;

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

        const [posts, total] = await Promise.all([
            prisma.posts.findMany({
                where: {
                    community_id: { in: communityIds },
                    status: 'active'
                },
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
                            post_comments: true
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
                where: {
                    community_id: { in: communityIds },
                    status: 'active'
                }
            })
        ]);

        const formattedPosts = posts.map(post => ({
            ...post,
            likes_count: post._count.post_likes,
            comments_count: post._count.post_comments,
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
                _count: {
                    select: {
                        post_likes: true,
                        post_comments: true
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

        const formattedPost = {
            ...post,
            likes_count: post._count.post_likes,
            comments_count: post._count.post_comments,
            is_liked: isLiked,
            _count: undefined,
            post_likes: undefined
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

export const createPost = async (req, res) => {
    try {
        const { id } = req.params; // community_id
        const userId = req.user.id;
        const { title, content, post_type = 'activity' } = req.body;

        // Validasi
        if (!title || title.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Judul postingan wajib diisi"
            });
        }

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

        if (!community.is_active) {
            return res.status(400).json({
                success: false,
                message: "Komunitas tidak aktif"
            });
        }

        // Cek apakah user adalah member aktif
        const membership = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId,
                status: 'active'
            }
        });

        if (!membership) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi anggota komunitas untuk membuat postingan"
            });
        }

        // Buat post
        const post = await prisma.posts.create({
            data: {
                community_id: parseInt(id),
                author_id: userId,
                title: title.trim(),
                content: content || null,
                post_type: post_type,
                is_pinned: false,
                total_likes: 0,
                total_comments: 0,
                status: 'active',
                created_at: new Date(),
                updated_at: new Date()
            },
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
                        community_slug: true
                    }
                }
            }
        });

        return res.status(201).json({
            success: true,
            message: "Postingan berhasil dibuat",
            data: post
        });

    } catch (error) {
        console.error("Create Post Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membuat postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const createPostWithMedia = async (req, res) => {
    try {
        const { id } = req.params; // community_id
        const userId = req.user.id;
        const { title, content, post_type = 'activity', is_pinned = false } = req.body;

        // Validasi
        if (!title || title.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Judul postingan wajib diisi"
            });
        }

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

        if (!community.is_active) {
            return res.status(400).json({
                success: false,
                message: "Komunitas tidak aktif"
            });
        }

        // Cek member
        const membership = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId,
                status: 'active'
            }
        });

        if (!membership) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi anggota komunitas untuk membuat postingan"
            });
        }

        // Buat post
        const post = await prisma.posts.create({
            data: {
                community_id: parseInt(id),
                author_id: userId,
                title: title.trim(),
                content: content || null,
                post_type: post_type,
                is_pinned: is_pinned === 'true' || is_pinned === true,
                total_likes: 0,
                total_comments: 0,
                status: 'active',
                created_at: new Date(),
                updated_at: new Date()
            }
        });

        // Proses media jika ada
        let mediaData = [];
        if (req.files && req.files.length > 0) {
            const mediaPromises = req.files.map((file, index) => {
                const mediaType = file.mimetype.startsWith('video') ? 'video' : 'image';
                return prisma.post_media.create({
                    data: {
                        post_id: post.post_id,
                        media_type: mediaType,
                        media_url: `/uploads/posts/${file.filename}`,
                        caption: null,
                        is_cover: index === 0,
                        sort_order: index,
                        created_at: new Date()
                    }
                });
            });
            mediaData = await Promise.all(mediaPromises);
        }

        // Ambil post dengan relasi
        const createdPost = await prisma.posts.findUnique({
            where: {
                post_id: post.post_id
            },
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
                        community_slug: true
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
                        post_comments: true
                    }
                }
            }
        });

        return res.status(201).json({
            success: true,
            message: "Postingan berhasil dibuat",
            data: {
                ...createdPost,
                likes_count: createdPost._count.post_likes,
                comments_count: createdPost._count.post_comments,
                _count: undefined
            },
            media: mediaData
        });

    } catch (error) {
        console.error("Create Post With Media Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membuat postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const updatePost = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const { title, content, post_type, is_pinned } = req.body;

        const post = await prisma.posts.findUnique({
            where: { post_id: parseInt(id) },
            include: {
                communities: true
            }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Postingan tidak ditemukan"
            });
        }

        // Cek permission: author atau admin komunitas atau system admin
        const isAuthor = post.author_id === userId;
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';
        
        let isCommunityAdmin = false;
        if (!isAuthor && !isSystemAdmin) {
            const admin = await prisma.community_admins.findFirst({
                where: {
                    community_id: post.community_id,
                    user_id: userId
                }
            });
            isCommunityAdmin = !!admin;
        }

        if (!isAuthor && !isCommunityAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate postingan ini"
            });
        }

        // Siapkan data update
        const updateData = {
            title: title ? title.trim() : undefined,
            content: content !== undefined ? content : undefined,
            post_type: post_type || undefined,
            updated_at: new Date()
        };

        // Hanya admin/author yang bisa pin post
        if (is_pinned !== undefined && (isCommunityAdmin || isSystemAdmin)) {
            updateData.is_pinned = is_pinned;
        }

        const updatedPost = await prisma.posts.update({
            where: {
                post_id: parseInt(id)
            },
            data: updateData,
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
                        community_slug: true
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
                        post_comments: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Postingan berhasil diperbarui",
            data: {
                ...updatedPost,
                likes_count: updatedPost._count.post_likes,
                comments_count: updatedPost._count.post_comments,
                _count: undefined
            }
        });

    } catch (error) {
        console.error("Update Post Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const deletePost = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const post = await prisma.posts.findUnique({
            where: { post_id: parseInt(id) },
            include: {
                communities: true,
                post_media: true
            }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Postingan tidak ditemukan"
            });
        }

        // Cek permission
        const isAuthor = post.author_id === userId;
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';
        
        let isCommunityAdmin = false;
        if (!isAuthor && !isSystemAdmin) {
            const admin = await prisma.community_admins.findFirst({
                where: {
                    community_id: post.community_id,
                    user_id: userId
                }
            });
            isCommunityAdmin = !!admin;
        }

        if (!isAuthor && !isCommunityAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk menghapus postingan ini"
            });
        }

        // Hapus media files
        if (post.post_media && post.post_media.length > 0) {
            post.post_media.forEach(media => {
                const filePath = path.join(process.cwd(), media.media_url);
                if (fs.existsSync(filePath)) {
                    fs.unlinkSync(filePath);
                }
            });
        }

        // Soft delete - set status = 'hidden'
        await prisma.posts.update({
            where: {
                post_id: parseInt(id)
            },
            data: {
                status: 'hidden',
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Postingan berhasil dihapus"
        });

    } catch (error) {
        console.error("Delete Post Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus postingan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

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

        return res.status(201).json({
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