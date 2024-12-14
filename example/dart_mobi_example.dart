import 'package:dart_mobi/dart_mobi.dart';
import 'package:dart_mobi/src/dart_mobi_rawml.dart';
import "dart:io";
import "dart:convert";

import 'package:dart_mobi/src/dart_mobi_reader.dart';

void main() async {
  final data = await File("quick.azw3").readAsBytes();
  final mobiData = await DartMobiReader.read(data);
  print(mobiData.drm);
  final rawml = mobiData.parseOpt(false, false, false);
  print(rawml.skel);
}
