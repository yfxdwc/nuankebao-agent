# modules/wellness/ — 养生记录模块

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的核心业务模块 — **养生记录**.
> 大健康销售"一键录入"主入口: 客户做完一次养生 → 立即在本模块录入 (部位/状态/用料/效果) → AI 自动生成跟进建议.

## 入口

| 入口 | 文件 | 说明 |
|---|---|---|
| **养生录入表单** | `screens/wellness_record_form_page.dart` | `WellnessRecordFormPage` — 结构化表单 (部位 + 状态 + 用料 + 效果 + 拍照) |
| **养生记录详情** | `screens/wellness_record_detail_page.dart` | `WellnessRecordDetailPage` — 单条记录详情 + 效果追踪 |

## 模块私有 widget

| Widget | 文件 | 用途 |
|---|---|---|
| `RatingSlider` | `widgets/rating_slider.dart` | 效果评分滑块 (1-5 星, 中年女性友好大滑块) |
| `WellnessPhotoUploader` | `widgets/wellness_photo_uploader.dart` | 拍照 + 上传 (base64 → 后端) |

## 依赖 (走 core/ 底座)

- `core/providers/service_providers.dart` — `wellnessApiProvider` (调 `api.dart` 养生域 API)
- `core/models/wellness_record.dart` — `WellnessRecord` freezed model
- `core/models/dictionaries.dart` — `Dictionary` freezed model (部位/状态/用料字典)
- `core/theme/app_theme.dart` — 配色
- `core/widgets/big_button.dart` — 通用大按钮 (其他模块共用)
- `core/widgets/empty_state.dart` — 通用空状态 (其他模块共用)

## 路由

| 路径 | 名称 | 说明 |
|---|---|---|
| `/wellness-records/new?customerId=X` | `wellness-record-new` | 新增 (强绑 customerId, 来自"+"弹窗) |
| `/wellness-records/:id` | `wellness-record-detail` | 详情 |
| `/wellness-records/:id/edit` | `wellness-record-edit` | 编辑 (复用 form page) |

⚠ **强约束**: 养生录入**必须从客户详情"+"进入** (`customerId` query param 必填), 不允许独立入口. `app_router.dart` 里有 error guard.

## 扩展指南

**新增"效果评估"细分维度** (e.g. 短期/中期/长期):
1. 改 `core/models/wellness_record.dart` (加 `shortTermRating` / `midTermRating` / `longTermRating`)
2. 在 `screens/wellness_record_form_page.dart` 的表单加 3 个 `RatingSlider`
3. ⚠ Schema 演进红线 (CHARTER §3.5): 加列必须 `DEFAULT '0'` 或 nullable

**替换"拍照"为视频录制**:
1. 在 `widgets/wellness_photo_uploader.dart` 改用 `image_picker.pickVideo()`
2. 在 `core/services/api.dart` 加 `uploadVideo` API (base64 → 后端, 大文件需 multipart)

## 关联模块

- **modules/customer/** — 养生记录依附于客户 (强绑 customerId)
- **modules/ai/** (待实施) — 录入后 AI 自动生成"下次跟进建议"

## 关联文档

- [CHARTER §4.3 模块化规则](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [CHARTER §3.5 Schema 演进红线](../../../docs/CHARTER.md#35-schema-演进红线-db-migration-必堵) (改 wellness_record 表必看)
- [ADR-0007 §详细方案](../../../docs/adr/0007-modular-architecture.md)
