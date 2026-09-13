# _deprecated/

**保留目的**：Plan F2 (2026-09-XX 实施) 重构 Flutter 信息架构，删 11 个旧 screen + service + widget，但留 1 周观察期以便主人真机验收后回滚。

**保留截止**：2026-09-XX (1 周后主人 review 真机后真删)

## 文件清单

### screens/
- `ai/ai_assistant_screen.dart` — AI 助手独立 tab (Plan F2 删除)
- `customers/customer_detail_screen.dart` — 旧详情页 (Plan F2 customers_page.dart 内置)
- `customers/customer_form_screen.dart` — 旧表单 (Plan F2 customers_page.dart 内置)
- `customers/customers_list_screen.dart` — 旧列表 (Plan F2 customers_page.dart 内置)
- `dashboard/dashboard_screen.dart` — 仪表盘 (CHARTER §1 反 vibe, 删除)
- `follow_ups/follow_ups_screen.dart` — 全局跟进列表 (改: 跟进入详情页时间线)
- `interactions/interactions_screen.dart` — 全局联系列表 (改: 联系入详情时间线)
- `reports/reports_screen.dart` — 报表 (中老年不看, 删除)
- `wellness/wellness_records_list_screen.dart` — 全局养生列表 (改: 养生入详情时间线)
- `wellness/wellness_record_detail_screen.dart` — 旧详情 (Plan F3 重新实现)
- `wellness/wellness_record_form_screen.dart` — 旧表单 (Plan F2.5 重新实现)

### services/
- `auth_service.dart` → 已合并到 `services/api.dart`
- `customer_service.dart` → 已合并到 `services/api.dart`
- `wellness_record_service.dart` → 已合并到 `services/api.dart`
- `photo_service.dart` → 已合并到 `services/api.dart`
- `misc_service.dart` (含 DictionaryService / FollowUpService / InteractionService / DashboardService) → 已合并到 `services/api.dart`
- `prediction_service.dart` → 已合并到 `services/api.dart`

### widgets/
- `photo_picker.dart` — 拍照组件 (Plan F2.5 重新实现)
- `prediction_widgets.dart` — 复购预测/效果分析卡片 (AI 功能下放到详情页)
- `stat_card.dart` — Dashboard 统计卡片 (Dashboard 删除)

## 回滚

如需回滚（主人真机验收发现 Plan F2 不可用）：

```bash
# 1. 恢复 _deprecated/ 内容到 lib/
mv flutter_app/lib/_deprecated/screens/* flutter_app/lib/screens/
mv flutter_app/lib/_deprecated/services/* flutter_app/lib/services/
mv flutter_app/lib/_deprecated/widgets/* flutter_app/lib/widgets/

# 2. 还原 router (git restore)
git restore flutter_app/lib/router/app_router.dart

# 3. 还原 providers (git restore)
git restore flutter_app/lib/providers/service_providers.dart

# 4. 重 build
cd flutter_app && flutter build apk
```

## 真删

1 周后主人 review 通过，用：

```bash
rm -rf flutter_app/lib/_deprecated
git add -u flutter_app/lib/
git commit -m "cleanup(flutter): 真删 Plan F2 旧 screen/service/widget (1 周观察期满)"
```