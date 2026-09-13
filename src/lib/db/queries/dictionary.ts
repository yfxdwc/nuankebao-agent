import { db } from "@/lib/db";
import { bodyPart, serviceItem, product } from "@/lib/db/schema";
import { asc } from "drizzle-orm";

export async function listBodyParts() {
  const rows = await db.select().from(bodyPart).orderBy(asc(bodyPart.id));
  return rows.map((r) => ({ ...r, id: r.id.toString() }));
}

export async function listServiceItems() {
  const rows = await db.select().from(serviceItem).orderBy(asc(serviceItem.id));
  return rows.map((r) => ({ ...r, id: r.id.toString() }));
}

export async function listProducts() {
  const rows = await db.select().from(product).orderBy(asc(product.id));
  return rows.map((r) => ({ ...r, id: r.id.toString() }));
}

export async function listAllDictionaries() {
  const [bp, si, pr] = await Promise.all([
    listBodyParts(),
    listServiceItems(),
    listProducts(),
  ]);
  return {
    bodyParts: bp,
    serviceItems: si,
    products: pr,
  };
}