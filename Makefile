# 暖客宝 Makefile
# 主人最常用命令入口, 避免记一堆 npm/pnpm/docker 命令

.PHONY: help dev build start stop logs shell db-migrate db-seed db-studio test test-watch test-run test-e2e lint type-check backup restore clean port-check

help: ## 显示帮助
	@echo "暖客宝 常用命令:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ============ 开发 ============

dev: ## 启动 dev server
	pnpm dev

build: ## 构建生产镜像
	docker compose build web

start: ## 启动生产服务
	docker compose up -d

stop: ## 停止服务
	docker compose down

logs: ## 看日志
	docker compose logs -f

shell: ## 进 web 容器
	docker compose exec web sh

# ============ 数据库 ============

db-migrate: ## 应用 migration
	pnpm db:migrate

db-seed: ## 灌入字典数据
	pnpm db:seed

db-studio: ## 打开 Drizzle Studio
	pnpm db:studio

db-reset: ## ⚠️ 删所有数据 (慎用)
	docker compose down postgres
	docker volume rm bbt-agent_bbt-postgres-data
	docker compose up -d postgres
	pnpm db:migrate
	pnpm db:seed

# ============ 测试 ============

test: ## 跑测试 (watch)
	pnpm test

test-run: ## 跑测试 (一次性)
	DATABASE_URL=postgres://nuankebao:nuankebao_password@localhost:5432/nuankebao_test pnpm test:run

test-e2e: ## 跑 E2E 测试 (需 dev server 跑着)
	pnpm test:e2e

test-all: ## 跑全部测试
	$(MAKE) test-run
	$(MAKE) test-e2e

type-check: ## TypeScript 类型检查
	pnpm type-check

lint: ## ESLint
	pnpm lint

# ============ 运维 ============

backup: ## 手动备份 (需 BACKUP_PASSPHRASE)
	@if [ -z "$$BACKUP_PASSPHRASE" ]; then \
		echo "❌ 需设置 BACKUP_PASSPHRASE 环境变量"; \
		echo "   export BACKUP_PASSPHRASE='你的密码'"; \
		exit 1; \
	fi
	./tools/backup.sh

restore: ## 恢复 (需 BACKUP_PASSPHRASE + 备份文件路径)
	@if [ -z "$$BACKUP_PASSPHRASE" ]; then \
		echo "❌ 需设置 BACKUP_PASSPHRASE 环境变量"; \
		exit 1; \
	fi
	@if [ -z "$(filter-out $@,restore)" ]; then \
		echo "用法: make restore <backup-file>"; \
		exit 1; \
	fi
	./tools/restore.sh $(filter-out $@,restore)

port-check: ## 端口检测
	./tools/check-port.sh $(filter-out $@,port-check)

# ============ 清理 ============

clean: ## 清理 build / cache
	rm -rf .next/ node_modules/.cache/ .turbo/ coverage/
	@echo "✓ 清理完成"

clean-all: ## 深度清理 (含 node_modules)
	$(MAKE) clean
	rm -rf node_modules/
	@echo "✓ 需重新 pnpm install"

# ============ 帮助 ============

.DEFAULT_GOAL := help