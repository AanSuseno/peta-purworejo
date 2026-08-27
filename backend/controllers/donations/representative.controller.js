import prisma from "../../lib/prisma.js";
import {checkCommunityAdmin, isSystemAdmin} from './helpers.js';

// UPDATE Donation Representative
export const updateDonationRepresentative = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const { representative_id } = req.body;

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) }
        });

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        // Check if user is community admin or system admin
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (donation.community_id) {
            const adminCheck = await checkCommunityAdmin(donation.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        if (!isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi admin komunitas untuk mengupdate perwakilan"
            });
        }

        // Check if representative exists
        const representative = await prisma.users.findUnique({
            where: { user_id: parseInt(representative_id) }
        });

        if (!representative) {
            return res.status(404).json({
                success: false,
                message: "Perwakilan tidak ditemukan"
            });
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: {
                representative_id: parseInt(representative_id),
                representation_status: 'authorized',
                representation_notes: null,
                updated_at: new Date()
            },
            include: {
                users_donations_donor_idTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true,
                        phone_number: true
                    }
                },
                donation_campaigns: {
                    select: {
                        title: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Perwakilan donasi berhasil diperbarui",
            data: updatedDonation
        });

    } catch (error) {
        console.error("Update Donation Representative Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui perwakilan donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// UPDATE Representation Status
export const updateDonationRepresentationStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const { representation_status, representation_notes } = req.body;

        if (!['authorized', 'revoked', 'expired'].includes(representation_status)) {
            return res.status(400).json({
                success: false,
                message: "Status representasi tidak valid"
            });
        }

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) }
        });

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        // Check permission
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (donation.community_id) {
            const adminCheck = await checkCommunityAdmin(donation.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        if (!isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate status representasi"
            });
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: {
                representation_status: representation_status,
                representation_notes: representation_notes || null,
                updated_at: new Date()
            },
            include: {
                users_donations_donor_idTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: `Status representasi berhasil diperbarui menjadi ${representation_status}`,
            data: updatedDonation
        });

    } catch (error) {
        console.error("Update Representation Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui status representasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const verifyRepresentative = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        if (!await isSystemAdmin(userId)) {
            return res.status(403).json({
                success: false,
                message: "Hanya System Admin yang dapat memverifikasi perwakilan"
            });
        }

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) }
        });

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        if (!donation.representative_id) {
            return res.status(400).json({
                success: false,
                message: "Donasi belum memiliki perwakilan"
            });
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: {
                representation_verified_by: userId,
                representation_verified_at: new Date(),
                updated_at: new Date()
            },
            include: {
                users_donations_donor_idTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true
                    }
                },
                users_donations_representation_verified_byTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: "Perwakilan berhasil diverifikasi",
            data: updatedDonation
        });

    } catch (error) {
        console.error("Verify Representative Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memverifikasi perwakilan",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// CANCEL Verification
export const cancelVerification = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        if (!await isSystemAdmin(userId)) {
            return res.status(403).json({
                success: false,
                message: "Hanya System Admin yang dapat membatalkan verifikasi"
            });
        }

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) }
        });

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: {
                representation_verified_by: null,
                representation_verified_at: null,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Verifikasi perwakilan berhasil dibatalkan",
            data: updatedDonation
        });

    } catch (error) {
        console.error("Cancel Verification Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membatalkan verifikasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};