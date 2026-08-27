import prisma from "../../lib/prisma.js";
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
        const communityId = parseInt(id);

        const community = await prisma.communities.findUnique({
            where: {
                community_id: communityId
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
                    where: {
                        status: 'active'
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
                    where: {
                        is_primary: true
                    }
                },
                _count: {
                    select: {
                        community_members: {
                            where: {
                                status: 'active'
                            }
                        },
                        posts: {
                            where: {
                                status: 'active'
                            }
                        }
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

        // Jalankan query tambahan secara paralel
        const [
            isMember,
            isAdmin,
            pendingCampaignsCount,
            activeCampaignsCount
        ] = await Promise.all([
            prisma.community_members.findFirst({
                where: {
                    community_id: communityId,
                    user_id: userId,
                    status: 'active'
                }
            }),

            prisma.community_admins.findFirst({
                where: {
                    community_id: communityId,
                    user_id: userId
                }
            }),

            // Jumlah campaign pending
            prisma.donation_campaigns.count({
                where: {
                    community_id: communityId,
                    approval_status: 'pending'
                }
            }),

            // Jumlah campaign aktif
            prisma.donation_campaigns.count({
                where: {
                    community_id: communityId,
                    status: 'active'
                }
            })
        ]);

        const formattedCommunity = {
            ...community,

            member_count: community._count.community_members,
            post_count: community._count.posts,

            // Tambahan yang bisa diakses Flutter
            pending_campaigns_count: pendingCampaignsCount,
            active_campaigns_count: activeCampaignsCount,

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
            error: process.env.NODE_ENV === 'development'
                ? error.message
                : undefined
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