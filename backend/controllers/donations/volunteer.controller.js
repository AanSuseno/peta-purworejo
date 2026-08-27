import prisma from "../../lib/prisma.js";
import {checkCommunityAdmin} from './helpers.js';

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