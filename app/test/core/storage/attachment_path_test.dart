/// @file        attachment_path_test.dart
/// @description AttachmentStorage.relativePathFor: the path of an attachment
///              is only ever a UUID file id and a short alphanumeric
///              extension under snowchat_attachments — a file id or a file
///              name from a sender (or a server) that tries to leave the
///              directory is refused or replaced.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/storage/local_file_protection.dart';

void main() {
  const id = '3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90';

  test('a UUID and the extension of the file name', () {
    expect(AttachmentStorage.relativePathFor(id, 'photo.JPG'),
        'snowchat_attachments/$id.jpg');
    expect(AttachmentStorage.relativePathFor(id.toUpperCase(), 'a.tar.gz'),
        'snowchat_attachments/$id.gz');
  });

  test('a file id that is not a UUID is refused', () {
    for (final bad in [
      '../../shared_prefs/FlutterSharedPreferences',
      '$id/../x',
      '..',
      '',
      '3f2a9c1e5b7d4e8a9c217d4e5f6a8b90',
    ]) {
      expect(() => AttachmentStorage.relativePathFor(bad, 'x.png'),
          throwsFormatException, reason: bad);
    }
  });

  test('an extension that is not 1–8 letters or digits becomes the fallback',
      () {
    for (final name in ['x', 'x.', 'x.p/ng', 'x./../y', 'x.toolongext', 'x.p ng', 'x.ü']) {
      expect(AttachmentStorage.relativePathFor(id, name),
          'snowchat_attachments/$id.bin', reason: name);
    }
    expect(AttachmentStorage.relativePathFor(id, 'x', fallbackExtension: 'jpg'),
        'snowchat_attachments/$id.jpg');
  });
}
