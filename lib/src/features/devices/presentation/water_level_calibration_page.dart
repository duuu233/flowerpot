import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../models/water_level_calibration_model.dart';

/// 水位校准向导（`docs/app_DP_问题修正说明.md` §5）。
///
/// - 入口页点「开始校准」发 DP140 = 0（设备进校准页提示倒空，不采样），等 `calib:begin:ok`；
/// - 1/4 ~ 3/4 用户做完动作再点按钮，依次发 1 / 2 / 3 采样；2/4、3/4 与上一次采样至少隔 5 秒，
///   按钮置灰倒计时；
/// - 4/4 发 4 计算并保存，`calib:step4` 的结果决定成功 / 失败页；
/// - 被拒时重发本步即可，不回第 1 页；保存失败才从头来；
/// - 退出入口：页头 ←、底部「取消校准」、Android 返回键 / 手势，都走同一个确认框，确认后发 5
///   并等 `calib:step5:ok`；
/// - 单步 3 分钟没动作设备看门狗会自动取消，这边同步提示并回到入口页。
class WaterLevelCalibrationPage extends StatefulWidget {
  const WaterLevelCalibrationPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<WaterLevelCalibrationPage> createState() =>
      _WaterLevelCalibrationPageState();
}

enum _Stage { entry, steps, success, failed }

class _WaterLevelCalibrationPageState extends State<WaterLevelCalibrationPage> {
  _Stage _stage = _Stage.entry;

  /// 1/4 ~ 4/4 的下标（0~3），只在 [_Stage.steps] 时有意义。
  int _stepIndex = 0;
  bool _submitting = false;

  /// 采样间隔倒计时剩余秒数，0 = 可以点。
  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _watchdog;

  /// 设备那边是否处在校准会话里（发过 0 且还没保存 / 取消 / 超时）。
  bool get _inSession => _stage == _Stage.steps;

  WaterLevelCalibrationStepModel get _step => _stage == _Stage.entry
      ? WaterLevelCalibrationModel.entry
      : WaterLevelCalibrationModel.steps[_stepIndex];

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _watchdog?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdown = WaterLevelCalibrationModel.sampleInterval.inSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _countdown = _countdown > 0 ? _countdown - 1 : 0);
      if (_countdown == 0) timer.cancel();
    });
  }

  /// 每次设备确认一步就重新计时；3 分钟内没下一步，设备会自动取消。
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(WaterLevelCalibrationModel.stepTimeout, _onWatchdog);
  }

  Future<void> _onWatchdog() async {
    if (!mounted || !_inSession) return;
    _countdownTimer?.cancel();
    setState(() {
      _stage = _Stage.entry;
      _stepIndex = 0;
      _countdown = 0;
    });
    await showAppDialog(
      context,
      title: '校准已超时',
      message: '单步操作超过 3 分钟，设备已自动取消校准。\n请从第 1 步重新开始。',
      confirmLabel: '我知道了',
      showCancel: false,
    );
  }

  Future<void> _handlePrimary() async {
    if (_submitting || _countdown > 0) return;
    if (_stage == _Stage.success) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_stage == _Stage.failed) {
      setState(() => _stage = _Stage.entry);
      return;
    }
    final state = FlowerpotScope.of(context);
    final step = _step;
    setState(() => _submitting = true);
    final result = await state.calibrateWaterLevel(
      widget.deviceId,
      step.dpValue,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result.success) {
      // 保存失败：设备显示失败页后回主界面，这次会话已结束，只能从头来。
      if (step.dpValue == 4 && result.code == 'calib_fail') {
        _watchdog?.cancel();
        setState(() => _stage = _Stage.failed);
        return;
      }
      // 其余失败重发本步即可（设备屏会写具体原因）。
      showAppMessage(context, result.message, tone: AppMessageTone.error);
      return;
    }

    if (step.dpValue == 4) {
      _watchdog?.cancel();
      setState(() => _stage = _Stage.success);
      return;
    }
    _armWatchdog();
    setState(() {
      if (_stage == _Stage.entry) {
        _stage = _Stage.steps;
        _stepIndex = 0;
      } else {
        _stepIndex += 1;
      }
    });
    if (_step.waitBeforeSample) _startCountdown();
  }

  /// 页头 ←、底部「取消校准」、系统返回统一走这里。
  Future<void> _requestExit() async {
    if (_submitting) return;
    if (!_inSession) {
      Navigator.of(context).pop(_stage == _Stage.success);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '取消校准',
      message: '取消后本次已记录的数据不会保存，确定退出校准吗？',
      confirmLabel: '取消校准',
      cancelLabel: '继续校准',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final state = FlowerpotScope.of(context);
    setState(() => _submitting = true);
    final result = await state.cancelWaterLevelCalibration(widget.deviceId);
    if (!mounted) return;
    _watchdog?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _submitting = false;
      _stage = _Stage.entry;
    });
    if (!result.success) {
      showAppMessage(context, result.message, tone: AppMessageTone.error);
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: AppPageScaffold(
        appBar: AppPageHeader(
          title: WaterLevelCalibrationModel.title,
          leading: AppBackButton(onPressed: _requestExit),
        ),
        background: AppPageBackground.standard,
        body: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('water-level-calibration-scroll-view'),
                  child: ResponsiveContent(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageMargin,
                      24,
                      AppSpacing.pageMargin,
                      24,
                    ),
                    child: _buildBody(),
                  ),
                ),
              ),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final (
      String instruction,
      WaterLevelCalibrationVisual visual,
      String label,
    ) = switch (_stage) {
      _Stage.success => (
        '校准完成！\n校准值已保存到设备。',
        WaterLevelCalibrationVisual.completed,
        '水位传感器校准完成',
      ),
      _Stage.failed => (
        '校准数据异常，\n请从第 1 步重新开始。',
        WaterLevelCalibrationVisual.emptyReservoir,
        '水位传感器校准失败',
      ),
      _ => (_step.instruction, _step.visual, _step.semanticLabel),
    };
    return Column(
      children: <Widget>[
        if (_stage == _Stage.steps) ...<Widget>[
          Text(
            '${_stepIndex + 1}/${WaterLevelCalibrationModel.steps.length}',
            key: const Key('water-level-calibration-progress'),
            style: AppTypography.status.copyWith(color: AppColors.brandPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const Key('water-level-calibration-stepper'),
            width: 195,
            child: AppStepIndicator(
              stepCount: WaterLevelCalibrationModel.steps.length,
              currentStep: _stepIndex,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(
          instruction,
          key: const Key('water-level-calibration-instruction'),
          textAlign: TextAlign.center,
          style: AppTypography.deviceTitle.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.47,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230, maxHeight: 164),
          child: Semantics(
            label: label,
            image: true,
            child: _CalibrationIllustration(visual: visual),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final primaryLabel = switch (_stage) {
      _Stage.success => '完成',
      _Stage.failed => '重新开始',
      _ =>
        _countdown > 0
            ? '${_step.primaryActionLabel}（${_countdown}s）'
            : _step.primaryActionLabel,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.sm,
        AppSpacing.pageMargin,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppPrimaryButton(
            key: const Key('calibration-primary-button'),
            label: primaryLabel,
            loading: _submitting,
            onPressed: _countdown > 0 ? null : _handlePrimary,
          ),
          if (_inSession) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AppOutlinedButton(
              key: const Key('calibration-cancel-button'),
              label: '取消校准',
              onPressed: _submitting ? null : _requestExit,
            ),
          ],
        ],
      ),
    );
  }
}

/// 示意图。加水那张图上印着旧流程的「30mL」，这里把字裁掉、改画「20mL」。
class _CalibrationIllustration extends StatelessWidget {
  const _CalibrationIllustration({required this.visual});

  final WaterLevelCalibrationVisual visual;

  /// 原图 460×328，「30mL」字样在右侧 x ≥ 320 的区域。
  static const double _aspectRatio = 460 / 328;
  static const double _textLeft = 320 / 460;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      switch (visual) {
        WaterLevelCalibrationVisual.emptyReservoir =>
          AppAssets.waterCalibrationRemoveInnerPot,
        WaterLevelCalibrationVisual.firstPour =>
          AppAssets.waterCalibrationAdd30ml,
        WaterLevelCalibrationVisual.secondPour =>
          AppAssets.waterCalibrationAddSecond30ml,
        WaterLevelCalibrationVisual.completed =>
          AppAssets.waterCalibrationComplete,
      },
      key: const Key('water-level-calibration-illustration'),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
    if (visual != WaterLevelCalibrationVisual.firstPour) return image;
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: ClipRect(
                  clipper: _LeftPartClipper(_textLeft),
                  child: image,
                ),
              ),
              Positioned(
                left: width * _textLeft,
                top: constraints.maxHeight * .1,
                child: Text(
                  '20mL',
                  style: AppTypography.status.copyWith(
                    color: AppColors.brandPrimary,
                    fontSize: width * .055,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LeftPartClipper extends CustomClipper<Rect> {
  const _LeftPartClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftPartClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
