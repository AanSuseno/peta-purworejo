import prisma from "../../lib/prisma.js";
import fs from "fs";
import path from "path";

export const createPost = async (req, res) => {
    try {
        const { id } = req.params; // community_id
        const userId = req.user.id;
        const {
            title,
            content,
            post_type = 'regular',
            visibility = 'public',
            // Event fields (optional)
            event_date,
            event_start_time,
            event_end_time,
            event_location,
            event_latitude,
            event_longitude,
            event_quota,
            event_registration_link
        } = req.body;

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

        // Validasi event fields jika post_type = event
        if (post_type === 'event' && !event_date) {
            return res.status(400).json({
                success: false,
                message: "Tanggal event wajib diisi untuk postingan event"
            });
        }

        // Buat data post
        const postData = {
            community_id: parseInt(id),
            author_id: userId,
            title: title.trim(),
            content: content || null,
            post_type: post_type,
            visibility: visibility,
            is_pinned: false,
            total_likes: 0,
            total_comments: 0,
            status: 'active',
            created_at: new Date(),
            updated_at: new Date()
        };

        // Tambahkan field event jika post_type = event
        if (post_type === 'event') {
            postData.event_date = event_date ? new Date(event_date) : null;
            // SIMPAN SEBAGAI STRING (langsung dari request)
            postData.event_start_time = event_start_time || null;
            postData.event_end_time = event_end_time || null;
            postData.event_location = event_location || null;
            postData.event_latitude = event_latitude ? parseFloat(event_latitude) : null;
            postData.event_longitude = event_longitude ? parseFloat(event_longitude) : null;
            postData.event_quota = event_quota ? parseInt(event_quota) : null;
            postData.event_registration_link = event_registration_link || null;
            postData.event_registered_count = 0;
            postData.event_status = 'upcoming';
        }

        // Buat post
        const post = await prisma.posts.create({
            data: postData,
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
                _count: {
                    select: {
                        post_likes: true,
                        post_comments: true,
                        event_participants: true
                    }
                }
            }
        });

        const formattedPost = {
            ...post,
            likes_count: post._count.post_likes,
            comments_count: post._count.post_comments,
            participants_count: post._count.event_participants,
            is_event: post.post_type === 'event',
            is_liked: false,
            is_participant: false,
            _count: undefined
        };

        return res.status(201).json({
            success: true,
            message: "Postingan berhasil dibuat",
            data: formattedPost
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
        const {
            title,
            content,
            post_type = 'regular',
            visibility = 'public',
            is_pinned = false,
            // Event fields
            event_date,
            event_start_time,
            event_end_time,
            event_location,
            event_latitude,
            event_longitude,
            event_quota,
            event_registration_link
        } = req.body;

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

        // Validasi event fields
        if (post_type === 'event' && !event_date) {
            return res.status(400).json({
                success: false,
                message: "Tanggal event wajib diisi untuk postingan event"
            });
        }

        // Buat data post
        const postData = {
            community_id: parseInt(id),
            author_id: userId,
            title: title.trim(),
            content: content || null,
            post_type: post_type,
            visibility: visibility,
            is_pinned: is_pinned === 'true' || is_pinned === true,
            total_likes: 0,
            total_comments: 0,
            status: 'active',
            created_at: new Date(),
            updated_at: new Date()
        };

        // Tambahkan field event jika post_type = event
        if (post_type === 'event') {
            postData.event_date = event_date ? new Date(event_date) : null;
            // SIMPAN SEBAGAI STRING (langsung dari request)
            postData.event_start_time = event_start_time || null;
            postData.event_end_time = event_end_time || null;
            postData.event_location = event_location || null;
            postData.event_latitude = event_latitude ? parseFloat(event_latitude) : null;
            postData.event_longitude = event_longitude ? parseFloat(event_longitude) : null;
            postData.event_quota = event_quota ? parseInt(event_quota) : null;
            postData.event_registration_link = event_registration_link || null;
            postData.event_registered_count = 0;
            postData.event_status = 'upcoming';
        }

        // Buat post
        const post = await prisma.posts.create({
            data: postData
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
                        post_comments: true,
                        event_participants: true
                    }
                }
            }
        });

        const formattedPost = {
            ...createdPost,
            likes_count: createdPost._count.post_likes,
            comments_count: createdPost._count.post_comments,
            participants_count: createdPost._count.event_participants,
            is_event: createdPost.post_type === 'event',
            is_liked: false,
            is_participant: false,
            _count: undefined
        };

        return res.status(201).json({
            success: true,
            message: "Postingan berhasil dibuat",
            data: formattedPost,
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
        const {
            title,
            content,
            post_type,
            visibility,
            is_pinned,
            // Event fields
            event_date,
            event_start_time,
            event_end_time,
            event_location,
            event_latitude,
            event_longitude,
            event_quota,
            event_registration_link,
            event_status
        } = req.body;

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
            visibility: visibility || undefined,
            updated_at: new Date()
        };

        // Hanya admin/author yang bisa pin post
        if (is_pinned !== undefined && (isCommunityAdmin || isSystemAdmin)) {
            updateData.is_pinned = is_pinned;
        }

        // Update event fields jika post_type = event
        if (post_type === 'event' || post.post_type === 'event') {
            let dateToUse = null;
            
            if (event_date !== undefined) {
                updateData.event_date = event_date ? new Date(event_date) : null;
            }
            // SIMPAN SEBAGAI STRING
            if (event_start_time !== undefined) {
                if (event_start_time && dateToUse) {
                    updateData.event_start_time = new Date(`${dateToUse}T${event_start_time}`);
                } else {
                    updateData.event_start_time = null;
                }
            }

            if (event_end_time !== undefined) {
                if (event_end_time && dateToUse) {
                    updateData.event_end_time = new Date(`${dateToUse}T${event_end_time}`);
                } else {
                    updateData.event_end_time = null;
                }
            }
            if (event_location !== undefined) {
                updateData.event_location = event_location || null;
            }
            if (event_latitude !== undefined) {
                updateData.event_latitude = event_latitude ? parseFloat(event_latitude) : null;
            }
            if (event_longitude !== undefined) {
                updateData.event_longitude = event_longitude ? parseFloat(event_longitude) : null;
            }
            if (event_quota !== undefined) {
                updateData.event_quota = event_quota ? parseInt(event_quota) : null;
            }
            if (event_registration_link !== undefined) {
                updateData.event_registration_link = event_registration_link || null;
            }
            if (event_status !== undefined) {
                updateData.event_status = event_status;
            }
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
                        post_comments: true,
                        event_participants: true
                    }
                }
            }
        });

        const formattedPost = {
            ...updatedPost,
            likes_count: updatedPost._count.post_likes,
            comments_count: updatedPost._count.post_comments,
            participants_count: updatedPost._count.event_participants,
            is_event: updatedPost.post_type === 'event',
            _count: undefined
        };

        return res.json({
            success: true,
            message: "Postingan berhasil diperbarui",
            data: formattedPost
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