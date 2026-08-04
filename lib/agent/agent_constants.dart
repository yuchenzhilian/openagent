// Shared constants for agent tool-call parsing and logging.
// Extracted from agent_runtime.dart and agent_prompt.dart to avoid duplication.

/// Opening tag for tool call XML blocks.
const kToolCallOpen = '<tool_call>';

/// Closing tag for tool call XML blocks.
const kToolCallClose = '</tool_call>';

/// Default timeout for tool execution (30 seconds).
const kDefaultToolTimeout = Duration(seconds: 30);

/// Maximum age for log files before trimming.
const kLogMaxAge = Duration(hours: 24);

/// Maximum number of lines in the execution log.
const kLogMaxLines = 5000;

/// Target number of lines after trimming the log.
const kLogTrimTarget = 3000;

/// Maximum length for argument summary in log output.
const kLogArgMaxLen = 80;

/// Maximum length for content preview (used in various truncation contexts).
const kContentPreviewMax = 8000;

/// Maximum length for content preview (longer context).
const kContentPreviewLong = 10000;

/// Maximum length for UI dump preview.
const kUiDumpPreviewMax = 2000;

/// Maximum length for UI dump preview (short).
const kUiDumpPreviewShort = 1000;

/// Maximum length for tool execution output preview.
const kToolOutputPreviewMax = 500;

/// Maximum length for skill description preview.
const kSkillDescPreviewMax = 200;

/// Default maximum ReAct loop steps.
const kDefaultMaxSteps = 5;

/// Maximum ReAct loop steps when Android automation is enabled.
const kAndroidMaxSteps = 20;

/// Maximum number of messages to keep in a chat session.
const kMaxSessionMessages = 200;
