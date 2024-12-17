A port of [libmobi](https://github.com/bfabiszewski/libmobi) to Dart.

**NOTE**: This package is a direct port of functions of libmobi mainly for my personal use and is not thoroughly tested. Use it at your own risk.

## Features

* Reading and parsing mobi, azw, azw3, azw4 files
* Reconstructing dictionary, reference and links
* Only rely on `UInt8List` so it is usable on web

## Usage

```dart
import 'package:dart_mobi/dart_mobi.dart';
import "dart:io";
import "dart:convert";
void main() async {
  final data = await File("example/980.mobi").readAsBytes();
  final mobiData = await DartMobiReader.read(data);
  final rawml = mobiData.parseOpt(true, true, false);
  print(utf8.decode(List<int>.from(rawml.markup!.data!)));
}
```

## TODO

* Write mobi files
* finish encryption