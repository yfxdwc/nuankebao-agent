CREATE TABLE IF NOT EXISTS "entitlement_grant" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"days" integer NOT NULL,
	"reason" text NOT NULL,
	"idempotency_key" text NOT NULL,
	"granted_by_user_id" bigint,
	"note" text,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "membership" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"plan_id" bigint,
	"member_until" timestamp with time zone,
	"auto_renew_state" text DEFAULT 'none' NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "plan" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"code" text NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"name" text NOT NULL,
	"price_cents" integer DEFAULT 0 NOT NULL,
	"interval_days" integer DEFAULT 30 NOT NULL,
	"auto_renew" boolean DEFAULT false NOT NULL,
	"features" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"effective_from" timestamp with time zone DEFAULT NOW() NOT NULL,
	"retired_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "referral_code" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"code" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "referral_reward" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"referrer_user_id" bigint NOT NULL,
	"referee_user_id" bigint NOT NULL,
	"code" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"reject_reason" text,
	"referee_phone_hash" text,
	"referee_signup_ip" text,
	"rewarded_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_grant_idempotency" ON "entitlement_grant" USING btree ("idempotency_key");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_grant_user" ON "entitlement_grant" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_membership_user" ON "membership" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_membership_until" ON "membership" USING btree ("member_until");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_plan_code_version" ON "plan" USING btree ("code","version");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_referral_code_user" ON "referral_code" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_referral_code_code" ON "referral_code" USING btree ("code");--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_referral_pair" ON "referral_reward" USING btree ("referrer_user_id","referee_user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_referral_referrer" ON "referral_reward" USING btree ("referrer_user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_referral_status" ON "referral_reward" USING btree ("status");