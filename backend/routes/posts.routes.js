// routes/posts.routes.js
import express from "express";
import {
    // Posts
    getCommunityPosts,
    getFeedPosts,
    getPostById,
    createPost,
    createPostWithMedia,
    updatePost,
    deletePost,
    toggleLikePost,
    // Event Participants
    registerForEvent,
    cancelEventRegistration,
    getEventParticipants,
    updateParticipantStatus,
    // Comments
    getCommentsByPost,
    createComment,
    updateComment,
    deleteComment
} from "../controllers/posts.controller.js";
import {
    authenticate
} from "../middlewares/auth.middleware.js";
import {
    uploadPostImages
} from "../middlewares/upload.middleware.js";

const router = express.Router();

// ============================================
// 🔒 SEMUA ROUTE HARUS LOGIN
// ============================================

// ============================================
// 📋 POSTS
// ============================================

// GET Posts by Community ID
router.get("/communities/:id/posts", authenticate, getCommunityPosts);

// GET Feed Posts (from communities user joined)
router.get("/posts/feed", authenticate, getFeedPosts);

// GET Post by ID
router.get("/posts/:id", authenticate, getPostById);

// CREATE Post (text only)
router.post("/communities/:id/posts", authenticate, createPost);

// CREATE Post with Media (upload file)
router.post(
    "/communities/:id/posts/media",
    authenticate,
    uploadPostImages,
    createPostWithMedia
);

// UPDATE Post
router.put("/posts/:id", authenticate, updatePost);

// DELETE Post
router.delete("/posts/:id", authenticate, deletePost);

// LIKE/UNLIKE Post
router.post("/posts/:id/like", authenticate, toggleLikePost);

// ============================================
// 🎯 EVENT PARTICIPANTS
// ============================================

// Register for Event
router.post("/posts/:id/event/register", authenticate, registerForEvent);

// Cancel Event Registration
router.delete("/posts/:id/event/cancel", authenticate, cancelEventRegistration);

// Get Event Participants
router.get("/posts/:id/event/participants", authenticate, getEventParticipants);

// Update Participant Status (for admin/author)
router.put("/posts/:id/event/participants", authenticate, updateParticipantStatus);

// ============================================
// 💬 COMMENTS
// ============================================

// GET Comments by Post ID
router.get("/posts/:id/comments", authenticate, getCommentsByPost);

// CREATE Comment
router.post("/posts/:id/comments", authenticate, createComment);

// UPDATE Comment
router.put("/comments/:id", authenticate, updateComment);

// DELETE Comment
router.delete("/comments/:id", authenticate, deleteComment);

export default router;