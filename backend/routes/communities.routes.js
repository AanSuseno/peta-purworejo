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
    transferOwnership
} from "../controllers/communities.controller.js";
import {
    authenticate,
    isSystemAdmin,
    isCommunityAdminOrFounder
} from "../middlewares/auth.middleware.js";

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

export default router;