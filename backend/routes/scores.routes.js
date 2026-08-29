// routes/score.routes.js

import express from "express";
import prisma from "../lib/prisma.js";

import {
    getCommunityScore,
    getCommunityScoreHistory,
    getCommunityScoreSummary,
    getTopCommunitiesByScore
} from "../controllers/score.controller.js";

const router = express.Router();

// Ranking 20 komunitas dengan skor tertinggi
router.get("/ranking/top", async (req, res) => {
    try {
        const data = await getTopCommunitiesByScore(prisma);

        return res.json({
            success: true,
            data
        });
    } catch (error) {
        console.error("Get Top Communities Error:", error);

        return res.status(500).json({
            success: false,
            message: "Gagal mengambil ranking komunitas"
        });
    }
});

// Skor komunitas
router.get("/:communityId", async (req, res) => {
    try {
        const communityId = parseInt(req.params.communityId);

        if (!Number.isInteger(communityId)) {
            return res.status(400).json({
                success: false,
                message: "Community ID tidak valid"
            });
        }

        const totalScore = await getCommunityScore(
            prisma,
            communityId
        );

        return res.json({
            success: true,
            data: {
                community_id: communityId,
                total_score: totalScore
            }
        });
    } catch (error) {
        console.error("Get Community Score Error:", error);

        return res.status(500).json({
            success: false,
            message: "Gagal mengambil skor komunitas"
        });
    }
});

// Riwayat skor
router.get("/:communityId/history", async (req, res) => {
    try {
        const communityId = parseInt(req.params.communityId);

        const result = await getCommunityScoreHistory(
            prisma,
            communityId,
            {
                page: req.query.page,
                limit: req.query.limit,
                scoreType: req.query.scoreType
            }
        );

        return res.json({
            success: true,
            ...result
        });
    } catch (error) {
        console.error("Get Score History Error:", error);

        return res.status(500).json({
            success: false,
            message: "Gagal mengambil riwayat skor"
        });
    }
});

// Summary skor
router.get("/:communityId/summary", async (req, res) => {
    try {
        const communityId = parseInt(req.params.communityId);

        const summary = await getCommunityScoreSummary(
            prisma,
            communityId
        );

        return res.json({
            success: true,
            data: summary
        });
    } catch (error) {
        console.error("Get Score Summary Error:", error);

        return res.status(500).json({
            success: false,
            message: "Gagal mengambil summary skor"
        });
    }
});

export default router;