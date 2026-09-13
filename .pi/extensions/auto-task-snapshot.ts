/**
 * Auto Task Snapshot + Auto Commit Extension (W8 治本, vibe coding 优化)
 *
 * 两个 hook 协作, 让你完全不需管 git:
 *
 * 1. turn_start (session 第一条 user 消息触发)
 *    - 自动打任务快照 (`git add -A && git commit --allow-empty -m "[SNAPSHOT]..."`)
 *    - 你不需要: 手动 `bash scripts/task-snapshot.sh start <name>`
 *               用 `/new-task <name> <描述>` prompt
 *               指望 agent 自觉读 AGENTS.md §7
 *
 * 2. agent_end (agent 说完话触发, 适配 vibe coding)
 *    - 自动 commit working tree 改动 (`git add -A && git commit -m "[pi] ..."`)
 *    - commit message 用 agent 最后一句话的前 50 字符
 *    - 你不需要: 手动 `git add` + `git commit`, cron 凑时间, 编辑器 auto-commit
 *
 * 失败: 两个 hook 都静默 + console.error, 不打扰用户, 不阻塞 pi
 *
 * 见 AGENTS.md §7, scripts/task-snapshot.sh.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RECENT_SNAPSHOT_THRESHOLD_SEC = 5 * 60; // 5 分钟内不打第二次 snapshot
const COMMIT_MSG_MAX_LEN = 50; // commit message 最大长度

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

function deriveCommitMsg(entries: SessionMessageEntry[]): string {
	const firstLine = extractFirstTextLine(entries, "assistant");
	if (firstLine) {
		return firstLine.length > COMMIT_MSG_MAX_LEN
			? firstLine.slice(0, COMMIT_MSG_MAX_LEN - 3) + "..."
			: firstLine;
	}
	return "wip";
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

	// ============== Hook 2: agent_end = 自动 commit (vibe coding 优化) ==============
	pi.on("agent_end", async (_event, ctx) => {
		try {
			// 1) 检查 working tree 是否有改动
			const { stdout: status, code: statusCode } = await pi.exec(
				"git",
				["status", "--porcelain"],
			);
			if (statusCode !== 0) return;
			if (!status.trim()) return; // 无改动, 跳过

			// 2) 拿 agent 最后一句话作 commit message
			const entries = ctx.sessionManager.getEntries() as SessionMessageEntry[];
			const msg = deriveCommitMsg(entries);

			// 3) commit (--no-verify 跳过 pre-commit hook 检查, vibe coding 下不卡)
			await pi.exec("git", ["add", "-A"]);
			const { code: commitCode, stderr } = await pi.exec("git", [
				"commit",
				"-m",
				`[pi] ${msg}`,
				"--no-verify",
			]);

			if (commitCode === 0) {
				if (ctx.hasUI) ctx.ui.notify(`✓ Auto-commit: ${msg}`, "info");
			} else {
				console.error(`[auto-commit] commit failed:`, stderr);
			}
		} catch (err) {
			console.error(`[auto-commit] error:`, err);
		}
	});
}
