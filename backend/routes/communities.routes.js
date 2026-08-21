import express from "express";
import {
    getAllCommunities,
    getCommunityById,
    getCommunityBySlug,
    searchCommunities,
    createCommunity,
    updateCommunity,
    deleteCommunity,
    getCommunityMembers,
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
    isSystemAdmin,
    isCommunityAdminOrFounder
} from "../middlewares/auth.middleware.js";
import {
    uploadCommunityLogo as uploadLogoMiddleware,
    uploadCommunityBanner as uploadBannerMiddleware,
    uploadCommunityMedia as uploadMediaMiddleware
} from "../middlewares/upload.middleware.js";

const router = express.Router();

router.get("/", authenticate, getAllCommunities);
router.get("/search", authenticate, searchCommunities);
router.get("/slug/:slug", authenticate, getCommunityBySlug);
router.get("/:id", authenticate, getCommunityById);
router.post("/", authenticate, createCommunity);
router.put("/:id", authenticate, isCommunityAdminOrFounder('id'), updateCommunity);
router.delete("/:id", authenticate, isCommunityAdminOrFounder('id'), deleteCommunity);
router.get("/:id/members", authenticate, getCommunityMembers);
router.post("/:id/join", authenticate, joinCommunity);
router.post("/:id/leave", authenticate, leaveCommunity);
router.post("/:id/admins", authenticate, isCommunityAdminOrFounder('id'), addCommunityAdmin);
router.delete("/:id/admins/:adminId", authenticate, isCommunityAdminOrFounder('id'), removeCommunityAdmin);
router.post("/:id/transfer", authenticate, isCommunityAdminOrFounder('id'), transferOwnership);
router.post("/:id/logo", authenticate, isCommunityAdminOrFounder('id'), uploadLogoMiddleware, uploadCommunityLogo);
router.post("/:id/banner", authenticate, isCommunityAdminOrFounder('id'), uploadBannerMiddleware, uploadCommunityBanner);
router.post("/:id/media", authenticate, isCommunityAdminOrFounder('id'), uploadMediaMiddleware, uploadCommunityMedia);
router.delete("/:id/logo", authenticate, isCommunityAdminOrFounder('id'), deleteCommunityLogo);
router.delete("/:id/banner", authenticate, isCommunityAdminOrFounder('id'), deleteCommunityBanner);

export default router;