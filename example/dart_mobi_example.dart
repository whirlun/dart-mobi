import 'package:dart_mobi/dart_mobi.dart';
import "dart:io";
import "dart:convert";
void main() async {
  final data = await File("example/980.mobi").readAsBytes();
  final mobiData = await DartMobiReader.read(data);
  final rawml = mobiData.parseOpt(true, true, false);
  print(utf8.decode(List<int>.from(rawml.markup!.data!)));
}
