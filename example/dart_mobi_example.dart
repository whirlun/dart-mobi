import 'package:dart_mobi/dart_mobi.dart';
import "dart:io";

import 'package:dart_mobi/src/dart_mobi_reader.dart';

void main() async {
  final data = await File("980.mobi").readAsBytes();
  final mobiData = await DartMobiReader.read(data);
}
