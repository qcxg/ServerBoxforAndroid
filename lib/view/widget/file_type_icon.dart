import 'package:flutter/material.dart';

enum FileVisualKind {
  folder,
  yaml,
  xml,
  json,
  source,
  shell,
  text,
  image,
  pdf,
  archive,
  table,
  database,
  audio,
  video,
  package,
  generic,
}

FileVisualKind fileVisualKind(String name, {required bool isDirectory}) {
  if (isDirectory) return FileVisualKind.folder;

  final lower = name.toLowerCase();
  final extension = lower.contains('.') ? lower.split('.').last : '';
  if (lower == 'dockerfile' || lower == 'makefile') {
    return FileVisualKind.source;
  }
  if (lower.startsWith('.env') || lower.endsWith('.env')) {
    return FileVisualKind.yaml;
  }

  return switch (extension) {
    'yaml' || 'yml' || 'toml' || 'ini' || 'conf' || 'config' =>
      FileVisualKind.yaml,
    'xml' || 'xsl' || 'svg' => FileVisualKind.xml,
    'json' || 'json5' || 'jsonl' => FileVisualKind.json,
    'dart' ||
    'js' ||
    'jsx' ||
    'ts' ||
    'tsx' ||
    'html' ||
    'htm' ||
    'css' ||
    'scss' ||
    'less' ||
    'py' ||
    'go' ||
    'rs' ||
    'java' ||
    'kt' ||
    'kts' ||
    'c' ||
    'cc' ||
    'cpp' ||
    'h' ||
    'hpp' ||
    'php' ||
    'rb' ||
    'swift' =>
      FileVisualKind.source,
    'sh' || 'bash' || 'zsh' || 'fish' || 'bat' || 'cmd' || 'ps1' =>
      FileVisualKind.shell,
    'txt' || 'md' || 'markdown' || 'log' || 'rtf' => FileVisualKind.text,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'ico' ||
    'heic' ||
    'avif' =>
      FileVisualKind.image,
    'pdf' => FileVisualKind.pdf,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' || 'xz' || 'tgz' =>
      FileVisualKind.archive,
    'csv' || 'tsv' || 'xls' || 'xlsx' || 'ods' => FileVisualKind.table,
    'db' || 'sqlite' || 'sqlite3' || 'sql' => FileVisualKind.database,
    'mp3' || 'wav' || 'flac' || 'aac' || 'm4a' || 'ogg' =>
      FileVisualKind.audio,
    'mp4' || 'mkv' || 'webm' || 'mov' || 'avi' || 'm4v' =>
      FileVisualKind.video,
    'apk' || 'aab' || 'deb' || 'rpm' || 'msi' || 'exe' =>
      FileVisualKind.package,
    _ => FileVisualKind.generic,
  };
}

final class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({
    super.key,
    required this.name,
    required this.isDirectory,
    this.size = 24,
  });

  final String name;
  final bool isDirectory;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = fileVisualKind(name, isDirectory: isDirectory);
    final icon = switch (kind) {
      FileVisualKind.folder => Icons.folder_rounded,
      FileVisualKind.yaml => Icons.account_tree_rounded,
      FileVisualKind.xml => Icons.code_rounded,
      FileVisualKind.json => Icons.data_object_rounded,
      FileVisualKind.source => Icons.code_rounded,
      FileVisualKind.shell => Icons.terminal_rounded,
      FileVisualKind.text => Icons.description_rounded,
      FileVisualKind.image => Icons.image_rounded,
      FileVisualKind.pdf => Icons.picture_as_pdf_rounded,
      FileVisualKind.archive => Icons.archive_rounded,
      FileVisualKind.table => Icons.table_chart_rounded,
      FileVisualKind.database => Icons.storage_rounded,
      FileVisualKind.audio => Icons.audio_file_rounded,
      FileVisualKind.video => Icons.video_file_rounded,
      FileVisualKind.package => Icons.apps_rounded,
      FileVisualKind.generic => Icons.insert_drive_file_rounded,
    };
    final color = switch (kind) {
      FileVisualKind.folder => scheme.primary,
      FileVisualKind.yaml => scheme.tertiary,
      FileVisualKind.xml || FileVisualKind.source || FileVisualKind.shell =>
        scheme.secondary,
      FileVisualKind.json || FileVisualKind.archive || FileVisualKind.package =>
        scheme.tertiary,
      FileVisualKind.pdf => scheme.error,
      FileVisualKind.image || FileVisualKind.audio || FileVisualKind.video =>
        scheme.primary,
      FileVisualKind.table || FileVisualKind.database => scheme.secondary,
      FileVisualKind.text || FileVisualKind.generic => scheme.onSurfaceVariant,
    };

    return Icon(icon, size: size, color: color.withAlpha(210));
  }
}
