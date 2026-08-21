// controllers/auth.controller.js
import { OAuth2Client } from "google-auth-library";
import jwt from "jsonwebtoken";
import prisma from "../lib/prisma.js";

const googleClient = new OAuth2Client(
    process.env.GOOGLE_CLIENT_ID
);

export const googleLogin = async (req, res) => {
    try {
        const { credential } = req.body;

        if (!credential) {
            return res.status(400).json({
                success: false,
                message: "Google credential tidak ditemukan"
            });
        }

        // Verifikasi token
        let payload;
        try {
            const ticket = await googleClient.verifyIdToken({
                idToken: credential,
                audience: process.env.GOOGLE_CLIENT_ID
            });
            payload = ticket.getPayload();
        } catch (verifyError) {
            if (verifyError.message.includes('Expiration time too far in future')) {
                payload = jwt.decode(credential);
                
                const now = Math.floor(Date.now() / 1000);
                if (payload.exp && payload.exp < now) {
                    throw new Error("Token sudah expired");
                }
                if (payload.aud !== process.env.GOOGLE_CLIENT_ID) {
                    throw new Error("Client ID tidak cocok");
                }
            } else {
                throw verifyError;
            }
        }

        const {
            sub: googleId,
            email,
            name,
            picture
        } = payload;

        // Cari user berdasarkan Google ID
        let user = await prisma.users.findUnique({
            where: {
                google_id: googleId
            },
            include: {
                user_roles: true
            }
        });

        // Kalau belum ada, buat user
        if (!user) {
            // Cek apakah email sudah terdaftar
            const existingUser = await prisma.users.findUnique({
                where: {
                    email: email
                }
            });

            if (existingUser) {
                // 🔥 CEK: Apakah user yang sudah ada masih aktif?
                if (!existingUser.is_active) {
                    return res.status(403).json({
                        success: false,
                        message: "Akun Anda telah dinonaktifkan. Silakan hubungi administrator untuk mengaktifkan kembali.",
                        error: "ACCOUNT_DEACTIVATED"
                    });
                }

                // Update user yang ada
                user = await prisma.users.update({
                    where: {
                        email: email
                    },
                    data: {
                        google_id: googleId,
                        full_name: name || existingUser.full_name,
                        profile_picture: picture || existingUser.profile_picture,
                        updated_at: new Date(),
                        last_login: new Date()
                    },
                    include: {
                        user_roles: true
                    }
                });
            } else {
                // User baru - langsung aktif
                const defaultRoleId = 1;
                
                const defaultRole = await prisma.user_roles.findUnique({
                    where: {
                        role_id: defaultRoleId
                    }
                });

                let roleIdToUse;

                if (!defaultRole) {
                    const firstRole = await prisma.user_roles.findFirst();
                    if (!firstRole) {
                        throw new Error("Tidak ada role yang tersedia di database. Silakan buat role terlebih dahulu.");
                    }
                    roleIdToUse = firstRole.role_id;
                } else {
                    roleIdToUse = defaultRoleId;
                }

                user = await prisma.users.create({
                    data: {
                        google_id: googleId,
                        email: email,
                        full_name: name || email.split('@')[0],
                        profile_picture: picture || null,
                        is_verified: true,
                        is_active: true,  // ✅ User baru selalu aktif
                        role_id: roleIdToUse,
                        created_at: new Date(),
                        updated_at: new Date(),
                        last_login: new Date()
                    },
                    include: {
                        user_roles: true
                    }
                });
            }
        } else {
            // 🔥 CEK: User ditemukan, tapi apakah masih aktif?
            if (!user.is_active) {
                return res.status(403).json({
                    success: false,
                    message: "Akun Anda telah dinonaktifkan. Silakan hubungi administrator untuk mengaktifkan kembali.",
                    error: "ACCOUNT_DEACTIVATED"
                });
            }

            // Update data user
            user = await prisma.users.update({
                where: {
                    user_id: user.user_id
                },
                data: {
                    full_name: name || user.full_name,
                    profile_picture: picture || user.profile_picture,
                    last_login: new Date(),
                    updated_at: new Date()
                },
                include: {
                    user_roles: true
                }
            });
        }

        // Buat JWT
        const token = jwt.sign(
            {
                userId: user.user_id,
                email: user.email,
                fullName: user.full_name,
                role: user.role_id,
                roleName: user.user_roles?.role_name || null
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "7d"
            }
        );

        return res.json({
            success: true,
            message: "Login berhasil",
            token,
            user: {
                id: user.user_id,
                email: user.email,
                full_name: user.full_name,
                profile_picture: user.profile_picture,
                is_verified: user.is_verified,
                role_id: user.role_id,
                role_name: user.user_roles?.role_name || null
            }
        });

    } catch (error) {
        console.error("Google Login Error:", error.message);

        if (error.message.includes('Expiration time')) {
            return res.status(401).json({
                success: false,
                message: "Masalah waktu sistem, silakan sinkronkan jam komputer Anda",
                error: "TIME_SYNC_ERROR"
            });
        }

        if (error.code === 'P2002') {
            return res.status(409).json({
                success: false,
                message: "Email sudah terdaftar",
                error: "DUPLICATE_EMAIL"
            });
        }

        return res.status(500).json({
            success: false,
            message: "Login Google gagal",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};