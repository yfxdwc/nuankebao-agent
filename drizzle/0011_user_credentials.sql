CREATE TABLE IF NOT EXISTS "franchise_placement_confirm" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"request_id" bigint NOT NULL,
	"confirmer_role" text NOT NULL,
	"confirmer_fid" bigint,
	"confirmer_user_id" bigint,
	"decision" text NOT NULL,
	"verified_by" text DEFAULT 'in_app' NOT NULL,
	"decided_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "franchise_placement_request" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"kind" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"initiator_fid" bigint NOT NULL,
	"initiator_user_id" bigint NOT NULL,
	"new_name" text,
	"new_phone_encrypted" text,
	"new_phone_hash" text,
	"new_notes_encrypted" text,
	"move_fid" bigint,
	"target_parent_fid" bigint NOT NULL,
	"target_side" text NOT NULL,
	"result_fid" bigint,
	"backfilled" boolean DEFAULT false NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"executed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "username" text;--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "password_hash" text;--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_placement_confirm_request_role" ON "franchise_placement_confirm" USING btree ("request_id","confirmer_role");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_placement_pending_slot" ON "franchise_placement_request" USING btree ("target_parent_fid","target_side") WHERE status = 'pending';--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_placement_initiator" ON "franchise_placement_request" USING btree ("initiator_fid");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_placement_status" ON "franchise_placement_request" USING btree ("status","expires_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_placement_move_fid" ON "franchise_placement_request" USING btree ("move_fid");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_user_username" ON "user" USING btree ("username");