// ============================================
// AI 洞察共享状态 (P5, 主人 2026-09-23 拍)
//
// 为什么需要它:
//   P5 之前, 客户详情页 AI 区的 3 张卡 (画像 / 话术 / 效果) **各自** 持有一份
//   local state + 各自打一个后端路由 + 各自烧一次 MiniMax。3 张卡互不知情,
//   用户连点 3 下 = 3 次调用, 同一份客户资料被喂 3 遍。
//
//   P5 之后: **一份共享状态** 对应后端 **一次** `/ai/insight` 调用。任何一张卡的
//   「生成」按钮都在打同一次调用, 三张卡同时出内容。
//
// 为什么用 `AsyncNotifierProvider` 而不是 `FutureProvider`:
//   FutureProvider 一旦被 watch 就会**立刻发请求** —— 相当于一进详情页就烧 3 段
//   AI (进页即扣费, 主人肯定不要)。这里 build() 返回 null (未生成), 只有显式
//   `generate()` 才真发请求。
//
// autoDispose: 关掉详情页就释放 (结果不该长期缓存 —— 客户数据随时在变)
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_insight.dart';
import '../providers/service_providers.dart';

/// AI 洞察 family 的 key (customerId)
final aiInsightProvider = AsyncNotifierProvider.autoDispose
    .family<AiInsightNotifier, AiInsightResult?, String>(AiInsightNotifier.new);

class AiInsightNotifier
    extends AutoDisposeFamilyAsyncNotifier<AiInsightResult?, String> {
  /// 跟进理由 (只影响「话术」那段)
  ///
  /// 放在 notifier 上而不是 UI 里: 3 张卡共用一次生成, 理由必须**统一** ——
  /// 在跟进卡里选了「好久没来了」, 再去点画像卡的重新生成, 也该按这个理由。
  String? _reason;

  /// 用户当前选的理由 (UI 回显用)
  String? get reason => _reason;

  @override
  Future<AiInsightResult?> build(String customerId) async {
    // ⚠ 不在这里发请求: 返回 null = "还没生成过"
    return null;
  }

  /// 生成 (或重新生成) 洞察 —— **唯一** 会打 AI 的入口
  Future<void> generate({String? reason, bool regenerate = false}) async {
    if (reason != null && reason.isNotEmpty) _reason = reason;
    this.regenerate = regenerate;

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(aiServiceProvider).insight(arg, reason: _reason),
    );
  }

  /// 上一次 generate 是不是「重新生成」(埋点用)
  bool regenerate = false;
}
