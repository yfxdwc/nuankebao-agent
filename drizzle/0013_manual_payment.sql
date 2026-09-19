CREATE TABLE IF NOT EXISTS "billing_config" (
	"key" text PRIMARY KEY NOT NULL,
	"value" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"updated_by_user_id" bigint,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "manual_payment_request" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" bigint NOT NULL,
	"plan_code" text DEFAULT 'monthly' NOT NULL,
	"amount_cents" integer NOT NULL,
	"days" integer DEFAULT 30 NOT NULL,
	"payer_note" text,
	"proof_url" text,
	"status" text DEFAULT 'pending' NOT NULL,
	"reviewed_by_user_id" bigint,
	"reviewed_at" timestamp with time zone,
	"reject_reason" text,
	"granted_days" integer,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_manual_pay_user" ON "manual_payment_request" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_manual_pay_status" ON "manual_payment_request" USING btree ("status","created_at");