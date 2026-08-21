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

        const user = await prisma.users.findUnique({
            where: {
                user_id: decoded.userId
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

// 🏢 Check Community Admin/Founder
export const isCommunityAdminOrFounder = (communityIdParam = 'communityId') => {
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

            // System admin memiliki akses ke semua komunitas
            if (user.user_roles?.role_name?.toLowerCase() === 'system_admin') {
                return next();
            }

            // Ambil community_id dari params, query, atau body
            const communityId = req.params[communityIdParam] || 
                               req.query[communityIdParam] || 
                               req.body[communityIdParam];

            if (!communityId) {
                return res.status(400).json({
                    success: false,
                    message: "Community ID tidak ditemukan"
                });
            }

            // Cek apakah user adalah admin atau founder dari komunitas
            const communityAdmin = await prisma.community_admins.findFirst({
                where: {
                    community_id: parseInt(communityId),
                    user_id: user.user_id,
                    role: {
                        in: ['admin', 'founder']
                    }
                }
            });

            // Cek apakah user adalah founder (dari communities table)
            const communityFounder = await prisma.communities.findFirst({
                where: {
                    community_id: parseInt(communityId),
                    founder_id: user.user_id
                }
            });

            if (!communityAdmin && !communityFounder) {
                return res.status(403).json({
                    success: false,
                    message: "Akses ditolak. Anda bukan admin atau founder dari komunitas ini.",
                    yourRole: user.user_roles?.role_name || 'unknown'
                });
            }

            // Simpan informasi admin/founder ke request
            req.communityAccess = {
                isAdmin: !!communityAdmin,
                isFounder: !!communityFounder,
                role: communityAdmin?.role || 'founder'
            };

            next();

        } catch (error) {
            console.error("Community Admin Check Error:", error);
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