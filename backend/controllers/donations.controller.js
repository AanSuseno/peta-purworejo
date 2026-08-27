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

// ============================================
// 💰 DONATIONS
// ============================================

// CREATE Donation
export const createDonation = async (req, res) => {
  try {
    const { id } = req.params;
    const {
      donation_type,
      amount,
      payment_method,
      goods_type,
      goods_name,
      goods_quantity,
      goods_unit,
      delivery_method,
      delivery_address,
      volunteer_availability,
      volunteer_skill,
      volunteer_notes,
      donor_name,
      donor_phone,
      donor_email,
      is_anonymous,
      donation_purpose,
      community_id
    } = req.body;

    const campaignId = parseInt(id);

    // Cek campaign exists dan aktif
    const campaign = await prisma.donation_campaigns.findUnique({
      where: { campaign_id: campaignId }
    });

    if (!campaign) {
      return res.status(404).json({ success: false, message: 'Campaign not found' });
    }

    if (campaign.status !== 'active' || campaign.approval_status !== 'approved') {
      return res.status(400).json({ 
        success: false, 
        message: 'Campaign is not active or not approved yet' 
      });
    }

    // Cek end_date
    if (campaign.end_date && new Date(campaign.end_date) < new Date()) {
      return res.status(400).json({ success: false, message: 'Campaign has ended' });
    }

    // Validasi berdasarkan tipe donasi
    if (donation_type === 'money') {
      if (!amount || amount <= 0) {
        return res.status(400).json({ 
          success: false, 
          message: 'Amount is required and must be greater than 0' 
        });
      }
    }

    if (donation_type === 'goods') {
      if (!goods_name || !goods_quantity) {
        return res.status(400).json({ 
          success: false, 
          message: 'Goods name and quantity are required' 
        });
      }
    }

    if (donation_type === 'volunteer') {
      if (!volunteer_availability) {
        return res.status(400).json({ 
          success: false, 
          message: 'Volunteer availability is required' 
        });
      }
      // Cek kuota volunteer
      if (campaign.volunteer_slots && 
          campaign.volunteer_registered >= campaign.volunteer_slots) {
        return res.status(400).json({ 
          success: false, 
          message: 'Volunteer slots are full' 
        });
      }
    }

    // Gunakan community_id dari campaign jika tidak disediakan
    const finalCommunityId = community_id || campaign.community_id;

    // File upload handling
    let proof_image = null;
    let goods_photo = null;
    if (req.file) {
      if (donation_type === 'money') {
        proof_image = req.file.path;
      } else if (donation_type === 'goods') {
        goods_photo = req.file.path;
      }
    }

    // Buat donasi
    const donation = await prisma.donations.create({
      data: {
        campaign_id: campaignId,
        donor_id: req.user?.user_id || null,
        donation_type,
        amount: amount ? parseFloat(amount) : null,
        payment_method,
        proof_image,
        goods_type,
        goods_name,
        goods_quantity: goods_quantity ? parseInt(goods_quantity) : null,
        goods_unit,
        goods_photo,
        delivery_method,
        delivery_address,
        volunteer_availability,
        volunteer_skill,
        volunteer_notes,
        donor_name: is_anonymous ? 'Anonymous' : (donor_name || req.user?.full_name),
        donor_phone: is_anonymous ? null : (donor_phone || req.user?.phone_number),
        donor_email: is_anonymous ? null : (donor_email || req.user?.email),
        is_anonymous: is_anonymous || false,
        is_verified: false,
        status: 'pending',
        community_id: finalCommunityId,
        donation_purpose: donation_purpose || 'donation'
      },
      include: {
        donation_campaigns: {
          select: {
            title: true,
            community_id: true
          }
        }
      }
    });

    // Untuk volunteer registration - buat entry di volunteer_registrations
    if (donation_type === 'volunteer' && req.user?.user_id) {
      await prisma.volunteer_registrations.create({
        data: {
          campaign_id: campaignId,
          user_id: req.user.user_id,
          availability: volunteer_availability,
          skills: volunteer_skill,
          notes: volunteer_notes,
          status: 'pending'
        }
      });

      // Update volunteer_registered count
      await prisma.donation_campaigns.update({
        where: { campaign_id: campaignId },
        data: {
          volunteer_registered: {
            increment: 1
          }
        }
      });
    }

    // Update total_donors
    await prisma.donation_campaigns.update({
      where: { campaign_id: campaignId },
      data: {
        total_donors: {
          increment: 1
        }
      }
    });

    // Jika donasi uang, update collected_amount
    if (donation_type === 'money' && amount) {
      await prisma.donation_campaigns.update({
        where: { campaign_id: campaignId },
        data: {
          collected_amount: {
            increment: parseFloat(amount)
          }
        }
      });
    }

    // Create notification untuk community admin
    if (finalCommunityId) {
      await createNotification({
        type: 'new_donation',
        title: 'New Donation Received',
        content: `New ${donation_type} donation for campaign "${campaign.title}"`,
        target_community_id: finalCommunityId,
        target_role: 'admin',
        created_by: req.user?.user_id || null
      });
    }

    res.status(201).json({
      success: true,
      data: donation,
      message: 'Donation submitted successfully, waiting for verification'
    });
  } catch (error) {
    console.error('Error createDonation:', error);
    res.status(500).json({ success: false, message: error.message });
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
    const { status, notes } = req.body;

    const donationId = parseInt(id);

    // Validasi status
    const validStatuses = ['pending', 'confirmed', 'rejected', 'delivered'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid status. Must be one of: pending, confirmed, rejected, delivered' 
      });
    }

    const donation = await prisma.donations.findUnique({
      where: { donation_id: donationId },
      include: {
        donation_campaigns: {
          include: {
            communities: true
          }
        }
      }
    });

    if (!donation) {
      return res.status(404).json({ success: false, message: 'Donation not found' });
    }

    // Cek authorization
    const isAdmin = req.user?.isAdmin;
    const isCommunityAdmin = await prisma.community_admins.findUnique({
      where: {
        community_id_user_id: {
          community_id: donation.community_id,
          user_id: req.user.user_id
        }
      }
    });

    if (!isAdmin && !isCommunityAdmin) {
      return res.status(403).json({ 
        success: false, 
        message: 'Only admin or community admin can update donation status' 
      });
    }

    // Update
    const updatedDonation = await prisma.donations.update({
      where: { donation_id: donationId },
      data: {
        status,
        confirmed_at: status === 'confirmed' ? new Date() : undefined,
        updated_at: new Date()
      }
    });

    // Jika status menjadi confirmed, update collected_amount jika money
    if (status === 'confirmed' && donation.donation_type === 'money' && donation.amount) {
      await prisma.donation_campaigns.update({
        where: { campaign_id: donation.campaign_id },
        data: {
          collected_amount: {
            increment: donation.amount
          }
        }
      });
    }

    // Jika status menjadi rejected dan sebelumnya confirmed, kurangi collected_amount
    if (status === 'rejected' && donation.donation_type === 'money' && donation.amount) {
      await prisma.donation_campaigns.update({
        where: { campaign_id: donation.campaign_id },
        data: {
          collected_amount: {
            decrement: donation.amount
          }
        }
      });
    }

    // Update volunteer status jika volunteer registration
    if (donation.donation_type === 'volunteer') {
      const volunteerStatus = status === 'confirmed' ? 'confirmed' 
                           : status === 'rejected' ? 'declined'
                           : 'pending';
                           
      await prisma.volunteer_registrations.updateMany({
        where: {
          campaign_id: donation.campaign_id,
          user_id: donation.donor_id
        },
        data: {
          status: volunteerStatus,
          confirmed_at: status === 'confirmed' ? new Date() : undefined
        }
      });
    }

    // Create notification
    if (donation.donor_id) {
      await createNotification({
        type: 'donation_status_update',
        title: `Donation ${status}`,
        content: `Your donation for "${donation.donation_campaigns.title}" has been ${status}`,
        target_user_id: donation.donor_id,
        created_by: req.user.user_id
      });
    }

    res.json({ 
      success: true, 
      data: updatedDonation,
      message: `Donation status updated to ${status}` 
    });
  } catch (error) {
    console.error('Error updateDonationStatus:', error);
    res.status(500).json({ success: false, message: error.message });
  }
};

// VERIFY Donation (admin only)
export const verifyDonation = async (req, res) => {
  try {
    const { id } = req.params;
    const { is_verified } = req.body;

    // Hanya admin yang bisa verifikasi
    if (!req.user?.isAdmin) {
      return res.status(403).json({ 
        success: false, 
        message: 'Only admin can verify donations' 
      });
    }

    const donation = await prisma.donations.findUnique({
      where: { donation_id: parseInt(id) },
      include: {
        donation_campaigns: true
      }
    });

    if (!donation) {
      return res.status(404).json({ success: false, message: 'Donation not found' });
    }

    const updatedDonation = await prisma.donations.update({
      where: { donation_id: parseInt(id) },
      data: {
        is_verified: is_verified === true,
        status: is_verified ? 'confirmed' : 'rejected',
        confirmed_at: is_verified ? new Date() : undefined
      }
    });

    // Jika verified dan money, update collected_amount
    if (is_verified && donation.donation_type === 'money' && donation.amount) {
      await prisma.donation_campaigns.update({
        where: { campaign_id: donation.campaign_id },
        data: {
          collected_amount: {
            increment: donation.amount
          }
        }
      });
    }

    // Create notification
    if (donation.donor_id) {
      await createNotification({
        type: 'donation_verified',
        title: is_verified ? 'Donation Verified' : 'Donation Rejected',
        content: `Your donation for "${donation.donation_campaigns.title}" has been ${is_verified ? 'verified' : 'rejected'}`,
        target_user_id: donation.donor_id,
        created_by: req.user.user_id
      });
    }

    res.json({ 
      success: true, 
      data: updatedDonation,
      message: is_verified ? 'Donation verified successfully' : 'Donation rejected' 
    });
  } catch (error) {
    console.error('Error verifyDonation:', error);
    res.status(500).json({ success: false, message: error.message });
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