// routes/donations.routes.js
import express from "express";
import {
    // Campaign CRUD
    getCampaigns,
    getCampaignById,
    createCampaign,
    updateCampaign,
    deleteCampaign,
    // Campaign Stats
    getCampaignStats,
    // Donations (money/goods/volunteer)
    createDonation,
    // getDonations,
    getDonationById,
    getDonationsByCampaign,
    getDonationsByCommunity,
    getMyDonations,
    updateDonationStatus,
    verifyDonation,
    // Community Representative
    updateDonationRepresentative,
    updateDonationRepresentationStatus,
    // Donation Approvals
    approveCommunityDonation,
    rejectCommunityDonation,
    // Volunteer Registrations
    registerAsVolunteer,
    updateVolunteerStatus,
    getVolunteersByCampaign,
    // Admin endpoints
    getDonationStats,
    getAllDonations,
    getPendingVerifications,
    // Community representative verification
    verifyRepresentative,
    cancelVerification,
    // Campaign management
    toggleCampaignStatus,
    getCampaignDonationSummary,
    getPendingCampaigns,
    approveCampaign,
    rejectCampaign,
} from "../controllers/donations/index.js";
import {
    authenticate
} from "../middlewares/auth.middleware.js";
import {
    uploadDonationProof,
    uploadDonationGoodsPhoto
} from "../middlewares/upload.middleware.js";

const router = express.Router();

// ============================================
// 🔒 SEMUA ROUTE HARUS LOGIN
// ============================================

// ============================================
// 📊 CAMPAIGN MANAGEMENT
// ============================================

// GET All Campaigns (with filters)
router.get("/campaigns", authenticate, getCampaigns);

// GET Campaign by ID
router.get("/campaigns/:id", authenticate, getCampaignById);

// GET Campaign Stats (summary)
router.get("/campaigns/:id/stats", authenticate, getCampaignStats);

// GET Campaign Donation Summary
router.get("/campaigns/:id/summary", authenticate, getCampaignDonationSummary);

// CREATE Campaign
router.post("/campaigns", authenticate, createCampaign);

// UPDATE Campaign
router.put("/campaigns/:id", authenticate, updateCampaign);

// TOGGLE Campaign Status (active/completed/cancelled)
router.patch("/campaigns/:id/status", authenticate, toggleCampaignStatus);

// DELETE Campaign (soft delete / archive)
router.delete("/campaigns/:id", authenticate, deleteCampaign);

// ============================================
// 💰 DONATIONS (Money, Goods, Volunteer)
// ============================================

// GET My Donations (user's own donations)
router.get("/donations/me", authenticate, getMyDonations);

// GET All Donations (admin only)
router.get("/donations/all", authenticate, getAllDonations);

// GET Donations by Campaign
router.get("/campaigns/:id/donations", authenticate, getDonationsByCampaign);

// GET Donations by Community
router.get("/communities/:id/donations", authenticate, getDonationsByCommunity);

// GET Donation by ID
router.get("/donations/:id", authenticate, getDonationById);

// CREATE Donation (money with proof image)
router.post(
    "/campaigns/:id/donate",
    authenticate,
    uploadDonationProof,
    createDonation
);

// CREATE Donation with Goods Photo
router.post(
    "/campaigns/:id/donate-goods",
    authenticate,
    uploadDonationGoodsPhoto,
    createDonation
);

// CREATE Volunteer Registration
router.post(
    "/campaigns/:id/volunteer",
    authenticate,
    registerAsVolunteer
);

// UPDATE Donation Status (admin/community admin)
router.put("/donations/:id/status", authenticate, updateDonationStatus);

// VERIFY Donation (admin only)
router.put("/donations/:id/verify", authenticate, verifyDonation);

// ============================================
// 👥 COMMUNITY REPRESENTATIVE
// ============================================

// UPDATE Donation Representative (community admin)
router.put("/donations/:id/representative", authenticate, updateDonationRepresentative);

// UPDATE Representation Status
router.put("/donations/:id/representation-status", authenticate, updateDonationRepresentationStatus);

// VERIFY Representative (admin)
router.put("/donations/:id/verify-representative", authenticate, verifyRepresentative);

// CANCEL Verification
router.delete("/donations/:id/verify-representative", authenticate, cancelVerification);

// ============================================
// ✅ COMMUNITY APPROVALS
// ============================================

// APPROVE Community Donation (community admin)
router.put("/donations/:id/approve", authenticate, approveCommunityDonation);

// REJECT Community Donation (community admin)
router.put("/donations/:id/reject", authenticate, rejectCommunityDonation);

// ============================================
// 🧑‍🤝‍🧑 VOLUNTEER MANAGEMENT
// ============================================

// GET Volunteers by Campaign
router.get("/campaigns/:id/volunteers", authenticate, getVolunteersByCampaign);

// UPDATE Volunteer Status
router.put("/volunteers/:id/status", authenticate, updateVolunteerStatus);

// ============================================
// 📈 ADMIN ENDPOINTS
// ============================================

// GET Donation Stats (overall)
router.get("/admin/donations/stats", authenticate, getDonationStats);

// GET Pending Verifications
router.get("/admin/donations/pending", authenticate, getPendingVerifications);

// GET All Donations (already defined above)

router.get("/campaigns/pending", authenticate, getPendingCampaigns);

// APPROVE Campaign
router.put("/campaigns/:id/approve", authenticate, approveCampaign);

// REJECT Campaign
router.put("/campaigns/:id/reject", authenticate, rejectCampaign);

export default router;