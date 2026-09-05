import prisma from "../../lib/prisma.js";
import { Prisma } from "@prisma/client";

export const registerForEvent = async (req, res) => {
    try {
        const { id } = req.params; // post_id
        const userId = req.user.id;

        const post = await prisma.posts.findUnique({
            where: {
                post_id: parseInt(id),
                post_type: 'event'
            }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Event tidak ditemukan"
            });
        }

        // Cek apakah event masih aktif
        if (post.event_status === 'completed' || post.event_status === 'cancelled') {
            return res.status(400).json({
                success: false,
                message: `Event sudah ${post.event_status}`
            });
        }

        // Cek quota
        if (post.event_quota && post.event_registered_count >= post.event_quota) {
            return res.status(400).json({
                success: false,
                message: "Kuota event sudah penuh"
            });
        }

        // Cek apakah sudah terdaftar
        const existingRegistration = await prisma.event_participants.findFirst({
            where: {
                post_id: parseInt(id),
                user_id: userId
            }
        });

        if (existingRegistration) {
            return res.status(400).json({
                success: false,
                message: "Anda sudah terdaftar untuk event ini"
            });
        }

        // Cek apakah user adalah member komunitas
        const membership = await prisma.community_members.findFirst({
            where: {
                community_id: post.community_id,
                user_id: userId,
                status: 'active'
            }
        });

        if (!membership) {
            return res.status(403).json({
                success: false,
                message: "Anda harus menjadi anggota komunitas untuk mendaftar event"
            });
        }

        // Daftar event
        const registration = await prisma.event_participants.create({
            data: {
                post_id: parseInt(id),
                user_id: userId,
                registration_date: new Date(),
                status: 'registered'
            },
            include: {
                users: {
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

        // Update registered count
        await prisma.posts.update({
            where: { post_id: parseInt(id) },
            data: {
                event_registered_count: {
                    increment: 1
                }
            }
        });

        return res.status(201).json({
            success: true,
            message: "Berhasil mendaftar event",
            data: registration
        });

    } catch (error) {
        console.error("Register For Event Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mendaftar event",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const cancelEventRegistration = async (req, res) => {
    try {
        const { id } = req.params; // post_id
        const userId = req.user.id;

        const registration = await prisma.event_participants.findFirst({
            where: {
                post_id: parseInt(id),
                user_id: userId
            }
        });

        if (!registration) {
            return res.status(404).json({
                success: false,
                message: "Pendaftaran event tidak ditemukan"
            });
        }

        // Hanya bisa cancel jika status registered atau attended
        if (registration.status === 'attended') {
            return res.status(400).json({
                success: false,
                message: "Tidak dapat membatalkan pendaftaran karena sudah attended"
            });
        }

        // Update status menjadi cancelled
        await prisma.event_participants.update({
            where: {
                participant_id: registration.participant_id
            },
            data: {
                status: 'cancelled'
            }
        });

        // Update registered count
        await prisma.posts.update({
            where: { post_id: parseInt(id) },
            data: {
                event_registered_count: {
                    decrement: 1
                }
            }
        });

        return res.json({
            success: true,
            message: "Berhasil membatalkan pendaftaran event"
        });

    } catch (error) {
        console.error("Cancel Event Registration Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal membatalkan pendaftaran event",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const getEventParticipants = async (req, res) => {
    try {
        const { id } = req.params; // post_id
        const { page = 1, limit = 20, status } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);

        const post = await prisma.posts.findUnique({
            where: {
                post_id: parseInt(id),
                post_type: 'event'
            }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Event tidak ditemukan"
            });
        }

        const where = {
            post_id: parseInt(id)
        };

        if (status) {
            where.status = status;
        }

        const [participants, total] = await Promise.all([
            prisma.event_participants.findMany({
                where,
                include: {
                    users: {
                        select: {
                            user_id: true,
                            full_name: true,
                            email: true,
                            profile_picture: true,
                            phone_number: true
                        }
                    }
                },
                orderBy: {
                    registration_date: 'desc'
                },
                skip,
                take
            }),
            prisma.event_participants.count({ where })
        ]);

        return res.json({
            success: true,
            data: participants,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error("Get Event Participants Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar peserta",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

export const updateParticipantStatus = async (req, res) => {
    try {
        const { id } = req.params; // post_id
        const { participant_id, status } = req.body;
        const userId = req.user.id;

        const post = await prisma.posts.findUnique({
            where: {
                post_id: parseInt(id),
                post_type: 'event'
            }
        });

        if (!post) {
            return res.status(404).json({
                success: false,
                message: "Event tidak ditemukan"
            });
        }

        // Cek apakah user adalah admin komunitas atau author event
        const isAuthor = post.author_id === userId;
        const isSystemAdmin = req.user.roleName?.toLowerCase() === 'system_admin';

        let isCommunityAdmin = false;
        if (!isAuthor && !isSystemAdmin) {
            const admin = await prisma.community_admins.findFirst({
                where: {
                    community_id: post.community_id,
                    user_id: userId
                }
            });
            isCommunityAdmin = !!admin;
        }

        if (!isAuthor && !isCommunityAdmin && !isSystemAdmin) {
            return res.status(403).json({
                success: false,
                message: "Anda tidak memiliki akses untuk mengupdate status peserta"
            });
        }

        const participant = await prisma.event_participants.findFirst({
            where: {
                participant_id: parseInt(participant_id),
                post_id: parseInt(id)
            }
        });

        if (!participant) {
            return res.status(404).json({
                success: false,
                message: "Peserta tidak ditemukan"
            });
        }

        const updatedParticipant = await prisma.event_participants.update({
            where: {
                participant_id: parseInt(participant_id)
            },
            data: {
                status: status
            },
            include: {
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
            message: "Status peserta berhasil diperbarui",
            data: updatedParticipant
        });

    } catch (error) {
        console.error("Update Participant Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal memperbarui status peserta",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};

/**
 * Ambil daftar event publik.
 *
 * PERBAIKAN vs versi lama:
 * 1. Urutan sekarang: event yang belum lewat (event_date >= sekarang)
 *    ditampilkan dulu, diurutkan dari yang paling dekat waktunya.
 *    Event yang sudah lewat ditaruh SETELAH itu, diurutkan dari yang
 *    paling baru lewat ke yang paling lama lewat — jadi yang paling
 *    lama lewat ada di paling bawah. Sebelumnya sort cuma
 *    `event_date: 'asc'`, yang bikin event lama (tanggal kecil) selalu
 *    nangkring di paling atas.
 * 2. Event yang sudah lewat TIDAK lagi disembunyikan cuma karena field
 *    `event_status` di database belum sempat diupdate jadi 'completed'
 *    (kalau tidak ada job yang update field ini secara berkala, field
 *    ini gampang basi/nyangkut di 'upcoming'). Yang otomatis
 *    disembunyikan cuma yang statusnya 'cancelled', kecuali memang
 *    difilter eksplisit.
 * 3. `event_status` yang dikirim ke frontend sekarang dihitung ulang
 *    real-time berdasarkan `event_date` vs waktu sekarang (kecuali
 *    'cancelled', yang tetap dihormati apa adanya), supaya badge di
 *    kartu event ("Akan datang" dll) tidak salah tampil untuk event
 *    yang tanggalnya sudah lewat.
 */
export const getAllPublicEvents = async (req, res) => {
    try {
        const { page = 1, limit = 20, search, status } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const take = parseInt(limit);
        const validStatuses = ['upcoming', 'ongoing', 'completed', 'cancelled'];
        const hasValidStatusFilter = status && validStatuses.includes(status);

        // ---- WHERE clause versi Prisma Client (dipakai buat hitung total) ----
        const where = {
            post_type: 'event',
            visibility: 'public',
            status: 'active'
        };

        if (search) {
            where.OR = [
                { title: { contains: search, mode: 'insensitive' } },
                { content: { contains: search, mode: 'insensitive' } }
            ];
        }

        if (hasValidStatusFilter) {
            where.event_status = status;
        } else {
            // Default: sembunyikan yang cancelled saja. Event yang sudah
            // lewat (completed) TETAP ditampilkan, tapi di bagian bawah
            // (lihat urutan raw query di bawah).
            where.event_status = { not: 'cancelled' };
        }

        const total = await prisma.posts.count({ where });

        if (total === 0) {
            return res.json({
                success: true,
                message: "Berhasil mengambil daftar event publik",
                data: [],
                pagination: { page: parseInt(page), limit: take, total: 0, totalPages: 0 },
                filters: { search: search || null, status: status || null }
            });
        }

        // ---- Urutan khusus lewat raw query (Prisma tidak bisa expresikan
        //      "urutan asc untuk yang akan datang, tapi desc untuk yang
        //      sudah lewat" lewat orderBy biasa) ----
        const conditions = [
            Prisma.sql`post_type = 'event'`,
            Prisma.sql`visibility = 'public'`,
            Prisma.sql`status = 'active'`
        ];

        if (search) {
            const pattern = `%${search}%`;
            conditions.push(
                Prisma.sql`(title ILIKE ${pattern} OR content ILIKE ${pattern})`
            );
        }

        if (hasValidStatusFilter) {
            conditions.push(Prisma.sql`event_status = ${status}`);
        } else {
            conditions.push(Prisma.sql`event_status <> 'cancelled'`);
        }

        const orderedRows = await prisma.$queryRaw`
            SELECT post_id FROM posts
            WHERE ${Prisma.join(conditions, ' AND ')}
            ORDER BY
                CASE WHEN event_date >= NOW() THEN 0 ELSE 1 END ASC,
                CASE WHEN event_date >= NOW() THEN event_date END ASC,
                CASE WHEN event_date < NOW() THEN event_date END DESC
            LIMIT ${take} OFFSET ${skip}
        `;

        const orderedIds = orderedRows.map((r) => r.post_id);

        if (orderedIds.length === 0) {
            return res.json({
                success: true,
                message: "Berhasil mengambil daftar event publik",
                data: [],
                pagination: {
                    page: parseInt(page),
                    limit: take,
                    total,
                    totalPages: Math.ceil(total / take)
                },
                filters: { search: search || null, status: status || null }
            });
        }

        const events = await prisma.posts.findMany({
            where: { post_id: { in: orderedIds } },
            include: {
                users: {
                    select: {
                        user_id: true,
                        full_name: true,
                        profile_picture: true
                    }
                },
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        logo: true,
                        community_slug: true
                    }
                },
                post_media: {
                    select: {
                        media_id: true,
                        media_url: true,
                        media_type: true,
                        is_cover: true
                    },
                    orderBy: {
                        sort_order: 'asc'
                    }
                },
                event_participants: {
                    where: {
                        status: 'registered'
                    },
                    select: {
                        participant_id: true,
                        user_id: true,
                        status: true
                    }
                },
                _count: {
                    select: {
                        event_participants: {
                            where: {
                                status: 'registered'
                            }
                        },
                        post_likes: true,
                        post_comments: true
                    }
                }
            }
        });

        // `findMany` dengan `post_id: { in: [...] }` TIDAK menjamin urutan
        // hasil sama dengan urutan array `in`, jadi kita urutkan ulang
        // manual sesuai `orderedIds` dari raw query di atas.
        const eventsById = new Map(events.map((e) => [e.post_id, e]));
        const sortedEvents = orderedIds
            .map((id) => eventsById.get(id))
            .filter(Boolean);

        const now = new Date();

        // Format response data + hitung ulang status secara real-time
        // berdasarkan tanggal, bukan cuma percaya field statis di DB.
        const formattedEvents = sortedEvents.map((event) => {
            let computedStatus = event.event_status;
            if (event.event_status !== 'cancelled' && event.event_date) {
                computedStatus = new Date(event.event_date) > now ? 'upcoming' : 'completed';
            }

            return {
                ...event,
                event_status: computedStatus,
                raw_event_status: event.event_status,
                event_registered_count: event._count.event_participants,
                total_likes: event._count.post_likes,
                total_comments: event._count.post_comments,
                participants: event.event_participants,
            };
        });

        return res.json({
            success: true,
            message: "Berhasil mengambil daftar event publik",
            data: formattedEvents,
            pagination: {
                page: parseInt(page),
                limit: take,
                total,
                totalPages: Math.ceil(total / take)
            },
            filters: {
                search: search || null,
                status: status || null
            }
        });

    } catch (error) {
        console.error("Get All Public Events Error:", error);
        return res.status(500).json({
            success: false,
            message: "Gagal mengambil daftar event",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
};