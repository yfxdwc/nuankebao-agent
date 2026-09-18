// ============================================
// 暖客宝 字典数据 seed
// 跑一次: pnpm db:seed
// ============================================

import { db } from "./index";
import { bodyPart, serviceItem, product, wellnessKnowledge } from "./schema";
import { sql } from "drizzle-orm";

async function seedBodyParts() {
  const items = [
    { name: "肩颈", description: "肩膀、颈部区域" },
    { name: "腰部", description: "腰部、腰椎" },
    { name: "膝盖", description: "膝关节" },
    { name: "头部", description: "头部、太阳穴" },
    { name: "背部", description: "后背" },
    { name: "腿部", description: "大小腿" },
    { name: "腹部", description: "腹部、肚脐周围" },
    { name: "足部", description: "脚底、脚踝" },
    { name: "手臂", description: "手臂、手腕" },
  ];

  for (const item of items) {
    await db.insert(bodyPart).values(item).onConflictDoNothing();
  }
  console.log(`✓ body_part: ${items.length} 条`);
}

async function seedServiceItems() {
  const items = [
    {
      // 主人 2026-09-18 拍: 养生记录表单默认项目 (置顶 + 下拉默认选中)
      name: "碧波庭-脉动负压提拉按摩",
      durationMinutes: null,
      defaultPriceCents: null,
      description: "碧波庭 脉动负压提拉按摩",
    },
    {
      name: "肩颈经络理疗",
      durationMinutes: 60,
      defaultPriceCents: 19800,
      description: "肩颈经络疏通, 缓解颈椎疲劳",
    },
    {
      name: "腰部推拿",
      durationMinutes: 60,
      defaultPriceCents: 19800,
      description: "腰部推拿按摩",
    },
    {
      name: "艾灸调理",
      durationMinutes: 90,
      defaultPriceCents: 29800,
      description: "艾灸温通经络, 散寒祛湿",
    },
    {
      name: "拔罐",
      durationMinutes: 30,
      defaultPriceCents: 9800,
      description: "传统拔罐, 祛湿排寒",
    },
    {
      name: "全身推拿",
      durationMinutes: 90,
      defaultPriceCents: 29800,
      description: "全身经络推拿",
    },
    {
      name: "足疗",
      durationMinutes: 45,
      defaultPriceCents: 12800,
      description: "足底反射区按摩",
    },
    {
      name: "刮痧",
      durationMinutes: 45,
      defaultPriceCents: 12800,
      description: "背部刮痧, 排毒祛湿",
    },
    {
      name: "头部按摩",
      durationMinutes: 30,
      defaultPriceCents: 9800,
      description: "头部穴位按摩, 缓解头痛",
    },
  ];

  for (const item of items) {
    await db.insert(serviceItem).values(item).onConflictDoNothing();
  }
  console.log(`✓ service_item: ${items.length} 条`);
}

async function seedProducts() {
  const items = [
    { name: "艾草精油", unit: "ml", description: "温通经络" },
    { name: "生姜精油", unit: "ml", description: "温中散寒" },
    { name: "薰衣草精油", unit: "ml", description: "舒缓放松" },
    { name: "热敷包", unit: "个", description: "中药热敷" },
    { name: "艾条", unit: "根", description: "艾灸用" },
    { name: "拔罐器", unit: "套", description: "玻璃拔罐" },
    { name: "刮痧板", unit: "个", description: "牛角刮痧板" },
    { name: "按摩膏", unit: "g", description: "推拿辅助" },
  ];

  for (const item of items) {
    await db.insert(product).values(item).onConflictDoNothing();
  }
  console.log(`✓ product: ${items.length} 条`);
}

async function seedWellnessKnowledge() {
  const items = [
    {
      title: "肩颈经络理疗 - 标准手法",
      content:
        "肩颈理疗主要针对斜方肌、肩胛提肌、头颈夹肌。手法包括: 1) 颈部揉按 3-5 分钟, 从风池穴到肩井穴; 2) 肩部提拿 5 分钟, 缓解斜方肌紧张; 3) 点穴 (风池 / 肩井 / 天宗) 各 1 分钟; 4) 颈肩部温热敷 10 分钟促进血液循环。",
      category: "physiotherapy" as const,
      tags: ["肩颈", "经络", "理疗"],
    },
    {
      title: "艾灸调理 - 温通经络",
      content:
        "艾灸适用于虚寒体质, 常见穴位: 1) 足三里 - 调理脾胃; 2) 关元 - 温补肾阳; 3) 气海 - 益气健脾。每次 15-20 分钟, 每周 2-3 次。禁忌: 实热证 / 阴虚火旺 / 孕妇腹部。",
      category: "physiotherapy" as const,
      tags: ["艾灸", "温阳", "调理"],
    },
    {
      title: "复购提醒话术模板",
      content:
        "对 30-45 天未到店的客户: '张姐, 上次做完肩颈之后您说睡眠改善挺明显的, 这段时间肩颈有没有又开始紧? 这次我们有个新项目...'. 避免直接推销, 先关心效果, 再切入项目推荐, 最后引导预约体验。",
      category: "customer_care" as const,
      tags: ["话术", "复购", "跟进"],
    },
    {
      title: "睡眠质量改善建议",
      content:
        "客户反馈睡眠差时, 建议: 1) 睡前 1 小时避免手机蓝光; 2) 颈椎问题常导致睡眠问题, 建议先做颈椎调理; 3) 配合艾灸调理睡眠 (足三里 + 内关); 4) 建议套餐: 5 次肩颈 + 3 次艾灸, 跨度 1 个月。",
      category: "wellness_tip" as const,
      tags: ["睡眠", "建议", "套餐"],
    },
    {
      title: "艾草精油使用指南",
      content:
        "艾草精油 5ml 用法: 1) 肩颈按摩时 3-5 滴, 加 10ml 基础油稀释; 2) 温热敷前涂抹; 3) 失眠可滴 1 滴在枕头; 禁忌: 孕妇 / 皮肤破损 / 过敏体质。",
      category: "product_guide" as const,
      tags: ["艾草精油", "用法", "禁忌"],
    },
    {
      title: "拔罐 - 祛湿排寒",
      content:
        "拔罐适合湿气重 / 肩颈僵硬 / 受寒。常用穴位: 大椎 / 肩井 / 背部膀胱经。留罐 10-15 分钟, 颜色判断: 紫色 = 寒湿, 红色 = 热, 粉色 = 正常。禁忌: 心脏病 / 孕妇 / 出血倾向。",
      category: "physiotherapy" as const,
      tags: ["拔罐", "祛湿", "寒"],
    },
    {
      title: "季节养生 - 秋季润燥",
      content:
        "秋季 (9-11 月) 干燥, 客户易出现: 1) 皮肤干; 2) 嗓子干; 3) 大便干。建议: 1) 多吃白色食物 (梨 / 银耳 / 百合); 2) 加做艾灸关元 / 足三里; 3) 配合精油按摩; 4) 推套餐: 5 次肩颈 + 5 次艾灸, 适合秋季调养。",
      category: "seasonal" as const,
      tags: ["秋季", "润燥", "季节"],
    },
    {
      title: "客户异议处理 - 价格",
      content:
        "客户说 '太贵了' 时: 1) 不直接降价, 先理解客户真实需求 ('您是觉得整体价格高, 还是想了解更细的?'). 2) 算日均: '一周 1 次, 一次 ¥200, 一天 ¥30, 比外卖还便宜'. 3) 推套餐: '买 5 次送 1 次, 平均每次省 ¥40'. 4) 给台阶: '您先体验一次, 觉得效果好再决定'. 不要在客户第一次拒绝时就推销。",
      category: "customer_care" as const,
      tags: ["异议", "价格", "推销"],
    },
    {
      title: "足疗 - 引火归元",
      content:
        "足疗适合: 1) 失眠多梦; 2) 腰膝酸软; 3) 上热下寒。重点穴位: 涌泉 (引火归元)、太溪 (补肾)、三阴交 (调三阴)。每次 40-60 分钟, 加 5ml 生姜精油。禁忌: 脚部皮肤破损 / 严重静脉曲张。",
      category: "physiotherapy" as const,
      tags: ["足疗", "涌泉", "失眠"],
    },
    {
      title: "初次到店客户接待",
      content:
        "新客户接待 6 步: 1) 微笑迎接, 倒温水; 2) 询问主诉 ('今天哪里不舒服?'). 3) 简单健康问卷 (既往病史 / 过敏). 4) 建议体验项目 (不强行推销). 5) 做完问感受. 6) 离店前: '您下周可以做 X 项目巩固效果'. 加微信发图, 24h 内回访. 复购率提升 30%。",
      category: "customer_care" as const,
      tags: ["新客", "接待", "流程"],
    },
  ];

  // 用 SQL 避免重复
  for (const item of items) {
    const exists = await db.execute(sql`
      SELECT 1 FROM wellness_knowledge WHERE title = ${item.title} LIMIT 1
    `);
    if ((exists as unknown as Array<unknown>).length === 0) {
      await db.insert(wellnessKnowledge).values(item);
    }
  }
  console.log(`✓ wellness_knowledge: ${items.length} 条`);
}

async function main() {
  console.log("=========================================");
  console.log(" 暖客宝 字典数据 seed");
  console.log("=========================================");
  console.log("");

  try {
    await seedBodyParts();
    await seedServiceItems();
    await seedProducts();
    await seedWellnessKnowledge();
    console.log("");
    console.log("✓ 全部字典数据 seed 完成");
  } catch (error) {
    console.error("✗ seed 失败:", error);
    process.exit(1);
  } finally {
    process.exit(0);
  }
}

main();