DROP INDEX IF EXISTS "idx_knowledge_category";--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_knowledge_category" ON "wellness_knowledge" USING btree ("category");