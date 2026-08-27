import prisma from "../../lib/prisma.js";
import path from "path";
import fs from 'fs';

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