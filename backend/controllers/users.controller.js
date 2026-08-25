// controllers/users.controller.js
import prisma from "../lib/prisma.js";
import bcrypt from "bcrypt";
import fs from "fs";
import path from "path";

// 📋 GET All Users (Admin Only)
export const getAllUsers = async (req, res) => {
    try {
        const { page = 1, limit = 10, search, role, is_active } = req.query;
        
        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {};
        
        if (search) {
            where.OR = [
                { full_name: { contains: search, mode: 'insensitive' } },
                { email: { contains: search, mode: 'insensitive' } }
            ];
        }
        
        if (role) {
            where.role_id = parseInt(role);
        }
        
        if (is_active !== undefined) {
            where.is_active = is_active === 'true';
        }

        const [users, total] = await Promise.all([
            prisma.users.findMany({
                where,
                select: {
                    user_id: true,
                    email: true,
                    full_name: true,
                    phone_number: true,
                    profile_picture: true,
                    bio: true,
                    kecamatan: true,
                    interests: true,
                    role_id: true,
                    is_verified: true,
                    is_active: true,
                    last_login: true,
                    created_at: true,
                    updated_at: true,
                    google_id: true,
                    user_roles: {
                        select: {
                            role_id: true,
                            role_name: true,
                            role_description: true
                        }
                    },
                    _count: {
                        select: {
                            communities: true,
                            community_members: true,
                            posts: true,
                        }
                    }
                },
                orderBy: {
                    created_at: 'desc'
                },
                skip,
                take
            }),
            prisma.users.count({ where })
        ]);

        return res.json({
            success: true,
            data: users,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get All Users Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil data users",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 👑 UPDATE User by ID (Admin Only)
export const updateUserByAdmin = async (req, res) => {
    try {
        const { id } = req.params;
        const { full_name, phone_number, bio, kecamatan, interests, role_id, is_verified, is_active } = req.body;

        const user = await prisma.users.findUnique({
            where: { user_id: parseInt(id) }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        if (role_id) {
            const role = await prisma.user_roles.findUnique({
                where: { role_id: parseInt(role_id) }
            });
            if (!role) {
                return res.status(400).json({
                    success: false,
                    message: "Role tidak valid"
                });
            }
        }

        const updatedUser = await prisma.users.update({
            where: { user_id: parseInt(id) },
            data: {
                full_name: full_name || undefined,
                phone_number: phone_number || undefined,
                bio: bio || undefined,
                kecamatan: kecamatan || undefined,
                interests: interests || undefined,
                role_id: role_id ? parseInt(role_id) : undefined,
                is_verified: is_verified !== undefined ? is_verified : undefined,
                is_active: is_active !== undefined ? is_active : undefined,
                updated_at: new Date()
            },
            select: {
                user_id: true,
                email: true,
                full_name: true,
                phone_number: true,
                profile_picture: true,
                bio: true,
                kecamatan: true,
                interests: true,
                role_id: true,
                is_verified: true,
                is_active: true,
                last_login: true,
                created_at: true,
                updated_at: true,
                user_roles: {
                    select: {
                        role_id: true,
                        role_name: true,
                        role_description: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "User berhasil diperbarui",
            data: updatedUser
        });

    } catch (error) {
        console.error("Update User By Admin Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui user",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 👑 DELETE User by ID (Admin Only)
export const deleteUserByAdmin = async (req, res) => {
    try {
        const { id } = req.params;

        const user = await prisma.users.findUnique({
            where: { user_id: parseInt(id) },
            include: {
                _count: {
                    select: {
                        communities: true,
                        community_admins: true,
                        posts: true
                    }
                }
            }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        // Cek apakah user punya komunitas
        if (user._count.communities > 0) {
            return res.status(400).json({
                success: false,
                message: `User tidak dapat dihapus karena memiliki ${user._count.communities} komunitas. Transfer kepemilikan terlebih dahulu.`
            });
        }

        // Jangan izinkan admin menghapus dirinya sendiri
        if (user.user_id === req.user.id) {
            return res.status(400).json({
                success: false,
                message: "Anda tidak dapat menghapus akun sendiri melalui admin. Gunakan endpoint deactivate."
            });
        }

        await prisma.users.delete({
            where: { user_id: parseInt(id) }
        });

        return res.json({
            success: true,
            message: "User berhasil dihapus"
        });

    } catch (error) {
        console.error("Delete User By Admin Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus user",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 📊 GET User Statistics (Admin Only)
export const getUserStatistics = async (req, res) => {
    try {
        const [
            totalUsers,
            activeUsers,
            verifiedUsers,
            usersByRole,
            usersByMonth
        ] = await Promise.all([
            prisma.users.count(),
            prisma.users.count({ where: { is_active: true } }),
            prisma.users.count({ where: { is_verified: true } }),
            prisma.users.groupBy({
                by: ['role_id'],
                _count: true,
                orderBy: {
                    role_id: 'asc'
                }
            }),
            prisma.$queryRaw`
                SELECT 
                    DATE_TRUNC('month', created_at) as month,
                    COUNT(*) as count
                FROM users
                WHERE created_at >= NOW() - INTERVAL '12 months'
                GROUP BY DATE_TRUNC('month', created_at)
                ORDER BY month DESC
            `
        ]);

        const roles = await prisma.user_roles.findMany();
        const roleMap = {};
        roles.forEach(role => {
            roleMap[role.role_id] = role.role_name;
        });

        const usersByRoleWithNames = usersByRole.map(item => ({
            role_id: item.role_id,
            role_name: roleMap[item.role_id] || 'Unknown',
            count: item._count  // Ini number, aman
        }));

        // 🔥 FIX: Konversi BigInt ke Number
        const formattedUsersByMonth = usersByMonth.map(item => ({
            month: item.month,
            count: Number(item.count)  // ← Konversi BigInt ke Number
        }));

        return res.json({
            success: true,
            data: {
                total: totalUsers,
                active: activeUsers,
                inactive: totalUsers - activeUsers,
                verified: verifiedUsers,
                unverified: totalUsers - verifiedUsers,
                by_role: usersByRoleWithNames,
                by_month: formattedUsersByMonth  // ← Pakai yang sudah di-convert
            }
        });

    } catch (error) {
        console.error("Get User Statistics Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil statistik user",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// ============================================
// 🔒 USER ROUTES (Harus login, hanya untuk diri sendiri)
// ============================================

// 👤 GET My Profile (dari token)
export const getMyProfile = async (req, res) => {
    try {
        const userId = req.user.id;

        const user = await prisma.users.findUnique({
            where: {
                user_id: userId
            },
            select: {
                user_id: true,
                email: true,
                full_name: true,
                phone_number: true,
                profile_picture: true,
                bio: true,
                kecamatan: true,
                interests: true,
                role_id: true,
                is_verified: true,
                is_active: true,
                last_login: true,
                created_at: true,
                updated_at: true,
                google_id: true,
                user_roles: {
                    select: {
                        role_id: true,
                        role_name: true,
                        role_description: true
                    }
                },
                communities: {
                    where: { is_active: true },
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true,
                        logo: true,
                        total_members: true,
                        is_verified: true
                    }
                },
                community_members: {
                    where: { status: 'active' },
                    select: {
                        community_id: true,
                        status: true,
                        join_date: true,
                        communities: {
                            select: {
                                community_id: true,
                                community_name: true,
                                community_slug: true,
                                total_members: true,
                                logo: true
                            }
                        }
                    }
                },
                community_admins: {
                    select: {
                        community_id: true,
                        role: true,
                        assigned_at: true,
                        communities: {
                            select: {
                                community_id: true,
                                community_name: true,
                                community_slug: true
                            }
                        }
                    }
                },
                _count: {
                    select: {
                        communities: true,
                        community_members: true,
                        posts: true,
                        event_participants: true
                    }
                }
            }
        });

        console.log(user)

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        return res.json({
            success: true,
            data: user
        });

    } catch (error) {
        console.error("Get My Profile Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil profil",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 📋 GET User by ID (Hanya untuk diri sendiri atau admin)
export const getUserById = async (req, res) => {
    try {
        const { id } = req.params;
        const currentUserId = req.user.id;
        const isAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        // Cek apakah user mengakses dirinya sendiri atau admin
        if (parseInt(id) !== currentUserId && !isAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk melihat data user lain"
            });
        }

        const user = await prisma.users.findUnique({
            where: {
                user_id: parseInt(id)
            },
            select: {
                user_id: true,
                email: true,
                full_name: true,
                phone_number: true,
                profile_picture: true,
                bio: true,
                kecamatan: true,
                interests: true,
                role_id: true,
                is_verified: true,
                is_active: true,
                last_login: true,
                created_at: true,
                updated_at: true,
                user_roles: {
                    select: {
                        role_id: true,
                        role_name: true,
                        role_description: true
                    }
                },
                communities: {
                    where: { is_active: true },
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true,
                        logo: true,
                        total_members: true,
                        is_verified: true
                    }
                },
                _count: {
                    select: {
                        communities: true,
                        community_members: true,
                        posts: true,
                        event_participants: true
                    }
                }
            }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        return res.json({
            success: true,
            data: user
        });

    } catch (error) {
        console.error("Get User By ID Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil data user",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 🏢 GET User's Communities (Hanya untuk diri sendiri atau admin)
export const getUserCommunities = async (req, res) => {
    try {
        const { id } = req.params;
        const currentUserId = req.user.id;
        const isAdmin = req.user.roleName?.toLowerCase() === 'system_admin';
        const { status = 'active' } = req.query;

        // Validasi akses
        if (parseInt(id) !== currentUserId && !isAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk melihat komunitas user lain"
            });
        }

        const user = await prisma.users.findUnique({
            where: { user_id: parseInt(id) }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        // Base select fields yang sama untuk semua
        const communityFields = {
            community_id: true,
            community_name: true,
            community_slug: true,
            logo: true,
            total_members: true,
            is_verified: true,
            created_at: true,
            description: true,
            kecamatan: true,
            total_score: true
        };

        // 1. Founder
        const founded = await prisma.communities.findMany({
            where: { founder_id: parseInt(id), is_active: true },
            select: communityFields
        });

        // 2. Admin
        const adminData = await prisma.community_admins.findMany({
            where: { user_id: parseInt(id) },
            select: {
                role: true,
                assigned_at: true,
                communities: { select: communityFields }
            }
        });

        // 3. Member
        const memberData = await prisma.community_members.findMany({
            where: { user_id: parseInt(id), status },
            select: {
                join_date: true,
                status: true,
                communities: { select: communityFields }
            },
            orderBy: { join_date: 'desc' }
        });

        // Combine dengan role info
        const allCommunities = [
            ...founded.map(c => ({ ...c, role: 'founder', role_type: 'founder' })),
            ...adminData.map(a => ({ ...a.communities, role: a.role, role_type: 'admin', assigned_at: a.assigned_at })),
            ...memberData.map(m => ({ ...m.communities, role: 'member', role_type: 'member', join_date: m.join_date, status: m.status }))
        ];

        // Sort by role priority
        const priority = { founder: 1, admin: 2, member: 3 };
        allCommunities.sort((a, b) => (priority[a.role_type] || 99) - (priority[b.role_type] || 99));

        return res.json({
            success: true,
            data: allCommunities,
            summary: {
                total: allCommunities.length,
                founded: founded.length,
                admin: adminData.length,
                member: memberData.length
            }
        });

    } catch (error) {
        console.error("Get User Communities Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil komunitas user",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// ✏️ UPDATE My Profile
export const updateMyProfile = async (req, res) => {
    try {
        const userId = req.user.id;
        const { full_name, phone_number, bio, kecamatan, interests } = req.body;

        if (full_name && full_name.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Nama lengkap tidak boleh kosong"
            });
        }

        const updatedUser = await prisma.users.update({
            where: {
                user_id: userId
            },
            data: {
                full_name: full_name ? full_name.trim() : undefined,
                phone_number: phone_number || undefined,
                bio: bio || undefined,
                kecamatan: kecamatan || undefined,
                interests: interests || undefined,
                updated_at: new Date()
            },
            select: {
                user_id: true,
                email: true,
                full_name: true,
                phone_number: true,
                profile_picture: true,
                bio: true,
                kecamatan: true,
                interests: true,
                role_id: true,
                is_verified: true,
                is_active: true,
                last_login: true,
                created_at: true,
                updated_at: true,
                user_roles: {
                    select: {
                        role_id: true,
                        role_name: true,
                        role_description: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Profil berhasil diperbarui",
            data: updatedUser
        });

    } catch (error) {
        console.error("Update My Profile Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui profil",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 📸 UPDATE My Profile Picture
export const updateMyProfilePicture = async (req, res) => {
    try {
        const userId = req.user.id;
        const { profile_picture } = req.body;

        if (!profile_picture) {
            return res.status(400).json({
                success: false,
                message: "URL profile picture wajib diisi"
            });
        }

        const updatedUser = await prisma.users.update({
            where: {
                user_id: userId
            },
            data: {
                profile_picture: profile_picture,
                updated_at: new Date()
            },
            select: {
                user_id: true,
                email: true,
                full_name: true,
                phone_number: true,
                profile_picture: true,
                bio: true,
                kecamatan: true,
                interests: true,
                role_id: true,
                is_verified: true,
                is_active: true,
                updated_at: true,
                user_roles: {
                    select: {
                        role_id: true,
                        role_name: true,
                        role_description: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Profile picture berhasil diperbarui",
            data: updatedUser
        });

    } catch (error) {
        console.error("Update Profile Picture Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui profile picture",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 🔑 CHANGE Password
export const changePassword = async (req, res) => {
    try {
        const userId = req.user.id;
        const { current_password, new_password, confirm_password } = req.body;

        if (!current_password || !new_password || !confirm_password) {
            return res.status(400).json({
                success: false,
                message: "Semua field password wajib diisi"
            });
        }

        if (new_password.length < 8) {
            return res.status(400).json({
                success: false,
                message: "Password baru minimal 8 karakter"
            });
        }

        if (new_password !== confirm_password) {
            return res.status(400).json({
                success: false,
                message: "Password baru dan konfirmasi password tidak cocok"
            });
        }

        const user = await prisma.users.findUnique({
            where: { user_id: userId }
        });

        if (!user.password_hash) {
            return res.status(400).json({
                success: false,
                message: "Akun ini menggunakan Google Login, tidak bisa mengubah password"
            });
        }

        const isPasswordValid = await bcrypt.compare(current_password, user.password_hash);
        if (!isPasswordValid) {
            return res.status(401).json({
                success: false,
                message: "Password saat ini salah"
            });
        }

        const hashedPassword = await bcrypt.hash(new_password, 10);

        await prisma.users.update({
            where: { user_id: userId },
            data: {
                password_hash: hashedPassword,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Password berhasil diubah"
        });

    } catch (error) {
        console.error("Change Password Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengubah password",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 🗑️ DELETE My Account (Soft delete / deactivate)
export const deactivateMyAccount = async (req, res) => {
    try {
        const userId = req.user.id;
        
        // Ambil dari query params (DELETE) atau body (POST)
        const body = req.body || {};
        const query = req.query || {};
        const confirmation = body.confirmation || query.confirmation;

        // Validasi confirmation
        if (!confirmation) {
            return res.status(400).json({
                success: false,
                message: "Parameter 'confirmation' wajib diisi. Ketik 'DELETE' untuk konfirmasi."
            });
        }

        if (confirmation !== 'DELETE') {
            return res.status(400).json({
                success: false,
                message: "Konfirmasi tidak valid. Ketik 'DELETE' untuk menghapus akun."
            });
        }

        // Cek user
        const user = await prisma.users.findUnique({
            where: { user_id: userId }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        // Cek apakah user sudah tidak aktif
        if (!user.is_active) {
            return res.status(400).json({
                success: false,
                message: "Akun sudah dalam keadaan tidak aktif"
            });
        }

        // ✅ Soft delete - deactivate account (tanpa verifikasi password)
        await prisma.users.update({
            where: { user_id: userId },
            data: {
                is_active: false,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Akun berhasil dinonaktifkan"
        });

    } catch (error) {
        console.error("Deactivate Account Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menonaktifkan akun",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// 🎭 GET All Roles (Public - tapi tetap harus login)
export const getAllRoles = async (req, res) => {
    try {
        const roles = await prisma.user_roles.findMany({
            orderBy: {
                role_id: 'asc'
            }
        });

        return res.json({
            success: true,
            data: roles
        });

    } catch (error) {
        console.error("Get All Roles Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil data roles",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const uploadMyProfilePicture = async (req, res) => {
    try {
        const userId = req.user.id;

        // Cek apakah file ada
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: "File gambar wajib diupload"
            });
        }

        // Dapatkan user untuk cek foto lama
        const user = await prisma.users.findUnique({
            where: { user_id: userId }
        });

        // Hapus foto lama jika ada
        if (user.profile_picture) {
            const oldFilePath = path.join(process.cwd(), user.profile_picture);
            if (fs.existsSync(oldFilePath)) {
                fs.unlinkSync(oldFilePath);
            }
        }

        // URL file yang diupload (relative path)
        const fileUrl = `/uploads/profiles/${req.file.filename}`;

        // Update database
        const updatedUser = await prisma.users.update({
            where: {
                user_id: userId
            },
            data: {
                profile_picture: fileUrl,
                updated_at: new Date()
            },
            select: {
                user_id: true,
                email: true,
                full_name: true,
                phone_number: true,
                profile_picture: true,
                bio: true,
                kecamatan: true,
                interests: true,
                role_id: true,
                is_verified: true,
                is_active: true,
                updated_at: true,
                user_roles: {
                    select: {
                        role_id: true,
                        role_name: true,
                        role_description: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Profile picture berhasil diupload",
            data: updatedUser,
            file: {
                filename: req.file.filename,
                url: fileUrl,
                size: req.file.size,
                mimetype: req.file.mimetype
            }
        });

    } catch (error) {
        console.error("Upload Profile Picture Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengupload profile picture",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};