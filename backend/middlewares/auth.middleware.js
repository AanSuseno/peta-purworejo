// middlewares/auth.middleware.js
import jwt from "jsonwebtoken";
import prisma from "../lib/prisma.js";

// 🔐 Verify JWT Token
export const authenticate = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;
        
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({
                success: false,
                message: "Token tidak ditemukan. Silakan login terlebih dahulu."
            });
        }

        const token = authHeader.split(' ')[1];

        let decoded;
        try {
            decoded = jwt.verify(token, process.env.JWT_SECRET);
        } catch (err) {
            if (err.name === 'TokenExpiredError') {
                return res.status(401).json({
                    success: false,
                    message: "Token sudah kadaluarsa. Silakan login ulang."
                });
            }
            return res.status(401).json({
                success: false,
                message: "Token tidak valid."
            });
        }

        // Pastikan decoded memiliki userId
        const userId = decoded.userId || decoded.id || decoded.user_id;
        if (!userId) {
            return res.status(401).json({
                success: false,
                message: "Token tidak valid: userId tidak ditemukan"
            });
        }

        const user = await prisma.users.findUnique({
            where: {
                user_id: parseInt(userId)
            },
            include: {
                user_roles: true
            }
        });

        if (!user) {
            return res.status(401).json({
                success: false,
                message: "User tidak ditemukan."
            });
        }

        if (!user.is_active) {
            return res.status(403).json({
                success: false,
                message: "Akun Anda tidak aktif. Silakan hubungi administrator."
            });
        }

        // Simpan user lengkap ke request
        req.user = {
            id: user.user_id,
            email: user.email,
            fullName: user.full_name,
            roleId: user.role_id,
            roleName: user.user_roles?.role_name,
            isVerified: user.is_verified,
            phoneNumber: user.phone_number,
            profilePicture: user.profile_picture
        };

        next();

    } catch (error) {
        console.error("Auth Middleware Error:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan pada autentikasi"
        });
    }
};

// 👑 Check Specific Role
export const requireRole = (allowedRoles) => {
    return async (req, res, next) => {
        try {
            if (!req.user) {
                return res.status(401).json({
                    success: false,
                    message: "Silakan login terlebih dahulu"
                });
            }

            const user = await prisma.users.findUnique({
                where: {
                    user_id: req.user.id
                },
                include: {
                    user_roles: true
                }
            });

            if (!user) {
                return res.status(404).json({
                    success: false,
                    message: "User tidak ditemukan"
                });
            }

            const userRoleName = user.user_roles?.role_name?.toLowerCase();
            
            // Check if user's role is in allowed roles
            if (!allowedRoles.map(r => r.toLowerCase()).includes(userRoleName)) {
                return res.status(403).json({
                    success: false,
                    message: `Akses ditolak. Diperlukan role: ${allowedRoles.join(', ')}`,
                    yourRole: user.user_roles?.role_name || 'unknown'
                });
            }

            next();

        } catch (error) {
            console.error("Role Check Error:", error);
            return res.status(500).json({
                success: false,
                message: "Terjadi kesalahan saat validasi role"
            });
        }
    };
};

// 👑 Check Admin System
export const isSystemAdmin = async (req, res, next) => {
    try {
        if (!req.user) {
            return res.status(401).json({
                success: false,
                message: "Silakan login terlebih dahulu"
            });
        }

        const user = await prisma.users.findUnique({
            where: {
                user_id: req.user.id
            },
            include: {
                user_roles: true
            }
        });

        if (!user) {
            return res.status(404).json({
                success: false,
                message: "User tidak ditemukan"
            });
        }

        // Check if role is system_admin (role_id = 4 or role_name = 'system_admin')
        if (user.role_id !== 4 && user.user_roles?.role_name?.toLowerCase() !== 'system_admin') {
            return res.status(403).json({
                success: false,
                message: "Akses ditolak. Hanya System Admin yang diizinkan.",
                yourRole: user.user_roles?.role_name || 'unknown'
            });
        }

        req.admin = {
            id: user.user_id,
            email: user.email,
            role: user.user_roles?.role_name
        };

        next();

    } catch (error) {
        console.error("System Admin Check Error:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat validasi system admin"
        });
    }
};

export const isCommunityAdminOrFounder = (communityIdParam = 'id') => {
    return async (req, res, next) => {
        try {
            if (!req.user) {
                return res.status(401).json({
                    success: false,
                    message: "Silakan login terlebih dahulu"
                });
            }

            const userId = req.user.id;
            
            // Ambil community_id dari params (default 'id')
            const communityId = req.params[communityIdParam] || 
                               req.query[communityIdParam] || 
                               req.body[communityIdParam];

            if (!communityId) {
                return res.status(400).json({
                    success: false,
                    message: "Community ID tidak ditemukan"
                });
            }

            console.log('[isCommunityAdminOrFounder] Checking permission:', {
                communityId,
                userId,
                param: communityIdParam
            });

            // CEK 1: Apakah user adalah admin di community_admins?
            const admin = await prisma.community_admins.findFirst({
                where: {
                    community_id: parseInt(communityId),
                    user_id: userId
                }
            });

            if (admin) {
                console.log('[isCommunityAdminOrFounder] User is admin with role:', admin.role);
                req.communityAccess = {
                    isAdmin: true,
                    isFounder: admin.role === 'founder',
                    role: admin.role
                };
                return next();
            }

            // CEK 2: Apakah user adalah system admin?
            const user = await prisma.users.findUnique({
                where: { user_id: userId },
                include: { user_roles: true }
            });

            if (user?.user_roles?.role_name?.toLowerCase() === 'system_admin') {
                console.log('[isCommunityAdminOrFounder] User is system admin');
                req.communityAccess = {
                    isAdmin: true,
                    isFounder: false,
                    role: 'system_admin'
                };
                return next();
            }

            // CEK 3: (OPTIONAL) Cek founder_id di communities untuk backward compatibility
            // HAPUS INI jika Anda sudah yakin semua transfer ownership mengupdate community_admins
            const community = await prisma.communities.findUnique({
                where: { community_id: parseInt(communityId) },
                select: { founder_id: true }
            });

            if (community && community.founder_id === userId) {
                console.log('[isCommunityAdminOrFounder] User is founder (from communities table)');
                req.communityAccess = {
                    isAdmin: true,
                    isFounder: true,
                    role: 'founder'
                };
                return next();
            }

            console.log('[isCommunityAdminOrFounder] Access denied');
            return res.status(403).json({
                success: false,
                message: "Akses ditolak. Anda bukan admin atau founder dari komunitas ini."
            });

        } catch (error) {
            console.error("[isCommunityAdminOrFounder] Error:", error);
            return res.status(500).json({
                success: false,
                message: "Terjadi kesalahan saat validasi akses komunitas"
            });
        }
    };
};

// 🔍 Check Community Membership
export const isCommunityMember = (communityIdParam = 'communityId') => {
    return async (req, res, next) => {
        try {
            if (!req.user) {
                return res.status(401).json({
                    success: false,
                    message: "Silakan login terlebih dahulu"
                });
            }

            const communityId = req.params[communityIdParam] || 
                               req.query[communityIdParam] || 
                               req.body[communityIdParam];

            if (!communityId) {
                return res.status(400).json({
                    success: false,
                    message: "Community ID tidak ditemukan"
                });
            }

            const membership = await prisma.community_members.findFirst({
                where: {
                    community_id: parseInt(communityId),
                    user_id: req.user.id,
                    status: 'active'
                }
            });

            if (!membership) {
                return res.status(403).json({
                    success: false,
                    message: "Anda bukan anggota dari komunitas ini"
                });
            }

            req.membership = membership;
            next();

        } catch (error) {
            console.error("Community Member Check Error:", error);
            return res.status(500).json({
                success: false,
                message: "Terjadi kesalahan saat validasi keanggotaan"
            });
        }
    };
};

// 📊 Check Own Resource
export const isOwnResource = (model, idParam = 'id', userIdField = 'user_id') => {
    return async (req, res, next) => {
        try {
            if (!req.user) {
                return res.status(401).json({
                    success: false,
                    message: "Silakan login terlebih dahulu"
                });
            }

            const resourceId = req.params[idParam];
            
            if (!resourceId) {
                return res.status(400).json({
                    success: false,
                    message: "Resource ID tidak ditemukan"
                });
            }

            // Cari resource di database
            const resource = await prisma[model].findUnique({
                where: {
                    [model === 'users' ? 'user_id' : `${model.slice(0, -1)}_id`]: parseInt(resourceId)
                }
            });

            if (!resource) {
                return res.status(404).json({
                    success: false,
                    message: "Resource tidak ditemukan"
                });
            }

            // Cek apakah user adalah pemilik resource
            if (resource[userIdField] !== req.user.id) {
                return res.status(403).json({
                    success: false,
                    message: "Anda tidak memiliki akses ke resource ini"
                });
            }

            req.resource = resource;
            next();

        } catch (error) {
            console.error("Own Resource Check Error:", error);
            return res.status(500).json({
                success: false,
                message: "Terjadi kesalahan saat validasi kepemilikan resource"
            });
        }
    };
};