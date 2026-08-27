import prisma from "../../lib/prisma.js";
import {checkCommunityAdmin, isSystemAdmin} from './helpers.js';

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
                    // 🔥 FIX: Hitung donations dan volunteer_registrations secara terpisah
                    _count: {
                        select: {
                            donations: true
                            // ❌ HAPUS: volunteer_registrations (tidak ada relasi langsung)
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

        // 🔥 FIX: Ambil count volunteer untuk setiap campaign secara terpisah
        const campaignIds = campaigns.map(c => c.campaign_id);
        
        // Get volunteer counts for all campaigns
        const volunteerCounts = await prisma.volunteer_registrations.groupBy({
            by: ['campaign_id'],
            where: {
                campaign_id: { in: campaignIds }
            },
            _count: true
        });

        // Create map for quick lookup
        const volunteerCountMap = {};
        volunteerCounts.forEach(v => {
            volunteerCountMap[v.campaign_id] = v._count;
        });

        // Format response
        const formattedCampaigns = campaigns.map(campaign => ({
            ...campaign,
            total_donors: campaign._count.donations,
            total_volunteers: volunteerCountMap[campaign.campaign_id] || 0, // 🔥 FIX: Ambil dari map
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
        console.log(req.query)

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
        const campaignId = Number(req.params.id);
        const userId = req.user.id;

        // Validasi campaign ID
        if (!Number.isInteger(campaignId)) {
            return res.status(400).json({
                success: false,
                message: "ID campaign tidak valid"
            });
        }

        // =========================================================
        // HELPER: CEK SYSTEM ADMIN
        // =========================================================
        const isSystemAdmin = async (userId) => {
            const user = await prisma.users.findUnique({
                where: {
                    user_id: userId
                },
                select: {
                    user_roles: {
                        select: {
                            role_name: true
                        }
                    }
                }
            });

            // Sesuaikan "admin" dengan role_name di database kamu
            return user?.user_roles?.role_name === "admin";
        };

        // =========================================================
        // HELPER: CEK COMMUNITY ADMIN
        // =========================================================
        const checkCommunityAdmin = async (communityId, userId) => {
            const admin = await prisma.community_admins.findUnique({
                where: {
                    community_id_user_id: {
                        community_id: communityId,
                        user_id: userId
                    }
                },
                select: {
                    role: true
                }
            });

            return {
                isAdmin: !!admin,
                role: admin?.role || null
            };
        };

        // =========================================================
        // 1. AMBIL CAMPAIGN
        // =========================================================
        const campaign = await prisma.donation_campaigns.findUnique({
            where: {
                campaign_id: campaignId
            },
            include: {
                // Community
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true,
                        logo: true,
                        description: true
                    }
                },

                // Creator
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        email: true,
                        profile_picture: true,
                        phone_number: true
                    }
                },

                // 5 donation terbaru yang sudah confirmed
                donations: {
                    where: {
                        status: "confirmed"
                    },
                    include: {
                        users_donations_donor_idTousers: {
                            select: {
                                user_id: true,
                                full_name: true,
                                profile_picture: true
                            }
                        }
                    },
                    orderBy: {
                        created_at: "desc"
                    },
                    take: 5
                }
            }
        });

        // =========================================================
        // 2. CAMPAIGN TIDAK DITEMUKAN
        // =========================================================
        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // =========================================================
        // 3. PERMISSION
        // =========================================================

        // Creator campaign
        const isCreator = campaign.creator_id === userId;

        // System admin
        const isSystemAdminUser = await isSystemAdmin(userId);

        let isAdmin = false;
        let isFounder = false;
        let userRole = null;

        // Community admin / founder
        if (campaign.community_id) {
            const adminCheck = await checkCommunityAdmin(
                campaign.community_id,
                userId
            );

            isAdmin = adminCheck.isAdmin;
            userRole = adminCheck.role;
            isFounder = adminCheck.role === "founder";
        }

        // Community member
        let isMember = false;

        if (campaign.community_id) {
            const membership = await prisma.community_members.findUnique({
                where: {
                    community_id_user_id: {
                        community_id: campaign.community_id,
                        user_id: userId
                    }
                },
                select: {
                    status: true
                }
            });

            isMember = membership?.status === "active";
        }

        // =========================================================
        // 4. DONATION STATISTICS
        // =========================================================

        const donationStats = await prisma.donations.aggregate({
            where: {
                campaign_id: campaignId,
                status: "confirmed"
            },
            _sum: {
                amount: true
            },
            _count: {
                _all: true
            }
        });

        const collectedAmount = Number(
            donationStats._sum.amount || 0
        );

        const totalDonors = donationStats._count._all;

        // =========================================================
        // 5. VOLUNTEER STATISTICS
        // =========================================================
        //
        // volunteer_registrations TIDAK mempunyai relation langsung
        // ke donation_campaigns pada schema Prisma.
        //
        // Jadi query berdasarkan campaign_id.
        //

        const totalVolunteers = await prisma.volunteer_registrations.count({
            where: {
                campaign_id: campaignId
            }
        });

        const confirmedVolunteers =
            await prisma.volunteer_registrations.count({
                where: {
                    campaign_id: campaignId,
                    status: "confirmed"
                }
            });

        // =========================================================
        // 6. PROGRESS
        // =========================================================

        const targetAmount = campaign.target_amount
            ? Number(campaign.target_amount)
            : null;

        const progress =
            targetAmount && targetAmount > 0
                ? Math.min(
                    (collectedAmount / targetAmount) * 100,
                    100
                )
                : 0;

        // =========================================================
        // 7. FORMAT RESPONSE
        // =========================================================

        const formattedCampaign = {
            ...campaign,

            // Jangan expose Decimal Prisma mentah
            target_amount: targetAmount,

            // Gunakan hasil aggregate yang aktual
            collected_amount: collectedAmount,

            // Donor hanya confirmed
            total_donors: totalDonors,

            // Volunteer
            total_volunteers: totalVolunteers,
            confirmed_volunteers: confirmedVolunteers,

            // Progress
            progress: Number(progress.toFixed(2)),

            // Statistik
            donation_stats: {
                total_confirmed: totalDonors,
                total_amount: collectedAmount
            },

            volunteer_stats: {
                total: totalVolunteers,
                confirmed: confirmedVolunteers
            },

            // Permission user
            user_permissions: {
                is_creator: isCreator,
                is_admin: isAdmin,
                is_founder: isFounder,
                is_system_admin: isSystemAdminUser,
                is_member: isMember,
                user_role: userRole,

                can_manage:
                    isCreator ||
                    isAdmin ||
                    isFounder ||
                    isSystemAdminUser,

                can_approve:
                    isAdmin ||
                    isFounder ||
                    isSystemAdminUser,

                can_delete:
                    isCreator ||
                    isAdmin ||
                    isFounder ||
                    isSystemAdminUser
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
            error:
                process.env.NODE_ENV === "development"
                    ? error.message
                    : undefined
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
                    users_donations_donor_idTousers: {
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
        const campaignId = Number(req.params.id);

        // =========================================================
        // VALIDASI ID
        // =========================================================
        if (!Number.isInteger(campaignId)) {
            return res.status(400).json({
                success: false,
                message: "ID campaign tidak valid"
            });
        }

        // =========================================================
        // CEK CAMPAIGN
        // =========================================================
        const campaign = await prisma.donation_campaigns.findUnique({
            where: {
                campaign_id: campaignId
            },
            select: {
                campaign_id: true,
                title: true
            }
        });

        if (!campaign) {
            return res.status(404).json({
                success: false,
                message: "Campaign donasi tidak ditemukan"
            });
        }

        // =========================================================
        // GROUP DONATIONS BERDASARKAN TYPE
        // =========================================================
        const donationsByType = await prisma.donations.groupBy({
            by: ["donation_type"],
            where: {
                campaign_id: campaignId,
                status: "confirmed"
            },
            _count: {
                _all: true
            },
            _sum: {
                amount: true
            }
        });

        // =========================================================
        // MONEY DONATIONS
        // =========================================================
        const moneyDonations = await prisma.donations.findMany({
            where: {
                campaign_id: campaignId,
                donation_type: "money",
                status: "confirmed"
            },
            select: {
                donation_id: true,
                amount: true,
                is_anonymous: true,
                donor_name: true,
                donor_id: true,
                created_at: true
            },
            orderBy: {
                created_at: "desc"
            }
        });

        // =========================================================
        // GOODS DONATIONS
        // =========================================================
        const goodsDonations = await prisma.donations.findMany({
            where: {
                campaign_id: campaignId,
                donation_type: "goods",
                status: "confirmed"
            },
            select: {
                donation_id: true,

                // Field yang memang ada di schema
                goods_name: true,
                goods_quantity: true,
                goods_unit: true,

                delivery_notes: true,
                is_anonymous: true,
                donor_name: true,
                donor_id: true,
                created_at: true
            },
            orderBy: {
                created_at: "desc"
            }
        });

        // =========================================================
        // VOLUNTEER REGISTRATIONS
        // =========================================================
        const volunteers = await prisma.volunteer_registrations.findMany({
            where: {
                campaign_id: campaignId,
                status: "confirmed"
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
            },
            orderBy: {
                created_at: "desc"
            }
        });

        // =========================================================
        // HELPER UNTUK MENCARI GROUP
        // =========================================================
        const getDonationGroup = (type) => {
            return donationsByType.find(
                (item) => item.donation_type === type
            );
        };

        const moneyGroup = getDonationGroup("money");
        const goodsGroup = getDonationGroup("goods");
        const volunteerDonationGroup = getDonationGroup("volunteer");

        // =========================================================
        // TOTAL DONATIONS
        // =========================================================
        const totalDonations = donationsByType.reduce(
            (total, donation) => total + donation._count._all,
            0
        );

        // Decimal Prisma perlu dikonversi ke Number
        const totalAmount = donationsByType.reduce(
            (total, donation) => {
                return total + Number(donation._sum.amount || 0);
            },
            0
        );

        // =========================================================
        // RESPONSE
        // =========================================================
        return res.json({
            success: true,
            data: {
                campaign_id: campaign.campaign_id,
                title: campaign.title,

                summary: {
                    total_donations: totalDonations,
                    total_amount: totalAmount,
                    total_volunteers: volunteers.length
                },

                breakdown: {
                    // -------------------------------------------------
                    // MONEY
                    // -------------------------------------------------
                    money: {
                        count: moneyGroup?._count._all || 0,
                        amount: Number(
                            moneyGroup?._sum.amount || 0
                        ),
                        details: moneyDonations.map((donation) => ({
                            donation_id: donation.donation_id,
                            amount: Number(donation.amount || 0),
                            is_anonymous: donation.is_anonymous,
                            donor_name: donation.is_anonymous
                                ? null
                                : donation.donor_name,
                            donor_id: donation.is_anonymous
                                ? null
                                : donation.donor_id,
                            created_at: donation.created_at
                        }))
                    },

                    // -------------------------------------------------
                    // GOODS
                    // -------------------------------------------------
                    goods: {
                        count: goodsGroup?._count._all || 0,

                        details: goodsDonations.map((donation) => ({
                            donation_id: donation.donation_id,
                            goods_name: donation.goods_name,
                            goods_quantity: donation.goods_quantity,
                            goods_unit: donation.goods_unit,
                            delivery_notes: donation.delivery_notes,
                            is_anonymous: donation.is_anonymous,
                            donor_name: donation.is_anonymous
                                ? null
                                : donation.donor_name,
                            donor_id: donation.is_anonymous
                                ? null
                                : donation.donor_id,
                            created_at: donation.created_at
                        }))
                    },

                    // -------------------------------------------------
                    // VOLUNTEER
                    // -------------------------------------------------
                    volunteer: {
                        // Volunteer registration sebenarnya
                        // disimpan di volunteer_registrations
                        count: volunteers.length,

                        // Jumlah donation record dengan type volunteer
                        donation_count:
                            volunteerDonationGroup?._count._all || 0,

                        details: volunteers.map((volunteer) => ({
                            user_id: volunteer.user_id,
                            full_name: volunteer.users?.full_name || null,
                            phone_number:
                                volunteer.users?.phone_number || null,
                            profile_picture:
                                volunteer.users?.profile_picture || null,
                            availability: volunteer.availability,
                            skills: volunteer.skills,
                            experience: volunteer.experience,
                            notes: volunteer.notes,
                            status: volunteer.status,
                            assigned_task: volunteer.assigned_task,
                            confirmed_at: volunteer.confirmed_at,
                            completed_at: volunteer.completed_at,
                            created_at: volunteer.created_at
                        }))
                    }
                }
            }
        });

    } catch (error) {
        console.error(
            "Get Campaign Donation Summary Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Gagal mengambil ringkasan donasi",
            error:
                process.env.NODE_ENV === "development"
                    ? error.message
                    : undefined
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
      payment_info, // ✅ Ganti dari bank_account_info & ewallet_info
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
      
      const isMember = await prisma.community_members.findUnique({
        where: {
          community_id_user_id: {
            community_id: communityIdInt,
            user_id: userId
          }
        }
      });

      const isAdmin = await prisma.community_admins.findUnique({
        where: {
          community_id_user_id: {
            community_id: communityIdInt,
            user_id: userId
          }
        }
      });

      if (!isMember && !isAdmin) {
        return res.status(403).json({ 
          success: false, 
          message: 'You must be an active member of this community to create a campaign' 
        });
      }

      // ✅ CEK BATAS CAMPAIGN AKTIF
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

    // ✅ CREATE CAMPAIGN - Perbaikan field
    const campaign = await prisma.donation_campaigns.create({
      data: {
        creator_id: userId,
        community_id: community_id ? parseInt(community_id) : null,
        title: title.trim(),
        description: description || null,
        donation_type: donation_type,
        target_amount: target_amount ? parseFloat(target_amount) : null,
        payment_info: payment_info || null, // ✅ Ganti dengan payment_info
        goods_description: goods_description || null,
        volunteer_needs: volunteer_needs || null,
        volunteer_slots: volunteer_slots ? parseInt(volunteer_slots) : null,
        start_date: startDate,
        end_date: endDate,
        status: 'pending',
        approval_status: 'pending', // ✅ Sudah ada di DB
        collected_amount: 0,
        total_donors: 0
        // ❌ HAPUS: volunteer_registered (tidak ada di DB)
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
            payment_info, // ✅ Ganti dari bank_account_info & ewallet_info
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
            payment_info: payment_info !== undefined ? payment_info : undefined, // ✅ Ganti
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
                updated_at: new Date(),
                status: 'active',
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

const createNotification = async (data) => {
    // Implementasi sesuai kebutuhan
    // Pastikan model notifications memiliki field yang sesuai
    return await prisma.notifications.create({
        data: {
            type: data.type,
            title: data.title,
            content: data.content,
            target_community_id: data.target_community_id,
            target_role: data.target_role || 'admin',
            created_by: data.created_by,
            is_global: false
        }
    });
};