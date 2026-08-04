/// Error recovery for RPA operation chains.
enum AutomationErrorType {
  interceptingDialog,
  navigationFailure,
  elementNotFound,
  timeout,
  unknownState
}

class AutomationError {
  final AutomationErrorType type;
  final String description;
  final List<String> recoveryActions;
  final int severity;
  const AutomationError(
      {required this.type,
      required this.description,
      required this.recoveryActions,
      this.severity = 3});
}

class RecoveryResult {
  final bool success;
  final String? errorMessage;
  final List<String> actionsTaken;
  const RecoveryResult(
      {required this.success, this.errorMessage, this.actionsTaken = const []});
}

class ErrorRecovery {
  AutomationError analyze(String toolOutput, String toolName) {
    final lower = toolOutput.toLowerCase();
    if (_containsAny(lower, [
      'dialog',
      '弹窗',
      'alert',
      'popup',
      '权限',
      'permission',
      'update',
      '更新'
    ])) {
      return AutomationError(
          type: AutomationErrorType.interceptingDialog,
          description: '检测到弹窗遮挡',
          recoveryActions: ['点击"取消"或"关闭"按钮', '点击"返回"键', '尝试"拒绝"或"稍后"'],
          severity: 2);
    }
    if (_containsAny(lower, [
      'navigation',
      'navigate',
      'page',
      '跳转',
      'not found',
      '找不到',
      'failed',
      '失败'
    ])) {
      return AutomationError(
          type: AutomationErrorType.navigationFailure,
          description: '页面跳转失败',
          recoveryActions: ['检查网络连接', '等待 2 秒后重试', '回退到上一页面'],
          severity: 3);
    }
    if (_containsAny(lower, [
      'element',
      '元素',
      'not found',
      'no such',
      '找不到',
      'click',
      'clickable',
      'unable to find'
    ])) {
      return AutomationError(
          type: AutomationErrorType.elementNotFound,
          description: '目标元素未找到',
          recoveryActions: ['刷新当前页面', '等待 1 秒后重试', '尝试滚动查找', '使用截图分析定位'],
          severity: 3);
    }
    if (_containsAny(lower, ['timeout', '超时', 'timed out'])) {
      return AutomationError(
          type: AutomationErrorType.timeout,
          description: '操作超时',
          recoveryActions: ['检查网络连接', '检查设备响应状态', '增加超时时间后重试'],
          severity: 4);
    }
    return AutomationError(
        type: AutomationErrorType.unknownState,
        description: '未知错误: $toolOutput',
        recoveryActions: ['回到桌面', '重新打开目标应用', '从头开始执行计划'],
        severity: 5);
  }

  Future<RecoveryResult> recover(AutomationError error,
      {Future<bool> Function(String action)? executeAction}) async {
    final actionsTaken = <String>[];
    for (final action in error.recoveryActions) {
      if (executeAction != null) {
        final success = await executeAction(action);
        actionsTaken.add(action);
        if (success)
          return RecoveryResult(success: true, actionsTaken: actionsTaken);
      }
    }
    return RecoveryResult(
        success: false, errorMessage: '所有恢复操作均失败', actionsTaken: actionsTaken);
  }

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
