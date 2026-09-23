/**
 * Auto Task Snapshot Extension (W8 治本, vibe coding 优化)
 *
 * 一个 hook, 让你不需要手动打快照:
 *
 * turn_start (session 第一条 user 消息触发)
 *   - 自动打任务快照 (`bash scripts/task-snapshot.sh start <name>`)
 *   - 你不需要: 手动跑 `bash scripts/task-snapshot.sh start <name>`
 *               用 `/new-task <name> <描述>` prompt
 *               指望 agent 自觉读 AGENTS.md §8
 *
 * 失败: 静默 + console.error, 不打扰用户, 不阻塞 pi
 *
 * ⚠⚠ 2026-09-23 主人拍板: **去掉 `agent_end` 自动 commit**
 *
 *   原来第二个 hook 会在 agent 说完话时把**整棵工作树** `git add -A` + commit
 *   (`wip(snapshot): <agent 最后一句话>`)。实测危害远大于收益:
 *
 *   ① **反复污染 history**. 本仓 agent 收尾时会自己提交语义化 commit, 但 hook 往往
 *      先抢一步 —— 于是同一个任务被拆成 `[SNAPSHOT] task-start: ...` / `wip(snapshot): ...`
 *      加上 agent 自己的 feat commit。实测一个任务最多清出 5 个垃圾 commit,
 *      每次都要 `git reset --soft` 重排。
 *   ② **会把别的 session 的在制品扫进自己的 commit** (最危险). 本仓经常多个 pi/codex
 *      session 同时在同一工作目录干活, 而 `git add -A` 不区分是谁改的 ——
 *      实测已经发生过: 把另一 session 的 `/admin/plan` 未提交改动扫进"记录页完善"的
 *      commit, 且 message 与内容完全无关 (考古灾难)。
 *   ③ **commit message 本身就是错的来源**. 用"agent 最后一句话"当标题, 出现过
 *      `[pi] 下面给你一份「大健康养生行业客户评分维度池」...` 这种把回复正文当
 *      commit 标题的荒唐结果。
 *
 *   **为什么可以直接去掉而不丢东西**: hook 想解决的问题 ("agent 改错了想回滚") 已由
 *   `turn_start` 覆盖 —— 它打的是 **git tag + dirty diff dump**
 *   (`.git/snapshots/<tag>.diff`, 见 scripts/task-snapshot.sh),
 *   不需要 commit 也能把"任务开始前的状态"完整存下来并回滚。
 *   中间态存盘的价值远小于"history 干净 + 不会误提交别人的东西"。
 *
 *   ➡ agent / 主人收尾时**自己**提交语义化 commit (feat/fix/refactor) —— 这是唯一提交来源。
 *
 * 见 AGENTS.md §8.1.3, docs/dev-modules/task-snapshot.md, scripts/task-snapshot.sh.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RECENT_SNAPSHOT_THRESHOLD_SEC = 5 * 60; // 5 分钟内不打第二次 snapshot

interface SessionMessageEntry {
	type: string;
	message?: {
		role: "user" | "assistant" | "system" | "tool";
		content?: string | Array<{ type: string; text?: string }>;
	};
}

/** 从 entries 找指定 role 的最后一条非空文本行 (跳过 markdown fence / 空行 / 列表标记) */
function extractFirstTextLine(entries: SessionMessageEntry[], role: "user" | "assistant"): string {
	for (let i = entries.length - 1; i >= 0; i--) {
		const e = entries[i];
		if (e.type !== "message" || e.message?.role !== role) continue;
		const content = e.message.content;
		let text = "";
		if (typeof content === "string") {
			text = content;
		} else if (Array.isArray(content)) {
			// 只接 type === "text" 的块 (跳过 type === "thinking" 等)
			const t = content.find((c) => c.type === "text");
			if (t?.text) text = t.text;
		}
		if (!text) continue;
		// 去除 <think>...</think> 思维块 (如果作为嵌入文本出现)
		const cleaned = text.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
		if (!cleaned) continue;
		// 第一条非空行 (跳过 markdown fence / 列表标记)
		const line = cleaned
			.split("\n")
			.map((l) => l.trim())
			.find((l) => l.length > 0 && !l.startsWith("```"));
		if (line) return line;
	}
	return "";
}

function deriveTaskName(entries: SessionMessageEntry[]): string {
	const ts = new Date().toISOString().replace(/[-:T.Z]/g, "").slice(0, 14); // YYYYMMDDHHMMSS
	const firstLine = extractFirstTextLine(entries, "user");
	if (firstLine) {
		const slug = firstLine
			.slice(0, 40)
			.toLowerCase()
			.replace(/[^a-z0-9._-]+/g, "-")
			.replace(/^-+|-+$/g, "");
		if (slug) return `auto-${slug}`;
	}
	return `auto-${ts}`;
}

export default function (pi: ExtensionAPI) {
	// ============== Hook 1: turn_start = 自动打 task snapshot ==============
	pi.on("turn_start", async (_event, ctx) => {
		try {
			// 只在 session 第一条 turn 触发
			const entries = ctx.sessionManager.getEntries() as SessionMessageEntry[];
			const userMsgCount = entries.filter(
				(e) => e.type === "message" && e.message?.role === "user",
			).length;
			if (userMsgCount > 1) return;

			// 检查 git 仓库
			const { code: gitCheck } = await pi.exec("git", ["rev-parse", "--git-dir"]);
			if (gitCheck !== 0) {
				// 不在 git 仓库 — 治本修 (2026-09-11 P3 静默失败):
				// 之前 silently return, 用户不知道为何 auto-snapshot 不工作.
				// 现在 console.error 让 pi log 可查, UI notify 让用户能看到.
				const cwd = process.cwd();
				console.error(
					`[auto-task-snapshot] not in a git repo (cwd=${cwd}); auto-snapshot disabled. ` +
					`Run \`git init\` + install hooks (bash scripts/install-git-hooks.sh) to enable. ` +
					`See AGENTS.md §9.`,
				);
				if (ctx.hasUI) {
					ctx.ui.notify(
						`⚠️ Auto-snapshot disabled: not in a git repo. Run \`git init\` + \`bash scripts/install-git-hooks.sh\`.`,
						"warning",
					);
				}
				return;
			}

			// 解析脚本路径 (相对 project root)
			const { stdout: gitRoot, code: rootCode } = await pi.exec("git", [
				"rev-parse",
				"--show-toplevel",
			]);
			if (rootCode !== 0 || !gitRoot.trim()) {
				// git rev-parse --show-toplevel 失败 — 罕见但可能 (corrupt repo / permission)
				console.error(
					`[auto-task-snapshot] git rev-parse --show-toplevel failed ` +
					`(code=${rootCode}); auto-snapshot disabled. See AGENTS.md §9.`,
				);
				if (ctx.hasUI) {
					ctx.ui.notify(
						`⚠️ Auto-snapshot disabled: git root detection failed (code=${rootCode}).`,
						"warning",
					);
				}
				return;
			}
			const scriptPath = `${gitRoot.trim()}/scripts/task-snapshot.sh`;
			// vcm-paused 2026-XX-XX: 外部 vcm 仓库暂停维护, 不再调 vcm snapshot。
			// 历史代码保留以便恢复时快速 diff 还原 (v0.21.0+ vcm snapshot 接口)。
			// const vcmCmd = `PATH="$PATH:${gitRoot.trim().replace(/\/sales-ai$/, '/vibe-coding-mgr/bin')}" command -v vcm`;

			// 5 分钟内打过则跳过
			const { stdout: tags } = await pi.exec("git", [
				"tag",
				"-l",
				"pre-auto-*",
				"--sort=-creatordate",
				"--format=%(creatordate:unix)",
			]);
			const now = Math.floor(Date.now() / 1000);
			if (tags.trim()) {
				const last = parseInt(tags.trim().split("\n")[0], 10);
				if (last && now - last < RECENT_SNAPSHOT_THRESHOLD_SEC) return;
			}

			// 派生 task name 并打 snapshot
			// vcm-paused 2026-XX-XX: 原 ADR-0038 Phase C 走 vcm snapshot, 现已统一走本地 task-snapshot.sh。
			// 历史 vcm 分支保留注释, 恢复时取消注释 + 删本地分支即可。
			const taskName = deriveTaskName(entries);
			let code: number;
			try {
				// vcm-paused: 直接走本地 task-snapshot.sh
				const r = await pi.exec(scriptPath, ["start", taskName]);
				code = r.code;

				// 历史 vcm snapshot 分支 (v0.21.0+), vcm-paused 后不再走:
				// const vcmCheck = await pi.exec("command", ["-v", "vcm"]);
				// if (vcmCheck.code === 0) {
				// 	const r = await pi.exec("vcm", ["snapshot", "start", taskName]);
				// 	code = r.code;
				// } else {
				// 	throw new Error("vcm not found");
				// }
			} catch {
				const r = await pi.exec(scriptPath, ["start", taskName]);
				code = r.code;
			}

			if (code === 0) {
				if (ctx.hasUI) ctx.ui.notify(`🔖 Auto-snapshot: ${taskName}`, "info");
			} else {
				console.error(`[auto-task-snapshot] snapshot failed: ${taskName}`);
			}
		} catch (err) {
			console.error(`[auto-task-snapshot] error:`, err);
		}
	});
}
