CREATE TYPE "public"."salon_activity_type" AS ENUM('system', 'announcement', 'question', 'comment');--> statement-breakpoint
CREATE TYPE "public"."salon_guest_status" AS ENUM('pending', 'accepted', 'declined', 'attended', 'absent', 'cancelled');--> statement-breakpoint
CREATE TYPE "public"."salon_invitation_status" AS ENUM('pending', 'accepted', 'tentative', 'declined', 'waitlist', 'attended', 'absent', 'cancelled');--> statement-breakpoint
CREATE TYPE "public"."salon_role" AS ENUM('organizer', 'staff', 'attendee');--> statement-breakpoint
CREATE TYPE "public"."salon_status" AS ENUM('draft', 'published', 'registration_closed', 'ongoing', 'finished', 'cancelled');--> statement-breakpoint
CREATE TYPE "public"."salon_visibility" AS ENUM('all', 'staff', 'organizer');--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "salon" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"subtitle" text,
	"description" text,
	"cover_url" text,
	"theme_tags" jsonb DEFAULT '[]'::jsonb,
	"organizer_user_id" bigint NOT NULL,
	"status" "salon_status" DEFAULT 'draft' NOT NULL,
	"start_at" timestamp with time zone NOT NULL,
	"end_at" timestamp with time zone,
	"registration_deadline_at" timestamp with time zone,
	"timezone" text DEFAULT 'Asia/Shanghai' NOT NULL,
	"location_name" text,
	"address" text,
	"floor_room" text,
	"lat" numeric(10, 7),
	"lng" numeric(10, 7),
	"parking_info" text,
	"transport_public" text,
	"transport_driving" text,
	"transport_pickup" text,
	"catering_meal_type" text,
	"catering_cuisine" text,
	"catering_dietary" text,
	"catering_time" text,
	"catering_payer" text,
	"lodging_hotel_name" text,
	"lodging_room_type" text,
	"lodging_price_cents" integer,
	"lodging_contact_name" text,
	"lodging_contact_phone_encrypted" text,
	"lodging_deadline_at" timestamp with time zone,
	"lodging_note" text,
	"dress_code" text,
	"fee_type" text DEFAULT 'free' NOT NULL,
	"fee_amount_cents" integer,
	"fee_note" text,
	"capacity_total" integer,
	"capacity_reserved" integer DEFAULT 0 NOT NULL,
	"agenda" jsonb DEFAULT '[]'::jsonb,
	"registration_form_schema" jsonb DEFAULT '[]'::jsonb,
	"visibility_settings" jsonb DEFAULT '{"attendeeList":"all","staffContact":"all"}'::jsonb,
	"created_by" bigint NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "salon_activity" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"salon_id" bigint NOT NULL,
	"author_user_id" bigint NOT NULL,
	"type" "salon_activity_type" DEFAULT 'comment' NOT NULL,
	"content" text NOT NULL,
	"metadata" jsonb,
	"visibility" "salon_visibility" DEFAULT 'all' NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "salon_attachment" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"salon_id" bigint NOT NULL,
	"name" text NOT NULL,
	"file_url" text NOT NULL,
	"file_type" text DEFAULT 'image' NOT NULL,
	"visibility" "salon_visibility" DEFAULT 'all' NOT NULL,
	"uploaded_by_user_id" bigint,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "salon_guest" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"salon_id" bigint NOT NULL,
	"brought_by_user_id" bigint NOT NULL,
	"name" text NOT NULL,
	"phone_encrypted" text NOT NULL,
	"phone_hash" text NOT NULL,
	"relation" text,
	"status" "salon_guest_status" DEFAULT 'pending' NOT NULL,
	"actual_attended" boolean DEFAULT false NOT NULL,
	"notes_encrypted" text,
	"created_by" bigint,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "salon_invitation" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"salon_id" bigint NOT NULL,
	"invitee_user_id" bigint,
	"invitee_name" text NOT NULL,
	"invitee_phone_encrypted" text NOT NULL,
	"invitee_phone_hash" text NOT NULL,
	"role_in_salon" "salon_role" DEFAULT 'attendee' NOT NULL,
	"staff_role" text,
	"invited_by_user_id" bigint,
	"status" "salon_invitation_status" DEFAULT 'pending' NOT NULL,
	"expected_guest_count" integer DEFAULT 0 NOT NULL,
	"actual_guest_count" integer,
	"responded_at" timestamp with time zone,
	"notes_encrypted" text,
	"registration_data" jsonb,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "salon_quota" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"salon_id" bigint NOT NULL,
	"assigned_to_user_id" bigint NOT NULL,
	"quota_value" integer NOT NULL,
	"deadline_at" timestamp with time zone,
	"note" text,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_by_user_id" bigint NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_organizer" ON "salon" USING btree ("organizer_user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_start_at" ON "salon" USING btree ("start_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_status" ON "salon" USING btree ("status");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_deleted_at" ON "salon" USING btree ("deleted_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_activity_salon" ON "salon_activity" USING btree ("salon_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_attachment_salon" ON "salon_attachment" USING btree ("salon_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_guest_salon" ON "salon_guest" USING btree ("salon_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_guest_brought_by" ON "salon_guest" USING btree ("brought_by_user_id");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_salon_guest_salon_phone" ON "salon_guest" USING btree ("salon_id","phone_hash");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_invitation_salon" ON "salon_invitation" USING btree ("salon_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_invitation_invitee" ON "salon_invitation" USING btree ("invitee_user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_invitation_phone_hash" ON "salon_invitation" USING btree ("invitee_phone_hash");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_salon_invitation_salon_phone" ON "salon_invitation" USING btree ("salon_id","invitee_phone_hash");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_quota_salon" ON "salon_quota" USING btree ("salon_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_salon_quota_assigned" ON "salon_quota" USING btree ("assigned_to_user_id");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_salon_quota_active_unique" ON "salon_quota" USING btree ("salon_id","assigned_to_user_id") WHERE is_active = true;