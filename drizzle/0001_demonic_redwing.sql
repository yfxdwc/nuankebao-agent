CREATE TYPE "public"."knowledge_category" AS ENUM('physiotherapy', 'wellness_tip', 'product_guide', 'customer_care', 'seasonal');--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "wellness_knowledge" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"content" text NOT NULL,
	"category" "knowledge_category" NOT NULL,
	"tags" jsonb DEFAULT '[]'::jsonb,
	"created_by" bigint,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_knowledge_category" ON "wellness_knowledge" USING btree ("category");