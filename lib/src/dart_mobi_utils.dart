import 'dart:typed_data';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';
import 'package:dart_mobi/src/dart_mobi_exception.dart';
import 'package:dart_mobi/src/dart_mobi_rawml.dart';
import 'package:dart_mobi/src/dart_mobi_reader.dart';

bool isMobiPocket(MobiData data) {
  if (data.pdbHeader == null) {
    return false;
  }
  return data.pdbHeader?.type == "BOOK" && data.pdbHeader?.creator == "MOBI";
}

bool isTextRead(MobiData data) {
  if (data.pdbHeader == null) {
    return false;
  }
  return data.pdbHeader?.type == "TEXt" && data.pdbHeader?.creator == "REAd";
}

int getFileVersion(MobiData data) {
  int version = 1;
  if (isMobiPocket(data)) {
    final headerSize = data.mobiHeader!.headerSize!;
    if (headerSize < mobiHeaderV2Size) {
      version = 2;
    } else if (data.mobiHeader!.version! > 1) {
      if ((data.mobiHeader!.version! > 2 && headerSize < mobiHeaderV3Size) ||
          (data.mobiHeader!.version! > 3 && headerSize < mobiHeaderV4Size) ||
          (data.mobiHeader!.version! > 5 && headerSize < mobiHeaderV5Size)) {
        return mobiNotSet;
      }
      version = data.mobiHeader!.version!;
    }
  }
  return version;
}

int get32BE(List<int> data) {
  var val = data[0] << 24;
  val |= data[1] << 16;
  val |= data[2] << 8;
  val |= data[3];
  return val;
}

void swapMobiData(MobiData data) {
  final temp = MobiData();
  temp.record0header = data.record0header;
  temp.mobiHeader = data.mobiHeader;
  temp.mobiExthHeader = data.mobiExthHeader;
  data.record0header = data.next?.record0header;
  data.mobiHeader = data.next?.mobiHeader;
  data.mobiExthHeader = data.next?.mobiExthHeader;
  data.next?.record0header = temp.record0header;
  data.next?.mobiHeader = temp.mobiHeader;
  data.next?.mobiExthHeader = temp.mobiExthHeader;
}

getMaxTextSize(MobiData m) {
  if (m.record0header!.textRecordCount! > 0) {
    int maxRecordSize = getMaxTextRecordSize(m);
    int maxSize = m.record0header!.textRecordCount! * maxRecordSize;
    if (m.mobiHeader != null && getFileVersion(m) <= 3) {
      if (m.record0header!.textLength! > maxSize) {
        maxSize = m.record0header!.textLength!;
      }
    }
    if (maxSize > rawTextSizeMax) {
      return mobiNotSet;
    }
    return maxSize;
  }
}

int getMaxTextRecordSize(MobiData m) {
  int maxRecordSize = record0TextSizeMax;
  if (m.record0header != null) {
    if (m.record0header!.textRecordSize! > record0TextSizeMax) {
      maxRecordSize = m.record0header!.textRecordSize!;
    }
    if (m.mobiHeader != null && getFileVersion(m) <= 3) {
      int textLength = maxRecordSize * m.record0header!.textRecordCount!;
      if (textLength <= rawTextSizeMax &&
          m.record0header!.textLength! > textLength) {
        maxRecordSize = record0TextSizeMax * 2;
      }
    }
  }
  return maxRecordSize;
}

int getKf8Offset(MobiData data) {
  if (data.kf8 && data.kf8BoundaryOffset != mobiNotSet) {
    return data.kf8BoundaryOffset + 1;
  }
  return 0;
}

int removeZeros(Uint8List buffer) {
  var pos = buffer.indexWhere((i) => i == 0);
  if (pos == -1) {
    return buffer.length;
  }
  pos++;
  int distance = 1;
  while (pos < buffer.length) {
    if (buffer[pos] != 0) {
      buffer[pos - distance] = buffer[pos];
    } else {
      distance++;
    }
    pos++;
  }
  return buffer.length - distance;
}

bool existsFdst(MobiData data) {
  if (data.mobiHeader == null || getFileVersion(data) <= 3) {
    return false;
  }
  if (getFileVersion(data) >= 8) {
    if (data.mobiHeader?.fdstIndex != null &&
        data.mobiHeader?.lastTextIndex != 65535) {
      return true;
    }
  } else {
    if ((data.mobiHeader?.fdstSectionCount != null &&
            data.mobiHeader!.fdstSectionCount! > 1) &&
        (data.mobiHeader?.lastTextIndex != null &&
            data.mobiHeader?.lastTextIndex! != 65535)) {
      return true;
    }
  }
  return false;
}

bool existsInfl(MobiData data) {
  if (data.mobiHeader == null) {
    return false;
  }
  if (data.mobiHeader?.inflectionIndex != null &&
      data.mobiHeader!.inflectionIndex != mobiNotSet) {
    return true;
  }
  return false;
}

bool existsGuideIndx(MobiData data) {
  if (data.mobiHeader == null) {
    return false;
  }
  if (data.mobiHeader?.guideIndex == null ||
      data.mobiHeader!.guideIndex == mobiNotSet) {
    return false;
  }
  return true;
}

bool existsOrth(MobiData data) {
  if (data.mobiHeader == null) {
    return false;
  }
  if (data.mobiHeader?.orthographicIndex == null ||
      data.mobiHeader!.orthographicIndex == mobiNotSet) {
    return false;
  }
  return true;
}

bool isDictionary(MobiData data) {
  if (getFileVersion(data) < 8 && existsOrth(data)) {
    return true;
  }
  return false;
}

bool existsNcx(MobiData data) {
  if (data.mobiHeader == null) {
    return false;
  }
  if (data.mobiHeader?.ncxIndex == null ||
      data.mobiHeader!.ncxIndex == mobiNotSet) {
    return false;
  }
  return true;
}

bool existsSkelIndx(MobiData data) {
  if (data.mobiHeader == null) {
    return false;
  }
  if (data.mobiHeader?.skeletonIndex == null ||
      data.mobiHeader!.skeletonIndex == mobiNotSet) {
    return false;
  }
  return true;
}

bool existsFragIndx(MobiData data) {
  if (data.mobiHeader == null) {
    return false;
  }
  if (data.mobiHeader?.fragmentIndex == null ||
      data.mobiHeader!.fragmentIndex == mobiNotSet) {
    return false;
  }
  return true;
}

int getFdstRecordNumber(MobiData data) {
  if (data.mobiHeader == null) {
    return mobiNotSet;
  }
  final offset = getKf8Offset(data);
  if (data.mobiHeader?.fdstIndex != null &&
      data.mobiHeader!.fdstIndex! != mobiNotSet) {
    if (data.mobiHeader?.fdstSectionCount != null &&
        data.mobiHeader!.fdstSectionCount! > 1) {
      return data.mobiHeader!.fdstIndex! + offset;
    }
  }
  if (data.mobiHeader?.fdstSectionCount != null &&
      data.mobiHeader!.fdstSectionCount! > 1) {
    if (data.mobiHeader?.lastTextIndex != null) {
      return data.mobiHeader!.lastTextIndex!;
    }
  }
  return mobiNotSet;
}

bool isRawmlKf8(MobiRawml rawml) {
  if (rawml.version != mobiNotSet && rawml.version >= 8) {
    return true;
  }
  return false;
}

bool isHybrid(MobiData data) {
  if (data.kf8BoundaryOffset != mobiNotSet) {
    return true;
  }
  return false;
}

int getFirstResourceRecord(MobiData data) {
  if (isHybrid(data) && data.kf8) {
    if (data.next?.mobiHeader?.imageIndex != null) {
      return data.next!.mobiHeader!.imageIndex!;
    }
  }
  if (data.mobiHeader?.imageIndex != null) {
    return data.mobiHeader!.imageIndex!;
  }
  return mobiNotSet;
}

void addFontResource(MobiPart part) {
  part.data = decodeFontResource(part);
  part.size = part.data!.length;
  part.fileType = determineFontType(part.data!, part.size);
  if (part.fileType == MobiFileType.unknown) {
    part.fileType = MobiFileType.ttf;
  }
}

void addAudioResource(MobiPart part) {
  part.data = decodeAudioResource(part);
  part.size = part.data!.length;
  part.fileType = MobiFileType.mp3;
}

void addVideoResource(MobiPart part) {
  part.data = decodeVideoResource(part);
  part.size = part.data!.length;
  part.fileType = MobiFileType.mpg;
}

MobiFileType determineFontType(Uint8List data, int size) {
  final otfMagic = "OTTO";
  final ttfMagic = "\\0\\1\\0\\0";
  final ttf2Magic = "true";
  final eq = ListEquality().equals;
  if (size > 4) {
    if (eq(data.sublist(0, 4), otfMagic.codeUnits)) {
      return MobiFileType.otf;
    }
    if (eq(data.sublist(0, 4), ttfMagic.codeUnits)) {
      return MobiFileType.ttf;
    }
    if (eq(data.sublist(0, 4), ttf2Magic.codeUnits)) {
      return MobiFileType.ttf;
    }
  }
  return MobiFileType.unknown;
}

Uint8List decodeFontResource(MobiPart part) {
  if (part.size < fontHeaderLen) {
    throw MobiInvalidDataException("Font resource too short");
  }
  final buffer = MobiBuffer(part.data!, 0);
  final header = FontHeader();
  header.magic = buffer.getString(4);
  if (header.magic != "FONT") {
    throw MobiInvalidDataException("Invalid magic for font resource");
  }
  header.decodedSize = buffer.getInt32();
  if (header.decodedSize == 0 || header.decodedSize > fontSizeMax) {
    throw MobiInvalidDataException("Invalid decoded size for font resource");
  }
  header.flags = buffer.getInt32();
  header.dataOffset = buffer.getInt32();
  header.xorKenLen = buffer.getInt32();
  header.xorKeyOffset = buffer.getInt32();
  final zlibFlag = 1;
  final xorFlag = 2;
  if (header.flags & xorFlag != 0 && header.xorKenLen > 0) {
    if (header.dataOffset > header.xorKeyOffset ||
        header.xorKenLen > buffer.maxlen ||
        header.xorKeyOffset > buffer.maxlen - header.xorKenLen) {
      throw MobiInvalidDataException("Invalid obfuscated font data offsets");
    }
    buffer.setPos(header.dataOffset);
    int i = 0;
    final xorLimit = header.xorKenLen * mobiFontObfuscatedBufferCount;
    while (buffer.offset < buffer.maxlen && i < xorLimit) {
      buffer.data[buffer.offset++] ^=
          buffer.data[header.xorKeyOffset + (i % header.xorKenLen)];
      i++;
    }
  }
  buffer.setPos(header.dataOffset);
  var decodedFont = List<int>.empty();
  final encodedSize = (buffer.maxlen - buffer.offset);
  final encodedFont = buffer.data.sublist(buffer.offset);
  if (header.flags & zlibFlag != 0) {
    ZLibDecoder zlib = ZLibDecoder();
    decodedFont = zlib.decodeBytes(encodedFont);
    if (decodedFont.length != header.decodedSize) {
      throw MobiInvalidDataException(
          "Decompressed font size is different from declared size.");
    }
  } else {
    if (header.decodedSize < encodedSize) {
      throw MobiInvalidDataException("Font size is larger than delcared size.");
    }
    decodedFont = encodedFont;
  }
  return Uint8List.fromList(decodedFont);
}

Uint8List decodeAudioResource(MobiPart part) {
  if (part.size < mediaHeaderLen) {
    throw MobiInvalidDataException("Audio resource too short");
  }
  final buffer = MobiBuffer(part.data!, 0);
  final magic = buffer.getString(4);
  if (magic != "AUDI") {
    throw MobiInvalidDataException("Invalid magic for audio resource");
  }
  final offset = buffer.getInt32();
  buffer.setPos(offset);
  return buffer.data.sublist(buffer.offset);
}

Uint8List decodeVideoResource(MobiPart part) {
  if (part.size < mediaHeaderLen) {
    throw MobiInvalidDataException("Video resource too short");
  }
  final buffer = MobiBuffer(part.data!, 0);
  final magic = buffer.getString(4);
  if (magic != "VIDE") {
    throw MobiInvalidDataException("Invalid magic for video resource");
  }
  final offset = buffer.getInt32();
  buffer.setPos(offset);
  return buffer.data.sublist(buffer.offset);
}

int base32Decode(Uint8List encoded) {
  int i = 0;
  while (encoded[i] == '0'.codeUnits[0]) {
    i++;
  }
  int encodedLength = encoded.length - i;
  if (encodedLength > 6) {
    throw MobiInvalidDataException("base32 encoded number too big");
  }
  final base = 32;
  int len = encodedLength;
  int decoded = 0;
  int value = 0;
  for (int j = i; j < encoded.length; j++) {
    int c = encoded[j];
    if (c >= 'A'.codeUnits[0] && c <= 'V'.codeUnits[0]) {
      value = c - 'A'.codeUnits[0] + 10;
    } else if (c >= '0'.codeUnits[0] && c <= '9'.codeUnits[0]) {
      value = c - '0'.codeUnits[0];
    } else {
      throw MobiInvalidDataException("Invalid character in base32 encoded");
    }
    decoded += (value * pow(base, --len)).toInt();
  }
  return decoded;
}

MobiPart? getResourceByUid(MobiRawml rawml, int uid) {
  if (rawml.resources == null) {
    return null;
  }
  MobiPart? curr = rawml.resources;
  while (curr != null) {
    if (curr.uid == uid) {
      return curr;
    }
    curr = curr.next;
  }
  return null;
}

MobiFileMeta getFileMetaByType(MobiFileType type) {
  MobiFileMeta meta = MobiFileMeta();
  if (!mobiFileMeta.containsKey(type)) {
    meta.fileType = MobiFileType.unknown;
    meta.extension = mobiFileMeta[MobiFileType.unknown]!["ext"]!;
    meta.mimeType = mobiFileMeta[MobiFileType.unknown]!["mime"]!;
  }
  meta.fileType = type;
  meta.extension = mobiFileMeta[type]!["ext"]!;
  meta.mimeType = mobiFileMeta[type]!["mime"]!;
  return meta;
}

bool mobiIsKf8(MobiData data) {
  final version = getFileVersion(data);
  if (version != mobiNotSet && version >= 8) {
    return true;
  }
  return false;
}

MobiEncoding getEncoding(MobiData data) {
  if (data.mobiHeader?.encoding == MobiEncoding.UTF8) {
    return MobiEncoding.UTF8;
  }
  return MobiEncoding.CP1252;
}

int ligatureToUtf16(int byte1, int byte2) {
  final uniReplacement = 0xfffd;
  int ligature = uniReplacement;
  final ligOE = 0x152;
  final ligoe = 0x153;
  final ligAE = 0xc6;
  final ligae = 0xe6;
  final ligss = 0xdf;
  switch (byte1) {
    case 1:
      if (byte2 == 0x45) {
        ligature = ligOE;
      }
    case 2:
      if (byte2 == 0x65) {
        ligature = ligoe;
      }
    case 3:
      if (byte2 == 0x45) {
        ligature = ligAE;
      }
    case 4:
      if (byte2 == 0x65) {
        ligature = ligae;
      }
    case 5:
      if (byte2 == 0x73) {
        ligature = ligss;
      }
  }
  return ligature;
}

int ligtureToCp1252(int byte1, int byte2) {
  int ligature = 0;
  final ligOE = 0x8c;
  final ligoe = 0x9c;
  final ligAE = 0xc6;
  final ligae = 0xe6;
  final ligss = 0xdf;
  switch (byte1) {
    case 1:
      if (byte2 == 0x45) {
        ligature = ligOE;
      }
    case 2:
      if (byte2 == 0x65) {
        ligature = ligoe;
      }
    case 3:
      if (byte2 == 0x45) {
        ligature = ligAE;
      }
    case 4:
      if (byte2 == 0x65) {
        ligature = ligae;
      }
    case 5:
      if (byte2 == 0x73) {
        ligature = ligss;
      }
  }
  return ligature;
}

const setBits = [
  0,
  1,
  1,
  2,
  1,
  2,
  2,
  3,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  2,
  3,
  3,
  4,
  3,
  4,
  4,
  5,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  3,
  4,
  4,
  5,
  4,
  5,
  5,
  6,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  4,
  5,
  5,
  6,
  5,
  6,
  6,
  7,
  5,
  6,
  6,
  7,
  6,
  7,
  7,
  8,
];

int mobiBigCount(int byte) {
  return setBits[byte];
}

class FontHeader {
  String magic = "";
  int decodedSize = 0;
  int flags = 0;
  int dataOffset = 0;
  int xorKenLen = 0;
  int xorKeyOffset = 0;
}
