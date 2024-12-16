import 'dart:typed_data';
import 'dart:math' show min;

import 'package:collection/collection.dart';
import 'package:dart_mobi/src/dart_mobi_encryption.dart';
import 'package:dart_mobi/src/dart_mobi_rawml.dart';
import 'package:dart_mobi/src/dart_mobi_utils.dart';

import 'dart_mobi_data.dart';
import 'dart_mobi_exception.dart';
import 'dart_mobi_const.dart';

class DartMobiReader {
  static Future<MobiData> read(Uint8List data) async {
    final mobiData = MobiData();
    final buffer = MobiBuffer(data, 0);
    mobiData.pdbHeader = await readPdbHeader(buffer);
    if (mobiData.pdbHeader!.type != "BOOK" &&
        mobiData.pdbHeader!.type != "MOBI") {
      throw MobiUnsupportedTypeException(mobiData.pdbHeader!.type);
    }

    if (mobiData.pdbHeader!.recordCount == 0) {
      throw MobiInvalidDataException("No Record Found");
    }
    final record = await readPdbRecordList(mobiData.pdbHeader!, buffer);
    await readPdbRecord(record, buffer);
    mobiData.mobiPdbRecord = record;
    mobiData.record0header = await readRecord0Header(mobiData, record, 0);

    if (mobiData.record0header!.encryptionType == mobiEncryptionV1) {
      EncryptionUtils.setDrmKey(mobiData, null);
    }
    if (mobiData.mobiExthHeader != null) {
      final boundaryRecNumber = getKf8BoundarySeqNumber(mobiData);
      if (boundaryRecNumber != mobiNotSet && boundaryRecNumber < 4294967295) {
        mobiData.kf8BoundaryOffset = boundaryRecNumber;
        mobiData.next = MobiData();
        mobiData.next!.pdbHeader = mobiData.pdbHeader;
        mobiData.next!.mobiPdbRecord = mobiData.mobiPdbRecord;
        mobiData.next!.drm = mobiData.drm;
        mobiData.next!.next = mobiData;
        mobiData.next!.record0header = await readRecord0Header(mobiData.next!,
            mobiData.next!.mobiPdbRecord!, boundaryRecNumber + 1);
        if (mobiData.kf8) {
          swapMobiData(mobiData);
        }
      }
    }
    var curr = mobiData.mobiExthHeader;
    while (curr != null) {
      curr = curr.next;
    }

    return mobiData;
  }

  static Future<MobiPdbHeader> readPdbHeader(MobiBuffer buffer) async {
    final mobiPdbHeader = MobiPdbHeader();
    mobiPdbHeader.name = buffer.getString(palmdbNameLength);
    mobiPdbHeader.attributes = buffer.getInt16();
    mobiPdbHeader.version = buffer.getInt16();
    mobiPdbHeader.creationTime = buffer.getInt32();
    mobiPdbHeader.modificationTime = buffer.getInt32();
    mobiPdbHeader.backupTime = buffer.getInt32();
    mobiPdbHeader.modificationNumber = buffer.getInt32();
    mobiPdbHeader.appInfoOffset = buffer.getInt32();
    mobiPdbHeader.sortInfoOffset = buffer.getInt32();
    mobiPdbHeader.type = buffer.getString(4);
    mobiPdbHeader.creator = buffer.getString(4);
    mobiPdbHeader.uid = buffer.getInt32();
    mobiPdbHeader.nextRecordListOffset = buffer.getInt32();
    mobiPdbHeader.recordCount = buffer.getInt16();
    return mobiPdbHeader;
  }

  static Future<MobiPdbRecord> readPdbRecordList(
      MobiPdbHeader header, MobiBuffer buffer) async {
    MobiPdbRecord head = MobiPdbRecord();
    var curr = head;
    for (int i = 0; i < header.recordCount!; i++) {
      if (buffer.offset + 8 > buffer.maxlen) {
        throw MobiInvalidDataException("Invalid Record");
      }
      if (i > 0) {
        curr.next = MobiPdbRecord();
        curr = curr.next!;
      }
      curr.offset = buffer.getInt32();
      curr.attrbutes = buffer.getInt8();
      final h = buffer.getInt8();
      final l = buffer.getInt16();
      curr.uid = h << 16 | l;
      curr.next = null;
    }
    return head;
  }

  static Future<void> readPdbRecord(
      MobiPdbRecord record, MobiBuffer buffer) async {
    MobiPdbRecord? curr = record;
    while (curr != null) {
      MobiPdbRecord? next;
      int size;
      if (curr.next != null) {
        next = curr.next!;
        size = next.offset! - curr.offset!;
      } else {
        final diff = buffer.maxlen - curr.offset!;
        if (diff <= 0) {
          throw MobiInvalidDataException("Wrong Record Size: $diff");
        }
        size = diff;
        next = null;
      }
      curr.size = size;
      try {
        buffer.seek(curr.offset!, true);
        curr.data = buffer.getStringAsByte(curr.size!);
      } on MobiBufferOverflowException {
        throw MobiInvalidDataException("Truncated data in record ${curr.uid}");
      }
      curr = next;
    }
  }

  static Future<MobiRecord0Header> readRecord0Header(
      MobiData data, MobiPdbRecord record, int seqNumber) async {
    final record0 = getRecordBySeqNumber(record, seqNumber);
    if (record0 == null) {
      throw MobiInvalidDataException("Record 0 not found");
    }
    if (record0.size! < record0HeaderLength) {
      throw MobiInvalidDataException("Record 0 is too short");
    }
    final buffer = MobiBuffer(record0.data!, 0);
    final compression = buffer.getInt16();
    buffer.seek(2);
    if (compression != compressionNone &&
        compression != compressionPalmDoc &&
        compression != compressionHuffCdic) {
      throw MobiInvalidDataException("Unsupported compression: $compression");
    }
    final record0Header = MobiRecord0Header();
    record0Header.compressionType = compression;
    record0Header.textLength = buffer.getInt32();
    record0Header.textRecordCount = buffer.getInt16();
    record0Header.textRecordSize = buffer.getInt16();
    record0Header.encryptionType = buffer.getInt16();
    record0Header.unknown = buffer.getInt16();

    if (isMobiPocket(data)) {
      try {
        data.mobiHeader = await readMobiHeader(record0Header, buffer);
        data.mobiExthHeader = await readExthHeader(buffer);
      } catch (e) {
        //these headers may not exist so do nothing if they didn't load correctly
      }
    }
    return record0Header;
  }

  static Future<MobiHeader> readMobiHeader(
      MobiRecord0Header record0, MobiBuffer buffer) async {
    var header = MobiHeader();
    bool isKF8 = false;
    header.magic = buffer.getString(4);
    if (header.magic != mobiHeaderMagic) {
      throw MobiInvalidDataException("Invalid Magic: ${header.magic}");
    }
    header.headerSize = buffer.getInt32();
    if (header.headerSize! == 0) {
      header.headerSize = 24;
    }
    int saved_maxlen = buffer.maxlen;

    // set maxlen to header size + offset - 8 just here to read the header
    if (buffer.maxlen > header.headerSize! + buffer.offset - 8) {
      buffer.maxlen = header.headerSize! + buffer.offset - 8;
    }

    header.mobiType = buffer.getInt32();

    try {
      final encoding = MobiEncoding.fromValue(buffer.getInt32());
      header.encoding = encoding;
    } on StateError {
      throw MobiInvalidDataException("Invalid Encoding in Mobi Header");
    }

    header.uid = buffer.getInt32();
    header.version = buffer.getInt32();
    if (header.headerSize! >= mobiHeaderV7Size && header.version! == 8) {
      isKF8 = true;
    }
    header.orthographicIndex = buffer.getInt32();
    header.inflectionIndex = buffer.getInt32();
    header.namesIndex = buffer.getInt32();
    header.keysIndex = buffer.getInt32();
    header.extra0Index = buffer.getInt32();
    header.extra1Index = buffer.getInt32();
    header.extra2Index = buffer.getInt32();
    header.extra3Index = buffer.getInt32();
    header.extra4Index = buffer.getInt32();
    header.extra5Index = buffer.getInt32();
    header.nonTextIndex = buffer.getInt32();
    header.fullNameOffset = buffer.getInt32();
    header.fullNameLength = buffer.getInt32();
    header.locale = buffer.getInt32();
    header.dictInputLang = buffer.getInt32();
    header.dictOutputLang = buffer.getInt32();
    header.minVersion = buffer.getInt32();
    header.imageIndex = buffer.getInt32();
    header.huffRecordIndex = buffer.getInt32();
    header.huffRecordCount = buffer.getInt32();
    header.datpRecordIndex = buffer.getInt32();
    header.datpRecordCount = buffer.getInt32();
    header.exthFlags = buffer.getInt32();
    buffer.seek(32);
    header.unknown6 = buffer.getInt32();
    header.drmOffset = buffer.getInt32();
    header.drmCount = buffer.getInt32();
    header.drmSize = buffer.getInt32();
    header.drmFlags = buffer.getInt32();
    buffer.seek(8);
    if (isKF8) {
      header.fdstIndex = buffer.getInt32();
    } else {
      header.firstTextIndex = buffer.getInt16();
      header.lastTextIndex = buffer.getInt16();
    }
    header.fdstSectionCount = buffer.getInt32();
    header.fcisIndex = buffer.getInt32();
    header.fcisCount = buffer.getInt32();
    header.flisIndex = buffer.getInt32();
    header.flisCount = buffer.getInt32();
    header.unknown10 = buffer.getInt32();
    header.unknown11 = buffer.getInt32();
    header.srcsIndex = buffer.getInt32();
    header.srcsCount = buffer.getInt32();
    header.unknown12 = buffer.getInt32();
    header.unknown13 = buffer.getInt32();
    buffer.seek(2);
    header.extraFlags = buffer.getInt16();
    header.ncxIndex = buffer.getInt32();
    if (isKF8) {
      header.fragmentIndex = buffer.getInt32();
      header.skeletonIndex = buffer.getInt32();
    } else {
      header.unknown14 = buffer.getInt32();
      header.unknown15 = buffer.getInt32();
    }

    header.datpIndex = buffer.getInt32();
    if (isKF8) {
      header.guideIndex = buffer.getInt32();
    } else {
      header.unknown16 = buffer.getInt32();
    }

    header.unknown17 = buffer.getInt32();
    header.unknown18 = buffer.getInt32();
    header.unknown19 = buffer.getInt32();
    header.unknown20 = buffer.getInt32();

    if (buffer.maxlen > buffer.offset) {
      buffer.offset = buffer.maxlen;
    }

    buffer.maxlen = saved_maxlen;
    if (header.fullNameOffset != 0 && header.fullNameLength != 0) {
      final savedOffset = buffer.offset;
      final fullNameLength = min(header.fullNameLength!, mobiTitleSizeMax);
      buffer.offset = header.fullNameOffset!;
      header.fullname = buffer.getString(fullNameLength);
      buffer.offset = savedOffset;
    }
    return header;
  }

  static Future<MobiExthHeader> readExthHeader(MobiBuffer buffer) async {
    final exthMagic = buffer.getString(4);
    final exthLength = buffer.getInt32() - 12;
    final recCount = buffer.getInt32();
    if (exthMagic != exthMagic ||
        exthLength + buffer.offset > buffer.maxlen ||
        recCount == 0 ||
        recCount > exthMaxCount) {
      throw MobiInvalidDataException("Invalid EXTH Header");
    }

    final savedMaxLen = buffer.maxlen;
    buffer.maxlen = exthLength + buffer.offset;
    final header = MobiExthHeader();
    var curr = header;
    for (int i = 0; i < recCount; i++) {
      if (curr.data != null) {
        curr.next = MobiExthHeader();
        curr = curr.next!;
      }
      curr.tag = buffer.getInt32();
      curr.size = buffer.getInt32() - 8;
      if (curr.size == 0) {
        continue;
      }

      if (buffer.offset + curr.size! > buffer.maxlen) {
        throw MobiInvalidDataException("record ${curr.tag} too long");
      }

      curr.data = buffer.getStringAsByte(curr.size!);
      curr.next = null;
    }
    buffer.maxlen = savedMaxLen;
    return header;
  }

  static MobiFdst readFdst(MobiData data) {
    var fdst = MobiFdst();
    final fdstRecordNumber = getFdstRecordNumber(data);
    if (fdstRecordNumber == mobiNotSet) {
      throw MobiInvalidDataException("FDST record number not found");
    }
    final fdstRecord =
        getRecordBySeqNumber(data.mobiPdbRecord!, fdstRecordNumber);
    if (fdstRecord == null) {
      throw MobiInvalidDataException("FDST record not found");
    }
    var buffer = MobiBuffer(fdstRecord.data!, 0);
    final fdstMagic = buffer.getString(4);
    final offset = buffer.getInt32();
    final sectionCount = buffer.getInt32();
    if (fdstMagic != "FDST" ||
        sectionCount <= 1 ||
        sectionCount != data.mobiHeader?.fdstSectionCount ||
        offset != 12) {
      throw MobiInvalidDataException(
          "FDST Parse Error, Magic: $fdstMagic, Section Count: $sectionCount, Data Offset: $offset");
    }
    if (buffer.maxlen - buffer.offset < sectionCount * 8) {
      throw MobiInvalidDataException("Record FDST too short");
    }
    fdst.fdstSectionCount = sectionCount;
    fdst.fdstSectionStarts = List.filled(sectionCount, 0);
    fdst.fdstSectionEnds = List.filled(sectionCount, 0);
    for (int i = 0; i < sectionCount; i++) {
      fdst.fdstSectionStarts[i] = buffer.getInt32();
      fdst.fdstSectionEnds[i] = buffer.getInt32();
    }
    return fdst;
  }

  static MobiPdbRecord? getRecordBySeqNumber(
      MobiPdbRecord record, int seqNumber) {
    MobiPdbRecord? curr = record;
    int i = 0;
    while (curr != null) {
      if (i++ == seqNumber) {
        return curr;
      }
      curr = curr.next;
    }
    return null;
  }

  static int getKf8BoundarySeqNumber(MobiData data) {
    final exthTag = getExthRecordByTag(data, MobiExthTag.kf8Boundary);
    if (exthTag != null) {
      var recNumber = decodeExthValue(exthTag.data!, exthTag.size!);
      recNumber--;
      final record = getRecordBySeqNumber(data.mobiPdbRecord!, recNumber);
      if (record != null && record.size! >= boundaryMagic.length) {
        if (String.fromCharCodes(record.data!) == boundaryMagic) {
          return recNumber;
        }
      }
    }
    return mobiNotSet;
  }

  static int decodeExthValue(Uint8List data, int size) {
    var val = 0;
    var i = min(size, 4);
    var s = 0;
    while (i-- != 0) {
      val |= data[s] << (i * 8);
      s++;
    }
    return val;
  }

  static MobiExthHeader? getExthRecordByTag(MobiData data, MobiExthTag tag) {
    if (data.mobiExthHeader == null) {
      return null;
    }

    var curr = data.mobiExthHeader;
    while (curr != null) {
      if (MobiExthTag.fromValue(curr.tag!) == tag) {
        return curr;
      }
      curr = curr.next;
    }
    return null;
  }
}

class MobiBuffer {
  final Uint8List data;
  int offset;
  int maxlen = 0;

  MobiBuffer(this.data, this.offset) {
    maxlen = data.length;
  }

  String getString(int length) {
    if (offset + length > maxlen) {
      throw MobiBufferOverflowException();
    }

    final val = String.fromCharCodes(data.sublist(offset, offset + length));
    offset += length;
    return val;
  }

  Uint8List getStringAsByte(int length) {
    if (offset + length > maxlen) {
      throw MobiBufferOverflowException();
    }
    final val = data.sublist(offset, offset + length);
    offset += length;
    return val;
  }

  int getInt8() {
    if (offset + 1 > maxlen) {
      throw MobiBufferOverflowException();
    }

    final val = data[offset];
    offset += 1;
    return val;
  }

  int getInt16() {
    if (offset + 2 > maxlen) {
      throw MobiBufferOverflowException();
    }
    final val = data[offset] << 8 | data[offset + 1];
    offset += 2;
    return val;
  }

  int getInt32() {
    if (offset + 4 > maxlen) {
      throw MobiBufferOverflowException();
    }

    final val = data[offset] << 24 |
        data[offset + 1] << 16 |
        data[offset + 2] << 8 |
        data[offset + 3];
    offset += 4;
    return val;
  }

  int getInt32Le() {
    if (offset + 4 > maxlen) {
      throw MobiBufferOverflowException();
    }

    final val = data[offset] |
        data[offset + 1] << 8 |
        data[offset + 2] << 16 |
        data[offset + 3] << 24;
    offset += 4;
    return val;
  }

  void seek(int diff, [bool set = false]) {
    if (set) {
      offset = diff;
      return;
    }
    if (diff >= 0) {
      if (offset + diff > maxlen) {
        throw MobiBufferOverflowException();
      }
      offset += diff;
    } else {
      diff = -diff;
      if (offset >= diff) {
        offset -= diff;
      } else {
        throw MobiBufferOverflowException();
      }
    }
  }

  (int, int) getVarLen(int len, {backward = false}) {
    bool hasStop = false;
    int val = 0;
    int byteCount = 0;
    int maxCount = backward ? offset : maxlen - offset;
    if (offset < maxlen && maxCount != 0) {
      maxCount = maxCount < 4 ? maxCount : 4;
      int byte;
      final stopFlag = 0x80;
      final mask = 0x7f;
      int shift = 0;
      int p = offset;
      do {
        if (backward) {
          byte = data[p];
          p--;
          val = val | (byte & mask) << shift;
          shift += 7;
        } else {
          byte = data[p];
          p++;
          val <<= 7;
          val |= (byte & mask);
        }
        byteCount++;
        hasStop = byte & stopFlag != 0;
      } while (!hasStop && (byteCount < maxCount));
    }
    if (!hasStop) {
      throw MobiBufferOverflowException();
    }
    offset = backward ? offset - byteCount : offset + byteCount;

    return (len + byteCount, val);
  }

  void add8(int data) {
    if (offset + 1 > maxlen) {
      throw MobiBufferOverflowException();
    }
    this.data[offset] = data;
    offset++;
  }

  void move(int moveOffset, int len) {
    int source = offset;
    if (moveOffset >= 0) {
      if (offset + moveOffset + len > maxlen) {
        throw MobiBufferOverflowException();
      }
      source += moveOffset;
    } else {
      moveOffset = -moveOffset;
      if (offset < moveOffset || offset + len > maxlen) {
        throw MobiBufferOverflowException();
      }
      source -= moveOffset;
    }

    data.setRange(offset, offset + len, data.getRange(source, source + len));
    offset += len;
  }

  void setPos(int pos) {
    if (pos <= maxlen) {
      offset = pos;
    } else {
      throw MobiBufferOverflowException();
    }
  }

  void copy(MobiBuffer dest, int len) {
    if (offset + len > maxlen) {
      throw MobiBufferOverflowException();
    }

    if (dest.offset + len > dest.maxlen) {
      throw MobiBufferOverflowException();
    }

    dest.data.setRange(
        dest.offset, dest.offset + len, data.getRange(offset, offset + len));
    dest.offset += len;
    offset += len;
  }

  // get Int64 value but padding 0 if the buffer data is shorter
  // offset will increase 4 bytes so each call will have 4 bytes overlap
  int fillInt64() {
    int val = 0;
    int i = 8;
    int bytesLeft = maxlen - offset;
    int p = offset;
    while (i-- != 0 && bytesLeft-- != 0) {
      val |= data[p] << (i * 8);
      p++;
    }
    offset += 4;
    return val;
  }

  void addRaw(Uint8List data, int len) {
    if (offset + len > maxlen) {
      throw MobiBufferOverflowException();
    }
    data.setRange(offset, offset + len, data.getRange(0, len));
  }

  Uint8List getRaw(int len) {
    return getStringAsByte(len);
  }

  bool matchMagic(String magic) {
    final magicLength = magic.length;
    if (offset + magicLength > maxlen) {
      return false;
    }
    final eq = ListEquality().equals;
    if (eq(data.sublist(offset, offset + magicLength), magic.codeUnits)) {
      return true;
    }
    return false;
  }

  bool matchMagicOffset(String magic, int offset) {
    bool match = false;
    if (offset < maxlen) {
      final savedOffset = this.offset;
      this.offset = offset;
      match = matchMagic(magic);
      this.offset = savedOffset;
    }
    return match;
  }
}
