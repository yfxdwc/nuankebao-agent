ALTER TABLE "customer" ADD COLUMN "last_interaction_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN "last_visit_at" timestamp with time zone;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_last_interaction" ON "customer" USING btree ("last_interaction_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_last_visit" ON "customer" USING btree ("last_visit_at");