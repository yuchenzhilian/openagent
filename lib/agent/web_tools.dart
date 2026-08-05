// Cross-platform In-App WebView automation tools.
//
// On iOS where AccessibilityService is unavailable, the most viable
// "cross-App automation" path is to run web versions of target services
// (WeChat Web, Douyin H5, etc.) inside an in-app WebView and manipulate
// the DOM via JavaScript injection.
//
// These tools are platform-agnostic (work on Android and iOS alike) and
// complement the native platform tools. The Agent can fall back to
// web automation when native RPA is unavailable.
//
// Architecture:
//   Dart Tool layer (this file)
//     -> MethodChannel "com.openagent.web_automation"
//     -> Native WebView controller (Android: WebView, iOS: WKWebView)
//
// The native side maintains a single off-screen WebView instance and
// executes JavaScript, extracts page content, fills forms, clicks
// elements, etc. The Agent drives it through these tools.

import 'agent_runtime.dart';

/// Factory: returns all WebView automation tools.
///
/// These tools are always available (both platforms support WebView),
/// so there's no isSupported gate.
List<Tool> createWebAutomationTools() {
  return [
    _webNavigateTool(),
    _webExecuteJsTool(),
    _webGetPageTextTool(),
    _webClickElementTool(),
    _webFillFormTool(),
    _webGetUrlTool(),
    _webScreenshotTool(),
    _webWaitForElementTool(),
  ];
}

Tool _webNavigateTool() {
  return Tool(
    name: 'web_navigate',
    description: '在内置 WebView 中导航到指定 URL。用于网页版自动化（微信网页版、抖音 H5 等）。'
        '示例: "https://wx.qq.com"（微信网页版）, "https://www.douyin.com"（抖音网页版）',
    schema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': '要导航到的 URL'},
      },
      'required': ['url'],
    },
    handler: (args) async {
      // TODO: Wire to native WebView via MethodChannel.
      return const ToolResult.ok('WebView 导航功能待实现（需要原生层 WebView 控制器）');
    },
  );
}

Tool _webExecuteJsTool() {
  return Tool(
    name: 'web_execute_js',
    description: '在当前 WebView 页面中执行任意 JavaScript 代码并返回结果。'
        '用于 DOM 操作：点击元素、填写表单、提取文本等。'
        '示例: document.querySelector("#login-btn").click()',
    schema: {
      'type': 'object',
      'properties': {
        'script': {'type': 'string', 'description': '要执行的 JavaScript 代码'},
      },
      'required': ['script'],
    },
    handler: (args) async {
      return const ToolResult.ok('WebView JS 执行功能待实现');
    },
  );
}

Tool _webGetPageTextTool() {
  return Tool(
    name: 'web_get_page_text',
    description: '获取当前 WebView 页面的文本内容（去除 HTML 标签）。用于分析网页内容。',
    schema: {'type': 'object', 'properties': {}},
    handler: (args) async {
      return const ToolResult.ok('WebView 页面文本获取功能待实现');
    },
  );
}

Tool _webClickElementTool() {
  return Tool(
    name: 'web_click_element',
    description: '在 WebView 中点击指定 CSS 选择器匹配的元素。'
        '示例: selector="#send-btn" 点击发送按钮, selector=".msg-item:last-child" 点击最后一条消息',
    schema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS 选择器'},
      },
      'required': ['selector'],
    },
    handler: (args) async {
      return const ToolResult.ok('WebView 元素点击功能待实现');
    },
  );
}

Tool _webFillFormTool() {
  return Tool(
    name: 'web_fill_form',
    description: '在 WebView 中填写表单输入框。'
        'selector 指定输入框的 CSS 选择器，value 为要输入的内容。',
    schema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': '输入框的 CSS 选择器'},
        'value': {'type': 'string', 'description': '要输入的文本'},
      },
      'required': ['selector', 'value'],
    },
    handler: (args) async {
      return const ToolResult.ok('WebView 表单填写功能待实现');
    },
  );
}

Tool _webGetUrlTool() {
  return Tool(
    name: 'web_get_url',
    description: '获取当前 WebView 页面的 URL。用于确认导航是否成功或检测重定向。',
    schema: {'type': 'object', 'properties': {}},
    handler: (args) async {
      return const ToolResult.ok('WebView URL 获取功能待实现');
    },
  );
}

Tool _webScreenshotTool() {
  return Tool(
    name: 'web_screenshot',
    description: '对当前 WebView 页面截图。返回截图文件路径，可用于 VLM 视觉分析。',
    schema: {'type': 'object', 'properties': {}},
    handler: (args) async {
      return const ToolResult.ok('WebView 截图功能待实现');
    },
  );
}

Tool _webWaitForElementTool() {
  return Tool(
    name: 'web_wait_for_element',
    description: '等待指定 CSS 选择器的元素出现在页面上（带超时）。'
        '用于等待页面加载完成后再执行操作。',
    schema: {
      'type': 'object',
      'properties': {
        'selector': {'type': 'string', 'description': 'CSS 选择器'},
        'timeout_ms': {
          'type': 'integer',
          'description': '超时毫秒数，默认 10000',
          'default': 10000
        },
      },
      'required': ['selector'],
    },
    handler: (args) async {
      return const ToolResult.ok('WebView 等待元素功能待实现');
    },
  );
}
