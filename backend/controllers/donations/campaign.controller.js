import prisma from "../../lib/prisma.js";
import {checkCommunityAdmin} from './helpers.js';

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
        const userId = req.user.id; // 🔥 Dapatkan user ID dari token

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

        // 🔥 CEK PERMISSION USER
        let isAdmin = false;
        let isFounder = false;
        let userRole = null;

        // 1. Cek apakah user adalah creator campaign
        const isCreator = campaign.creator_id === userId;

        // 2. Cek apakah user adalah system admin
        const isSystemAdminUser = await isSystemAdmin(userId);

        // 3. Cek apakah user adalah admin/founder komunitas
        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(campaign.community_id, userId);
            isAdmin = adminCheck.isAdmin;
            isFounder = adminCheck.role === 'founder';
            userRole = adminCheck.role;
        }

        // 🔥 Cek apakah user adalah member komunitas
        let isMember = false;
        if (campaign.community_id) {
            const membership = await prisma.community_members.findFirst({
                where: {
                    community_id: campaign.community_id,
                    user_id: userId,
                    status: 'active'
                }
            });
            isMember = !!membership;
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
            _count: undefined,
            
            // 🔥 TAMBAHKAN INFORMASI PERMISSION USER
            user_permissions: {
                is_creator: isCreator,
                is_admin: isAdmin,
                is_founder: isFounder,
                is_system_admin: isSystemAdminUser,
                is_member: isMember,
                user_role: userRole,
                can_manage: isCreator || isAdmin || isFounder || isSystemAdminUser,
                can_approve: isAdmin || isFounder || isSystemAdminUser,
                can_delete: isCreator || isAdmin || isFounder || isSystemAdminUser,
            }
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
    const {
      community_id,
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
      end_date
    } = req.body;

    // ✅ VALIDASI
    if (!title || !donation_type) {
      return res.status(400).json({ 
        success: false, 
        message: 'Title and donation type are required' 
      });
    }

    // ✅ VALIDASI DONATION_TYPE
    const validTypes = ['money', 'goods', 'volunteer'];
    if (!validTypes.includes(donation_type)) {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid donation type. Must be: money, goods, or volunteer' 
      });
    }

    // 🔥 PERBAIKAN: Gunakan req.user.id, BUKAN req.user.user_id
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ 
        success: false, 
        message: 'User not authenticated' 
      });
    }

    // ✅ CEK COMMUNITY MEMBERSHIP (jika ada community_id)
    if (community_id) {
      const communityIdInt = parseInt(community_id);
      
      // Cek apakah user adalah member aktif
      const isMember = await prisma.community_members.findUnique({
        where: {
          community_id_user_id: {
            community_id: communityIdInt,
            user_id: userId  // ✅ userId sudah benar (dari req.user.id)
          }
        }
      });

      // Cek apakah user adalah admin community
      const isAdmin = await prisma.community_admins.findUnique({
        where: {
          community_id_user_id: {
            community_id: communityIdInt,
            user_id: userId  // ✅ userId sudah benar
          }
        }
      });

      if (!isMember && !isAdmin) {
        return res.status(403).json({ 
          success: false, 
          message: 'You must be an active member of this community to create a campaign' 
        });
      }

      // ✅ CEK BATAS CAMPAIGN AKTIF (opsional)
      const activeCampaigns = await prisma.donation_campaigns.count({
        where: {
          community_id: communityIdInt,
          status: 'active',
          approval_status: 'approved'
        }
      });

      if (activeCampaigns >= 5) {
        return res.status(400).json({ 
          success: false, 
          message: 'Maximum 5 active campaigns per community' 
        });
      }
    }

    // ✅ CEK TANGGAL
    const startDate = start_date ? new Date(start_date) : new Date();
    const endDate = end_date ? new Date(end_date) : null;

    if (endDate && endDate < startDate) {
      return res.status(400).json({ 
        success: false, 
        message: 'End date must be after start date' 
      });
    }

    // ✅ CREATE CAMPAIGN
    const campaign = await prisma.donation_campaigns.create({
      data: {
        creator_id: userId,  // 🔥 userId dari req.user.id
        community_id: community_id ? parseInt(community_id) : null,
        title: title.trim(),
        description: description || null,
        donation_type: donation_type,
        target_amount: target_amount ? parseFloat(target_amount) : null,
        bank_account_info: bank_account_info || null,
        ewallet_info: ewallet_info || null,
        goods_description: goods_description || null,
        volunteer_needs: volunteer_needs || null,
        volunteer_slots: volunteer_slots ? parseInt(volunteer_slots) : null,
        start_date: startDate,
        end_date: endDate,
        status: 'pending',
        approval_status: 'pending',
        collected_amount: 0,
        total_donors: 0,
        volunteer_registered: 0
      },
      include: {
        communities: {
          select: {
            community_id: true,
            community_name: true,
            logo: true
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

    // ✅ KIRIM NOTIFIKASI KE COMMUNITY ADMINS
    if (community_id) {
      try {
        await createNotification({
          type: 'campaign_pending',
          title: 'New Campaign Pending Approval',
          content: `Campaign "${title}" needs your approval`,
          target_community_id: parseInt(community_id),
          target_role: 'admin',
          created_by: userId
        });
      } catch (notifError) {
        console.error('Error sending notification:', notifError);
      }
    }

    res.status(201).json({ 
      success: true, 
      data: campaign,
      message: 'Campaign created successfully. Waiting for admin approval.'
    });

  } catch (error) {
    console.error('Error createCampaign:', error);
    
    if (error.code === 'P2002') {
      return res.status(400).json({ 
        success: false, 
        message: 'A campaign with this title already exists' 
      });
    }

    if (error.code === 'P2003') {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid community or user reference' 
      });
    }

    res.status(500).json({ 
      success: false, 
      message: error.message || 'Failed to create campaign' 
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