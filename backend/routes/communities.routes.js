// routes/communities.routes.js
import express from "express";
import {
    getAllCommunities,
    getCommunityById,
    getCommunityMembers,
    createCommunity,
    updateCommunity,
    deleteCommunity,
    joinCommunity,
    leaveCommunity,
    addCommunityAdmin,
    removeCommunityAdmin,
    transferOwnership,
    uploadCommunityLogo,
    uploadCommunityBanner,
    uploadCommunityMedia,
    deleteCommunityLogo,
    deleteCommunityBanner
} from "../controllers/communities.controller.js";
import {
    authenticate,
    isCommunityAdminOrFounder,
    isSystemAdmin
} from "../middlewares/auth.middleware.js";
import {
    uploadCommunityLogo as uploadLogoMiddleware,
    uploadCommunityBanner as uploadBannerMiddleware,
    uploadCommunityMedia as uploadMediaMiddleware
} from "../middlewares/upload.middleware.js";

const router = express.Router();

// Public routes (butuh auth)
router.get("/", authenticate, getAllCommunities);
router.get("/:id", authenticate, getCommunityById);
router.get("/:id/members", authenticate, getCommunityMembers);

// Create community
router.post("/", authenticate, createCommunity);

// Update & Delete - butuh admin/founder
router.put("/:id", authenticate, isCommunityAdminOrFounder('id'), updateCommunity);
router.delete("/:id", authenticate, isCommunityAdminOrFounder('id'), deleteCommunity);

// Join & Leave
router.post("/:id/join", authenticate, joinCommunity);
router.post("/:id/leave", authenticate, leaveCommunity);

// Admin management - butuh admin/founder
router.post("/:id/admins", authenticate, isCommunityAdminOrFounder('id'), addCommunityAdmin);
router.delete("/:id/admins/:adminId", authenticate, isCommunityAdminOrFounder('id'), removeCommunityAdmin);
router.post("/:id/transfer", authenticate, isCommunityAdminOrFounder('id'), transferOwnership);

// Media upload - butuh admin/founder
router.post("/:id/logo", authenticate, isCommunityAdminOrFounder('id'), uploadLogoMiddleware, uploadCommunityLogo);
router.post("/:id/banner", authenticate, isCommunityAdminOrFounder('id'), uploadBannerMiddleware, uploadCommunityBanner);
router.post("/:id/media", authenticate, isCommunityAdminOrFounder('id'), uploadMediaMiddleware, uploadCommunityMedia);

// Delete media - butuh admin/founder
router.delete("/:id/logo", authenticate, isCommunityAdminOrFounder('id'), deleteCommunityLogo);
router.delete("/:id/banner", authenticate, isCommunityAdminOrFounder('id'), deleteCommunityBanner);

export default router;