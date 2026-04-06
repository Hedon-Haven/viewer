import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'global_vars.dart';

/// Recursive async function to copy a directory into another
/// Source: https://stackoverflow.com/a/76166248
Future<void> _copyDirectory(Directory source, Directory destination) async {
  /// create destination folder if not exist
  if (!(await destination.exists())) {
    await destination.create(recursive: true);
  }

  /// get all files from source (recursive: false is important here)
  await for (final entity in source.list(recursive: false)) {
    final newPath = destination.path +
        Platform.pathSeparator +
        entity.path.split(Platform.pathSeparator).last;
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(newPath));
    }
  }
}

/// Delete destination directory if it exists and copy source directory over it
Future<void> forceCopyDirectory(Directory source, Directory destination) async {
  await deleteDirectory(destination);
  await destination.create(recursive: true);

  await _copyDirectory(source, destination);
}

Future<void> deleteDirectory(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  } else {
    logger.w("Directory ${directory.path} does not exist; cannot delete");
  }
}

Future<String> getExtractTempDir() async {
  final tempDir = await getTemporaryDirectory();
  final String random =
      String.fromCharCodes(List.generate(5, (_) => Random().nextInt(26) + 97));
  final outputDir = Directory("${tempDir.path}/extracted_plugin/$random");
  logger.d("Deleting and recreating temp dir at ${outputDir.path}");
  await outputDir.create(recursive: true);
  return outputDir.path;
}

Future<void> extractZipTo(String zipFilePath, String extractPath) async {
  final zipBytes = await File(zipFilePath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes);

  // Resolve absolute, normalized extract path to prevent bypasses
  final safeExtractPath = p.normalize(p.absolute(extractPath));

  for (final entry in archive) {
    // Normalize the entry name (e.g., remove './' and '//')
    final entryName = p.normalize(entry.name);
    final fullPath = p.join(safeExtractPath, entryName);

    // Zip slip check: ensure the resolved path is inside the extraction directory
    if (!fullPath.startsWith(safeExtractPath)) {
      throw Exception(
          'Zip slip detected: "${entry.name}" tries to escape extraction directory.');
    }

    if (entry.isFile) {
      final data = entry.content as List<int>;
      final outputFile = File(fullPath);
      await outputFile.create(recursive: true);
      await outputFile.writeAsBytes(data);
    } else if (entry.isDirectory) {
      await Directory(fullPath).create(recursive: true);
    } else {
      // Reject links, devices, etc.
      throw Exception(
          'Unsupported entry type: "${entry.name}" (only files and directories allowed)');
    }
  }
}
