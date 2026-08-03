// Built-in tools for the Agent runtime.
//
// These tools are pure-Dart (no native calls, no network) so they work
// on every platform without additional setup. Each tool is a factory
// function that returns a [Tool] instance.
library builtin_tools;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform, File, HttpClient, HttpClientRequest, Directory;
import 'agent_runtime.dart';
import '../data/services/schedule_service.dart';

part 'builtin_tools/builtin_math_time.dart';
part 'builtin_tools/builtin_data_utils.dart';
part 'builtin_tools/builtin_assistant.dart';

/// Returns all built-in tools for quick registration.
List<Tool> builtinTools() => [
      calculatorTool(),
      dateTimeTool(),
      textCounterTool(),
      unitConverterTool(),
      jsonFormatterTool(),
      // Stage 19: Web & HTTP tools.
      webSearchTool(),
      httpFetchTool(),
      htmlToTextTool(),
      // Stage 19: Utility tools.
      randomNumberTool(),
      uuidGeneratorTool(),
      base64CodecTool(),
      colorConverterTool(),
      timerTool(),
      weatherTool(),
      ipInfoTool(),
      textTemplateTool(),
      // Stage 19: Agent analysis tool.
      agentAnalyzeAndPlanTool(),
      // Stage 21: More utility tools.
      urlCodecTool(),
      regexTesterTool(),
      stringCaseTool(),
      encodeDecodeTool(),
      // Stage 22: Hash & data tools.
      hashTool(),
      textStatsAdvancedTool(),
      csvJsonTool(),
      markdownTableTool(),
      passwordGeneratorTool(),
      dateCalculatorTool(),
    ];