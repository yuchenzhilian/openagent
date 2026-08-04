/// Lightweight intent classifier for agent routing.
///
/// Uses keyword + regex rules (no ML model) to classify user intent into
/// one of several categories.  This allows the ReAct loop to skip unnecessary
/// "thinking" steps and route directly to the appropriate tool or skill.
///
/// Classification is cheap (~1ms) and runs entirely on-device.

import 'agent_runtime.dart' show Tool;

/// Intent categories.
enum IntentCategory {
  /// Simple math calculation — route directly to calculator tool.
  mathCalc,

  /// Date/time query — route directly to dateTime tool.
  dateTime,

  /// Knowledge base query — search local knowledge base first.
  knowledgeQuery,

  /// Web search — needs internet access.
  webSearch,

  /// Android automation task — enable android_rpa skill.
  androidAutomation,

  /// Complex task that needs full ReAct loop.
  complexTask,

  /// General chat — no tools needed.
  generalChat,
}

/// Result of intent classification.
class IntentResult {
  final IntentCategory category;
  final String confidence; // 'high', 'medium', 'low'
  final String? suggestedTool;

  const IntentResult({
    required this.category,
    this.confidence = 'medium',
    this.suggestedTool,
  });
}

/// Classifies user input into intent categories using keyword/regex rules.
class IntentClassifier {
  /// Classify the user's input text.
  IntentResult classify(String input) {
    if (input.isEmpty) {
      return const IntentResult(category: IntentCategory.generalChat, confidence: 'high');
    }

    final trimmed = input.trim().toLowerCase();

    // 1. Math calculation — detect arithmetic expressions.
    if (_isMathExpression(trimmed)) {
      return const IntentResult(
        category: IntentCategory.mathCalc,
        confidence: 'high',
        suggestedTool: 'calculator',
      );
    }

    // 2. Date/time query.
    if (_isDateTimeQuery(trimmed)) {
      return const IntentResult(
        category: IntentCategory.dateTime,
        confidence: 'high',
        suggestedTool: 'datetime',
      );
    }

    // 3. Android automation — detect UI interaction keywords.
    if (_isAndroidAutomation(trimmed)) {
      return const IntentResult(
        category: IntentCategory.androidAutomation,
        confidence: 'medium',
      );
    }

    // 4. Knowledge base query.
    if (_isKnowledgeQuery(trimmed)) {
      return const IntentResult(
        category: IntentCategory.knowledgeQuery,
        confidence: 'medium',
        suggestedTool: 'knowledge_search',
      );
    }

    // 5. Web search — explicit request for online info.
    if (_isWebSearch(trimmed)) {
      return const IntentResult(
        category: IntentCategory.webSearch,
        confidence: 'high',
        suggestedTool: 'web_search',
      );
    }

    // 6. Complex task — multi-step, planning needed.
    if (_isComplexTask(trimmed)) {
      return const IntentResult(
        category: IntentCategory.complexTask,
        confidence: 'medium',
      );
    }

    // Default: general chat.
    return const IntentResult(category: IntentCategory.generalChat, confidence: 'high');
  }

  /// Check if the input is a math expression.
  bool _isMathExpression(String input) {
    // Detect patterns like: "2+2", "3*5", "sqrt(16)", "what is 2+2"
    final mathPatterns = [
      RegExp(r'^[\d\s+\-*/().%^,]+$'),           // pure math expression
      RegExp(r'(calculate|compute|solve|what is|what\'s)\s+\d'),
      RegExp(r'\d+\s*[\+\-\*/]\s*\d+'),           // arithmetic operators
      RegExp(r'(sqrt|pow|abs|sin|cos|tan|log)\(.*\)'),
    ];
    return mathPatterns.any((p) => p.hasMatch(input));
  }

  /// Check if the input is a date/time query.
  bool _isDateTimeQuery(String input) {
    final datePatterns = [
      RegExp(r'(what|current|today|now|time|date|when|day)'),
      RegExp(r'(几点了|今天|日期|时间|现在|星期)'),
      RegExp(r'^\d{1,2}:\d{2}\s*(am|pm)?$', caseSensitive: false),
    ];
    return datePatterns.any((p) => p.hasMatch(input));
  }

  /// Check if the input involves Android automation.
  bool _isAndroidAutomation(String input) {
    final androidPatterns = [
      RegExp(r'(click|tap|swipe|scroll|open app|launch|install|uninstall)'),
      RegExp(r'(打开|关闭|点击|滑动|安装|卸载|删除|发送|拍照|截图)'),
      RegExp(r'(wechat|weixin|微信|抖音|douyin|支付宝|alipay)'),
      RegExp(r'(send message|拨号|call|短信|sms)'),
    ];
    return androidPatterns.any((p) => p.hasMatch(input));
  }

  /// Check if the input is a knowledge base query.
  bool _isKnowledgeQuery(String input) {
    final knowledgePatterns = [
      RegExp(r'(what is|who is|what are|tell me about|explain|define)'),
      RegExp(r'(是什么|是谁|什么是|告诉我|解释|定义)'),
      RegExp(r'(how does|how to|how do|why is|why does)'),
      RegExp(r'(原理|概念|意思|含义|区别|比较)'),
    ];
    return knowledgePatterns.any((p) => p.hasMatch(input));
  }

  /// Check if the input requires web search.
  bool _isWebSearch(String input) {
    final webPatterns = [
      RegExp(r'(search|find|look up|google|news|weather|forecast)'),
      RegExp(r'(搜索|查找|查询|天气|新闻|最新)'),
      RegExp(r'(stock|price|股价|价格|汇率|exchange rate)'),
      RegExp(r'^https?://'),  // URL pasted
    ];
    return webPatterns.any((p) => p.hasMatch(input));
  }

  /// Check if the input is a complex multi-step task.
  bool _isComplexTask(String input) {
    final complexPatterns = [
      RegExp(r'(plan|步骤|第一步|首先|然后|接着)'),
      RegExp(r'(compare|对比|分析|analyze|evaluate|评估)'),
      RegExp(r'(create|build|make|写|编写|生成|generate)'),
      RegExp(r'(多个|一系列|several|multiple|list of)'),
      // Long input likely needs complex processing.
      input.length > 200,
    ];
    return complexPatterns.any((p) => p is RegExp ? p.hasMatch(input) : p);
  }
}