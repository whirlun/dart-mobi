import 'dart:typed_data';
import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_rawml.dart';

import 'dart_mobi_encryption.dart';

class MobiData {
  bool kf8 = true;
  int kf8BoundaryOffset = mobiNotSet;
  MobiPdbHeader? pdbHeader;
  MobiRecord0Header? record0header;
  MobiHeader? mobiHeader;
  MobiExthHeader? mobiExthHeader;
  MobiPdbRecord? mobiPdbRecord;
  MobiData? next;
  MobiDrm? drm;
  MobiRawml rawml = MobiRawml();

  MobiData();
}

class MobiPdbHeader {
  String? name; // 0 database name title + author
  int? attributes; // 32
  int? version; // 34
  int? creationTime; // 36
  int? modificationTime; // 40
  int? backupTime; // 44
  int? modificationNumber; // 48
  int? appInfoOffset; // 52
  int? sortInfoOffset; // 56
  String? type; // 60
  String? creator; // 64
  int? uid; //68
  int? nextRecordListOffset; // 72
  int? recordCount; // 76
  @override
  String toString() {
    return 'MobiPdbHeader{name: $name, attributes: $attributes, version: $version, creationTime: $creationTime, modificationTime: $modificationTime, backupTime: $backupTime, modificationNumber: $modificationNumber, appInfoOffset: $appInfoOffset, sortInfoOffset: $sortInfoOffset, type: $type, creator: $creator, uid: $uid, nextRecordListOffset: $nextRecordListOffset, recordCount: $recordCount}';
  }

  MobiPdbHeader();
}

class MobiRecord0Header {
  int?
      compressionType; // 0 1 == no compression, 2 = PalmDOC compression, 17480 = HUFF/CDIC compression
  // int unused; // 2
  int? textLength; // 4 uncompressed length
  int? textRecordCount; // 8
  int? textRecordSize; // 10 max size of each record always 4096
  int?
      encryptionType; // 12 0 == no encryption, 1 = Old Mobipocket Encryption, 2 = Mobipocket Encryption
  int? unknown; // 14 usually 0
  @override
  String toString() {
    return 'MobiRecord0Header{compressionType: $compressionType, textLength: $textLength, textRecordCount: $textRecordCount, textRecordSize: $textRecordSize, encryptionType: $encryptionType, unknown: $unknown}';
  }

  MobiRecord0Header();
}

class MobiHeader {
  String? magic; // 16 "MOBI"
  int? headerSize; // 20 length of header including magic length
  int? mobiType; // 24
  MobiEncoding? encoding; // 28
  int? uid; // 32
  int? version; // 36
  int? orthographicIndex; // 40 UINT32_MAX if not net
  int? inflectionIndex; // 44 UINT32_MAX if not set
  int? namesIndex; // 48 UINT32_MAX if not set
  int? keysIndex; //52 UINT32_MAX if not set
  int? extra0Index; // 56 UINT32_MAX if not set
  int? extra1Index; // 60 UINT32_MAX if not set
  int? extra2Index; // 64 UINT32_MAX if not set
  int? extra3Index; // 68 UINT32_MAX if not set
  int? extra4Index; // 72 UINT32_MAX if not set
  int? extra5Index; // 76 UINT32_MAX if not set
  int? nonTextIndex; //80
  int? fullNameOffset; // 84 offset in record 0 of the full name of the book
  int? fullNameLength; // 88
  int?
      locale; // 92 first byte is main language: 09 = English, next byte is dialect, 08 = British, 04 = US
  int? dictInputLang; // 96
  int? dictOutputLang; // 100
  int? minVersion; // 104
  int? imageIndex; // 108 first record number containing an image
  int? huffRecordIndex; // 112 first huffman compression record
  int? huffRecordCount; // 116 huffman compression record count
  int? datpRecordIndex; // 120 section number of DATP record
  int? datpRecordCount; // 124 DATP records count
  int? exthFlags; // 128 if bit 6 is set then there's an exth record
  // 32 unknown bytes usually 0
  int? unknown6; // 164 UINT32_MAX
  int? drmOffset; // 168 offset to DRM key info, UINT32_MAX if no DRM
  int? drmCount; // 172 number of entries in DRM info
  int? drmSize; // 176 number of bytes in DRM info
  int? drmFlags; // 180 some flags, bit 0 set if password encrypted
  // 8 unknown bytes
  int? firstTextIndex; // 192 section number of first text record
  int? lastTextIndex; // 194
  int? fdstIndex; // 192 KF8 section number of FDST record
  int? fdstSectionCount; // 196 KF8
  int? fcisIndex; // 200
  int? fcisCount; // 204
  int? flisIndex; // 208
  int? flisCount; // 212
  int? unknown10; // 216
  int? unknown11; // 220
  int? srcsIndex; // 224
  int? srcsCount; // 228
  int? unknown12; // 232
  int? unknown13; // 236
  // int fill 0;
  int? extraFlags; // 242
  int? ncxIndex; // 246
  int? unknown14; // 248
  int? fragmentIndex; // 248 KF8
  int? unknown15; // 252
  int? skeletonIndex; // 252 KF8
  int? datpIndex; // 256
  int? unknown16; //260
  int? guideIndex; // 260 KF8
  int? unknown17; // 264
  int? unknown18; //268
  int? unknown19; //272
  int? unknown20; // 276
  String? fullname; // variable offset

  MobiHeader();
}

enum MobiEncoding {
  CP1252(value: 1252),
  UTF8(value: 65001),
  UTF16(value: 65002);

  const MobiEncoding({required this.value});
  static MobiEncoding fromValue(int value) {
    return MobiEncoding.values.firstWhere((element) => element.value == value);
  }

  final int value;
}

// metadata and data of an EXTH record, forming a linked list
class MobiExthHeader {
  int? tag; // 32 bit
  int? size; // 32 bit
  Uint8List? data;
  MobiExthHeader? next;

  @override
  String toString() {
    return 'MobiExthHeader{tag: $tag, size: $size}';
  }

  MobiExthHeader();
}

class MobiPdbRecord {
  int? offset;
  int? size;
  int? attrbutes;
  int? uid;
  Uint8List? data;
  MobiPdbRecord? next;
  @override
  String toString() {
    return 'MobiPdbRecord{offset: $offset, size: $size, attrbutes: $attrbutes, uid: $uid}';
  }

  MobiPdbRecord();
}

enum MobiExthTag {
  drmServer(1),
  drmCommerce(2),
  drmBookBase(3),

  title(99),
  author(100),
  publisher(101),
  imprint(102),
  description(103),
  isbm(104),
  subject(105),
  publishingDate(106),
  review(107),
  contributer(108),
  rights(109),
  subjectCode(110),
  type(111),
  source(112),
  asin(113),
  version(114),
  sample(115),
  startReading(116),
  adult(117),
  price(118),
  curency(119),
  kf8Boundary(121),
  fixedLayout(122),
  bookType(123),
  orientationLock(124),
  countResouces(125),
  originalResolution(126),
  zeroGutter(127),
  zeroMargin(128),
  kf8CoverUri(129),
  resCoffSet(131),
  regionMag(132),

  dictName(200),
  coverOffset(201),
  thumbOffset(202),
  hasFakeCover(203),
  creatorSoft(204),
  creatorMajor(205),
  creatorMinor(206),
  creatorBuild(207),
  waterMark(208),
  tamperKeys(209),

  fontSignature(300),

  clippingLimit(401),
  publisherLimit(402),
  unknown403(403),
  ttsDisable(404),
  readForFree(405),
  rental(406),
  unknown407(407),
  unknown450(450),
  unknown451(451),
  unknown452(452),
  unknown453(453),

  docType(501),
  lastUpdate(502),
  updatedTitle(503),
  asin504(504),
  titleFileAs(508),
  creatorFileAs(517),
  publisherFileAs(522),
  language(524),
  alignment(525),
  creatorString(526),
  pageDir(527),
  overrideFonts(528),
  sourceDesc(529),
  dictLangIn(531),
  dictLangout(532),
  inputSource(534),
  creatorBuildRev(535),

  unknown(-1);

  final int value;
  const MobiExthTag(this.value);
  static MobiExthTag fromValue(int value) {
    for (var e in MobiExthTag.values) {
      if (e.value == value) {
        return e;
      }
    }
    return MobiExthTag.unknown;
  }
}
