// controllers/auth.mobile.controller.js
import { OAuth2Client } from "google-auth-library";
import jwt from "jsonwebtoken";
import prisma from "../lib/prisma.js";

const MOBILE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID_WEB;

if (!MOBILE_CLIENT_ID) {
  throw new Error("GOOGLE_CLIENT_ID_WEB belum diset di .env");
}

export const mobileGoogleLogin = async (req, res) => {
  try {
    const { credential, platform = "mobile" } = req.body;

    // Validasi input
    if (!credential) {
      return res.status(400).json({
        success: false,
        message: "Google credential tidak ditemukan",
        error: "MISSING_CREDENTIAL",
      });
    }

    console.log(`📱 Mobile login attempt from platform: ${platform}`);

    let payload;
    try {
      const googleClient = new OAuth2Client(MOBILE_CLIENT_ID);
      const ticket = await googleClient.verifyIdToken({
        idToken: credential,
        audience: MOBILE_CLIENT_ID,
      });
      payload = ticket.getPayload();
      console.log(`✅ Token verified for mobile user: ${payload.email}`);
    } catch (verifyError) {
      console.error("❌ Mobile token verification error:", verifyError.message);
      return res.status(401).json({
        success: false,
        message: "Token Google tidak valid atau kadaluarsa. Silakan login ulang.",
        error: "INVALID_TOKEN",
      });
    }

    const {
      sub: googleId,
      email,
      name,
      picture,
      email_verified,
    } = payload;

    // Validasi email
    if (!email) {
      return res.status(400).json({
        success: false,
        message: "Email tidak ditemukan dari Google",
        error: "MISSING_EMAIL",
      });
    }

    // Cari atau buat user
    let user = await prisma.users.findUnique({
      where: { google_id: googleId },
      include: { user_roles: true },
    });

    if (!user) {
      // Cek apakah email sudah terdaftar (misal daftar lewat cara lain)
      const existingUser = await prisma.users.findUnique({
        where: { email },
        include: { user_roles: true },
      });

      if (existingUser) {
        if (!existingUser.is_active) {
          return res.status(403).json({
            success: false,
            message: "Akun Anda telah dinonaktifkan. Silakan hubungi administrator.",
            error: "ACCOUNT_DEACTIVATED",
          });
        }

        user = await prisma.users.update({
          where: { email },
          data: {
            google_id: googleId,
            full_name: name || existingUser.full_name,
            profile_picture: picture || existingUser.profile_picture,
            updated_at: new Date(),
            last_login: new Date(),
          },
          include: { user_roles: true },
        });
        console.log(`✅ Existing mobile user updated: ${email}`);
      } else {
        const defaultRoleId = 1;

        let roleIdToUse = defaultRoleId;
        const defaultRole = await prisma.user_roles.findUnique({
          where: { role_id: defaultRoleId },
        });

        if (!defaultRole) {
          const firstRole = await prisma.user_roles.findFirst();
          if (!firstRole) {
            throw new Error("Tidak ada role yang tersedia di database");
          }
          roleIdToUse = firstRole.role_id;
        }

        user = await prisma.users.create({
          data: {
            google_id: googleId,
            email,
            full_name: name || email.split("@")[0],
            profile_picture: picture || null,
            // FIX: sebelumnya `email_verified || true` selalu bernilai true
            // apa pun isi email_verified. Sekarang benar-benar mengikuti
            // status dari Google.
            is_verified: Boolean(email_verified),
            is_active: true,
            role_id: roleIdToUse,
            created_at: new Date(),
            updated_at: new Date(),
            last_login: new Date(),
          },
          include: { user_roles: true },
        });
        console.log(`✅ New mobile user created: ${email}`);
      }
    } else {
      if (!user.is_active) {
        return res.status(403).json({
          success: false,
          message: "Akun Anda telah dinonaktifkan. Silakan hubungi administrator.",
          error: "ACCOUNT_DEACTIVATED",
        });
      }

      user = await prisma.users.update({
        where: { user_id: user.user_id },
        data: {
          full_name: name || user.full_name,
          profile_picture: picture || user.profile_picture,
          last_login: new Date(),
          updated_at: new Date(),
        },
        include: { user_roles: true },
      });
      console.log(`✅ Mobile user updated: ${email}`);
    }

    const token = jwt.sign(
      {
        userId: user.user_id,
        email: user.email,
        fullName: user.full_name,
        role: user.role_id,
        roleName: user.user_roles?.role_name || null,
        platform,
        clientType: "mobile",
      },
      process.env.JWT_SECRET,
      { expiresIn: "30d" }
    );

    return res.status(200).json({
      success: true,
      message: "Login berhasil",
      token,
      user: {
        id: user.user_id,
        email: user.email,
        full_name: user.full_name,
        profile_picture: user.profile_picture,
        is_verified: user.is_verified,
        is_active: user.is_active,
        role_id: user.role_id,
        role_name: user.user_roles?.role_name || null,
        platform,
      },
    });
  } catch (error) {
    console.error("❌ Mobile Google Login Error:", error.message);
    console.error("📚 Stack:", error.stack);

    if (error.code === "P2002") {
      return res.status(409).json({
        success: false,
        message: "Email sudah terdaftar dengan akun lain.",
        error: "DUPLICATE_EMAIL",
      });
    }

    return res.status(500).json({
      success: false,
      message: "Login Google gagal. Silakan coba lagi.",
      error: process.env.NODE_ENV === "development" ? error.message : "INTERNAL_SERVER_ERROR",
    });
  }
};

/// Endpoint baru: GET /auth/me
/// Dipakai Flutter saat app dibuka untuk memvalidasi JWT yang tersimpan
/// dan mengambil data profil terbaru, tanpa perlu login ulang ke Google.
/// Pasang di belakang middleware `requireAuth` (lihat auth.middleware.js).
export const getMe = async (req, res) => {
  try {
    const user = await prisma.users.findUnique({
      where: { user_id: req.user.userId },
      include: { user_roles: true },
    });

    if (!user || !user.is_active) {
      return res.status(401).json({
        success: false,
        message: "Sesi tidak valid",
        error: "INVALID_SESSION",
      });
    }

    return res.status(200).json({
      success: true,
      user: {
        id: user.user_id,
        email: user.email,
        full_name: user.full_name,
        profile_picture: user.profile_picture,
        is_verified: user.is_verified,
        is_active: user.is_active,
        role_id: user.role_id,
        role_name: user.user_roles?.role_name || null,
      },
    });
  } catch (error) {
    console.error("❌ getMe error:", error.message);
    return res.status(500).json({
      success: false,
      message: "Gagal mengambil profil",
      error: "INTERNAL_SERVER_ERROR",
    });
  }
};
