import express from "express";
import prisma from "./lib/prisma.js";
import cors from "cors";
import "dotenv/config";
import authRoutes from "./routes/auth.routes.js";

process.env.TZ = 'Asia/Jakarta';

const app = express();

const PORT = 3000;

app.use(cors());
app.use(express.json());

app.use("/auth", authRoutes);

app.get("/", (req, res) => {
    res.json({
        message: "Express berjalan!"
    });
});

app.get("/test-db", async (req, res) => {
    try {
        await prisma.$connect();

        res.json({
            success: true,
            message: "Berhasil terhubung ke PostgreSQL!"
        });

    } catch (error) {
        console.error("Database error:", error);

        res.status(500).json({
            success: false,
            message: "Gagal terhubung ke PostgreSQL",
            error: error.message
        });
    }
});

app.listen(PORT, () => {
    console.log(`Server berjalan di http://localhost:${PORT}`);
});