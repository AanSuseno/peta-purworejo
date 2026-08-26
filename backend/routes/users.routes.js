// routes/users.routes.js
import express from "express";
import {
    // Admin Only
    getAllUsers,
    updateUserByAdmin,
    deleteUserByAdmin,
    getUserStatistics,
    // User (harus login)
    getMyProfile,
    getUserById,
    getUserCommunities,
    updateMyProfile,
    changePassword,
    deactivateMyAccount,
    getAllRoles,
    uploadMyProfilePicture,
    updateMyProfilePicture
} from "../controllers/users.controller.js";
import {
    authenticate,
    isSystemAdmin,
    requireRole
} from "../middlewares/auth.middleware.js";
import { uploadProfilePicture, handleUploadError } from "../middlewares/upload.middleware.js";

const router = express.Router();
router.get("/", authenticate, isSystemAdmin, getAllUsers);
router.get("/stats/overview", authenticate, isSystemAdmin, getUserStatistics);
router.delete("/me", authenticate, deactivateMyAccount);
router.get("/roles", authenticate, getAllRoles);
router.get("/me/profile", authenticate, getMyProfile);
router.put("/me/profile", authenticate, updateMyProfile);
router.put("/me/profile-picture", authenticate, updateMyProfilePicture);
router.put("/me/password", authenticate, changePassword);
router.post("/me/profile-picture/upload", authenticate, uploadProfilePicture, handleUploadError, uploadMyProfilePicture);
router.put("/me/profile-picture", authenticate, updateMyProfilePicture);
router.get("/:id/communities", authenticate, getUserCommunities);
router.get("/:id", getUserById);
router.put("/:id", authenticate, isSystemAdmin, updateUserByAdmin);
router.delete("/:id", authenticate, isSystemAdmin, deleteUserByAdmin);



export default router;