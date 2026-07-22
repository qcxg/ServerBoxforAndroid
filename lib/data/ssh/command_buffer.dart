String normalizeCommandBufferText(String source) {
  return source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// Prepares a whole command buffer for a single paste followed by Enter.
///
/// Internal line breaks are preserved for multiline shell constructs. Trailing
/// line breaks are removed because the caller emits exactly one final Enter.
String prepareCommandBufferForSendAll(String source) {
  var normalized = normalizeCommandBufferText(source);
  while (normalized.endsWith('\n')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Builds one atomic payload for an interactive SSH terminal.
///
/// A PTY expects carriage returns for Enter. Internal line breaks and the final
/// execution Enter are included in the same write, without bracketed-paste
/// markers that shells render as selected/highlighted text.
String buildCommandBufferSendAllPayload(String source) {
  final prepared = prepareCommandBufferForSendAll(source);
  if (prepared.trim().isEmpty) return '';
  return '${prepared.replaceAll('\n', '\r')}\r';
}

/// Splits a local command buffer into one command per non-empty line.
///
/// Leading and trailing whitespace on each command is preserved. Use the
/// all-at-once send mode for shell constructs whose blank lines are meaningful.
List<String> splitCommandBufferLines(String source) {
  return normalizeCommandBufferText(
    source,
  ).split('\n').where((line) => line.trim().isNotEmpty).toList();
}

/// Builds independently executable PTY writes for line-by-line mode.
List<String> buildCommandBufferLinePayloads(String source) {
  return splitCommandBufferLines(source)
      .map((command) => '$command\r')
      .toList(growable: false);
}
