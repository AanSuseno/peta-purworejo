import prisma from "../lib/prisma.js";
import slugify from "slugify";
import path from "path";
import fs from 'fs';

export const getAllCommunities = async (req, res) => {
    try {
        const userId = req.user.id;
        const {
            page = 1,
            limit = 10,
            search,
            category_id,
            kecamatan,
            is_verified,
            sort_by = 'total_members',
            sort_order = 'desc'
        } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = { is_active: true };

        if (search) {
            where.OR = [
                { community_name: { contains: search, mode: 'insensitive' } },
                { description: { contains: search, mode: 'insensitive' } }
            ];
        }

        if (category_id) {
            where.category_id = parseInt(category_id);
        }

        if (kecamatan) {
            where.kecamatan = { contains: kecamatan, mode: 'insensitive' };
        }

        if (is_verified !== undefined) {
            where.is_verified = is_verified === 'true';
        }

        let orderBy = {};
        if (sort_by === 'total_members' || sort_by === 'total_score' || sort_by === 'created_at') {
            orderBy[sort_by] = sort_order;
        } else {
            orderBy = { total_members: 'desc' };
        }

        const [communities, total] = await Promise.all([
            prisma.communities.findMany({
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
                            },
                            posts: {
                                where: { status: 'active' }
                            }
                        }
                    }
                },
                orderBy,
                skip,
                take
            }),
            prisma.communities.count({ where })
        ]);

        // Ambil komunitas mana saja (dari hasil di halaman ini) yang sudah
        // diikuti user, biar app tidak perlu nebak-nebak status join sendiri
        // dan tetap benar walau list di-refresh atau app dibuka ulang.
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
            post_count: community._count.posts,
            _count: undefined,
            is_member: joinedIds.has(community.community_id),
            is_founder: community.founder_id === userId
        }));

        return res.json({
            success: true,
            data: formattedCommunities,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get All Communities Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil data komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const getCommunityById = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const community = await prisma.communities.findUnique({
            where: {
                community_id: parseInt(id)
            },
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
                        profile_picture: true,
                        email: true
                    }
                },
                community_members: {
                    where: { status: 'active' },
                    include: {
                        users: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true
                            }
                        }
                    },
                    take: 10,
                    orderBy: {
                        join_date: 'desc'
                    }
                },
                community_admins: {
                    include: {
                        users: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true,
                                email: true
                            }
                        }
                    }
                },
                community_locations: {
                    where: { is_primary: true }
                },
                _count: {
                    select: {
                        community_members: {
                            where: { status: 'active' }
                        },
                        posts: {
                            where: { status: 'active' }
                        },
                    }
                }
            }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        // Cek status user untuk info tambahan
        const isMember = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId,
                status: 'active'
            }
        });

        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });

        const formattedCommunity = {
            ...community,
            member_count: community._count.community_members,
            post_count: community._count.posts,
            _count: undefined,
            user_access: {
                is_member: !!isMember,
                is_admin: !!isAdmin,
                is_founder: community.founder_id === userId
            }
        };

        // Sembunyikan email jika bukan admin/member
        if (!isMember && !isAdmin) {
            formattedCommunity.users.email = undefined;
        }

        return res.json({
            success: true,
            data: formattedCommunity
        });

    } catch (error) {
        console.error("Get Community By ID Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil data komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const getCommunityBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        const userId = req.user.id;

        const community = await prisma.communities.findUnique({
            where: { community_slug: slug },
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
                        profile_picture: true,
                        email: true
                    }
                },
                community_members: {
                    where: { status: 'active' },
                    include: {
                        users: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true
                            }
                        }
                    },
                    take: 10,
                    orderBy: {
                        join_date: 'desc'
                    }
                },
                community_admins: {
                    include: {
                        users: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true,
                                email: true
                            }
                        }
                    }
                },
                community_locations: {
                    where: { is_primary: true }
                },
                _count: {
                    select: {
                        community_members: {
                            where: { status: 'active' }
                        },
                        posts: {
                            where: { status: 'active' }
                        },
                    }
                }
            }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        const isMember = await prisma.community_members.findFirst({
            where: {
                community_id: community.community_id,
                user_id: userId,
                status: 'active'
            }
        });

        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: community.community_id,
                user_id: userId
            }
        });

        const formattedCommunity = {
            ...community,
            member_count: community._count.community_members,
            post_count: community._count.posts,
            _count: undefined,
            user_access: {
                is_member: !!isMember,
                is_admin: !!isAdmin,
                is_founder: community.founder_id === userId
            }
        };

        if (!isMember && !isAdmin) {
            formattedCommunity.users.email = undefined;
        }

        return res.json({
            success: true,
            data: formattedCommunity
        });

    } catch (error) {
        console.error("Get Community By Slug Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil data komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

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

export const createCommunity = async (req, res) => {
    try {
        const userId = req.user.id;
        const {
            community_name,
            description,
            category_id,
            kecamatan,
            address,
            contact_email,
            contact_phone,
            logo,
            banner
        } = req.body;

        if (!community_name || community_name.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Nama komunitas wajib diisi"
            });
        }

        const existingCommunity = await prisma.communities.findFirst({
            where: {
                community_name: community_name.trim()
            }
        });

        if (existingCommunity) {
            return res.status(409).json({
                success: false,
                message: `Komunitas dengan nama "${community_name}" sudah terdaftar`
            });
        }

        const slug = slugify(community_name, {
            lower: true,
            strict: true,
            remove: /[*+~.()'"!:@]/g
        });

        let finalSlug = slug;
        let slugCounter = 1;
        while (true) {
            const slugExists = await prisma.communities.findUnique({
                where: { community_slug: finalSlug }
            });
            if (!slugExists) break;
            finalSlug = `${slug}-${slugCounter}`;
            slugCounter++;
        }

        if (category_id) {
            const category = await prisma.categories.findUnique({
                where: { category_id: parseInt(category_id) }
            });
            if (!category) {
                return res.status(400).json({
                    success: false,
                    message: "Kategori tidak valid"
                });
            }
        }

        const community = await prisma.communities.create({
            data: {
                community_name: community_name.trim(),
                community_slug: finalSlug,
                description: description || null,
                logo: logo || null,
                banner: banner || null,
                category_id: category_id ? parseInt(category_id) : null,
                founder_id: userId,
                kecamatan: kecamatan || null,
                address: address || null,
                contact_email: contact_email || null,
                contact_phone: contact_phone || null,
                total_members: 1,
                total_score: 0,
                is_verified: false,
                is_active: true,
                created_at: new Date(),
                updated_at: new Date()
            },
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
                        profile_picture: true,
                        email: true
                    }
                }
            }
        });

        // Tambahkan founder sebagai member
        await prisma.community_members.create({
            data: {
                community_id: community.community_id,
                user_id: userId,
                status: 'active',
                join_date: new Date()
            }
        });

        // Tambahkan founder sebagai admin
        await prisma.community_admins.create({
            data: {
                community_id: community.community_id,
                user_id: userId,
                role: 'founder',
                assigned_at: new Date()
            }
        });

        return res.status(201).json({
            success: true,
            message: "Komunitas berhasil dibuat",
            data: community
        });

    } catch (error) {
        console.error("Create Community Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membuat komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const updateCommunity = async (req, res) => {
    try {
        const { id } = req.params;
        const {
            community_name,
            description,
            category_id,
            kecamatan,
            address,
            contact_email,
            contact_phone,
            logo,
            banner,
            is_verified,
            is_active
        } = req.body;

        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        if (community_name && community_name.trim() !== community.community_name) {
            const existingCommunity = await prisma.communities.findFirst({
                where: {
                    community_name: community_name.trim(),
                    community_id: { not: parseInt(id) }
                }
            });

            if (existingCommunity) {
                return res.status(409).json({
                    success: false,
                    message: `Komunitas dengan nama "${community_name}" sudah terdaftar`
                });
            }
        }

        if (category_id) {
            const category = await prisma.categories.findUnique({
                where: { category_id: parseInt(category_id) }
            });
            if (!category) {
                return res.status(400).json({
                    success: false,
                    message: "Kategori tidak valid"
                });
            }
        }

        const updateData = {
            community_name: community_name ? community_name.trim() : undefined,
            description: description !== undefined ? description : undefined,
            category_id: category_id ? parseInt(category_id) : undefined,
            kecamatan: kecamatan !== undefined ? kecamatan : undefined,
            address: address !== undefined ? address : undefined,
            contact_email: contact_email !== undefined ? contact_email : undefined,
            contact_phone: contact_phone !== undefined ? contact_phone : undefined,
            logo: logo !== undefined ? logo : undefined,
            banner: banner !== undefined ? banner : undefined,
            is_verified: is_verified !== undefined ? is_verified : undefined,
            is_active: is_active !== undefined ? is_active : undefined,
            updated_at: new Date()
        };

        if (community_name && community_name.trim() !== community.community_name) {
            const slug = slugify(community_name.trim(), {
                lower: true,
                strict: true,
                remove: /[*+~.()'"!:@]/g
            });

            let finalSlug = slug;
            let slugCounter = 1;
            while (true) {
                const slugExists = await prisma.communities.findFirst({
                    where: {
                        community_slug: finalSlug,
                        community_id: { not: parseInt(id) }
                    }
                });
                if (!slugExists) break;
                finalSlug = `${slug}-${slugCounter}`;
                slugCounter++;
            }
            updateData.community_slug = finalSlug;
        }

        const updatedCommunity = await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: updateData,
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
                        profile_picture: true,
                        email: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Komunitas berhasil diperbarui",
            data: updatedCommunity
        });

    } catch (error) {
        console.error("Update Community Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const deleteCommunity = async (req, res) => {
    try {
        const { id } = req.params;

        const community = await prisma.communities.findUnique({
            where: { community_id: parseInt(id) },
            include: {
                _count: {
                    select: {
                        community_members: true,
                        posts: true
                    }
                }
            }
        });

        if (!community) {
            return res.status(404).json({
                success: false,
                message: "Komunitas tidak ditemukan"
            });
        }

        await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                is_active: false,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Komunitas berhasil dinonaktifkan",
            data: {
                community_id: community.community_id,
                community_name: community.community_name,
                members_count: community._count.community_members,
                posts_count: community._count.posts
            }
        });

    } catch (error) {
        console.error("Delete Community Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

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

        console.log(`📊 [Members] Found ${members.length} members, total: ${total}, page: ${pageNum}, limit: ${limitNum}`);

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

export const addCommunityAdmin = async (req, res) => {
    try {
        const { id } = req.params;
        const { user_id, role = 'admin' } = req.body;
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

        // Middleware sudah handle auth, tapi tetap cek founder
        if (community.founder_id !== userId) {
            return res.status(403).json({
                success: false,
                message: "Hanya founder yang bisa menambah admin"
            });
        }

        const user = await prisma.users.findUnique({
            where: { user_id: parseInt(user_id) }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        const member = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: parseInt(user_id),
                status: 'active'
            }
        });

        if (!member) {
            return res.status(400).json({
                success: false,
                message: "User harus menjadi anggota komunitas terlebih dahulu"
            });
        }

        const existingAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: parseInt(user_id)
            }
        });

        if (existingAdmin) {
            return res.status(400).json({
                success: false,
                message: "User sudah menjadi admin komunitas ini"
            });
        }

        const admin = await prisma.community_admins.create({
            data: {
                community_id: parseInt(id),
                user_id: parseInt(user_id),
                role: role === 'founder' ? 'founder' : 'admin',
                assigned_at: new Date()
            },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        profile_picture: true,
                        email: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Admin berhasil ditambahkan",
            data: admin
        });

    } catch (error) {
        console.error("Add Community Admin Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menambah admin",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const removeCommunityAdmin = async (req, res) => {
    try {
        const { id, adminId } = req.params;
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

        if (community.founder_id !== userId) {
            return res.status(403).json({
                success: false,
                message: "Hanya founder yang bisa menghapus admin"
            });
        }

        const admin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                admin_id: parseInt(adminId)
            }
        });

        if (!admin) {
            return res.status(404).json({
                success: false,
                message: "Admin tidak ditemukan"
            });
        }

        if (admin.role === 'founder') {
            return res.status(400).json({
                success: false,
                message: "Tidak bisa menghapus founder"
            });
        }

        await prisma.community_admins.delete({
            where: {
                admin_id: parseInt(adminId)
            }
        });

        return res.json({
            success: true,
            message: "Admin berhasil dihapus"
        });

    } catch (error) {
        console.error("Remove Community Admin Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus admin",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const transferOwnership = async (req, res) => {
    try {
        const { id } = req.params;
        const { new_founder_id } = req.body;
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

        if (community.founder_id !== userId) {
            return res.status(403).json({
                success: false,
                message: "Hanya founder yang bisa transfer kepemilikan"
            });
        }

        const newFounder = await prisma.users.findUnique({
            where: { user_id: parseInt(new_founder_id) }
        });

        if (!newFounder) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        const member = await prisma.community_members.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: parseInt(new_founder_id),
                status: 'active'
            }
        });

        if (!member) {
            return res.status(400).json({
                success: false,
                message: "User harus menjadi anggota komunitas terlebih dahulu"
            });
        }

        await prisma.$transaction([
            // 1. Update founder_id di communities
            prisma.communities.update({
                where: { community_id: parseInt(id) },
                data: {
                    founder_id: parseInt(new_founder_id),
                    updated_at: new Date()
                }
            }),
            
            // 2. Update role di community_admins - old founder jadi admin
            prisma.community_admins.updateMany({
                where: {
                    community_id: parseInt(id),
                    user_id: userId
                },
                data: {
                    role: 'admin'
                }
            }),
            
            // 3. Update role di community_admins - new founder jadi founder
            prisma.community_admins.updateMany({
                where: {
                    community_id: parseInt(id),
                    user_id: parseInt(new_founder_id)
                },
                data: {
                    role: 'founder'
                }
            }),
            
            // 4. Jika new founder belum ada di community_admins, tambahkan
            // Cek dulu apakah sudah ada
            prisma.community_admins.upsert({
                where: {
                    community_id_user_id: {
                        community_id: parseInt(id),
                        user_id: parseInt(new_founder_id)
                    }
                },
                update: {
                    role: 'founder',
                    assigned_at: new Date()
                },
                create: {
                    community_id: parseInt(id),
                    user_id: parseInt(new_founder_id),
                    role: 'founder',
                    assigned_at: new Date()
                }
            })
        ]);

        return res.json({
            success: true,
            message: "Kepemilikan komunitas berhasil ditransfer"
        });

    } catch (error) {
        console.error("Transfer Ownership Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal transfer kepemilikan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 📸 UPLOAD Community Logo
export const uploadCommunityLogo = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

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

        // Cek permission (admin/founder atau system admin)
        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        if (!isAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk upload logo komunitas ini"
            });
        }

        // Cek file
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: "File logo wajib diupload"
            });
        }

        // Hapus logo lama jika ada
        if (community.logo) {
            const oldFilePath = path.join(process.cwd(), community.logo);
            if (fs.existsSync(oldFilePath)) {
                fs.unlinkSync(oldFilePath);
            }
        }

        // URL file
        const fileUrl = `/uploads/communities/${req.file.filename}`;

        // Update database
        const updatedCommunity = await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                logo: fileUrl,
                updated_at: new Date()
            },
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
                        profile_picture: true,
                        email: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Logo komunitas berhasil diupload",
            data: updatedCommunity,
            file: {
                filename: req.file.filename,
                url: fileUrl,
                size: req.file.size,
                mimetype: req.file.mimetype
            }
        });

    } catch (error) {
        console.error("Upload Community Logo Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengupload logo komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 📸 UPLOAD Community Banner
export const uploadCommunityBanner = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

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

        // Cek permission (admin/founder atau system admin)
        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        if (!isAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk upload banner komunitas ini"
            });
        }

        // Cek file
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: "File banner wajib diupload"
            });
        }

        // Hapus banner lama jika ada
        if (community.banner) {
            const oldFilePath = path.join(process.cwd(), community.banner);
            if (fs.existsSync(oldFilePath)) {
                fs.unlinkSync(oldFilePath);
            }
        }

        // URL file
        const fileUrl = `/uploads/communities/${req.file.filename}`;

        // Update database
        const updatedCommunity = await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                banner: fileUrl,
                updated_at: new Date()
            },
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
                        profile_picture: true,
                        email: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Banner komunitas berhasil diupload",
            data: updatedCommunity,
            file: {
                filename: req.file.filename,
                url: fileUrl,
                size: req.file.size,
                mimetype: req.file.mimetype
            }
        });

    } catch (error) {
        console.error("Upload Community Banner Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengupload banner komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 📸 UPLOAD Logo & Banner Sekaligus (Multiple)
export const uploadCommunityMedia = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

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

        // Cek permission
        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        if (!isAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk upload media komunitas ini"
            });
        }

        const updateData = {};
        const uploadedFiles = [];

        // Proses logo jika ada
        if (req.files && req.files.logo && req.files.logo.length > 0) {
            const logoFile = req.files.logo[0];
            
            // Hapus logo lama
            if (community.logo) {
                const oldFilePath = path.join(process.cwd(), community.logo);
                if (fs.existsSync(oldFilePath)) {
                    fs.unlinkSync(oldFilePath);
                }
            }
            
            const logoUrl = `/uploads/communities/${logoFile.filename}`;
            updateData.logo = logoUrl;
            uploadedFiles.push({
                type: 'logo',
                filename: logoFile.filename,
                url: logoUrl,
                size: logoFile.size
            });
        }

        // Proses banner jika ada
        if (req.files && req.files.banner && req.files.banner.length > 0) {
            const bannerFile = req.files.banner[0];
            
            // Hapus banner lama
            if (community.banner) {
                const oldFilePath = path.join(process.cwd(), community.banner);
                if (fs.existsSync(oldFilePath)) {
                    fs.unlinkSync(oldFilePath);
                }
            }
            
            const bannerUrl = `/uploads/communities/${bannerFile.filename}`;
            updateData.banner = bannerUrl;
            uploadedFiles.push({
                type: 'banner',
                filename: bannerFile.filename,
                url: bannerUrl,
                size: bannerFile.size
            });
        }

        if (Object.keys(updateData).length === 0) {
            return res.status(400).json({
                success: false,
                message: "Tidak ada file yang diupload. Kirim logo atau banner."
            });
        }

        updateData.updated_at = new Date();

        // Update database
        const updatedCommunity = await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: updateData,
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
                        profile_picture: true,
                        email: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Media komunitas berhasil diupload",
            data: updatedCommunity,
            files: uploadedFiles
        });

    } catch (error) {
        console.error("Upload Community Media Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengupload media komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 🗑️ DELETE Community Logo
export const deleteCommunityLogo = async (req, res) => {
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

        // Cek permission
        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        if (!isAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk menghapus logo komunitas ini"
            });
        }

        if (!community.logo) {
            return res.status(400).json({
                success: false,
                message: "Komunitas tidak memiliki logo"
            });
        }

        // Hapus file
        const filePath = path.join(process.cwd(), community.logo);
        if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
        }

        // Update database
        await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                logo: null,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Logo komunitas berhasil dihapus"
        });

    } catch (error) {
        console.error("Delete Community Logo Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus logo komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 🗑️ DELETE Community Banner
export const deleteCommunityBanner = async (req, res) => {
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

        // Cek permission
        const isAdmin = await prisma.community_admins.findFirst({
            where: {
                community_id: parseInt(id),
                user_id: userId
            }
        });
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        if (!isAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk menghapus banner komunitas ini"
            });
        }

        if (!community.banner) {
            return res.status(400).json({
                success: false,
                message: "Komunitas tidak memiliki banner"
            });
        }

        // Hapus file
        const filePath = path.join(process.cwd(), community.banner);
        if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
        }

        // Update database
        await prisma.communities.update({
            where: { community_id: parseInt(id) },
            data: {
                banner: null,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Banner komunitas berhasil dihapus"
        });

    } catch (error) {
        console.error("Delete Community Banner Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus banner komunitas",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};