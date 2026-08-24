-- CreateEnum
CREATE TYPE "admin_role_enum" AS ENUM ('admin', 'founder');

-- CreateEnum
CREATE TYPE "campaign_status_enum" AS ENUM ('active', 'completed', 'cancelled');

-- CreateEnum
CREATE TYPE "collab_status_enum" AS ENUM ('pending', 'accepted', 'rejected', 'expired');

-- CreateEnum
CREATE TYPE "donation_status_enum" AS ENUM ('pending', 'confirmed', 'rejected', 'delivered');

-- CreateEnum
CREATE TYPE "donation_type_enum" AS ENUM ('money', 'goods', 'volunteer');

-- CreateEnum
CREATE TYPE "event_status_enum" AS ENUM ('upcoming', 'ongoing', 'completed', 'cancelled');

-- CreateEnum
CREATE TYPE "media_type_enum" AS ENUM ('image', 'video');

-- CreateEnum
CREATE TYPE "member_status_enum" AS ENUM ('pending', 'active', 'inactive', 'rejected');

-- CreateEnum
CREATE TYPE "notif_target_role_enum" AS ENUM ('all', 'admin', 'member');

-- CreateEnum
CREATE TYPE "participant_status_enum" AS ENUM ('registered', 'attended', 'absent', 'cancelled');

-- CreateEnum
CREATE TYPE "post_status_enum" AS ENUM ('active', 'reported', 'hidden');

-- CreateEnum
CREATE TYPE "post_type_enum" AS ENUM ('regular', 'event');

-- CreateEnum
CREATE TYPE "post_visibility_enum" AS ENUM ('public', 'community_only');

-- CreateEnum
CREATE TYPE "report_status_enum" AS ENUM ('pending', 'processed', 'rejected');

-- CreateEnum
CREATE TYPE "report_target_enum" AS ENUM ('post', 'comment', 'community', 'user', 'event');

-- CreateEnum
CREATE TYPE "volunteer_status_enum" AS ENUM ('pending', 'confirmed', 'declined', 'completed');

-- CreateTable
CREATE TABLE "categories" (
    "category_id" SERIAL NOT NULL,
    "category_name" VARCHAR(50) NOT NULL,
    "category_icon" VARCHAR(50),
    "category_description" TEXT,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "categories_pkey" PRIMARY KEY ("category_id")
);

-- CreateTable
CREATE TABLE "collaboration_requests" (
    "collab_id" SERIAL NOT NULL,
    "sender_community_id" INTEGER NOT NULL,
    "receiver_community_id" INTEGER NOT NULL,
    "message" TEXT,
    "status" "collab_status_enum" NOT NULL DEFAULT 'pending',
    "post_id" INTEGER,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "collaboration_requests_pkey" PRIMARY KEY ("collab_id")
);

-- CreateTable
CREATE TABLE "communities" (
    "community_id" SERIAL NOT NULL,
    "community_name" VARCHAR(100) NOT NULL,
    "community_slug" VARCHAR(120) NOT NULL,
    "description" TEXT,
    "logo" VARCHAR(255),
    "banner" VARCHAR(255),
    "category_id" INTEGER,
    "founder_id" INTEGER NOT NULL,
    "kecamatan" VARCHAR(50),
    "address" TEXT,
    "contact_email" VARCHAR(100),
    "contact_phone" VARCHAR(20),
    "total_members" INTEGER NOT NULL DEFAULT 0,
    "total_score" INTEGER NOT NULL DEFAULT 0,
    "is_verified" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "communities_pkey" PRIMARY KEY ("community_id")
);

-- CreateTable
CREATE TABLE "community_admins" (
    "admin_id" SERIAL NOT NULL,
    "community_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "role" "admin_role_enum" NOT NULL,
    "assigned_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "community_admins_pkey" PRIMARY KEY ("admin_id")
);

-- CreateTable
CREATE TABLE "community_locations" (
    "location_id" SERIAL NOT NULL,
    "community_id" INTEGER NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "address" TEXT,
    "latitude" DECIMAL(10,8),
    "longitude" DECIMAL(11,8),
    "google_maps_url" VARCHAR(255),
    "is_primary" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "community_locations_pkey" PRIMARY KEY ("location_id")
);

-- CreateTable
CREATE TABLE "community_members" (
    "member_id" SERIAL NOT NULL,
    "community_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "join_date" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "member_status_enum" NOT NULL DEFAULT 'pending',
    "left_date" TIMESTAMP(6),

    CONSTRAINT "community_members_pkey" PRIMARY KEY ("member_id")
);

-- CreateTable
CREATE TABLE "donation_campaigns" (
    "campaign_id" SERIAL NOT NULL,
    "community_id" INTEGER,
    "creator_id" INTEGER NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "description" TEXT,
    "donation_type" "donation_type_enum" NOT NULL,
    "target_amount" DECIMAL(15,2),
    "collected_amount" DECIMAL(15,2) NOT NULL DEFAULT 0,
    "bank_account_info" TEXT,
    "ewallet_info" TEXT,
    "goods_description" TEXT,
    "volunteer_needs" TEXT,
    "volunteer_slots" INTEGER,
    "volunteer_registered" INTEGER NOT NULL DEFAULT 0,
    "start_date" DATE,
    "end_date" DATE,
    "status" "campaign_status_enum" NOT NULL DEFAULT 'active',
    "total_donors" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "donation_campaigns_pkey" PRIMARY KEY ("campaign_id")
);

-- CreateTable
CREATE TABLE "donations" (
    "donation_id" SERIAL NOT NULL,
    "campaign_id" INTEGER NOT NULL,
    "donor_id" INTEGER,
    "donation_type" "donation_type_enum" NOT NULL,
    "amount" DECIMAL(15,2),
    "payment_method" VARCHAR(50),
    "proof_image" VARCHAR(255),
    "goods_type" VARCHAR(50),
    "goods_name" VARCHAR(100),
    "goods_quantity" INTEGER,
    "goods_unit" VARCHAR(20),
    "goods_photo" VARCHAR(255),
    "delivery_method" VARCHAR(50),
    "delivery_address" TEXT,
    "volunteer_availability" VARCHAR(50),
    "volunteer_skill" VARCHAR(100),
    "volunteer_notes" TEXT,
    "donor_name" VARCHAR(100),
    "donor_phone" VARCHAR(20),
    "donor_email" VARCHAR(100),
    "is_anonymous" BOOLEAN NOT NULL DEFAULT false,
    "is_verified" BOOLEAN NOT NULL DEFAULT false,
    "status" "donation_status_enum" NOT NULL DEFAULT 'pending',
    "confirmed_at" TIMESTAMP(6),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "donations_pkey" PRIMARY KEY ("donation_id")
);

-- CreateTable
CREATE TABLE "event_participants" (
    "participant_id" SERIAL NOT NULL,
    "post_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "registration_date" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "participant_status_enum" NOT NULL DEFAULT 'registered',

    CONSTRAINT "event_participants_pkey" PRIMARY KEY ("participant_id")
);

-- CreateTable
CREATE TABLE "goods_categories" (
    "category_id" SERIAL NOT NULL,
    "category_name" VARCHAR(50) NOT NULL,
    "icon" VARCHAR(50),
    "unit_default" VARCHAR(20),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "goods_categories_pkey" PRIMARY KEY ("category_id")
);

-- CreateTable
CREATE TABLE "notification_reads" (
    "read_id" SERIAL NOT NULL,
    "notification_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "is_read" BOOLEAN NOT NULL DEFAULT false,
    "read_at" TIMESTAMP(6),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notification_reads_pkey" PRIMARY KEY ("read_id")
);

-- CreateTable
CREATE TABLE "notification_targets" (
    "target_id" SERIAL NOT NULL,
    "notification_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notification_targets_pkey" PRIMARY KEY ("target_id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "notification_id" SERIAL NOT NULL,
    "type" VARCHAR(50) NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "content" TEXT,
    "link" VARCHAR(255),
    "target_community_id" INTEGER,
    "target_user_id" INTEGER,
    "target_role" "notif_target_role_enum" NOT NULL DEFAULT 'all',
    "is_global" BOOLEAN NOT NULL DEFAULT false,
    "created_by" INTEGER,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("notification_id")
);

-- CreateTable
CREATE TABLE "post_comments" (
    "comment_id" SERIAL NOT NULL,
    "post_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "content" TEXT NOT NULL,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "post_comments_pkey" PRIMARY KEY ("comment_id")
);

-- CreateTable
CREATE TABLE "post_likes" (
    "like_id" SERIAL NOT NULL,
    "post_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "post_likes_pkey" PRIMARY KEY ("like_id")
);

-- CreateTable
CREATE TABLE "post_media" (
    "media_id" SERIAL NOT NULL,
    "post_id" INTEGER NOT NULL,
    "media_type" "media_type_enum" NOT NULL,
    "media_url" VARCHAR(255) NOT NULL,
    "caption" VARCHAR(200),
    "is_cover" BOOLEAN NOT NULL DEFAULT false,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "post_media_pkey" PRIMARY KEY ("media_id")
);

-- CreateTable
CREATE TABLE "posts" (
    "post_id" SERIAL NOT NULL,
    "community_id" INTEGER NOT NULL,
    "author_id" INTEGER NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "content" TEXT,
    "post_type" "post_type_enum" NOT NULL DEFAULT 'regular',
    "visibility" "post_visibility_enum" NOT NULL DEFAULT 'public',
    "is_pinned" BOOLEAN NOT NULL DEFAULT false,
    "total_likes" INTEGER NOT NULL DEFAULT 0,
    "total_comments" INTEGER NOT NULL DEFAULT 0,
    "status" "post_status_enum" NOT NULL DEFAULT 'active',
    "event_date" DATE,
    "event_start_time" TIME(6),
    "event_end_time" TIME(6),
    "event_location" VARCHAR(255),
    "event_latitude" DECIMAL(10,8),
    "event_longitude" DECIMAL(11,8),
    "event_quota" INTEGER,
    "event_registration_link" VARCHAR(500),
    "event_registered_count" INTEGER NOT NULL DEFAULT 0,
    "event_status" "event_status_enum" DEFAULT 'upcoming',
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "posts_pkey" PRIMARY KEY ("post_id")
);

-- CreateTable
CREATE TABLE "reports" (
    "report_id" SERIAL NOT NULL,
    "reporter_id" INTEGER NOT NULL,
    "target_type" "report_target_enum" NOT NULL,
    "target_id" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "status" "report_status_enum" NOT NULL DEFAULT 'pending',
    "processed_by" INTEGER,
    "processed_at" TIMESTAMP(6),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "reports_pkey" PRIMARY KEY ("report_id")
);

-- CreateTable
CREATE TABLE "user_roles" (
    "role_id" SERIAL NOT NULL,
    "role_name" VARCHAR(30) NOT NULL,
    "role_description" TEXT,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_roles_pkey" PRIMARY KEY ("role_id")
);

-- CreateTable
CREATE TABLE "users" (
    "user_id" SERIAL NOT NULL,
    "email" VARCHAR(100) NOT NULL,
    "password_hash" VARCHAR(255),
    "full_name" VARCHAR(100) NOT NULL,
    "phone_number" VARCHAR(20),
    "profile_picture" VARCHAR(255),
    "bio" TEXT,
    "kecamatan" VARCHAR(50),
    "interests" TEXT,
    "role_id" INTEGER NOT NULL,
    "is_verified" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "last_login" TIMESTAMP(6),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "google_id" VARCHAR(255),

    CONSTRAINT "users_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "volunteer_registrations" (
    "registration_id" SERIAL NOT NULL,
    "campaign_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "availability" VARCHAR(50),
    "skills" TEXT,
    "experience" TEXT,
    "notes" TEXT,
    "status" "volunteer_status_enum" NOT NULL DEFAULT 'pending',
    "assigned_task" TEXT,
    "confirmed_at" TIMESTAMP(6),
    "completed_at" TIMESTAMP(6),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "volunteer_registrations_pkey" PRIMARY KEY ("registration_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "categories_category_name_key" ON "categories"("category_name");

-- CreateIndex
CREATE INDEX "idx_collab_receiver" ON "collaboration_requests"("receiver_community_id");

-- CreateIndex
CREATE INDEX "idx_collab_sender" ON "collaboration_requests"("sender_community_id");

-- CreateIndex
CREATE UNIQUE INDEX "communities_community_slug_key" ON "communities"("community_slug");

-- CreateIndex
CREATE INDEX "idx_communities_category_id" ON "communities"("category_id");

-- CreateIndex
CREATE INDEX "idx_communities_founder_id" ON "communities"("founder_id");

-- CreateIndex
CREATE INDEX "idx_communities_is_verified" ON "communities"("is_verified");

-- CreateIndex
CREATE INDEX "idx_community_admins_community_id" ON "community_admins"("community_id");

-- CreateIndex
CREATE INDEX "idx_community_admins_user_id" ON "community_admins"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "community_admins_community_id_user_id_key" ON "community_admins"("community_id", "user_id");

-- CreateIndex
CREATE INDEX "idx_community_locations_community_id" ON "community_locations"("community_id");

-- CreateIndex
CREATE INDEX "idx_community_members_community_id" ON "community_members"("community_id");

-- CreateIndex
CREATE INDEX "idx_community_members_user_id" ON "community_members"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "community_members_community_id_user_id_key" ON "community_members"("community_id", "user_id");

-- CreateIndex
CREATE INDEX "idx_donation_campaigns_community_id" ON "donation_campaigns"("community_id");

-- CreateIndex
CREATE INDEX "idx_donation_campaigns_status" ON "donation_campaigns"("status");

-- CreateIndex
CREATE INDEX "idx_donations_campaign_id" ON "donations"("campaign_id");

-- CreateIndex
CREATE INDEX "idx_donations_donor_id" ON "donations"("donor_id");

-- CreateIndex
CREATE INDEX "idx_donations_status" ON "donations"("status");

-- CreateIndex
CREATE INDEX "idx_event_participants_post_id" ON "event_participants"("post_id");

-- CreateIndex
CREATE UNIQUE INDEX "event_participants_post_id_user_id_key" ON "event_participants"("post_id", "user_id");

-- CreateIndex
CREATE UNIQUE INDEX "goods_categories_category_name_key" ON "goods_categories"("category_name");

-- CreateIndex
CREATE INDEX "idx_notification_reads_notification_id" ON "notification_reads"("notification_id");

-- CreateIndex
CREATE INDEX "idx_notification_reads_user_id" ON "notification_reads"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "notification_reads_notification_id_user_id_key" ON "notification_reads"("notification_id", "user_id");

-- CreateIndex
CREATE INDEX "idx_notification_targets_notification_id" ON "notification_targets"("notification_id");

-- CreateIndex
CREATE UNIQUE INDEX "notification_targets_notification_id_user_id_key" ON "notification_targets"("notification_id", "user_id");

-- CreateIndex
CREATE INDEX "idx_notifications_is_global" ON "notifications"("is_global");

-- CreateIndex
CREATE INDEX "idx_notifications_target_community" ON "notifications"("target_community_id");

-- CreateIndex
CREATE INDEX "idx_notifications_target_user" ON "notifications"("target_user_id");

-- CreateIndex
CREATE INDEX "idx_post_comments_post_id" ON "post_comments"("post_id");

-- CreateIndex
CREATE INDEX "idx_post_comments_user_id" ON "post_comments"("user_id");

-- CreateIndex
CREATE INDEX "idx_post_likes_post_id" ON "post_likes"("post_id");

-- CreateIndex
CREATE UNIQUE INDEX "post_likes_post_id_user_id_key" ON "post_likes"("post_id", "user_id");

-- CreateIndex
CREATE INDEX "idx_post_media_post_id" ON "post_media"("post_id");

-- CreateIndex
CREATE INDEX "idx_posts_author_id" ON "posts"("author_id");

-- CreateIndex
CREATE INDEX "idx_posts_community_id" ON "posts"("community_id");

-- CreateIndex
CREATE INDEX "idx_posts_status" ON "posts"("status");

-- CreateIndex
CREATE INDEX "idx_posts_post_type" ON "posts"("post_type");

-- CreateIndex
CREATE INDEX "idx_posts_event_date" ON "posts"("event_date");

-- CreateIndex
CREATE INDEX "idx_posts_visibility" ON "posts"("visibility");

-- CreateIndex
CREATE INDEX "idx_reports_status" ON "reports"("status");

-- CreateIndex
CREATE INDEX "idx_reports_target" ON "reports"("target_type", "target_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_roles_role_name_key" ON "user_roles"("role_name");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_google_id_unique" ON "users"("google_id");

-- CreateIndex
CREATE INDEX "idx_users_kecamatan" ON "users"("kecamatan");

-- CreateIndex
CREATE INDEX "idx_users_role_id" ON "users"("role_id");

-- CreateIndex
CREATE INDEX "idx_volunteer_registrations_campaign_id" ON "volunteer_registrations"("campaign_id");

-- CreateIndex
CREATE UNIQUE INDEX "volunteer_registrations_campaign_id_user_id_key" ON "volunteer_registrations"("campaign_id", "user_id");

-- AddForeignKey
ALTER TABLE "collaboration_requests" ADD CONSTRAINT "collaboration_requests_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("post_id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "collaboration_requests" ADD CONSTRAINT "collaboration_requests_receiver_community_id_fkey" FOREIGN KEY ("receiver_community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "collaboration_requests" ADD CONSTRAINT "collaboration_requests_sender_community_id_fkey" FOREIGN KEY ("sender_community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "communities" ADD CONSTRAINT "communities_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("category_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "communities" ADD CONSTRAINT "communities_founder_id_fkey" FOREIGN KEY ("founder_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "community_admins" ADD CONSTRAINT "community_admins_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "community_admins" ADD CONSTRAINT "community_admins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "community_locations" ADD CONSTRAINT "community_locations_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "community_members" ADD CONSTRAINT "community_members_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "community_members" ADD CONSTRAINT "community_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "donation_campaigns" ADD CONSTRAINT "donation_campaigns_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "donation_campaigns" ADD CONSTRAINT "donation_campaigns_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "donations" ADD CONSTRAINT "donations_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "donation_campaigns"("campaign_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "donations" ADD CONSTRAINT "donations_donor_id_fkey" FOREIGN KEY ("donor_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "event_participants" ADD CONSTRAINT "event_participants_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("post_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "event_participants" ADD CONSTRAINT "event_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notification_reads" ADD CONSTRAINT "notification_reads_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "notifications"("notification_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notification_reads" ADD CONSTRAINT "notification_reads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notification_targets" ADD CONSTRAINT "notification_targets_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "notifications"("notification_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notification_targets" ADD CONSTRAINT "notification_targets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_target_community_id_fkey" FOREIGN KEY ("target_community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("post_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "post_likes" ADD CONSTRAINT "post_likes_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("post_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "post_likes" ADD CONSTRAINT "post_likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "post_media" ADD CONSTRAINT "post_media_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("post_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "posts" ADD CONSTRAINT "posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "posts" ADD CONSTRAINT "posts_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "communities"("community_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_processed_by_fkey" FOREIGN KEY ("processed_by") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "user_roles"("role_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "volunteer_registrations" ADD CONSTRAINT "volunteer_registrations_campaign_id_fkey" FOREIGN KEY ("campaign_id") REFERENCES "donation_campaigns"("campaign_id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "volunteer_registrations" ADD CONSTRAINT "volunteer_registrations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;
