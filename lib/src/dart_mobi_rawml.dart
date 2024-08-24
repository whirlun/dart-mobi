import 'dart:typed_data';

import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';
import 'package:dart_mobi/src/dart_mobi_exception.dart';
import 'package:dart_mobi/src/dart_mobi_utils.dart';

extension RawmlParser on MobiData {
  MobiRawml parseOpt(bool parseToc, bool parseDict, bool reconstruct) {
    final maxLen = getMaxTextSize(this);
    if (maxLen == mobiNotSet) {
      throw MobiInvalidDataException("Text Length Too Long");
    }

    int length = maxLen;
  }

  String getRawml(int length) {
    if (record0header!.textLength! > length) {
      throw MobiInvalidParameterException(
          "Text Length in Record 0 is Longer Than Declared Length");
    }
  }
}

class MobiRawml {
  int version = 0;
  MobiFdst? fdst;
  MobiIndx? skel;
  MobiIndx? frag;
  MobiIndx? guide;
  MobiIndx? ncx;
  MobiIndx? orth;
  MobiIndx? infl;
  MobiPart? flow;
  MobiPart? markup;
  MobiPart? resources;
}

class MobiFdst {
  int fdstSectionCount = 0;
  List<int> fdstSectionStarts = [];
  List<int> fdstSectionEnds = [];
}

class MobiIndx {
  int type = 0;
  int entriesCount = 0;
  MobiEncoding? encoding;
  int totalEntriesCount = 0;
  int ordtOffset = 0;
  int ligtOffset = 0;
  int ligtEntriesCount = 0;
  int cncxRecordsCount = 0;
  MobiPdbRecord? cncxRecord;
  String orthIndexName = "";
}

class MobiPart {
  int uid = 0;
  MobiFileType fileType = MobiFileType.unknown;
  int size = 0;
  Uint8List? data;
  MobiPart? next;
}

enum MobiFileType {
  unknown,
  html,
  css,
  svg,
  opf,
  ncx,
  jpg,
  gif,
  png,
  bmp,
  otf,
  ttf,
  mp3,
  mpg,
  pdf,
  font,
  audio,
  video,
  eof
}
