import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

class BackupService {
  /// Genera un archivo .zip con packs.json y todas las carpetas de stickers,
  /// y abre el diálogo del sistema para guardarlo en el teléfono.
  Future<String?> exportBackupZip() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final packsJsonFile =
        File('${docsDir.path}/${AppConstants.packsJsonFileName}');
    final packsDir =
        Directory('${docsDir.path}/${AppConstants.packsFolderName}');

    if (!await packsJsonFile.exists()) {
      throw Exception('Aún no hay paquetes guardados para respaldar.');
    }

    final archive = Archive();

    // 1. Agregar packs.json a la raíz del ZIP
    final jsonBytes = await packsJsonFile.readAsBytes();
    archive.addFile(
      ArchiveFile(
        AppConstants.packsJsonFileName,
        jsonBytes.length,
        jsonBytes,
      ),
    );

    // 2. Recorrer recursivamente la carpeta packs/ y agregar cada imagen con ruta relativa
    if (await packsDir.exists()) {
      final entities = await packsDir.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is File) {
          final relativePath = entity.path
              .substring(docsDir.path.length + 1)
              .replaceAll('\\', '/');
          final fileBytes = await entity.readAsBytes();
          archive.addFile(
            ArchiveFile(relativePath, fileBytes.length, fileBytes),
          );
        }
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Error al comprimir el archivo ZIP.');
    }

    final backupFileName =
        'stickers_backup_${DateTime.now().millisecondsSinceEpoch}.zip';

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar copia de seguridad de stickers',
      fileName: backupFileName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: Uint8List.fromList(zipBytes),
    );

    return savedPath;
  }

  /// Abre el selector de archivos para elegir un .zip y restaura todos los paquetes
  /// corrigiendo automáticamente las rutas absolutas al directorio actual de la app.
  Future<int> importBackupZip() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Seleccionar respaldo .zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return 0;
    }

    final pickedFile = result.files.first;
    final Uint8List zipBytes;
    if (pickedFile.bytes != null) {
      zipBytes = pickedFile.bytes!;
    } else if (pickedFile.path != null) {
      zipBytes = await File(pickedFile.path!).readAsBytes();
    } else {
      throw Exception('No se pudo leer el archivo seleccionado.');
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final docsDir = await getApplicationDocumentsDirectory();

    // 1. Extraer todos los archivos físicos dentro de <documents>/
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final safeName = entry.name.replaceAll('\\', '/');
      if (safeName.contains('..')) continue;

      final outFile = File('${docsDir.path}/$safeName');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>, flush: true);
    }

    // 2. Normalizar las rutas en packs.json por si el respaldo viene de otra instalación
    final packsJsonFile =
        File('${docsDir.path}/${AppConstants.packsJsonFileName}');
    if (!await packsJsonFile.exists()) {
      throw Exception(
        'El archivo ZIP no contiene un archivo packs.json válido.',
      );
    }

    final decoded =
        jsonDecode(await packsJsonFile.readAsString()) as Map<String, dynamic>;
    final packsList = decoded['packs'] as List<dynamic>? ?? [];

    for (final packItem in packsList) {
      final packMap = packItem as Map<String, dynamic>;
      final packId = packMap['id'] as String;
      final packBasePath =
          '${docsDir.path}/${AppConstants.packsFolderName}/$packId';

      if (packMap['trayImagePath'] != null) {
        packMap['trayImagePath'] = '$packBasePath/tray.png';
      }

      final stickersList = packMap['stickers'] as List<dynamic>? ?? [];
      for (final stickerItem in stickersList) {
        final sMap = stickerItem as Map<String, dynamic>;
        final sId = sMap['id'] as String;
        final stickerFolder = '$packBasePath/stickers/$sId';

        sMap['sourcePath'] = '$stickerFolder/source.png';
        if (sMap['webpPath'] != null) {
          sMap['webpPath'] = '$stickerFolder/export.webp';
        }
        if (sMap['originalPhotoPath'] != null) {
          sMap['originalPhotoPath'] = '$stickerFolder/original.jpg';
        }
      }
    }

    const encoder = JsonEncoder.withIndent('  ');
    await packsJsonFile.writeAsString(encoder.convert(decoded), flush: true);

    return packsList.length;
  }
}
