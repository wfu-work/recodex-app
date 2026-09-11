import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';

import '../models/bridge_models.dart';
import 'relay_protocol.dart';

class ComposerImage {
  ComposerImage({
    required this.name,
    required this.bytes,
    required this.thumbnail,
  });

  static const maxCount = 4;
  static const maxBytes = 6 * 1024 * 1024;
  final String name;
  final Uint8List bytes;
  final Uint8List thumbnail;
  final Map<String, String> _uploadIds = {};
  String uploadId(String scope) =>
      _uploadIds.putIfAbsent(scope, () => RelayProtocol.randomId('img'));
  EventAttachment get attachment => EventAttachment(
    type: 'image',
    mime: 'image/png',
    thumbnailDataUrl: 'data:image/png;base64,${base64Encode(thumbnail)}',
  );

  static Future<ComposerImage> fromFile(XFile file) async {
    if (await file.length() > 25 * 1024 * 1024) {
      throw const FormatException('原图过大，请选择小于 25 MB 的图片');
    }
    return fromBytes(await file.readAsBytes(), name: file.name);
  }

  static Future<ComposerImage> fromBytes(
    Uint8List source, {
    String name = '截图.png',
  }) async {
    if (source.isEmpty || source.length > 25 * 1024 * 1024) {
      throw const FormatException('图片为空或超过 25 MB');
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(source);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 80 * 1000 * 1000) {
        throw const FormatException('图片尺寸过大，请先缩小图片');
      }
      Future<Uint8List> resize(int maxSide) async {
        final scale = math.min(
          1.0,
          maxSide / math.max(descriptor!.width, descriptor.height),
        );
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            return (await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }

      var bytes = await resize(2048);
      if (bytes.length > maxBytes) bytes = await resize(1536);
      if (bytes.length > maxBytes) {
        throw const FormatException('图片处理后仍超过 6 MB，请缩小后再添加');
      }
      return ComposerImage(
        name: name,
        bytes: bytes,
        thumbnail: await resize(240),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取图片，请选择 PNG、JPEG 或 WebP 图片');
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class ImageMessageContext {
  const ImageMessageContext({
    required this.host,
    required this.cwd,
    required this.threadId,
  });
  final String host;
  final String cwd;
  final String? threadId;
  String get key => jsonEncode([host, cwd, threadId]);
}

class ImageCommandException implements Exception {
  const ImageCommandException(this.code, this.message);
  final String code;
  final String message;
  bool get uncertain => const [
    'COMMAND_OUTCOME_UNKNOWN',
    'APP_SERVER_TIMEOUT',
    'APP_SERVER_UNAVAILABLE',
    'CONNECTION_LOST',
  ].contains(code);
  @override
  String toString() => message;
}

enum ImageSendOutcome { accepted, rejected, unknown }

/// Sequential acknowledgements keep large images below the frame limit. A
/// retry begins with the same upload id and resumes at the host's offset.
Future<String> uploadComposerImage({
  required ComposerImage image,
  required ImageMessageContext context,
  required Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  request,
  required void Function(double) onProgress,
  int chunkBytes = 96 * 1024,
}) async {
  final id = image.uploadId(context.key);
  final digest = await Sha256().hash(image.bytes);
  final ready = await request('image.upload.begin', {
    'uploadId': id,
    'mime': 'image/png',
    'size': image.bytes.length,
    'sha256': digest.bytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join(),
    'cwd': context.cwd,
    if (context.threadId != null) 'threadId': context.threadId,
  });
  var offset = (ready['offset'] as num?)?.toInt() ?? 0;
  if (offset < 0 || offset > image.bytes.length || chunkBytes <= 0) {
    throw const FormatException('图片上传进度无效');
  }
  onProgress(offset / image.bytes.length);
  while (offset < image.bytes.length) {
    final end = math.min(offset + chunkBytes, image.bytes.length);
    final result = await request('image.upload.append', {
      'uploadId': id,
      'offset': offset,
      'data': base64Encode(Uint8List.sublistView(image.bytes, offset, end)),
    });
    final next = (result['offset'] as num?)?.toInt();
    if (next != end) throw const FormatException('图片上传未完整确认，请重试');
    offset = end;
    onProgress(offset / image.bytes.length);
  }
  final result = await request('image.upload.finish', {'uploadId': id});
  if (result['attachmentId'] != id) throw const FormatException('图片上传校验未通过');
  return id;
}
