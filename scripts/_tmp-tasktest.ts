import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
(async () => {
  const h = hashForLookup("13900008801");
  await db.delete(customer).where(eq(customer.phoneHash, h));
  const old = new Date(Date.now() - 70 * 86_400_000);
  const veryOld = new Date(Date.now() - 120 * 86_400_000);
  const [c] = await db.insert(customer).values({
    name: "冒烟-该联系了",
    phoneEncrypted: encryptField("13900008801"),
    phoneHash: h,
    createdBy: BigInt(1),
    lastInteractionAt: old,
    lastVisitAt: veryOld,
  }).returning({ id: customer.id });
  console.log("临时客户 id:", c.id.toString(), "(70 天没联系 / 120 天没到店)");
  process.exit(0);
})();
