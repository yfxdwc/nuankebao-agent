// ============================================
// 养生记录表单 (Plan F2.5)
// 强绑 customerId (来自 query param)
// 结构化字段: 部位 + 服务 + 评分 + 反馈 + 照片 + 下次建议
// 中老年大字 + 大按钮
// ============================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/dictionaries.dart';
import '../../../core/models/follow_up.dart' show FollowUpTask;
import '../../../core/providers/service_providers.dart';
import '../../../core/services/api.dart' show FollowUpService;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_section.dart';

import '../widgets/rating_slider.dart';
import '../widgets/wellness_photo_uploader.dart';

import '../../../core/theme/tokens.g.dart';
/// YYYY-MM-DD (后端 serviceDate / nextAdviceDate 的口径)
String _fmtDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 「下次建议日期」→ 顺手建一条跟进任务 (2026-09-24, 主人问: 「选了下次建议日期,
///   保存后是否应该自动创建跟进任务?」→ 是)
///
/// 为什么: 这个日期是技师/销售**明确指定**的跟进时点, 属于 CHARTER §1.4 的
///   「可落地的跟进指引」。原来它只喂洞察规则 7 (进窗口期才在「现在该做」冒一条,
///   还得手动点「建任务」) —— 窗口期没人打开 App 就漏了; 直接落任务, 「跟进待办」
///   列表 + 每日提醒都能挂住它。
///
/// **幂等**: 该客户已有 pending 任务 → 返回 null 不重复建 (与每日生成脚本
///   `scripts/refresh-follow-up-tasks.ts` 的「一人同时只留一条 pending」同口径)。
/// **失败**: 不在这里吞 —— 调用方负责 (记录已保存 = 主操作成功, 任务建不上
///   不该让保存看起来失败)。
///
/// 到点时刻: 建议日期是"日", 任务要"时间点" → 取当天 09:00 (本地), 跟其它任务一致。
Future<FollowUpTask?> createAdviceFollowUpTaskIfAbsent({
  required FollowUpService followUps,
  required String customerId,
  required DateTime adviceDate,
}) async {
  final pending =
      await followUps.list(customerId: customerId, status: 'pending');
  if (pending.isNotEmpty) return null;
  return followUps.create({
    'customerId': customerId,
    'dueAt': DateTime(adviceDate.year, adviceDate.month, adviceDate.day, 9)
        .toUtc()
        .toIso8601String(),
    'reason': '按建议日期回访',
  });
}

/// 新增记录时默认选中的服务项目 (主人 2026-09-18 拍: 「碧波庭-脉动负压提拉按摩」置顶 + 下拉 + 默认选中)
/// 字典里找不到 → 不预选 (不硬编码假项目), 用户自己选
const String _defaultServiceItemName = '碧波庭-脉动负压提拉按摩';

class WellnessRecordFormPage extends ConsumerStatefulWidget {
  final String? recordId;
  final String? customerId; // 来自 query param (?customerId=X)

  const WellnessRecordFormPage({
    super.key,
    this.recordId,
    this.customerId,
  }) : assert(recordId != null || customerId != null,
            'recordId 或 customerId 必须有一个');

  @override
  ConsumerState<WellnessRecordFormPage> createState() => _WellnessRecordFormPageState();
}

class _WellnessRecordFormPageState extends ConsumerState<WellnessRecordFormPage> {
  // 字典 —— null = 加载中; 非 null (含空字典) = 加载完成
  Dictionaries? _dict;

  // 字典加载失败 (B4, 2026-09-24 修「无限转圈」: 抛异常时进入错误态, 不是死循环)
  Object? _dictError;

  // 选中字段
  final Set<String> _bodyPartIds = {};
  String? _serviceItemId;
  // 睡眠 / 情绪 = 1-10 (2026-09-24 主人拍), 默认 5 (中间值, 不预设好坏);
  //   疼痛 1-10 默认 前 5 / 后 3 (后默认略低是历史约定: 做完通常会轻一点)
  int _prePainLevel = 5;
  int _preSleep = 5;
  int _preMood = 5;
  int _postPainLevel = 3;
  int _postSleep = 5;
  int _postMood = 5;
  final _processCtrl = TextEditingController();
  final _feedbackCtrl = TextEditingController();
  DateTime? _nextAdviceDate;
  List<String> _photoUrls = [];

  /// 记录日期 (2026-09-24 修 + 补):
  ///   · **修 bug**: 原 `_submit` 永远发 `serviceDate = 今天` —— 编辑老记录会把它
  ///     挪到今天 (时间线 / 趋势 / 复购周期全跟着错)。现在编辑载入原日期。
  ///   · **补录**: 记录日期可选 (默认今天, 可往前选), 补昨天的单不再做不到。
  DateTime _serviceDate = DateTime.now();

  /// 有未保存的改动 → 离开时确认 (2026-09-24, 长表单填一半被打断 = 全丢)
  bool _dirty = false;

  /// 草稿: 已恢复过 / 自动暂存计时器 (弱网 / 被电话打断都不丢)
  bool _draftRestored = false;
  Timer? _draftTimer;

  /// 身体部位是否展开 (未选超 8 个时折叠, 2026-09-24)
  bool _partsExpanded = false;

  bool _loading = false;
  String? _effectiveCustomerId;

  /// 新建时是否已按「上一次记录」预填 (P3 提速, 主人 2026-09-23 拍)
  ///
  /// 为什么这是记录提速的最大单点 (预估 ~50s → ~5s):
  ///   连续到店的客户, **上次结束的状态物理上就是这次开始的状态**。
  ///   原先却写死 `_prePainLevel = 5`, 逼销售重新拖 6 次滑块。
  ///   现在直接拿上次的 post* 当前 pre*, 并且 post* 默认 = pre* (="无变化"),
  ///   真的没变化时**一跳直达保存**。
  bool _prefilledFromLast = false;

  /// 预填来源的那次记录日期 (UI 提示用: "按 9月12日那次填好")
  String? _prefilledFromDate;

  @override
  void initState() {
    super.initState();
    _loadDict();
    if (widget.recordId != null) {
      _loadExisting();
    } else {
      _effectiveCustomerId = widget.customerId;
      // 新建 → 先试**未保存草稿** (用户自己填过的优先), 没有草稿再沿用上次
      _initCreateForm();
    }
  }

  Future<void> _loadDict() async {
    try {
      final d = await ref.read(dictionaryServiceProvider).all();
      if (!mounted) return;
      setState(() {
        _dict = d;
        _dictError = null;
        // 新增: 默认选中「碧波庭-脉动负压提拉按摩」
        // 编辑: _loadExisting() 已填好原值 (谁后到谁生效, 两边都不覆盖非空值)
        _serviceItemId ??= _defaultServiceItemIdOf(d);
      });
    } catch (e) {
      if (!mounted) return;
      // 修「无限转圈」: body 用 _dict == null 渲染 LoadingState, 抛异常时
      // _dict 永远是 null → 永远 LoadingState → 永远转圈。必须切到错误态。
      setState(() => _dictError = e);
    }
  }

  /// 找默认服务项目 id: 先精确匹配全名, 再宽松匹配「碧波庭」, 都没有 → null
  String? _defaultServiceItemIdOf(Dictionaries d) {
    for (final s in d.serviceItems) {
      if (s.name.trim() == _defaultServiceItemName) return s.id;
    }
    for (final s in d.serviceItems) {
      if (s.name.contains('碧波庭')) return s.id;
    }
    return null;
  }

  /// 新建时沿用「该客户上一次记录」(P3 提速)
  ///
  /// 口径 (为什么取 post 当这次的 pre):
  ///   上次「做完之后」的身体状态 = 这次「开始之前」的状态。中间没有服务,
  ///   所以这是**物理等价的**, 不是拍脑袋。
  ///
  /// 拿不到上次记录 (首次到店) → 什么都不做, 保留原默认值。
  Future<void> _loadLastRecord() async {
    final cid = _effectiveCustomerId;
    if (cid == null) return;
    try {
      final list = await ref
          .read(wellnessRecordServiceProvider)
          .list(customerId: cid, limit: 1);
      if (!mounted || list.isEmpty) return;
      final last = list.first;
      setState(() {
        // 部位 / 服务: 大概率一样 (同一疗程) —— 但不覆盖用户已手动改过的值
        _bodyPartIds.addAll(last.bodyPartIds);
        _serviceItemId = last.serviceItemId;

        // 本次的「前」= 上次的「后」
        final pPain = (last.postCondition['pain_level'] as num?)?.toInt();
        final pSleep = (last.postCondition['sleep_quality'] as num?)?.toInt();
        final pMood = (last.postCondition['mood'] as num?)?.toInt();
        if (pPain != null) _prePainLevel = pPain;
        if (pSleep != null) _preSleep = pSleep;
        if (pMood != null) _preMood = pMood;

        // 本次的「后」默认 = 「前」→ 改善量为 0 (= "没变化", 中性而非虚报效果)
        _postPainLevel = _prePainLevel;
        _postSleep = _preSleep;
        _postMood = _preMood;

        _prefilledFromLast = true;
        _prefilledFromDate = last.serviceDate;
      });
    } catch (_) {
      // 预填失败不算错 —— 退化成"从默认值开始填", 绝不能让表单打不开
    }
  }

  /// 「清空重填」—— 不想沿用上次时用 (回到出厂默认)
  void _resetToDefaults() {
    _clearDraft();
    setState(() {
      _dirty = false;
      _bodyPartIds.clear();
      _serviceItemId = _dict == null ? null : _defaultServiceItemIdOf(_dict!);
      _prePainLevel = 5;
      _preSleep = 5;
      _preMood = 5;
      _postPainLevel = 3;
      _postSleep = 5;
      _postMood = 5;
      _prefilledFromLast = false;
      _prefilledFromDate = null;
    });
  }

  Future<void> _loadExisting() async {
    final r = await ref.read(wellnessRecordServiceProvider).getById(widget.recordId!);
    if (!mounted) return;
    setState(() {
      _effectiveCustomerId = r.customerId;
      // 修 bug: 编辑必须保留原记录日期 (原来 _submit 一律发今天 → 会把老记录挪到今天)
      _serviceDate = DateTime.tryParse(r.serviceDate) ?? DateTime.now();
      _bodyPartIds.addAll(r.bodyPartIds);
      _serviceItemId = r.serviceItemId;
      _processCtrl.text = r.processNote ?? '';
      _feedbackCtrl.text = r.customerFeedback ?? '';
      _nextAdviceDate = r.nextAdviceDate != null ? DateTime.tryParse(r.nextAdviceDate!) : null;
      _photoUrls.addAll(r.photos);
      // preCondition / postCondition: {pain_level, sleep_quality, mood}
      _prePainLevel = (r.preCondition['pain_level'] as num?)?.toInt() ?? 5;
      _preSleep = (r.preCondition['sleep_quality'] as num?)?.toInt() ?? 5;
      _preMood = (r.preCondition['mood'] as num?)?.toInt() ?? 5;
      _postPainLevel = (r.postCondition['pain_level'] as num?)?.toInt() ?? 3;
      _postSleep = (r.postCondition['sleep_quality'] as num?)?.toInt() ?? 5;
      _postMood = (r.postCondition['mood'] as num?)?.toInt() ?? 5;
    });
  }

  @override
  void dispose() {
    // 离开前落一次草稿 (有未保存改动时; 弱网/被电话打断都不丢内容)
    _draftTimer?.cancel();
    if (_dirty && widget.recordId == null) {
      // fire-and-forget: dispose 不能 await
      _saveDraft();
    }
    _processCtrl.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  /// 「下次建议日期」落任务的执行 + 反馈 (撤销 / 埋点 / 刷列表)。
  ///
  /// 失败静默: 记录已保存 (主操作), 任务没建上不该弹错吓人 —— 但会静默失败,
  ///   所以只在成功时给 SnackBar (含「撤销」, 建错了能一键撤)。
  Future<void> _createAdviceTaskIfNeeded() async {
    final date = _nextAdviceDate;
    final cid = _effectiveCustomerId;
    if (date == null || cid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final task = await createAdviceFollowUpTaskIfAbsent(
        followUps: ref.read(followUpServiceProvider),
        customerId: cid,
        adviceDate: date,
      );
      if (task == null) return; // 已有 pending → 不重复, 也不打扰
      ref.read(usageServiceProvider).track('follow_up_create',
          props: {'source': 'wellness_record_advice'});
      ref.invalidate(customerFollowUpTasksProvider(cid));
      final label =
          '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('已保存 · 顺手建了 $label 的跟进提醒',
            style: const TextStyle(fontSize: AppTheme.fontMd)),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await ref.read(followUpServiceProvider).cancel(task.id);
              ref.invalidate(customerFollowUpTasksProvider(cid));
            } catch (_) {
              // 撤销失败: 让用户去「跟进待办」手动完成/取消, 不弹错
            }
          },
        ),
      ));
    } catch (_) {
      // 静默: 记录保存成功才是主操作
    }
  }

  /// 这一客户在这天是否已经记过 (同日重复录入提醒用)
  Future<bool> _hasRecordOn(DateTime day) async {
    final cid = _effectiveCustomerId;
    if (cid == null) return false;
    try {
      final list = await ref
          .read(wellnessRecordServiceProvider)
          .list(customerId: cid, limit: 20);
      return list.any((r) => r.serviceDate == _fmtDay(day));
    } catch (_) {
      // 查不到就不拦 (宁可少一次提醒, 不能因为查询失败挡住保存)
      return false;
    }
  }

  Future<bool?> _confirmDuplicate(DateTime day) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('这一天已经记过一次'),
          content: Text(
            '${_fmtDay(day)} 已经有一条养生记录了, 再存一条会出现重复。\n'
            '如果确实做了两次, 可以继续保存。',
            style: const TextStyle(fontSize: AppTheme.fontMd, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续保存', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
          ],
        ),
      );

  Future<void> _submit() async {
    if (_serviceItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请选择服务项目',
          style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      return;
    }
    setState(() => _loading = true);

    // 新建: 同一天已有记录 → 先问一句 (2026-09-24, 防重复录入)
    if (widget.recordId == null && await _hasRecordOn(_serviceDate)) {
      if (!mounted) return;
      final go = await _confirmDuplicate(_serviceDate);
      if (go != true) {
        if (mounted) setState(() => _loading = false);
        return;
      }
    }

    final data = <String, dynamic>{
      'customerId': _effectiveCustomerId,
      'serviceDate': _fmtDay(_serviceDate),
      'serviceItemId': _serviceItemId,
      'bodyPartIds': _bodyPartIds.toList(),
      // ⚠ `scale: 10` = 睡眠/情绪的新量程声明 (2026-09-24 起 1-10)。
      //   后端评分按它归一化; **历史记录没有这个键** → 仍按 1-5 解释 (跨度 4),
      //   所以老记录的分数不会被静默改写 (详见 scoring.ts::singleImprovement 注释)。
      'preCondition': {
        'scale': 10,
        'pain_level': _prePainLevel,
        'sleep_quality': _preSleep,
        'mood': _preMood,
      },
      'postCondition': {
        'scale': 10,
        'pain_level': _postPainLevel,
        'sleep_quality': _postSleep,
        'mood': _postMood,
      },
      if (_processCtrl.text.isNotEmpty) 'processNote': _processCtrl.text,
      if (_feedbackCtrl.text.isNotEmpty) 'customerFeedback': _feedbackCtrl.text,
      if (_nextAdviceDate != null)
        'nextAdviceDate': _nextAdviceDate!.toIso8601String().split('T').first,
      'photos': _photoUrls,
    };

    try {
      if (widget.recordId != null) {
        await ref.read(wellnessRecordServiceProvider).update(widget.recordId!, data);
        ref.read(usageServiceProvider).track('record_edit');
      } else {
        await ref.read(wellnessRecordServiceProvider).create(data);
        ref.read(usageServiceProvider).track('record_create');
        // 选了「下次建议日期」→ 顺手落一条跟进任务 (见 helper 注释)
        await _createAdviceTaskIfNeeded();
      }
      if (!mounted) return;
      _dirty = false; // 已保存 → 离开不再确认
      await _clearDraft();
      ref.invalidate(customerWellnessRecordsProvider(_effectiveCustomerId!));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e',
          style: const TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 记录日期区块 (2026-09-24: 补录 + 默认今天)
  Widget _buildServiceDate() {
    final isToday = _sameDay(_serviceDate, DateTime.now());
    return AppSectionHeader(
      title: '记录日期',
      subtitle: '默认今天; 补录以前的单子可以改',
      padding: EdgeInsets.zero,
      action: OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _serviceDate,
            firstDate: DateTime.now().subtract(const Duration(days: 730)),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) {
            setState(() => _serviceDate = picked);
            _markDirty();
          }
        },
        icon: const Icon(Icons.event, size: AppSize.iconSm),
        label: Text(
          isToday ? '今天' : _fmtDay(_serviceDate),
          style: const TextStyle(fontSize: AppTheme.fontSm),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSize.controlLg),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// 标记「有未保存改动」并排一次草稿自动暂存
  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    // 测试环境 / 平台不支持 → 静默关掉草稿 (绝不能因为草稿把表单打不开)
    try {
      // ⚠ 2s 超时: 平台通道不可用 (测试 / 某些 web 场景) 时 getInstance 可能
      //   既不返回也不抛 → 不能让它卡住"沿用上次/草稿恢复"整条初始化链。
      return await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  String get _draftKey =>
      'wellness_draft_${_effectiveCustomerId ?? widget.customerId ?? 'x'}';

  Future<void> _saveDraft() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    try {
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'serviceDate': _fmtDay(_serviceDate),
          'serviceItemId': _serviceItemId,
          'bodyPartIds': _bodyPartIds.toList(),
          'pre': [_prePainLevel, _preSleep, _preMood],
          'post': [_postPainLevel, _postSleep, _postMood],
          'processNote': _processCtrl.text,
          'customerFeedback': _feedbackCtrl.text,
          'nextAdviceDate': _nextAdviceDate == null ? null : _fmtDay(_nextAdviceDate!),
          'photoUrls': _photoUrls,
        }),
      );
    } catch (_) {}
  }

  /// 恢复草稿 (超过 7 天视为陈旧, 直接清掉不恢复)
  Future<bool> _restoreDraft() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return false;
    final raw = prefs.getString(_draftKey);
    if (raw == null) return false;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse('${m['savedAt']}');
      if (savedAt == null ||
          DateTime.now().difference(savedAt).inDays > 7) {
        await prefs.remove(_draftKey);
        return false;
      }
      final pre = (m['pre'] as List?)?.cast<num>() ?? const [];
      final post = (m['post'] as List?)?.cast<num>() ?? const [];
      final advice = m['nextAdviceDate'] == null
          ? null
          : DateTime.tryParse('${m['nextAdviceDate']}');
      final serviceDay = DateTime.tryParse('${m['serviceDate']}');
      setState(() {
        if (serviceDay != null) _serviceDate = serviceDay;
        _serviceItemId = m['serviceItemId'] as String? ?? _serviceItemId;
        _bodyPartIds
          ..clear()
          ..addAll(((m['bodyPartIds'] as List?) ?? const []).cast<String>());
        if (pre.length == 3) {
          _prePainLevel = pre[0].toInt();
          _preSleep = pre[1].toInt();
          _preMood = pre[2].toInt();
        }
        if (post.length == 3) {
          _postPainLevel = post[0].toInt();
          _postSleep = post[1].toInt();
          _postMood = post[2].toInt();
        }
        _processCtrl.text = m['processNote'] as String? ?? '';
        _feedbackCtrl.text = m['customerFeedback'] as String? ?? '';
        _nextAdviceDate = advice;
        _photoUrls = ((m['photoUrls'] as List?) ?? const []).cast<String>();
        _draftRestored = true;
        _dirty = true; // 草稿 = 用户自己填的未保存内容 → 离开仍要确认
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearDraft() async {
    _draftTimer?.cancel();
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    try {
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _initCreateForm() async {
    final restored = await _restoreDraft();
    if (!restored) _loadLastRecord();
  }

  /// 离开确认 (有未保存改动时) —— 草稿已自动暂存, 所以文案是"提醒"而非"要丢了"
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有没保存的内容'),
        content: const Text(
          '已经自动暂存成草稿, 下次进来能接着填。\n要现在离开吗?',
          style: TextStyle(fontSize: AppTheme.fontMd, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续填写', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('离开', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 有未保存改动 → 拦一次, 让用户确认 (填一半被打断不再静默丢)
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.recordId == null ? '添加养生记录' : '编辑养生记录'),
        toolbarHeight: AppSize.appBarHeight,
      ),
      // 保存吸底 (2026-09-24): 表单很长 (含 6 滑块 + 照片条), 不再让用户滑到底才能保存
      bottomNavigationBar: _dict == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s12),
                child: FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(
                          width: AppSize.iconLg,
                          height: AppSize.iconLg,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: AppSize.iconLg),
                  label: Text(widget.recordId == null ? '保存' : '保存修改'),
                  style: FilledButton.styleFrom(
                    minimumSize:
                        const Size(double.infinity, AppSize.buttonLgHeight),
                  ),
                ),
              ),
            ),
      body: _dict == null
          ? (_dictError != null
              // 字典加载失败 → 错误态, 给重试按钮 (原则 8: 必须告诉下一步做什么)
              //   ⚠ 不能用 ErrorState.error 直接显示 —— 那是网络错, 这里可能是后端字典接口挂了,
              //   区分文案让用户知道是「字典没加载」, 不是笼统的「网络问题」。
              ? AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '字典没加载出来',
                  hint: '下拉选不了部位 / 服务, 先重试一下',
                  action: FilledButton.icon(
                    onPressed: _loadDict,
                    icon: const Icon(Icons.refresh, size: AppSize.iconMd),
                    label: const Text('重试'),
                  ),
                )
              : const LoadingState())
          : WellnessPhotoUploaderScope(
              upload: (b64) => ref.read(photoServiceProvider).upload(b64),
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s16),
                children: [
                  // P3 提速: 沿用上次时给一条明确提示
                  //   —— 不提示的话销售不知道已经填好了, 反而会把每个字段重看一遍
                  // 草稿恢复提示 (2026-09-24): 用户自己填到一半的 → 优先于「沿用上次」
                  if (_draftRestored) ...[
                    _PrefillBanner(
                      title: '已恢复上次没保存的内容',
                      subtitle: '接着填就行; 不想用就「清空重填」',
                      date: null,
                      onReset: _resetToDefaults,
                    ),
                    const SizedBox(height: AppSpace.s16),
                  ] else if (_prefilledFromLast && _prefilledFromDate != null) ...[
                    _PrefillBanner(
                      title: '已按 ${_prefilledFromDate!} 那次填好',
                      subtitle: '没变化可直接保存; 有变化只改对应项',
                      date: _prefilledFromDate,
                      onReset: _resetToDefaults,
                    ),
                    const SizedBox(height: AppSpace.s16),
                  ],
                  // 记录日期 (2026-09-24: 补录 + 修编辑改日期的 bug)
                  _buildServiceDate(),
                  const SizedBox(height: AppSpace.s20),
                  _buildServiceSelector(),
                  const SizedBox(height: AppSpace.s20),
                  _buildBodyPartSelector(),
                  const SizedBox(height: AppSpace.s20),
                  _buildConditionCompare(),
                  const SizedBox(height: AppSpace.s20),
                  _buildTextField('操作过程', _processCtrl,
                      hint: '可记录理疗手法、特殊处理等',
                      quickPhrases: const [
                        '动作到位',
                        '力度偏轻',
                        '加了拔罐',
                        '重点做肩颈',
                        '客户中途要求加重',
                      ]),
                  const SizedBox(height: AppSpace.s20),
                  _buildTextField('客户反馈', _feedbackCtrl,
                      hint: '客户说的原话',
                      quickPhrases: const [
                        '说疼痛减轻',
                        '觉得轻松了',
                        '睡眠改善',
                        '想约下次',
                        '说没感觉',
                      ]),
                  const SizedBox(height: AppSpace.s20),
                  _buildDatePicker(),
                  const SizedBox(height: AppSpace.s20),
                  WellnessPhotoUploader(
                    existingUrls: _photoUrls,
                    onChanged: (urls) => setState(() => _photoUrls = urls),
                    onPhotoUploaded: () =>
                        ref.read(usageServiceProvider).track('record_photo_taken'),
                  ),
                  const SizedBox(height: AppSpace.s24),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildBodyPartSelector() {
    // 2026-09-24: **已选置顶** + 未选超 8 个折叠
    //   (部位字典大了以后, 已选的被冲散在列表里要一个个找)
    final selected = _dict!.bodyParts
        .where((p) => _bodyPartIds.contains(p.id))
        .toList();
    final rest =
        _dict!.bodyParts.where((p) => !_bodyPartIds.contains(p.id)).toList();
    final shownRest = _partsExpanded ? rest : rest.take(8).toList();
    final hiddenCount = rest.length - shownRest.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题 + 「已选 N 个」合并成一个区块头 (旧版是标题下面再挂一行小字)
        AppSectionHeader(
          title: '身体部位 (可多选)',
          subtitle: '已选 ${_bodyPartIds.length} 个',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpace.s12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final bp in [...selected, ...shownRest])
              _bodyPartChip(bp),
            if (hiddenCount > 0)
              ActionChip(
                label: Text('还有 $hiddenCount 个',
                    style: const TextStyle(fontSize: AppTheme.fontSm)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _partsExpanded = true),
              ),
            if (_partsExpanded && rest.isNotEmpty)
              ActionChip(
                label: const Text('收起',
                    style: TextStyle(fontSize: AppTheme.fontSm)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _partsExpanded = false),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bodyPartChip(BodyPart bp) {
    final selected = _bodyPartIds.contains(bp.id);
    return FilterChip(
      label: Text(
        bp.name,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          color: selected ? Colors.white : AppTheme.textPrimary,
        ),
      ),
      selected: selected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _bodyPartIds.add(bp.id);
          } else {
            _bodyPartIds.remove(bp.id);
          }
        });
        _markDirty();
      },
      selectedColor: AppTheme.primary,
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s12, vertical: AppSpace.s8),
    );
  }

  Widget _buildServiceSelector() {
    final items = _dict!.serviceItems;
    // 防御: 编辑历史记录时, 若其服务项目已被字典删除 → 显示空 (不崩)
    ServiceItem? selected;
    for (final it in items) {
      if (it.id == _serviceItemId) {
        selected = it;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: '服务项目 (单选) *',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpace.s8),
        // 2026-09-24: DropdownButtonFormField → **底部弹层 + 搜索**
        //   (项目一多, 下拉菜单又长又难找; 弹层还能直接搜)
        InkWell(
          key: const ValueKey('serviceItemField'),
          onTap: _pickServiceItem,
          borderRadius: BorderRadius.circular(AppRadius.r10),
          child: InputDecorator(
            decoration: const InputDecoration(hintText: '请选择服务项目'),
            isEmpty: selected == null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.name ?? '',
                    key: const ValueKey('serviceItemName'),
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down,
                    size: AppSize.iconXl, color: AppTheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickServiceItem() async {
    final items = _dict?.serviceItems ?? const <ServiceItem>[];
    if (items.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _ServicePickerSheet(items: items, current: _serviceItemId),
    );
    if (picked != null && picked != _serviceItemId) {
      setState(() => _serviceItemId = picked);
      _markDirty();
    }
  }

  Widget _buildConditionCompare() {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(
          title: '理疗前 → 后',
          subtitle: '每项前后各一行; 差值自动算',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpace.s8),
        Container(
          // 测试契约 key (对比卡高度断言用: 紧凑一行式 vs 旧两行式)
          key: const ValueKey('conditionCompareCard'),
          padding: const EdgeInsets.all(AppSpace.s16),
          decoration: BoxDecoration(
            color: t.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: t.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ① 疼痛程度 (1-10, 越低越好)
              _MetricCompare(
                name: '疼痛程度',
                delta: _DeltaBadge(
                  pre: _prePainLevel,
                  post: _postPainLevel,
                  lowerIsBetter: true,
                ),
                pre: PainSlider(
                  label: '前',
                  value: _prePainLevel,
                  accent: t.textSecondary,
                  compact: true,
                  onChanged: (v) {
                    setState(() => _prePainLevel = v);
                    _markDirty();
                  },
                ),
                post: PainSlider(
                  label: '后',
                  value: _postPainLevel,
                  compact: true,
                  onChanged: (v) {
                    setState(() => _postPainLevel = v);
                    _markDirty();
                  },
                ),
              ),
              const Divider(height: AppSpace.s16),
              // ② 睡眠质量 (1-5, 越高越好)
              _MetricCompare(
                name: '睡眠质量',
                delta: _DeltaBadge(
                  pre: _preSleep,
                  post: _postSleep,
                  lowerIsBetter: false,
                ),
                pre: TenRatingSlider(
                  label: '前',
                  value: _preSleep,
                  accent: t.textSecondary,
                  compact: true,
                  onChanged: (v) {
                    setState(() => _preSleep = v);
                    _markDirty();
                  },
                ),
                post: TenRatingSlider(
                  label: '后',
                  value: _postSleep,
                  compact: true,
                  onChanged: (v) {
                    setState(() => _postSleep = v);
                    _markDirty();
                  },
                ),
              ),
              const Divider(height: AppSpace.s16),
              // ③ 情绪 (1-5, 越高越好)
              _MetricCompare(
                name: '情绪',
                delta: _DeltaBadge(
                  pre: _preMood,
                  post: _postMood,
                  lowerIsBetter: false,
                ),
                pre: TenRatingSlider(
                  label: '前',
                  value: _preMood,
                  accent: t.textSecondary,
                  compact: true,
                  onChanged: (v) {
                    setState(() => _preMood = v);
                    _markDirty();
                  },
                ),
                post: TenRatingSlider(
                  label: '后',
                  value: _postMood,
                  compact: true,
                  onChanged: (v) {
                    setState(() => _postMood = v);
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 文本区块 = 标题 + 输入框 + **常用短语 chips** (2026-09-24)
  ///
  /// 为什么加短语: 中年用户打字慢, 这两栏是全页最慢的一段 —— 点一下抵打 7-8 个字。
  /// 短语只**追加**不清空 (保留自由输入), 用「 · 」分隔, 点了可继续改。
  Widget _buildTextField(
    String label,
    TextEditingController ctrl, {
    String? hint,
    List<String> quickPhrases = const [],
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(title: label, padding: EdgeInsets.zero),
        const SizedBox(height: AppSpace.s8),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: AppTheme.fontMd),
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => _markDirty(),
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.all(AppSpace.s16),
          ),
        ),
        if (quickPhrases.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s6),
          Wrap(
            spacing: AppSpace.s8,
            runSpacing: AppSpace.s4,
            children: [
              for (final p in quickPhrases)
                _PhraseChip(
                  phrase: p,
                  // 已在文本里 = 已加 (用 contains 而不是分词比较: 手动打字打进去的
                  //   也算已加, 这样"同一句不会被写第二遍"更稳)
                  added: ctrl.text.contains(p),
                  onAdd: () {
                    // ⚠ 二次判定: 用户可能刚把这句话**手打**进文本框, 而 chip 的
                    //   `added` 还是上一次 build 的值 (父级没重建) → 这里再看一眼,
                    //   否则又会重复追加。
                    if (ctrl.text.contains(p)) {
                      setState(() {});
                      return;
                    }
                    final cur = ctrl.text.trim();
                    ctrl.text = cur.isEmpty ? p : '$cur · $p';
                    ctrl.selection =
                        TextSelection.collapsed(offset: ctrl.text.length);
                    _markDirty();
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2026-09-24 主人: 「选择日期按键太大, 可以收到标题 (下次建议日期) 同一行」
        //   → 标题行右侧一个紧凑日期按钮 (44pt), 不再独占一行 48pt 整宽按钮
        AppSectionHeader(
          title: '下次建议日期',
          subtitle: '可选 · 到日子会提醒跟进, 并顺手建一条跟进任务',
          padding: EdgeInsets.zero,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _nextAdviceDate ?? DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _nextAdviceDate = picked);
                _markDirty();
              }
            },
            icon: const Icon(Icons.calendar_today, size: AppSize.iconSm),
            label: Text(
              _nextAdviceDate == null
                  ? '选择'
                  : '${_nextAdviceDate!.year}-${_nextAdviceDate!.month.toString().padLeft(2, '0')}-${_nextAdviceDate!.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: AppTheme.fontSm),
            ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSize.controlLg),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // 清除按钮 (2026-09-24): 选了日期后能置空 (原来只能改不能清)
              if (_nextAdviceDate != null) ...[
                const SizedBox(width: AppSpace.s2),
                IconButton(
                  onPressed: () {
                    setState(() => _nextAdviceDate = null);
                    _markDirty();
                  },
                  icon: const Icon(Icons.close, size: AppSize.iconSm),
                  tooltip: '清除日期',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(AppSpace.s4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        // 快捷档位 (2026-09-24): 实际业务里 80% 是 7/14/30 天后, 比开日期选择器快 3 步
        Wrap(
          spacing: AppSpace.s8,
          runSpacing: AppSpace.s4,
          children: [
            for (final d in const [7, 14, 30])
              ChoiceChip(
                label: Text('$d 天后',
                    style: const TextStyle(fontSize: AppTheme.fontSm)),
                selected: _nextAdviceDate != null &&
                    _sameDay(_nextAdviceDate!,
                        DateTime.now().add(Duration(days: d))),
                onSelected: (_) {
                  setState(() => _nextAdviceDate =
                      DateTime.now().add(Duration(days: d)));
                  _markDirty();
                },
              ),
          ],
        ),
      ],
    );
  }
}
/// 一项指标的「前 → 后」对比块 (指标名 + 差值徽章 + 两个滑块)
class _MetricCompare extends StatelessWidget {
  const _MetricCompare({
    required this.name,
    required this.delta,
    required this.pre,
    required this.post,
  });

  final String name;
  final Widget delta;
  final Widget pre;
  final Widget post;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: AppType.md,
                  fontWeight: AppWeight.semibold,
                  color: t.textPrimary,
                ),
              ),
            ),
            delta,
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        pre,
        const SizedBox(height: AppSpace.s2),
        post,
      ],
    );
  }
}

/// 「前 → 后」差值徽章: `↓5 改善` / `↑2 变差` / `持平`
///
/// 颜色是信号 (ui-principles 原则 5): 改善 = success, 变差 = warning, 持平 = 中性。
/// [lowerIsBetter]: 疼痛 (越低越好) = true; 睡眠 / 情绪 (越高越好) = false。
class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({
    required this.pre,
    required this.post,
    required this.lowerIsBetter,
  });

  final int pre;
  final int post;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final raw = post - pre;
    final improved = raw != 0 && (lowerIsBetter ? raw < 0 : raw > 0);

    final Color bg;
    final Color fg;
    if (raw == 0) {
      bg = t.surfaceSubtle;
      fg = t.textTertiary;
    } else if (improved) {
      bg = t.successSurface;
      fg = t.success;
    } else {
      bg = t.warningSurface;
      fg = t.warning;
    }
    final text = raw == 0
        ? '持平'
        : '${raw < 0 ? '↓' : '↑'}${raw.abs()} ${improved ? '改善' : '变差'}';

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s8, vertical: AppSpace.s2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppType.xs,
          fontWeight: AppWeight.semibold,
          color: fg,
        ),
      ),
    );
  }
}

/// 「已按上次填好」提示条 (P3 记录提速)
///
/// 为什么必须有这条: 自动预填是"静默"的 —— 不提示的话销售不知道已经填好了,
///   反而会把每个字段再检查一遍, 提速效果归零。提示 + 「清空重填」两者缺一不可。
class _PrefillBanner extends StatelessWidget {
  const _PrefillBanner({
    required this.title,
    required this.subtitle,
    required this.onReset,
    this.date,
  });

  /// 主文案 (例: 「已按 2026-09-12 那次填好」/「已恢复上次没保存的内容」)
  final String title;

  /// 副文案
  final String subtitle;

  /// 兼容旧调用方 (有日期时拼进 title; 现在 title 由调用方给全)
  final String? date;

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s12, AppSpace.s10, AppSpace.s8, AppSpace.s10),
      decoration: BoxDecoration(
        color: t.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.primaryLight),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: AppSize.iconMd, color: t.primaryDark),
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppType.sm,
                    fontWeight: AppWeight.semibold,
                    color: t.primaryDark,
                  ),
                ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSize.controlSm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('清空重填'),
          ),
        ],
      ),
    );
  }
}

/// 服务项目选择弹层 (2026-09-24): 搜索框 + 列表
///
/// 为什么从 `DropdownButtonFormField` 换成弹层:
///   下拉菜单高度受限、不能搜索、项目多了要滑很久; 弹层能占 60% 屏高 + 直接搜。
class _ServicePickerSheet extends StatefulWidget {
  const _ServicePickerSheet({required this.items, this.current});

  final List<ServiceItem> items;
  final String? current;

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? widget.items
        : widget.items
            .where((s) => s.name.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.s16, 0, AppSpace.s16, AppSpace.s8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  hintText: '搜索服务项目',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的服务项目',
                        style: TextStyle(
                            fontSize: AppTheme.fontMd,
                            color: t.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final s = list[i];
                        final isCurrent = s.id == widget.current;
                        return ListTile(
                          title: Text(s.name,
                              style: const TextStyle(fontSize: AppTheme.fontMd)),
                          trailing: isCurrent
                              ? Icon(Icons.check, color: t.primary)
                              : null,
                          onTap: () => Navigator.pop(ctx, s.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常用短语 chip (2026-09-24)
///
/// 行为: 点一下 → 追加到文本框; **已在文本里 → 变成「已加」态 (打勾 + 不可点)**。
///   修的问题: 原来连点同一个短语会重复拼 (`动作到位 · 动作到位 · …`)。
class _PhraseChip extends StatelessWidget {
  const _PhraseChip({
    required this.phrase,
    required this.added,
    required this.onAdd,
  });

  final String phrase;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ActionChip(
      avatar: added
          ? Icon(Icons.check, size: AppSize.iconSm, color: t.success)
          : null,
      label: Text(
        phrase,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          color: added ? t.textTertiary : AppTheme.textPrimary,
        ),
      ),
      visualDensity: VisualDensity.compact,
      // 已加 → 不可点 (点了也不会重复写; 要改内容直接在文本框里编辑)
      onPressed: added ? null : onAdd,
    );
  }
}
