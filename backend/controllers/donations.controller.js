// controllers/donations.controller.js
import prisma from "../lib/prisma.js";
import fs from "fs";
import path from "path";

// ============================================
// HELPER FUNCTIONS
// ============================================

// Check if user is community admin or founder
const checkCommunityAdmin = async (communityId, userId) => {
    const admin = await prisma.community_admins.findFirst({
        where: {
            community_id: parseInt(communityId),
            user_id: userId
        }
    });
    
    if (admin) return { isAdmin: true, role: admin.role };
    
    // Check if user is founder from communities table
    const community = await prisma.communities.findUnique({
        where: { community_id: parseInt(communityId) },
        select: { founder_id: true }
    });
    
    if (community && community.founder_id === userId) {
        return { isAdmin: true, role: 'founder' };
    }
    
    return { isAdmin: false };
};

// Check if user is system admin
const isSystemAdmin = async (userId) => {
    const user = await prisma.users.findUnique({
        where: { user_id: userId },
        include: { user_roles: true }
    });
    return user?.user_roles?.role_name?.toLowerCase() === 'system_admin';
};

// ============================================
// 📊 CAMPAIGN CRUD
// ============================================

// GET All Campaigns
export const getCampaigns = async (req, res) => {
    try {
        const {
            page = 1,
            limit = 10,
            status,
            donation_type,
            community_id,
            search,
            show_pending = false // filter untuk admin
        } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        // Build where clause
        const where = {};

        // 🔥 IMPORTANT: DEFAULT hanya tampilkan campaign yang APPROVED
        // Kecuali admin minta lihat pending
        if (show_pending !== 'true') {
            where.approval_status = 'approved';
        }

        // ✅ VALIDATE status against enum
        const validStatuses = ['pending', 'active', 'completed', 'cancelled'];
        if (status && validStatuses.includes(status)) {
            where.status = status;
        } else if (status) {
            // Log invalid status but don't error - just ignore it
            console.warn(`Invalid status value received: ${status}, ignoring filter`);
        }

        if (status) where.status = status;
        if (donation_type) where.donation_type = donation_type;
        if (community_id) where.community_id = parseInt(community_id);
        if (search) {
            where.OR = [
                { title: { contains: search, mode: 'insensitive' } },
                { description: { contains: search, mode: 'insensitive' } }
            ];
        }

        const [campaigns, total] = await Promise.all([
            prisma.donation_campaigns.findMany({
                where,
                include: {
                    communities: {
                        select: {
                            community_id: true,
                            community_name: true,
                            community_slug: true,
                            logo: true
                        }
                    },
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            email: true,
                            profile_picture: true
                        }
                    },
                    _count: {
                        select: {
                            donations: true,
                            volunteer_registrations: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'desc'
                },
                skip,
                take
            }),
            prisma.donation_campaigns.count({ where })
        ]);

        // Format response
        const formattedCampaigns = campaigns.map(campaign => ({
            ...campaign,
            total_donors: campaign._count.donations,
            total_volunteers: campaign._count.volunteer_registrations,
            progress: campaign.target_amount 
                ? Math.min((parseFloat(campaign.collected_amount) / parseFloat(campaign.target_amount)) * 100, 100)
                : 0,
            // Tambahkan info approval
            is_approved: campaign.approval_status === 'approved',
            is_pending: campaign.approval_status === 'pending',
            is_rejected: campaign.approval_status === 'rejected',
            _count: undefined
        }));
        console.log(formattedCampaigns)

        return res.json({
            success: true,
            data: formattedCampaigns,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Campaigns Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar campaign",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Campaign by ID
export const getCampaignById = async (req, res) => {
    try {
        const { id } = req.params;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) },
            include: {
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true,
                        logo: true,
                        description: true
                    }
                },
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true,
                        phone_number: true
                    }
                },
                donations: {
                    where: {
                        status: 'confirmed'
                    },
                    include: {
                        users_donations_representative_idTousers: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true
                            }
                        }
                    },
                    orderBy: {
                        created_at: 'desc'
                    },
                    take: 5
                },
                volunteer_registrations: {
                    where: {
                        status: 'confirmed'
                    },
                    include: {
                        users: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true,
                                phone_number: true
                            }
                        }
                    },
                    orderBy: {
                        created_at: 'desc'
                    },
                    take: 5
                },
                _count: {
                    select: {
                        donations: true,
                        volunteer_registrations: true
                    }
                }
            }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Get donation stats
        const donationStats = await prisma.donations.aggregate({
            where: {
                campaign_id: parseInt(id),
                status: 'confirmed'
            },
            _sum: {
                amount: true
            },
            _count: true
        });

        const formattedCampaign = {
            ...campaign,
            total_donors: campaign._count.donations,
            total_volunteers: campaign._count.volunteer_registrations,
            collected_amount: parseFloat(campaign.collected_amount),
            target_amount: campaign.target_amount ? parseFloat(campaign.target_amount) : null,
            progress: campaign.target_amount 
                ? Math.min((parseFloat(campaign.collected_amount) / parseFloat(campaign.target_amount)) * 100, 100)
                : 0,
            donation_stats: {
                total_confirmed: donationStats._count,
                total_amount: donationStats._sum.amount || 0
            },
            _count: undefined
        };

        return res.json({
            success: true,
            data: formattedCampaign
        });

    } catch (error) {
        console.error("Get Campaign By ID Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil campaign donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Campaign Stats
export const getCampaignStats = async (req, res) => {
    try {
        const { id } = req.params;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Get all donation stats
        const [donationStats, volunteerStats, recentDonations] = await Promise.all([
            prisma.donations.aggregate({
                where: {
                    campaign_id: parseInt(id),
                    status: 'confirmed'
                },
                _sum: {
                    amount: true
                },
                _count: true
            }),
            prisma.volunteer_registrations.aggregate({
                where: {
                    campaign_id: parseInt(id),
                    status: 'confirmed'
                },
                _count: true
            }),
            prisma.donations.findMany({
                where: {
                    campaign_id: parseInt(id),
                    status: 'confirmed'
                },
                include: {
                    users_donations_representative_idTousers: {
                        select: {
                            user_id: true,
                            full_name: true,
                            profile_picture: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'desc'
                },
                take: 10
            })
        ]);

        return res.json({
            success: true,
            data: {
                campaign_id: parseInt(id),
                title: campaign.title,
                status: campaign.status,
                target_amount: campaign.target_amount,
                collected_amount: campaign.collected_amount,
                progress: campaign.target_amount 
                    ? Math.min((parseFloat(campaign.collected_amount) / parseFloat(campaign.target_amount)) * 100, 100)
                    : 0,
                total_donors: donationStats._count,
                total_volunteers: volunteerStats._count,
                recent_donations: recentDonations,
                start_date: campaign.start_date,
                end_date: campaign.end_date
            }
        });

    } catch (error) {
        console.error("Get Campaign Stats Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil statistik campaign",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Campaign Donation Summary
export const getCampaignDonationSummary = async (req, res) => {
    try {
        const { id } = req.params;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Group donations by type
        const donationsByType = await prisma.donations.groupBy({
            by: ['donation_type'],
            where: {
                campaign_id: parseInt(id),
                status: 'confirmed'
            },
            _count: true,
            _sum: {
                amount: true
            }
        });

        // Get money donations breakdown
        const moneyDonations = await prisma.donations.findMany({
            where: {
                campaign_id: parseInt(id),
                donation_type: 'money',
                status: 'confirmed'
            },
            select: {
                amount: true,
                payment_method: true,
                is_anonymous: true,
                created_at: true
            }
        });

        // Get goods donations breakdown
        const goodsDonations = await prisma.donations.findMany({
            where: {
                campaign_id: parseInt(id),
                donation_type: 'goods',
                status: 'confirmed'
            },
            select: {
                goods_type: true,
                goods_name: true,
                goods_quantity: true,
                goods_unit: true,
                is_anonymous: true,
                created_at: true
            }
        });

        // Get volunteer registrations
        const volunteers = await prisma.volunteer_registrations.findMany({
            where: {
                campaign_id: parseInt(id),
                status: 'confirmed'
            },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        phone_number: true,
                        profile_picture: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            data: {
                campaign_id: parseInt(id),
                title: campaign.title,
                summary: {
                    total_donations: donationsByType.reduce((acc, d) => acc + d._count, 0),
                    total_amount: donationsByType.reduce((acc, d) => acc + (d._sum.amount || 0), 0),
                    total_volunteers: volunteers.length
                },
                breakdown: {
                    money: {
                        count: donationsByType.find(d => d.donation_type === 'money')?._count || 0,
                        amount: donationsByType.find(d => d.donation_type === 'money')?._sum.amount || 0,
                        details: moneyDonations
                    },
                    goods: {
                        count: donationsByType.find(d => d.donation_type === 'goods')?._count || 0,
                        details: goodsDonations
                    },
                    volunteer: {
                        count: volunteers.length,
                        details: volunteers.map(v => ({
                            user_id: v.user_id,
                            full_name: v.users.full_name,
                            phone_number: v.users.phone_number,
                            availability: v.availability,
                            skills: v.skills,
                            notes: v.notes
                        }))
                    }
                }
            }
        });

    } catch (error) {
        console.error("Get Campaign Donation Summary Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil ringkasan donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// CREATE Campaign
export const createCampaign = async (req, res) => {
    try {
        const userId = req.user.id;
        const {
            title,
            description,
            donation_type,
            target_amount,
            bank_account_info,
            ewallet_info,
            goods_description,
            volunteer_needs,
            volunteer_slots,
            start_date,
            end_date,
            community_id
        } = req.body;

        // Validasi
        if (!title || title.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Judul campaign wajib diisi"
            });
        }

        if (!donation_type || !['money', 'goods', 'volunteer'].includes(donation_type)) {
            return res.status(400).json({
                success: false,
                message: "Tipe donasi tidak valid"
            });
        }

        // Cek community
        let community = null;
        let isSystemAdminUser = false;
        let isCommunityAdmin = false;

        if (community_id) {
            community = await prisma.communities.findUnique({
                where: { community_id: parseInt(community_id) }
            });

            if (!community) {
                return res.status(404).json({
                    success: false,
                    message: "Komunitas tidak ditemukan"
                });
            }

            // Cek apakah user adalah admin/founder
            const adminCheck = await checkCommunityAdmin(community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
            isSystemAdminUser = await isSystemAdmin(userId);

            // Cek apakah user adalah MEMBER (bukan admin)
            const membership = await prisma.community_members.findFirst({
                where: {
                    community_id: parseInt(community_id),
                    user_id: userId,
                    status: 'active'
                }
            });

            // Jika bukan admin dan bukan system admin, HARUS jadi member
            if (!isCommunityAdmin && !isSystemAdminUser) {
                if (!membership) {
                    return res.status(403).json({
                        success: false,
                        message: "Anda harus menjadi anggota komunitas untuk membuat campaign donasi"
                    });
                }
            }
        }

        // Build campaign data
        const campaignData = {
            title: title.trim(),
            description: description || null,
            donation_type: donation_type,
            creator_id: userId,
            target_amount: target_amount ? parseFloat(target_amount) : null,
            bank_account_info: bank_account_info || null,
            ewallet_info: ewallet_info || null,
            goods_description: goods_description || null,
            volunteer_needs: volunteer_needs || null,
            volunteer_slots: volunteer_slots ? parseInt(volunteer_slots) : null,
            start_date: start_date ? new Date(start_date) : null,
            end_date: end_date ? new Date(end_date) : null,
            status: 'active', // ✅ Valid enum value
            collected_amount: 0,
            total_donors: 0,
            created_at: new Date(),
            updated_at: new Date()
        };

        // 🔥 KUNCI: Tentukan approval_status
        // - Admin/Founder/System Admin: langsung approved
        // - Member biasa: pending approval
        if (isCommunityAdmin || isSystemAdminUser) {
            campaignData.approval_status = 'approved';
            campaignData.approved_by = userId;
            campaignData.approved_at = new Date();
        } else {
            campaignData.approval_status = 'pending';
        }

        // Only add community_id if it exists
        if (community_id) {
            campaignData.community_id = parseInt(community_id);
        }

        const campaign = await prisma.donation_campaigns.create({
            data: campaignData,
            include: {
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true
                    }
                },
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true
                    }
                },
                users_donation_campaigns_approved_byTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true
                    }
                }
            }
        });

        // Message berbeda tergantung approval status
        const message = campaign.approval_status === 'approved'
            ? "Campaign donasi berhasil dibuat dan langsung aktif"
            : "Campaign donasi berhasil dibuat, menunggu persetujuan admin komunitas";

        return res.status(201).json({
            success: true,
            message: message,
            data: campaign
        });

    } catch (error) {
        console.error("Create Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membuat campaign donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// UPDATE Campaign
export const updateCampaign = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const {
            title,
            description,
            target_amount,
            bank_account_info,
            ewallet_info,
            goods_description,
            volunteer_needs,
            volunteer_slots,
            start_date,
            end_date,
            status
        } = req.body;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Check permission
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(campaign.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        const isCreator = campaign.creator_id === userId;

        if (!isCreator && !isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate campaign ini"
            });
        }

        // Build update data
        const updateData = {
            title: title ? title.trim() : undefined,
            description: description !== undefined ? description : undefined,
            target_amount: target_amount !== undefined ? parseFloat(target_amount) : undefined,
            bank_account_info: bank_account_info !== undefined ? bank_account_info : undefined,
            ewallet_info: ewallet_info !== undefined ? ewallet_info : undefined,
            goods_description: goods_description !== undefined ? goods_description : undefined,
            volunteer_needs: volunteer_needs !== undefined ? volunteer_needs : undefined,
            volunteer_slots: volunteer_slots !== undefined ? parseInt(volunteer_slots) : undefined,
            start_date: start_date !== undefined ? new Date(start_date) : undefined,
            end_date: end_date !== undefined ? new Date(end_date) : undefined,
            updated_at: new Date()
        };

        // Only system admin can change status
        if (status && isSystemAdminUser) {
            updateData.status = status;
        }

        const updatedCampaign = await prisma.donation_campaigns.update({
            where: { campaign_id: parseInt(id) },
            data: updateData,
            include: {
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true
                    }
                },
                users: {
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
            message: "Campaign donasi berhasil diperbarui",
            data: updatedCampaign
        });

    } catch (error) {
        console.error("Update Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui campaign donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// TOGGLE Campaign Status
export const toggleCampaignStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;
        const userId = req.user.id;

        const validStatuses = ['active', 'completed', 'cancelled'];
        if (!status || !validStatuses.includes(status)) {
            return res.status(400).json({
                success: false,
                message: "Status tidak valid. Gunakan: active, completed, atau cancelled"
            });
        }

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Check permission
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(campaign.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        const isCreator = campaign.creator_id === userId;

        if (!isCreator && !isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengubah status campaign"
            });
        }

        const updatedCampaign = await prisma.donation_campaigns.update({
            where: { campaign_id: parseInt(id) },
            data: {
                status: status,
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: `Status campaign berhasil diubah menjadi ${status}`,
            data: updatedCampaign
        });

    } catch (error) {
        console.error("Toggle Campaign Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengubah status campaign",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// DELETE Campaign
export const deleteCampaign = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Check permission
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(campaign.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        const isCreator = campaign.creator_id === userId;

        if (!isCreator && !isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk menghapus campaign ini"
            });
        }

        // Soft delete - update status to cancelled
        await prisma.donation_campaigns.update({
            where: { campaign_id: parseInt(id) },
            data: {
                status: 'cancelled',
                updated_at: new Date()
            }
        });

        return res.json({
            success: true,
            message: "Campaign donasi berhasil dihapus"
        });

    } catch (error) {
        console.error("Delete Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menghapus campaign donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// ============================================
// 💰 DONATIONS
// ============================================

// CREATE Donation
export const createDonation = async (req, res) => {
    try {
        const { id } = req.params; // campaign_id
        const userId = req.user.id;
        const {
            donation_type,
            amount,
            payment_method,
            // Goods fields
            goods_type,
            goods_name,
            goods_quantity,
            goods_unit,
            delivery_method,
            delivery_address,
            // Volunteer fields
            volunteer_availability,
            volunteer_skill,
            volunteer_notes,
            // Donor info
            donor_name,
            donor_phone,
            donor_email,
            is_anonymous,
            // Community representation
            community_id,
            donation_purpose,
            // Representative
            representative_id
        } = req.body;

        // Validasi
        if (!donation_type || !['money', 'goods', 'volunteer'].includes(donation_type)) {
            return res.status(400).json({
                success: false,
                message: "Tipe donasi tidak valid"
            });
        }

        // Get campaign
        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        if (campaign.status !== 'active') {
            return res.status(400).json({
                success: false,
                message: `Campaign sudah ${campaign.status}`
            });
        }

        // Validate based on donation type
        if (donation_type === 'money') {
            if (!amount || parseFloat(amount) <= 0) {
                return res.status(400).json({
                    success: false,
                    message: "Jumlah donasi wajib diisi dan harus lebih dari 0"
                });
            }
        }

        if (donation_type === 'goods') {
            if (!goods_name) {
                return res.status(400).json({
                    success: false,
                    message: "Nama barang wajib diisi"
                });
            }
        }

        if (donation_type === 'volunteer') {
            if (!volunteer_availability) {
                return res.status(400).json({
                    success: false,
                    message: "Ketersediaan waktu wajib diisi"
                });
            }
        }

        // Build donation data
        const donationData = {
            campaign_id: parseInt(id),
            donor_id: userId,
            donation_type: donation_type,
            is_anonymous: is_anonymous === 'true' || is_anonymous === true,
            status: 'pending',
            created_at: new Date(),
            community_id: community_id ? parseInt(community_id) : campaign.community_id,
            donation_purpose: donation_purpose || null
        };

        // Add type-specific fields
        if (donation_type === 'money') {
            donationData.amount = parseFloat(amount);
            donationData.payment_method = payment_method || null;
            
            // Handle proof image upload
            if (req.file) {
                donationData.proof_image = `/uploads/donations/${req.file.filename}`;
            }
        }

        if (donation_type === 'goods') {
            donationData.goods_type = goods_type || null;
            donationData.goods_name = goods_name;
            donationData.goods_quantity = goods_quantity ? parseInt(goods_quantity) : null;
            donationData.goods_unit = goods_unit || 'unit';
            donationData.delivery_method = delivery_method || null;
            donationData.delivery_address = delivery_address || null;
            
            // Handle goods photo upload
            if (req.file) {
                donationData.goods_photo = `/uploads/donations/${req.file.filename}`;
            }
        }

        if (donation_type === 'volunteer') {
            donationData.volunteer_availability = volunteer_availability;
            donationData.volunteer_skill = volunteer_skill || null;
            donationData.volunteer_notes = volunteer_notes || null;
        }

        // Donor info (if provided, otherwise use user data)
        const user = await prisma.users.findUnique({
            where: { user_id: userId }
        });

        donationData.donor_name = donor_name || user.full_name;
        donationData.donor_phone = donor_phone || user.phone_number;
        donationData.donor_email = donor_email || user.email;

        // Set representative if provided
        if (representative_id) {
            const representative = await prisma.users.findUnique({
                where: { user_id: parseInt(representative_id) }
            });

            if (!representative) {
                return res.status(404).json({
                    success: false,
                    message: "Perwakilan tidak ditemukan"
                });
            }

            donationData.representative_id = parseInt(representative_id);
            donationData.representation_status = 'authorized';
        }

        // Create donation
        const donation = await prisma.donations.create({
            data: donationData,
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
                        profile_picture: true,
                        phone_number: true
                    }
                }
            }
        });

        // If money donation and representative is set, auto-approve community
        if (donation_type === 'money' && representative_id) {
            await prisma.donations.update({
                where: { donation_id: donation.donation_id },
                data: {
                    community_approval_status: 'approved',
                    community_approved_at: new Date()
                }
            });
        }

        return res.status(201).json({
            success: true,
            message: "Donasi berhasil dibuat, menunggu verifikasi",
            data: donation
        });

    } catch (error) {
        console.error("Create Donation Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membuat donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET My Donations
export const getMyDonations = async (req, res) => {
    try {
        const userId = req.user.id;
        const { page = 1, limit = 10, status, donation_type } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {
            donor_id: userId
        };

        if (status) where.status = status;
        if (donation_type) where.donation_type = donation_type;

        const [donations, total] = await Promise.all([
            prisma.donations.findMany({
                where,
                include: {
                    donation_campaigns: {
                        select: {
                            title: true,
                            donation_type: true,
                            communities: {
                                select: {
                                    community_name: true,
                                    community_slug: true
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
        console.error("Get My Donations Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Donations by Campaign
export const getDonationsByCampaign = async (req, res) => {
    try {
        const { id } = req.params;
        const { page = 1, limit = 20, status, donation_type } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {
            campaign_id: parseInt(id)
        };

        if (status) where.status = status;
        if (donation_type) where.donation_type = donation_type;

        const [donations, total] = await Promise.all([
            prisma.donations.findMany({
                where,
                include: {
                    users_donations_representative_idTousers: {
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
                    },
                    communities: {
                        select: {
                            community_name: true
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

        // Calculate totals
        const totals = await prisma.donations.aggregate({
            where: {
                campaign_id: parseInt(id),
                status: 'confirmed'
            },
            _sum: {
                amount: true
            },
            _count: true
        });

        return res.json({
            success: true,
            data: donations,
            summary: {
                total_donations: totals._count,
                total_amount: totals._sum.amount || 0
            },
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Donations By Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Donations by Community
export const getDonationsByCommunity = async (req, res) => {
    try {
        const { id } = req.params;
        const { page = 1, limit = 20, status, donation_type } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {
            community_id: parseInt(id)
        };

        if (status) where.status = status;
        if (donation_type) where.donation_type = donation_type;

        const [donations, total] = await Promise.all([
            prisma.donations.findMany({
                where,
                include: {
                    users_donations_representative_idTousers: {
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
                            title: true,
                            donation_type: true
                        }
                    },
                    communities: {
                        select: {
                            community_name: true,
                            community_slug: true
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

        // Get community donation summary
        const summary = await prisma.donations.aggregate({
            where: {
                community_id: parseInt(id),
                status: 'confirmed'
            },
            _sum: {
                amount: true
            },
            _count: true
        });

        return res.json({
            success: true,
            data: donations,
            summary: {
                total_donations: summary._count,
                total_amount: summary._sum.amount || 0
            },
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Donations By Community Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Donation by ID
export const getDonationById = async (req, res) => {
    try {
        const { id } = req.params;

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) },
            include: {
                donation_campaigns: {
                    select: {
                        title: true,
                        donation_type: true,
                        target_amount: true,
                        collected_amount: true,
                        communities: {
                            select: {
                                community_name: true,
                                community_slug: true
                            }
                        }
                    }
                },
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true,
                        logo: true
                    }
                },
                users_donations_representative_idTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true,
                        phone_number: true
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

        if (!donation) {
            return res.status(404).json({
                success: false,
                message: "Donasi tidak ditemukan"
            });
        }

        return res.json({
            success: true,
            data: donation
        });

    } catch (error) {
        console.error("Get Donation By ID Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// UPDATE Donation Status
export const updateDonationStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;
        const userId = req.user.id;

        if (!['pending', 'confirmed', 'rejected', 'delivered'].includes(status)) {
            return res.status(400).json({
                success: false,
                message: "Status tidak valid"
            });
        }

        const donation = await prisma.donations.findUnique({
            where: { donation_id: parseInt(id) },
            include: {
                donation_campaigns: true
            }
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

        // Campaign creator can manage their campaign donations
        const isCampaignCreator = donation.donation_campaigns.creator_id === userId;

        if (!isSystemAdminUser && !isCommunityAdmin && !isCampaignCreator) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate status donasi"
            });
        }

        // Prepare update data
        const updateData = {
            status: status,
            updated_at: new Date()
        };

        // If status is confirmed, update campaign collected amount
        if (status === 'confirmed' && donation.status !== 'confirmed') {
            updateData.confirmed_at = new Date();
            
            // Update campaign collected amount for money donations
            if (donation.donation_type === 'money' && donation.amount) {
                await prisma.donation_campaigns.update({
                    where: { campaign_id: donation.campaign_id },
                    data: {
                        collected_amount: {
                            increment: donation.amount
                        },
                        total_donors: {
                            increment: 1
                        }
                    }
                });
            }
        }

        // If status is rejected and was previously confirmed, decrement
        if (status === 'rejected' && donation.status === 'confirmed') {
            if (donation.donation_type === 'money' && donation.amount) {
                await prisma.donation_campaigns.update({
                    where: { campaign_id: donation.campaign_id },
                    data: {
                        collected_amount: {
                            decrement: donation.amount
                        },
                        total_donors: {
                            decrement: 1
                        }
                    }
                });
            }
        }

        const updatedDonation = await prisma.donations.update({
            where: { donation_id: parseInt(id) },
            data: updateData,
            include: {
                donation_campaigns: {
                    select: {
                        title: true,
                        collected_amount: true,
                        total_donors: true
                    }
                },
                users_donations_representative_idTousers: {
                    select: {
                        user_id: true,
                        full_name: true,
                        profile_picture: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: `Status donasi berhasil diperbarui menjadi ${status}`,
            data: updatedDonation
        });

    } catch (error) {
        console.error("Update Donation Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui status donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// VERIFY Donation (admin only)
export const verifyDonation = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const { is_verified } = req.body;

        // Check if user is system admin
        if (!await isSystemAdmin(userId)) {
            return res.status(403).json({
                success: false,
                message: "Hanya System Admin yang dapat memverifikasi donasi"
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
                is_verified: is_verified === 'true' || is_verified === true,
                updated_at: new Date()
            },
            include: {
                donation_campaigns: {
                    select: {
                        title: true
                    }
                },
                communities: {
                    select: {
                        community_name: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: `Donasi berhasil ${is_verified ? 'diverifikasi' : 'unverifikasi'}`,
            data: updatedDonation
        });

    } catch (error) {
        console.error("Verify Donation Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memverifikasi donasi",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// ============================================
// 👥 COMMUNITY REPRESENTATIVE
// ============================================

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
                users_donations_representative_idTousers: {
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
                users_donations_representative_idTousers: {
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

// VERIFY Representative (admin only)
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
                users_donations_representative_idTousers: {
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

// ============================================
// ✅ COMMUNITY APPROVALS
// ============================================

// APPROVE Community Donation
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

// ============================================
// 🧑‍🤝‍🧑 VOLUNTEER REGISTRATIONS
// ============================================

// REGISTER as Volunteer
export const registerAsVolunteer = async (req, res) => {
    try {
        const { id } = req.params; // campaign_id
        const userId = req.user.id;
        const {
            availability,
            skills,
            experience,
            notes
        } = req.body;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        if (campaign.status !== 'active') {
            return res.status(400).json({
                success: false,
                message: `Campaign sudah ${campaign.status}`
            });
        }

        // Check if already registered
        const existingRegistration = await prisma.volunteer_registrations.findFirst({
            where: {
                campaign_id: parseInt(id),
                user_id: userId
            }
        });

        if (existingRegistration) {
            return res.status(400).json({
                success: false,
                message: "Anda sudah terdaftar sebagai volunteer untuk campaign ini"
            });
        }

        // Check quota
        if (campaign.volunteer_slots) {
            const currentVolunteers = await prisma.volunteer_registrations.count({
                where: {
                    campaign_id: parseInt(id),
                    status: 'confirmed'
                }
            });

            if (currentVolunteers >= campaign.volunteer_slots) {
                return res.status(400).json({
                    success: false,
                    message: "Kuota volunteer sudah penuh"
                });
            }
        }

        const registration = await prisma.volunteer_registrations.create({
            data: {
                campaign_id: parseInt(id),
                user_id: userId,
                availability: availability || null,
                skills: skills || null,
                experience: experience || null,
                notes: notes || null,
                status: 'pending',
                created_at: new Date()
            },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        phone_number: true,
                        profile_picture: true,
                        bio: true,
                        interests: true
                    }
                },
                donation_campaigns: {
                    select: {
                        title: true,
                        volunteer_needs: true
                    }
                }
            }
        });

        return res.status(201).json({
            success: true,
            message: "Berhasil mendaftar sebagai volunteer, menunggu konfirmasi",
            data: registration
        });

    } catch (error) {
        console.error("Register As Volunteer Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mendaftar sebagai volunteer",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// UPDATE Volunteer Status
export const updateVolunteerStatus = async (req, res) => {
    try {
        const { id } = req.params; // registration_id
        const userId = req.user.id;
        const { status, assigned_task } = req.body;

        if (!['pending', 'confirmed', 'declined', 'completed'].includes(status)) {
            return res.status(400).json({
                success: false,
                message: "Status tidak valid"
            });
        }

        const registration = await prisma.volunteer_registrations.findUnique({
            where: { registration_id: parseInt(id) },
            include: {
                donation_campaigns: true
            }
        });

        if (!registration) {
            return res.status(404).json({
                success: false,
                message: "Registrasi volunteer tidak ditemukan"
            });
        }

        // Check permission
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (registration.donation_campaigns.community_id) {
            const adminCheck = await checkCommunityAdmin(
                registration.donation_campaigns.community_id, 
                userId
            );
            isCommunityAdmin = adminCheck.isAdmin;
        }

        const isCampaignCreator = registration.donation_campaigns.creator_id === userId;

        if (!isSystemAdminUser && !isCommunityAdmin && !isCampaignCreator) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate status volunteer"
            });
        }

        // Prepare update data
        const updateData = {
            status: status,
            updated_at: new Date()
        };

        if (assigned_task !== undefined) {
            updateData.assigned_task = assigned_task;
        }

        if (status === 'confirmed') {
            updateData.confirmed_at = new Date();
        }

        if (status === 'completed') {
            updateData.completed_at = new Date();
        }

        const updatedRegistration = await prisma.volunteer_registrations.update({
            where: { registration_id: parseInt(id) },
            data: updateData,
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        phone_number: true,
                        profile_picture: true
                    }
                },
                donation_campaigns: {
                    select: {
                        title: true,
                        volunteer_needs: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            message: `Status volunteer berhasil diperbarui menjadi ${status}`,
            data: updatedRegistration
        });

    } catch (error) {
        console.error("Update Volunteer Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui status volunteer",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Volunteers by Campaign
export const getVolunteersByCampaign = async (req, res) => {
    try {
        const { id } = req.params;
        const { page = 1, limit = 20, status } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const where = {
            campaign_id: parseInt(id)
        };

        if (status) where.status = status;

        const [volunteers, total] = await Promise.all([
            prisma.volunteer_registrations.findMany({
                where,
                include: {
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            email: true,
                            phone_number: true,
                            profile_picture: true,
                            bio: true,
                            interests: true,
                            kecamatan: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'desc'
                },
                skip,
                take
            }),
            prisma.volunteer_registrations.count({ where })
        ]);

        return res.json({
            success: true,
            data: volunteers,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Volunteers By Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar volunteer",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// ============================================
// 📈 ADMIN ENDPOINTS
// ============================================

// GET Donation Stats
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

export const approveCampaign = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const { rejection_reason } = req.body;

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) },
            include: {
                communities: true
            }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Cek apakah campaign sudah di-approve
        if (campaign.approval_status === 'approved') {
            return res.status(400).json({
                success: false,
                message: "Campaign ini sudah disetujui"
            });
        }

        // Cek permission: siapa yang bisa approve?
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(campaign.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        // Hanya admin/founder/system admin yang bisa approve
        if (!isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Hanya admin komunitas atau system admin yang dapat menyetujui campaign"
            });
        }

        // Update approval status
        const updatedCampaign = await prisma.donation_campaigns.update({
            where: { campaign_id: parseInt(id) },
            data: {
                approval_status: 'approved',
                approved_by: userId,
                approved_at: new Date(),
                rejection_reason: null,
                updated_at: new Date()
            },
            include: {
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true
                    }
                },
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true
                    }
                },
                users_donation_campaigns_approved_byTousers: {
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
            message: "Campaign donasi berhasil disetujui dan sekarang publik",
            data: updatedCampaign
        });

    } catch (error) {
        console.error("Approve Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menyetujui campaign",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// REJECT Campaign (community admin / founder / system admin)
export const rejectCampaign = async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        const { rejection_reason } = req.body;

        if (!rejection_reason || rejection_reason.trim() === '') {
            return res.status(400).json({
                success: false,
                message: "Alasan penolakan wajib diisi"
            });
        }

        const campaign = await prisma.donation_campaigns.findUnique({
            where: { campaign_id: parseInt(id) },
            include: {
                communities: true
            }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // Cek apakah campaign sudah di-approve
        if (campaign.approval_status === 'approved') {
            return res.status(400).json({
                success: false,
                message: "Campaign ini sudah disetujui, tidak bisa ditolak"
            });
        }

        // Cek permission
        const isSystemAdminUser = await isSystemAdmin(userId);
        let isCommunityAdmin = false;

        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(campaign.community_id, userId);
            isCommunityAdmin = adminCheck.isAdmin;
        }

        if (!isCommunityAdmin && !isSystemAdminUser) {
            return res.status(403).json({
                success: false,
                message: "Hanya admin komunitas atau system admin yang dapat menolak campaign"
            });
        }

        // Update approval status
        const updatedCampaign = await prisma.donation_campaigns.update({
            where: { campaign_id: parseInt(id) },
            data: {
                approval_status: 'rejected',
                rejection_reason: rejection_reason.trim(),
                updated_at: new Date()
            },
            include: {
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true
                    }
                },
                users: {
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
            message: "Campaign donasi ditolak",
            data: updatedCampaign
        });

    } catch (error) {
        console.error("Reject Campaign Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal menolak campaign",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

// GET Pending Campaigns (untuk admin)
export const getPendingCampaigns = async (req, res) => {
    try {
        const userId = req.user.id;
        const { page = 1, limit = 20, community_id } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        // Cek user role
        const isSystemAdminUser = await isSystemAdmin(userId);

        // Build where clause
        const where = {
            approval_status: 'pending'
        };

        // Jika bukan system admin, filter berdasarkan komunitas yang dia admin
        if (!isSystemAdminUser) {
            // Dapatkan komunitas yang user admin
            const adminCommunities = await prisma.community_admins.findMany({
                where: {
                    user_id: userId
                },
                select: {
                    community_id: true
                }
            });

            const communityIds = adminCommunities.map(c => c.community_id);

            // Tambahkan founder communities
            const foundedCommunities = await prisma.communities.findMany({
                where: {
                    founder_id: userId
                },
                select: {
                    community_id: true
                }
            });

            const foundedIds = foundedCommunities.map(c => c.community_id);

            const allCommunityIds = [...new Set([...communityIds, ...foundedIds])];

            if (allCommunityIds.length === 0) {
                return res.json({
                    success: true,
                    data: [],
                    message: "Anda tidak memiliki akses untuk melihat pending campaigns",
                    pagination: {
                        page: parseInt(page),
                        limit: parseInt(limit),
                        total: 0,
                        totalPages: 0
                    }
                });
            }

            where.community_id = { in: allCommunityIds };

            // Filter spesifik community jika diminta
            if (community_id) {
                if (!allCommunityIds.includes(parseInt(community_id))) {
                    return res.status(403).json({
                        success: false,
                        message: "Anda tidak memiliki akses ke komunitas ini"
                    });
                }
                where.community_id = parseInt(community_id);
            }
        } else {
            // System admin bisa lihat semua
            if (community_id) {
                where.community_id = parseInt(community_id);
            }
        }

        const [campaigns, total] = await Promise.all([
            prisma.donation_campaigns.findMany({
                where,
                include: {
                    communities: {
                        select: {
                            community_id: true,
                            community_name: true,
                            community_slug: true,
                            logo: true
                        }
                    },
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            email: true,
                            profile_picture: true
                        }
                    },
                    _count: {
                        select: {
                            donations: true,
                            volunteer_registrations: true
                        }
                    }
                },
                orderBy: {
                    created_at: 'asc'
                },
                skip,
                take
            }),
            prisma.donation_campaigns.count({ where })
        ]);

        return res.json({
            success: true,
            data: campaigns,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Pending Campaigns Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar pending campaign",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};