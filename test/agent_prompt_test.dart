// Tests for the system prompt builder.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/agent_prompt.dart';

void main() {
  group('buildSystemPrompt', () {
    test('returns minimal prompt when no tools', () {
      final prompt = buildSystemPrompt(
        hasTools: false,
        hasAndroidTools: false,
        toolList: '',
      );
      expect(prompt, '你是一个有用的助手。直接回答用户的问题。');
    });

    test('includes tool list when hasTools is true', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- calculator: 计算数学表达式',
      );
      expect(prompt, contains('可用工具:'));
      expect(prompt, contains('- calculator: 计算数学表达式'));
      expect(prompt, contains('<tool_call>'));
      expect(prompt, contains('</tool_call>'));
    });

    test('includes Android automation rules when hasAndroidTools is true', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: true,
        toolList: '- android_click_by_text: 点击文字',
      );
      expect(prompt, contains('Android 自动化专属规则'));
      expect(prompt, contains('android_dump_ui'));
    });

    test('does not include Android rules when hasAndroidTools is false', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- calculator: 计算',
      );
      expect(prompt, isNot(contains('Android 自动化专属规则')));
    });

    test('includes tool call format instructions', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('{"name": "工具名"'));
      expect(prompt, contains('每次只调用一个工具'));
      expect(prompt, contains('最终回答用自然语言组织'));
    });

    test('includes rule N (smart skill suggestion)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('规则 N'));
      expect(prompt, contains('智能 Skill 建议'));
    });

    test('includes rule O (autonomous decision priority)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('规则 O'));
      expect(prompt, contains('自主决策优先'));
    });

    test('includes rule Q (long-term memory priority)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('规则 Q'));
      expect(prompt, contains('agent_memory_set'));
    });

    test('includes rule R (heuristic task decomposition)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('规则 R'));
      expect(prompt, contains('agent_analyze_and_plan'));
    });

    test('includes rule S (account/game automation)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('规则 S'));
      expect(prompt, contains('longterm_memory'));
    });

    test('includes MCP + Skills rules (K)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('MCP + Skills 自主决策原则'));
    });

    test('includes session lifecycle rules (M)', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '- test_tool',
      );
      expect(prompt, contains('会话生命周期'));
      expect(prompt, contains('session_bootstrap'));
    });

    test('empty toolList results in empty section', () {
      final prompt = buildSystemPrompt(
        hasTools: true,
        hasAndroidTools: false,
        toolList: '',
      );
      expect(prompt, contains('可用工具:'));
      // The tool list section will be empty but the prompt should still be valid.
      expect(prompt.length, greaterThan(100));
    });
  });
}