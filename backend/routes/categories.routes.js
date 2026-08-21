// routes/categories.routes.js
import express from "express";
import {
    getAllCategories,
    getCategoryById,
    createCategory,
    updateCategory,
    deleteCategory,
    searchCategories
} from "../controllers/categories.controller.js";
import { 
    authenticate, 
    requireRole,
    isSystemAdmin 
} from "../middlewares/auth.middleware.js";

const router = express.Router();

router.get("/", getAllCategories);
router.get("/search", searchCategories);
router.get("/:id", getCategoryById);

// 🔒 Protected routes - Hanya System Admin y
router.post("/", authenticate, isSystemAdmin, createCategory);
router.put("/:id", authenticate, isSystemAdmin, updateCategory);
router.delete("/:id", authenticate, isSystemAdmin, deleteCategory);

export default router;