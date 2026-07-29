import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';

String formatFileListModified(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${twoDigits(local.year % 100)}-'
      '${twoDigits(local.month)}-'
      '${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:'
      '${twoDigits(local.minute)}';
}

String formatFileListSize(int bytes) => bytes.bytes2Str.replaceAll(' ', '');

final class FileListMetadata extends StatelessWidget {
  const FileListMetadata({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant.withAlpha(205),
            fontSize: 10,
            height: 1.05,
            letterSpacing: -0.1,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
