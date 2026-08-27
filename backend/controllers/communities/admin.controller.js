import prisma from "../../lib/prisma.js";

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