import express from "express";
import { googleLogin } from "../controllers/auth.controller.js";

const router = express.Router();

// Tambahkan middleware untuk log
router.use((req, res, next) => {
    console.log(`📡 [${new Date().toISOString()}] ${req.method} ${req.path}`);
    console.log("📦 Body:", req.body);
    next();
});

// Route Google Login
router.post("/google", googleLogin);

// Route test untuk cek status
router.get("/test", (req, res) => {
    res.json({
        status: "OK",
        googleClientId: process.env.GOOGLE_CLIENT_ID ? "Set" : "Not Set",
        jwtSecret: process.env.JWT_SECRET ? "Set" : "Not Set",
        timestamp: new Date().toISOString()
    });
});

export default router;