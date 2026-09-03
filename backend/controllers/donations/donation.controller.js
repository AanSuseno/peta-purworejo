import prisma from "../../lib/prisma.js";
import fs from "fs";

import path from "path";

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
      community_id,
      delivery_notes
    } = req.body;

    const campaignId = parseInt(id);

    console.log('🔍 ========== CREATE DONATION ==========');
    console.log('📝 Body:', req.body);
    console.log('📸 File:', req.file); // ← HARUSNYA ADA
    console.log('📸 File fieldname:', req.file?.fieldname);
    console.log('📸 File path:', req.file?.path);
    console.log('========================================');

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

    const isAnonymousBool = is_anonymous === true || is_anonymous === 'true';

    // Gunakan community_id dari campaign jika tidak disediakan
    const finalCommunityId = community_id ? parseInt(community_id) : campaign.community_id;

    const community = await prisma.communities.findUnique({
      where: { community_id: finalCommunityId },
      select: { founder_id: true }
    });

    const representativeId = req.body.representative_id
      ? parseInt(req.body.representative_id)
      : community?.founder_id || null;

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

        proof_image,

        goods_name,
        goods_quantity: goods_quantity
          ? parseInt(goods_quantity)
          : null,
        goods_unit,

        delivery_notes,

        donor_name: isAnonymousBool
          ? 'Anonymous'
          : (donor_name || req.user?.full_name),

        donor_phone: isAnonymousBool
          ? null
          : (donor_phone || req.user?.phone_number),

        donor_email: isAnonymousBool
          ? null
          : (donor_email || req.user?.email),

        is_anonymous: isAnonymousBool,

        status: 'pending',

        community_id: finalCommunityId,
      },

      include: {
        donation_campaigns: {
          select: {
            title: true,
            community_id: true,
          },
        },
      },
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
          status: 'pending',
        },
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
        users_donations_donor_idTousers: {
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
    const user = await prisma.users.findUnique({
      where: { user_id: req.user.id },
      include: { user_roles: true }
    });
    const isAdmin = user?.user_roles?.role_name?.toLowerCase() === 'system_admin';
    const isCommunityAdmin = await prisma.community_admins.findUnique({
      where: {
        community_id_user_id: {
          community_id: donation.community_id,
          user_id: req.user.id
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

const checkDistributionAccess = async (req, campaign) => {
  const userId = req.user.id;
  const isSystemAdmin = req.user.roleName?.toLowerCase() === "system_admin";
  const isCreator = campaign.creator_id === userId;

  let isCommunityAdmin = false;
  if (!isSystemAdmin && !isCreator && campaign.community_id) {
    const admin = await prisma.community_admins.findFirst({
      where: {
        community_id: campaign.community_id,
        user_id: userId
      }
    });
    isCommunityAdmin = !!admin;
  }

  return { allowed: isSystemAdmin || isCreator || isCommunityAdmin, isSystemAdmin, isCreator, isCommunityAdmin };
};

// CREATE Distribution (dengan upload bukti/evidence gambar)
export const createDistribution = async (req, res) => {
  try {
    const { id } = req.params; // campaign_id
    const campaignId = parseInt(id);
    const {
      recipient_name,
      recipient_phone,
      recipient_address,
      amount,
      description
    } = req.body;

    if (!recipient_name || recipient_name.trim() === "") {
      return res.status(400).json({
        success: false,
        message: "Nama penerima wajib diisi"
      });
    }

    if (!amount || parseFloat(amount) <= 0) {
      return res.status(400).json({
        success: false,
        message: "Jumlah distribusi wajib diisi dan harus lebih dari 0"
      });
    }

    const campaign = await prisma.donation_campaigns.findUnique({
      where: { campaign_id: campaignId }
    });

    if (!campaign) {
      return res.status(404).json({
        success: false,
        message: "Campaign tidak ditemukan"
      });
    }

    // Cek permission: system admin, admin komunitas, atau creator campaign
    const { allowed } = await checkDistributionAccess(req, campaign);
    if (!allowed) {
      return res.status(403).json({
        success: false,
        message: "Hanya admin, admin komunitas, atau pembuat campaign yang dapat membuat distribusi"
      });
    }

    const distributionAmount = parseFloat(amount);

    // Validasi sisa dana (khusus donation_type money)
    if (campaign.donation_type === "money") {
      const alreadyDistributed = parseFloat(campaign.total_distributed || 0);
      const collected = parseFloat(campaign.collected_amount || 0);
      const remaining = collected - alreadyDistributed;

      if (distributionAmount > remaining) {
        return res.status(400).json({
          success: false,
          message: `Jumlah distribusi melebihi sisa dana yang tersedia (Rp${remaining})`
        });
      }
    }

    // Buat distribusi
    const distribution = await prisma.donation_distributions.create({
      data: {
        campaign_id: campaignId,
        recipient_name: recipient_name.trim(),
        recipient_phone: recipient_phone || null,
        recipient_address: recipient_address || null,
        amount: distributionAmount,
        description: description || null,
        status: "pending",
        created_at: new Date(),
        updated_at: new Date()
      }
    });

    // Upload bukti evidence (multer field: evidence_images, multiple files)
    let evidenceData = [];
    if (req.files && req.files.length > 0) {
      const evidencePromises = req.files.map((file, index) =>
        prisma.distribution_evidences.create({
          data: {
            distribution_id: distribution.distribution_id,
            evidence_url: `/uploads/distributions/${file.filename}`,
            caption: req.body[`caption_${index}`] || null,
            uploaded_at: new Date()
          }
        })
      );
      evidenceData = await Promise.all(evidencePromises);
    }

    const createdDistribution = await prisma.donation_distributions.findUnique({
      where: { distribution_id: distribution.distribution_id },
      include: {
        distribution_evidences: true,
        donation_campaigns: {
          select: { title: true, community_id: true }
        }
      }
    });

    return res.status(201).json({
      success: true,
      message: "Distribusi berhasil dibuat",
      data: createdDistribution
    });

  } catch (error) {
    console.error("Create Distribution Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal membuat distribusi",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};

// ADD Evidence ke distribusi yang sudah ada
export const addDistributionEvidence = async (req, res) => {
  try {
    const { id } = req.params; // distribution_id

    const distribution = await prisma.donation_distributions.findUnique({
      where: { distribution_id: parseInt(id) },
      include: { donation_campaigns: true }
    });

    if (!distribution) {
      return res.status(404).json({ success: false, message: "Distribusi tidak ditemukan" });
    }

    const { allowed } = await checkDistributionAccess(req, distribution.donation_campaigns);
    if (!allowed) {
      return res.status(403).json({
        success: false,
        message: "Hanya admin, admin komunitas, atau pembuat campaign yang dapat menambah bukti"
      });
    }

    if (!req.files || req.files.length === 0) {
      return res.status(400).json({ success: false, message: "Tidak ada file yang diupload" });
    }

    const evidencePromises = req.files.map((file, index) =>
      prisma.distribution_evidences.create({
        data: {
          distribution_id: distribution.distribution_id,
          evidence_url: `/uploads/distributions/${file.filename}`,
          caption: req.body[`caption_${index}`] || null,
          uploaded_at: new Date()
        }
      })
    );
    const evidenceData = await Promise.all(evidencePromises);

    return res.status(201).json({
      success: true,
      message: "Bukti distribusi berhasil ditambahkan",
      data: evidenceData
    });

  } catch (error) {
    console.error("Add Distribution Evidence Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal menambahkan bukti distribusi",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};

// GET Distributions by Campaign
export const getDistributionsByCampaign = async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 20, status } = req.query;

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const take = parseInt(limit);

    const where = { campaign_id: parseInt(id) };
    if (status) where.status = status;

    const [distributions, total] = await Promise.all([
      prisma.donation_distributions.findMany({
        where,
        include: {
          distribution_evidences: true
        },
        orderBy: { created_at: "desc" },
        skip,
        take
      }),
      prisma.donation_distributions.count({ where })
    ]);

    const summary = await prisma.donation_distributions.aggregate({
      where: { campaign_id: parseInt(id), status: "distributed" },
      _sum: { amount: true },
      _count: true
    });

    return res.json({
      success: true,
      data: distributions,
      summary: {
        total_distributions: summary._count,
        total_distributed: summary._sum.amount || 0
      },
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        totalPages: Math.ceil(total / parseInt(limit))
      }
    });

  } catch (error) {
    console.error("Get Distributions By Campaign Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal mengambil daftar distribusi",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};

// GET Distribution by ID
export const getDistributionById = async (req, res) => {
  try {
    const { id } = req.params;

    const distribution = await prisma.donation_distributions.findUnique({
      where: { distribution_id: parseInt(id) },
      include: {
        distribution_evidences: true,
        donation_campaigns: {
          select: {
            title: true,
            donation_type: true,
            communities: {
              select: { community_name: true, community_slug: true }
            }
          }
        }
      }
    });

    if (!distribution) {
      return res.status(404).json({ success: false, message: "Distribusi tidak ditemukan" });
    }

    return res.json({ success: true, data: distribution });

  } catch (error) {
    console.error("Get Distribution By ID Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal mengambil distribusi",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};

// UPDATE Distribution Status
export const updateDistributionStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const { status, recipient_name, recipient_phone, recipient_address, amount, description } = req.body;

    const distributionId = parseInt(id);

    const distribution = await prisma.donation_distributions.findUnique({
      where: { distribution_id: distributionId },
      include: { donation_campaigns: true }
    });

    if (!distribution) {
      return res.status(404).json({ success: false, message: "Distribusi tidak ditemukan" });
    }

    const { allowed } = await checkDistributionAccess(req, distribution.donation_campaigns);
    if (!allowed) {
      return res.status(403).json({
        success: false,
        message: "Hanya admin, admin komunitas, atau pembuat campaign yang dapat mengubah distribusi"
      });
    }

    const validStatuses = ["pending", "distributed", "cancelled"];
    if (status && !validStatuses.includes(status)) {
      return res.status(400).json({
        success: false,
        message: "Status tidak valid. Harus salah satu dari: pending, distributed, cancelled"
      });
    }

    const wasDistributed = distribution.status === "distributed";
    const willBeDistributed = status === "distributed";

    const updateData = {
      recipient_name: recipient_name ? recipient_name.trim() : undefined,
      recipient_phone: recipient_phone !== undefined ? recipient_phone : undefined,
      recipient_address: recipient_address !== undefined ? recipient_address : undefined,
      amount: amount !== undefined ? parseFloat(amount) : undefined,
      description: description !== undefined ? description : undefined,
      status: status || undefined,
      distributed_at: willBeDistributed && !wasDistributed ? new Date() : undefined,
      updated_at: new Date()
    };

    const updatedDistribution = await prisma.donation_distributions.update({
      where: { distribution_id: distributionId },
      data: updateData,
      include: { distribution_evidences: true }
    });

    // Sinkronkan total_distributed di campaign
    if (!wasDistributed && willBeDistributed) {
      await prisma.donation_campaigns.update({
        where: { campaign_id: distribution.campaign_id },
        data: { total_distributed: { increment: updatedDistribution.amount } }
      });
    } else if (wasDistributed && status && status !== "distributed") {
      await prisma.donation_campaigns.update({
        where: { campaign_id: distribution.campaign_id },
        data: { total_distributed: { decrement: distribution.amount } }
      });
    }

    return res.json({
      success: true,
      message: "Distribusi berhasil diperbarui",
      data: updatedDistribution
    });

  } catch (error) {
    console.error("Update Distribution Status Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal memperbarui distribusi",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};

// DELETE Distribution
export const deleteDistribution = async (req, res) => {
  try {
    const { id } = req.params;
    const distributionId = parseInt(id);

    const distribution = await prisma.donation_distributions.findUnique({
      where: { distribution_id: distributionId },
      include: {
        donation_campaigns: true,
        distribution_evidences: true
      }
    });

    if (!distribution) {
      return res.status(404).json({ success: false, message: "Distribusi tidak ditemukan" });
    }

    const { allowed } = await checkDistributionAccess(req, distribution.donation_campaigns);
    if (!allowed) {
      return res.status(403).json({
        success: false,
        message: "Hanya admin, admin komunitas, atau pembuat campaign yang dapat menghapus distribusi"
      });
    }

    // Hapus file evidence dari disk
    if (distribution.distribution_evidences.length > 0) {
      distribution.distribution_evidences.forEach((evidence) => {
        const filePath = path.join(process.cwd(), evidence.evidence_url);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      });
    }

    // Jika sudah distributed, kembalikan total_distributed di campaign
    if (distribution.status === "distributed") {
      await prisma.donation_campaigns.update({
        where: { campaign_id: distribution.campaign_id },
        data: { total_distributed: { decrement: distribution.amount } }
      });
    }

    // distribution_evidences ikut terhapus (onDelete: Cascade)
    await prisma.donation_distributions.delete({
      where: { distribution_id: distributionId }
    });

    return res.json({
      success: true,
      message: "Distribusi berhasil dihapus"
    });

  } catch (error) {
    console.error("Delete Distribution Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal menghapus distribusi",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};

export const completeCampaign = async (req, res) => {
  try {
    const { id } = req.params;
    const campaignId = parseInt(id);

    const campaign = await prisma.donation_campaigns.findUnique({
      where: { campaign_id: campaignId }
    });

    if (!campaign) {
      return res.status(404).json({
        success: false,
        message: "Campaign tidak ditemukan"
      });
    }

    if (campaign.approval_status !== "approved") {
      return res.status(400).json({
        success: false,
        message: "Campaign belum disetujui, tidak bisa ditandai selesai"
      });
    }

    if (campaign.status === "completed") {
      return res.status(400).json({
        success: false,
        message: "Campaign sudah ditandai selesai sebelumnya"
      });
    }

    if (campaign.status === "cancelled") {
      return res.status(400).json({
        success: false,
        message: "Campaign yang dibatalkan tidak bisa ditandai selesai"
      });
    }

    // Cek permission: system admin, admin komunitas, atau creator campaign
    const { allowed } = await checkDistributionAccess(req, campaign);
    if (!allowed) {
      return res.status(403).json({
        success: false,
        message: "Hanya admin, admin komunitas, atau pembuat campaign yang dapat menandai campaign selesai"
      });
    }

    const updatedCampaign = await prisma.donation_campaigns.update({
      where: { campaign_id: campaignId },
      data: {
        status: "completed",
        // ⚠️ hapus baris ini kalau kolom completed_at belum ada di schema
        // completed_at: new Date(),
        updated_at: new Date()
      }
    });

    return res.json({
      success: true,
      message: "Campaign berhasil ditandai selesai",
      data: updatedCampaign
    });

  } catch (error) {
    console.error("Complete Campaign Error:", error);
    return res.status(500).json({
      success: false,
      message: "Gagal menandai campaign selesai",
      error: process.env.NODE_ENV === "development" ? error.message : undefined
    });
  }
};