import prisma from "../../lib/prisma.js";
import {checkCommunityAdmin} from './helpers.js';

export const approveCommunityDonation = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) }
        });

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        // Check if user is community admin
        let isCommunityAdmin = false;
        if (donation.community_id) {
            const adminCheck = await checkCommunityAdmin(donation.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        const isSystemAdminUser = await isSystemAdmin(userId);

        if (!isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi admin komunitas untuk menyetujui donasi"
            });
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: {
                community_approval_status: 'approved',
                community_approved_at: new Date(),
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Donasi berhasil disetujui oleh komunitas",
            data: updatedDonation
        });

    } catch (error) {
        console.error("Approve Community Donation Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menyetujui donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// REJECT Community Donation
export const rejectCommunityDonation = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) }
        });

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        // Check if user is community admin
        let isCommunityAdmin = false;
        if (donation.community_id) {
            const adminCheck = await checkCommunityAdmin(donation.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        const isSystemAdminUser = await isSystemAdmin(userId);

        if (!isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi admin komunitas untuk menolak donasi"
            });
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: {
                community_approval_status: 'rejected',
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Donasi berhasil ditolak oleh komunitas",
            data: updatedDonation
        });

    } catch (error) {
        console.error("Reject Community Donation Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menolak donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const getDonationStats = async (req, res) => {
    try {
        const userId = req.user.id;

        if (!await isSystemAdmin(userId)) {
            return res.status(403).json({
                success: false,
                message: "Hanya System Admin yang dapat mengakses statistik donasi"
            });
        }

        const [
            totalDonations,
            totalAmount,
            pendingVerifications,
            confirmedDonations,
            goodsDonations,
            volunteerRegistrations,
            completedVolunteers,
            campaignStats
        ] = await Promise.all([
            prisma.donations.count(),
            prisma.donations.aggregate({
                where: { status: 'confirmed' },
                _sum: { amount: true }
            }),
            prisma.donations.count({
                where: { status: 'pending' }
            }),
            prisma.donations.count({
                where: { status: 'confirmed' }
            }),
            prisma.donations.count({
                where: { donation_type: 'goods' }
            }),
            prisma.volunteer_registrations.count(),
            prisma.volunteer_registrations.count({
                where: { status: 'completed' }
            }),
            prisma.donation_campaigns.aggregate({
                _count: true,
                _sum: {
                    target_amount: true,
                    collected_amount: true
                }
            })
        ]);

        return res.json({
            success: true,
            data: {
                summary: {
                    total_donations: totalDonations,
                    total_amount: totalAmount._sum.amount || 0,
                    pending_verifications: pendingVerifications,
                    confirmed_donations: confirmedDonations,
                    goods_donations: goodsDonations,
                    volunteer_registrations: volunteerRegistrations,
                    completed_volunteers: completedVolunteers
                },
                campaigns: {
                    total: campaignStats._count,
                    total_target: campaignStats._sum.target_amount || 0,
                    total_collected: campaignStats._sum.collected_amount || 0
                }
            }
        });

    } catch (error) {
        console.error("Get Donation Stats Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil statistik donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Pending Verifications
export const getPendingVerifications = async (req, res) => {
    try {
        const userId = req.user.id;

        if (!await isSystemAdmin(userId)) {
            return res.status(403).json({
                success: false,
                message: "Hanya System Admin yang dapat melihat verifikasi pending"
            });
        }

        const { page = 1, limit = 20 } = req.query;
        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const [donations, total] = await Promise.all([
            prisma.donations.findMany({
                where: {
                    status: 'pending'
                },
                include: {
                    donation_campaigns: {
                        select: {
                            title: true,
                            donation_type: true,
                            communities: {
                                select: {
                                    community_name: true
                                }
                            }
                        }
                    },
                    communities: {
                        select: {
                            community_id: true,
                            community_name: true,
                            community_slug: true
                        }
                    },
                    users_donations_representative_idTousers: {
                        select: {
                            user_id: true,
                            full_name: true,
                            email: true,
                            profile_picture: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'asc'
                },
                skip,
                take
            }),
            prisma.donations.count({
                where: { status: 'pending' }
            })
        ]);

        return res.json({
            success: true,
            data: donations,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Pending Verifications Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar verifikasi pending",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET All Donations (admin)
export const getAllDonations = async (req, res) => {
    try {
        const userId = req.user.id;

        if (!await isSystemAdmin(userId)) {
            return res.status(403).json({
                success: false,
                message: "Hanya System Admin yang dapat melihat semua donasi"
            });
        }

        const {
            page = 1,
            limit = 20,
            status,
            donation_type,
            campaign_id,
            community_id,
            start_date,
            end_date
        } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {};
        if (status) where.status = status;
        if (donation_type) where.donation_type = donation_type;
        if (campaign_id) where.campaign_id = parseInt(campaign_id);
        if (community_id) where.community_id = parseInt(community_id);
        if (start_date) where.created_at = { gte: new Date(start_date) };
        if (end_date) where.created_at = { ...where.created_at, lte: new Date(end_date) };

        const [donations, total] = await Promise.all([
            prisma.donations.findMany({
                where,
                include: {
                    donation_campaigns: {
                        select: {
                            title: true,
                            donation_type: true
                        }
                    },
                    communities: {
                        select: {
                            community_id: true,
                            community_name: true,
                            community_slug: true
                        }
                    },
                    users_donations_representative_idTousers: {
                        select: {
                            user_id: true,
                            full_name: true,
                            email: true,
                            profile_picture: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'desc'
                },
                skip,
                take
            }),
            prisma.donations.count({ where })
        ]);

        return res.json({
            success: true,
            data: donations,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get All Donations Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil semua donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};