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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

process.env.TZ = 'Asia/Jakarta';

const app = express();
const PORT = 3000;

const uploadDir = path.join(__dirname, "uploads");
const uploadDirs = [
    uploadDir,
    path.join(uploadDir, "profiles"),
    path.join(uploadDir, "communities")
];

uploadDirs.forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
        console.log(`📁 Folder created: ${dir}`);
    }
});

app.use(cors());

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use("/uploads", express.static(uploadDir));

app.use((req, res, next) => {
    console.log(`📡 [${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
});

app.use("/auth", authRoutes);
app.use("/categories", categoriesRoutes);
app.use("/users", usersRoutes);
app.use("/communities", communitiesRoutes);

app.get("/test-upload", (req, res) => {
    const files = {};
    
    // Cek folder profiles
    const profilesDir = path.join(uploadDir, "profiles");
    if (fs.existsSync(profilesDir)) {
        files.profiles = fs.readdirSync(profilesDir);
    }
    
    // Cek folder communities
    const communitiesDir = path.join(uploadDir, "communities");
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

app.listen(PORT, () => {
    console.log(`Server berjalan di http://localhost:${PORT}`);
});