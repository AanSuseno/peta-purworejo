// server.js
import express from "express";
import prisma from "./lib/prisma.js";
import cors from "cors";
import "dotenv/config";
import path from "path";
import { fileURLToPath } from "url";
import fs from "fs";

import authRoutes from "./routes/auth.routes.js";
import categoriesRoutes from "./routes/categories.routes.js";
import usersRoutes from "./routes/users.routes.js";
import communitiesRoutes from "./routes/communities.routes.js";
import postsRoutes from "./routes/posts.routes.js";
import donationRoutes from "./routes/donations.routes.js";
import scoresRoutes from "./routes/scores.routes.js";

// Import cleanup functions
import { cleanupUnusedFiles, getFileStats } from "./utils/cleanup.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

process.env.TZ = 'Asia/Jakarta';

const app = express();
const PORT = 3000;

// Setup uploads folder
const uploadDir = path.join(__dirname, "uploads");
const uploadDirs = [
    uploadDir,
    path.join(uploadDir, "profiles"),
    path.join(uploadDir, "communities"),
    path.join(uploadDir, "donations"),
    path.join(uploadDir, "distributions")
];

uploadDirs.forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
        console.log(`📁 Folder created: ${dir}`);
    }
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use("/uploads", express.static(uploadDir));

// Logging
app.use((req, res, next) => {
    console.log(`📡 [${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
});

// =============================================
// CLEANUP ENDPOINTS
// =============================================

// GET: Lihat statistik file
app.get("/file-stats", async (req, res) => {
    try {
        const stats = await getFileStats();
        res.json(stats);
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

// GET: Hapus file yang tidak terpakai
app.get("/cleanup-files", async (req, res) => {
    try {
        const result = await cleanupUnusedFiles();
        res.json(result);
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

// POST: Hapus file yang tidak terpakai (lebih aman)
app.post("/cleanup-files", async (req, res) => {
    try {
        const result = await cleanupUnusedFiles();
        res.json(result);
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message
        });
    }
});

// =============================================
// ROUTES
// =============================================

app.use("/auth", authRoutes);
app.use("/categories", categoriesRoutes);
app.use("/users", usersRoutes);
app.use("/communities", communitiesRoutes);
app.use("/posts", postsRoutes);
app.use("/donations", donationRoutes);
app.use("/scores", scoresRoutes);

// Test upload
app.get("/test-upload", (req, res) => {
    const files = {};
    const profilesDir = path.join(uploadDir, "profiles");
    const communitiesDir = path.join(uploadDir, "communities");
    
    if (fs.existsSync(profilesDir)) {
        files.profiles = fs.readdirSync(profilesDir);
    }
    if (fs.existsSync(communitiesDir)) {
        files.communities = fs.readdirSync(communitiesDir);
    }
    
    res.json({
        success: true,
        upload_dir: uploadDir,
        files: files,
        urls: {
            profiles: files.profiles?.map(f => `/uploads/profiles/${f}`) || [],
            communities: files.communities?.map(f => `/uploads/communities/${f}`) || []
        }
    });
});

// Health check
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'OK' });
});

// Start server
app.listen(PORT, () => {
    console.log(`🚀 Server running at http://localhost:${PORT}`);
});

export default app;