// controllers/auth.controller.js
import { OAuth2Client } from "google-auth-library";
import jwt from "jsonwebtoken";
import prisma from "../lib/prisma.js";

// 🔑 Multiple Client IDs untuk berbagai platform
const CLIENT_IDS = {
  web: process.env.GOOGLE_CLIENT_ID_WEB,
  android: process.env.GOOGLE_CLIENT_ID_ANDROID,
  default: process.env.GOOGLE_CLIENT_ID_WEB, // Fallback
};

export const googleLogin = async (req, res) => {
  try {
    const { credential, platform = 'web' } = req.body; // 🔑 Terima platform

    if (!credential) {
      return res.status(400).json({
        success: false,
        message: "Google credential tidak ditemukan"
      });
    }

    // 🔑 Pilih client ID sesuai platform
    const clientId = CLIENT_IDS[platform] || CLIENT_IDS.default;
    
    console.log(`🟡 Login attempt from platform: ${platform}`);
    console.log(`🟡 Using client ID: ${clientId.substring(0, 20)}...`);

    // Verifikasi token
    let payload;
    try {
      const googleClient = new OAuth2Client(clientId);
      const ticket = await googleClient.verifyIdToken({
        idToken: credential,
        audience: clientId // 🔑 Validasi dengan client ID yang sesuai
      });
      payload = ticket.getPayload();
      console.log(`✅ Token verified for: ${payload.email}`);
    } catch (verifyError) {
      console.error("❌ Token verification error:", verifyError.message);
      
      // Fallback: coba decode manual
      try {
        payload = jwt.decode(credential);
        const now = Math.floor(Date.now() / 1000);
        
        if (payload.exp && payload.exp < now) {
          throw new Error("Token sudah expired");
        }
        
        // 🔑 Validasi audience sesuai platform
        if (payload.aud !== clientId) {
          throw new Error(`Client ID tidak cocok untuk platform ${platform}`);
        }
      } catch (decodeError) {
        throw verifyError; // Lempar error asli
      }
    }

    const {
      sub: googleId,
      email,
      name,
      picture,
      email_verified = false
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
            message: "Akun Anda telah dinonaktifkan. Silakan hubungi administrator.",
            error: "ACCOUNT_DEACTIVATED"
          });
        }

        // Update user yang ada dengan google_id
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
        console.log(`✅ Existing user updated: ${email}`);
      } else {
        // User baru - langsung aktif
        const defaultRoleId = 1;
        
        // Cek role default
        let roleIdToUse = defaultRoleId;
        const defaultRole = await prisma.user_roles.findUnique({
          where: {
            role_id: defaultRoleId
          }
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
            email: email,
            full_name: name || email.split('@')[0],
            profile_picture: picture || null,
            is_verified: email_verified || true,
            is_active: true,
            role_id: roleIdToUse,
            created_at: new Date(),
            updated_at: new Date(),
            last_login: new Date()
          },
          include: {
            user_roles: true
          }
        });
        console.log(`✅ New user created: ${email}`);
      }
    } else {
      // 🔥 CEK: User ditemukan, tapi apakah masih aktif?
      if (!user.is_active) {
        return res.status(403).json({
          success: false,
          message: "Akun Anda telah dinonaktifkan. Silakan hubungi administrator.",
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
      console.log(`✅ User updated: ${email}`);
    }

    // Buat JWT dengan info platform
    const token = jwt.sign(
      {
        userId: user.user_id,
        email: user.email,
        fullName: user.full_name,
        role: user.role_id,
        roleName: user.user_roles?.role_name || null,
        platform: platform // 🔑 Tambahkan platform ke JWT
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
        is_active: user.is_active,
        role_id: user.role_id,
        role_name: user.user_roles?.role_name || null
      }
    });

  } catch (error) {
    console.error("❌ Google Login Error:", error.message);
    console.error("📚 Stack:", error.stack);

    // Error handling yang lebih baik
    if (error.message.includes('Expiration time')) {
      return res.status(401).json({
        success: false,
        message: "Token Google sudah kadaluarsa. Silakan login ulang.",
        error: "TOKEN_EXPIRED"
      });
    }

    if (error.message.includes('Client ID tidak cocok')) {
      return res.status(401).json({
        success: false,
        message: "Client ID tidak cocok. Pastikan menggunakan aplikasi yang benar.",
        error: "INVALID_CLIENT_ID"
      });
    }

    if (error.code === 'P2002') {
      return res.status(409).json({
        success: false,
        message: "Email sudah terdaftar dengan akun lain.",
        error: "DUPLICATE_EMAIL"
      });
    }

    return res.status(500).json({
      success: false,
      message: "Login Google gagal. Silakan coba lagi.",
      error: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
};