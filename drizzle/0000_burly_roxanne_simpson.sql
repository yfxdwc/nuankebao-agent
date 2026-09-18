CREATE TYPE "public"."gender" AS ENUM('M', 'F', 'U');--> statement-breakpoint
CREATE TYPE "public"."interaction_type" AS ENUM('phone', 'wechat', 'visit', 'holiday_greeting', 'other');--> statement-breakpoint
CREATE TYPE "public"."task_status" AS ENUM('pending', 'done', 'cancelled');--> statement-breakpoint
CREATE TYPE "public"."user_role" AS ENUM('admin', 'manager', 'sales');--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "audit_log" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"table_name" text NOT NULL,
	"record_id" bigserial NOT NULL,
	"operation" text NOT NULL,
	"user_id" bigserial,
	"changed_fields" jsonb,
	"ip_address" "inet",
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "body_part" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"description" text,
	CONSTRAINT "body_part_name_unique" UNIQUE("name")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "customer" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"gender" "gender",
	"birth_year" integer,
	"phone_encrypted" text NOT NULL,
	"phone_hash" text NOT NULL,
	"health_tags_encrypted" text,
	"disease_history_encrypted" text,
	"notes_encrypted" text,
	"created_by" bigserial NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "follow_up_task" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"customer_id" bigserial NOT NULL,
	"due_at" timestamp with time zone NOT NULL,
	"reason" text NOT NULL,
	"ai_suggestion_encrypted" text,
	"status" "task_status" DEFAULT 'pending' NOT NULL,
	"completed_at" timestamp with time zone,
	"completed_notes_encrypted" text,
	"assigned_to" bigserial,
	"created_by" bigserial,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "interaction" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"customer_id" bigserial NOT NULL,
	"type" "interaction_type" NOT NULL,
	"summary_encrypted" text,
	"follow_up_at" timestamp with time zone,
	"created_by" bigserial NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "product" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"unit" text,
	"description" text,
	CONSTRAINT "product_name_unique" UNIQUE("name")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "service_item" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"duration_minutes" integer,
	"default_price_cents" integer,
	"description" text,
	CONSTRAINT "service_item_name_unique" UNIQUE("name")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "staff" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" bigserial,
	"display_name" text NOT NULL,
	"store_id" bigserial,
	"specialties" jsonb DEFAULT '[]'::jsonb,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "store" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"address" text,
	"phone_encrypted" text,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "user" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"phone_encrypted" text NOT NULL,
	"phone_hash" text NOT NULL,
	"role" "user_role" DEFAULT 'sales' NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "wellness_record" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"customer_id" bigserial NOT NULL,
	"service_date" date NOT NULL,
	"store_id" bigserial,
	"staff_id" bigserial,
	"service_item_id" bigserial NOT NULL,
	"pre_condition_encrypted" text NOT NULL,
	"post_condition_encrypted" text NOT NULL,
	"process_note_encrypted" text,
	"customer_feedback_encrypted" text,
	"photos" jsonb DEFAULT '[]'::jsonb,
	"next_advice_date" date,
	"created_by" bigserial NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "wellness_record_body_part" (
	"wellness_record_id" bigserial NOT NULL,
	"body_part_id" bigserial NOT NULL,
	CONSTRAINT "wellness_record_body_part_wellness_record_id_body_part_id_pk" PRIMARY KEY("wellness_record_id","body_part_id")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "wellness_record_product" (
	"wellness_record_id" bigserial NOT NULL,
	"product_id" bigserial NOT NULL,
	"quantity" numeric(10, 2),
	CONSTRAINT "wellness_record_product_wellness_record_id_product_id_pk" PRIMARY KEY("wellness_record_id","product_id")
);
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "audit_log" ADD CONSTRAINT "audit_log_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "customer" ADD CONSTRAINT "customer_created_by_user_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "follow_up_task" ADD CONSTRAINT "follow_up_task_customer_id_customer_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customer"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "follow_up_task" ADD CONSTRAINT "follow_up_task_assigned_to_user_id_fk" FOREIGN KEY ("assigned_to") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "follow_up_task" ADD CONSTRAINT "follow_up_task_created_by_user_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "interaction" ADD CONSTRAINT "interaction_customer_id_customer_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customer"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "interaction" ADD CONSTRAINT "interaction_created_by_user_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "staff" ADD CONSTRAINT "staff_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "staff" ADD CONSTRAINT "staff_store_id_store_id_fk" FOREIGN KEY ("store_id") REFERENCES "public"."store"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record" ADD CONSTRAINT "wellness_record_customer_id_customer_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customer"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record" ADD CONSTRAINT "wellness_record_store_id_store_id_fk" FOREIGN KEY ("store_id") REFERENCES "public"."store"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record" ADD CONSTRAINT "wellness_record_staff_id_staff_id_fk" FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record" ADD CONSTRAINT "wellness_record_service_item_id_service_item_id_fk" FOREIGN KEY ("service_item_id") REFERENCES "public"."service_item"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record" ADD CONSTRAINT "wellness_record_created_by_user_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record_body_part" ADD CONSTRAINT "wellness_record_body_part_wellness_record_id_wellness_record_id_fk" FOREIGN KEY ("wellness_record_id") REFERENCES "public"."wellness_record"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record_body_part" ADD CONSTRAINT "wellness_record_body_part_body_part_id_body_part_id_fk" FOREIGN KEY ("body_part_id") REFERENCES "public"."body_part"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record_product" ADD CONSTRAINT "wellness_record_product_wellness_record_id_wellness_record_id_fk" FOREIGN KEY ("wellness_record_id") REFERENCES "public"."wellness_record"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "wellness_record_product" ADD CONSTRAINT "wellness_record_product_product_id_product_id_fk" FOREIGN KEY ("product_id") REFERENCES "public"."product"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_audit_table_record" ON "audit_log" USING btree ("table_name","record_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_audit_user" ON "audit_log" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_customer_phone_hash" ON "customer" USING btree ("phone_hash");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_deleted_at" ON "customer" USING btree ("deleted_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_followup_due" ON "follow_up_task" USING btree ("due_at") WHERE status = 'pending';--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_followup_assigned" ON "follow_up_task" USING btree ("assigned_to","status");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_interaction_customer" ON "interaction" USING btree ("customer_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_user_phone_hash" ON "user" USING btree ("phone_hash");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_wellness_customer" ON "wellness_record" USING btree ("customer_id","service_date" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_wellness_service_date" ON "wellness_record" USING btree ("service_date");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_wellness_staff" ON "wellness_record" USING btree ("staff_id","service_date");