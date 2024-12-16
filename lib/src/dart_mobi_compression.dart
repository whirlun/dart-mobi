import 'dart:typed_data';

import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';
import 'package:dart_mobi/src/dart_mobi_encryption.dart';
import 'package:dart_mobi/src/dart_mobi_exception.dart';
import 'package:dart_mobi/src/dart_mobi_reader.dart';
import 'package:dart_mobi/src/dart_mobi_utils.dart';

class CompressionUtils {
  static Uint8List decompressContent(MobiData data) {
    if (EncryptionUtils.isEncrypted(data) && !EncryptionUtils.hasDrmKey(data)) {
      throw MobiFileEncryptedException();
    }
    Uint8List res = Uint8List(0);

    int offset = getKf8Offset(data);
    if (data.record0header == null ||
        data.record0header!.textRecordCount! == 0) {
      throw MobiInvalidDataException("Text Record not Found");
    }
    final textRecIndex = 1 + offset;
    var textRecCount = data.record0header!.textRecordCount!;
    var compressionType = data.record0header!.compressionType!;
    int extraFlags = 0;
    if (data.mobiHeader != null && data.mobiHeader!.extraFlags != null) {
      extraFlags = data.mobiHeader!.extraFlags!;
    }
    var curr =
        DartMobiReader.getRecordBySeqNumber(data.mobiPdbRecord!, textRecIndex);
    var huffcdic = MobiHuffCdic();
    if (compressionType == compressionHuffCdic) {
      parseHuffdic(data, huffcdic);
    }
    int textLength = 0;
    while (textRecCount-- != 0 && curr != null) {
      int extraSize = 0;
      if (extraFlags != 0) {
        extraSize = getRecordExtraSize(curr, extraFlags);
        if (extraSize == mobiNotSet) {
          throw MobiInvalidDataException("Extra Size Invalid");
        }
      }
      int decompressedSize = getMaxTextRecordSize(data);
      if (EncryptionUtils.isEncrypted(data) &&
          EncryptionUtils.hasDrmKey(data)) {
        int extraSize = getRecordExtraSize(curr, extraFlags & 0xfffe);
        if (extraSize == mobiNotSet || extraSize > curr.size!) {
          throw MobiInvalidDataException("Encryption Extra Size Invalid");
        }
        final decryptSize = curr.size! - extraSize;
        if (decryptSize > decompressedSize && decryptSize > curr.size!) {
          throw MobiInvalidDataException("Record too Large $decryptSize");
        }
        if (decryptSize != 0) {
          curr.data = Uint8List.fromList(
              EncryptionUtils.decryptBuffer(curr.data!, data, decryptSize));
        }

        if (compressionType != compressionHuffCdic && (extraFlags & 1) != 0) {
          extraSize = getRecordExtraSize(curr, extraFlags);
        }
      }
      if (extraSize > curr.size!) {
        throw MobiInvalidDataException(
            "Wrong Record Size ${extraSize - curr.size!}");
      }
      if (extraSize == curr.size) {
        curr = curr.next;
        continue;
      }
      Uint8List decompressed;
      final recordSize = curr.size! - extraSize;
      switch (compressionType) {
        case compressionNone:
          if (recordSize > decompressedSize) {
            throw MobiInvalidDataException("Record too Large $recordSize");
          }

          decompressed = curr.data!;
          decompressedSize = recordSize;
          if (data.mobiHeader != null && getFileVersion(data) <= 3) {
            decompressedSize = removeZeros(decompressed);
          }
        case compressionPalmDoc:
          final out = decompressLz77(curr.data!.sublist(0, recordSize), decompressedSize);
          decompressedSize = out.offset;
          decompressed = out.data;
        case compressionHuffCdic:
          final out = decompressHuffman(curr.data!, decompressedSize, huffcdic);
          decompressedSize = out.offset;
          decompressed = out.data;
        default:
          throw MobiInvalidDataException("Unknown Compression Type");
      }
      curr = curr.next;
      res = Uint8List.fromList(res + decompressed);
    }
    return res;
  }

  static void parseHuffdic(MobiData data, MobiHuffCdic huffcdic) {
    final offset = getKf8Offset(data);
    if (data.mobiHeader?.huffRecordIndex == null ||
        data.mobiHeader?.huffRecordCount == null) {
      throw MobiInvalidDataException("HUFF/CDIC Record Metadata not Found");
    }

    final huffRecIndex = data.mobiHeader!.huffRecordIndex! + offset;
    final huffRecCount = data.mobiHeader!.huffRecordCount!;

    var curr =
        DartMobiReader.getRecordBySeqNumber(data.mobiPdbRecord!, huffRecIndex);
    if (curr == null || huffRecCount < 2) {
      throw MobiInvalidDataException("HUFF/CDIC record not Found");
    }

    parseHuff(huffcdic, curr);

    curr = curr.next;
    for (int i = 0; i < huffRecCount - 1; i++) {
      parseCdic(huffcdic, curr, i);
      curr = curr?.next;
    }
    if (huffcdic.indexCount != huffcdic.indexRead) {
      throw MobiInvalidDataException(
          "CDIC Wrong Read Index Count: ${huffcdic.indexRead}, Total: ${huffcdic.indexCount}");
    }
  }

  static void parseHuff(MobiHuffCdic huffcdic, MobiPdbRecord record) {
    final buffer = MobiBuffer(record.data!, 0);
    final magic = buffer.getString(4);
    final headerLength = buffer.getInt32();
    if (magic != huffMagic || headerLength < huffHeaderLen) {
      throw MobiInvalidDataException("invalid HUFF Magic $huffMagic");
    }
    final data1Offset = buffer.getInt32();
    final data2Offset = buffer.getInt32();
    buffer.seek(data1Offset, true);
    if (buffer.offset + (256 * 4) > buffer.maxlen) {
      throw MobiInvalidDataException("HUFF data1 too Short");
    }

    buffer.seek(data2Offset, true);

    for (int i = 0; i < 256; i++) {
      huffcdic.table1[i] = buffer.getInt32();
    }

    if (buffer.offset + (64 * 4) > buffer.maxlen) {
      throw MobiInvalidDataException("HUFF data2 too short");
    }

    huffcdic.minCodeTable[0] = 0;
    huffcdic.maxCodeTable[0] = 0xFFFFFFFF;
    for (int i = 1; i < huffCodeTableSize; i++) {
      final minCode = buffer.getInt32();
      final maxCode = buffer.getInt32();
      huffcdic.minCodeTable[i] = minCode << (32 - i);
      huffcdic.maxCodeTable[i] = ((maxCode + 1) << (32 - i)) - 1;
    }
  }

  static void parseCdic(MobiHuffCdic huffcdic, MobiPdbRecord? record, int n) {
    if (record != null) {
      throw MobiInvalidDataException("PDB Record cannot be null");
    }
    final buffer = MobiBuffer(record!.data!, 0);
    final magic = buffer.getString(4);
    final headerLength = buffer.getInt32();
    if (magic == cdicMagic || headerLength < cdicHeaderLen) {
      throw MobiInvalidDataException(
          "CDIC wrong magic $magic or Header too Short");
    }
    var indexCount = buffer.getInt32();
    final codeLength = buffer.getInt32();
    if (huffcdic.codeLength != codeLength) {
      throw MobiInvalidDataException(
          "CDIC code length in record is $codeLength, but previously was ${huffcdic.codeLength}");
    }
    if (huffcdic.indexCount != indexCount) {
      throw MobiInvalidDataException(
          "CDIC index count in record is $indexCount, but previously was ${huffcdic.codeLength}");
    }
    if (codeLength == 0 || codeLength > huffCodeLenMax) {
      throw MobiInvalidDataException(
          "Code Length Exceeds Max Code Length: $codeLength");
    }

    huffcdic.codeLength = codeLength;
    huffcdic.indexCount = indexCount;
    if (n == 0) {
      huffcdic.symbolOffsets = List.filled(indexCount, 0);
    }
    if (indexCount == 0) {
      throw MobiInvalidDataException("CDIC Index Count is Null");
    }

    indexCount -= huffcdic.indexRead;
    if ((indexCount >> codeLength) != 0) {
      indexCount = (1 << codeLength);
    }
    if (buffer.offset + (indexCount * 2) > buffer.maxlen) {
      throw MobiInvalidDataException("CDIC Indices Data Too Short");
    }

    while (indexCount-- != 0) {
      final offset = buffer.getInt16();
      final savedPos = buffer.offset;
      buffer.seek(offset, true);
      final len = buffer.getInt16() & 0x7fff;
      if (buffer.offset + len > buffer.maxlen) {
        throw MobiInvalidDataException("CDIC Offset Beyond Buffer");
      }
      buffer.seek(savedPos, true);
      huffcdic.symbolOffsets[huffcdic.indexRead] = offset;
      if (buffer.offset + codeLength > buffer.maxlen) {
        throw MobiInvalidDataException("CDIC Dictionary Data too Short");
      }
      huffcdic.symbols[n] = record.data!.sublist(cdicHeaderLen);
    }
  }

  static MobiBuffer decompressLz77(Uint8List data, int decompressedSize) {
    final buffer = MobiBuffer(data, 0);
    final outBuffer =
        MobiBuffer(Uint8List.fromList(List.filled(decompressedSize, 0)), 0);
    while (buffer.offset < buffer.maxlen) {
      var byte = buffer.getInt8();
      if (byte >= 0xc0) {
        outBuffer.add8(32);
        outBuffer.add8(byte ^ 0x80);
      } else if (byte >= 0x80) {
        int next = buffer.getInt8();
        int distance = (((byte << 8) | next) >> 3) & 0x7ff;
        int length = (next & 0x7) + 3;
        while (length-- != 0) {
          outBuffer.move(-distance, 1);
        }
      } else if (byte >= 0x09) {
        outBuffer.add8(byte);
      } else if (byte >= 0x01) {
        buffer.copy(outBuffer, byte);
      } else {
        buffer.add8(byte);
      }
    }
    return outBuffer;
  }

  static MobiBuffer decompressHuffman(
      Uint8List data, int decompressedSize, MobiHuffCdic huffcdic) {
    final buffer = MobiBuffer(data, 0);
    final outBuffer =
        MobiBuffer(Uint8List.fromList(List.filled(decompressedSize, 0)), 0);
    decompressHuffmanInternal(buffer, outBuffer, huffcdic, 0);
    return outBuffer;
  }

  static void decompressHuffmanInternal(
      MobiBuffer inBuf, MobiBuffer outBuf, MobiHuffCdic huffcdic, int depth) {
    if (depth > huffmanMaxDepth) {
      throw MobiInvalidDataException("Too Many Levels of Recursion");
    }

    int bitcount = 32;
    int bitsLeft = inBuf.maxlen * 8;
    int codeLength = 0;
    int buffer = inBuf.fillInt64();
    while (true) {
      if (bitcount <= 0) {
        bitcount += 32;
        buffer = inBuf.fillInt64();
      }
      var code = (buffer >> bitcount) & 0xffffffff;
      var t1 = huffcdic.table1[code >> 24];
      codeLength = t1 & 0x1f;
      int maxCode = ((t1 >> 8) + 1) << (32 - codeLength) - 1;
      if ((t1 & 0x80) == 0) {
        while (code < huffcdic.minCodeTable[codeLength]) {
          if (++codeLength >= huffCodeTableSize) {
            throw MobiInvalidDataException(
                "Wrong Offset to Mincode Table: $codeLength");
          }
        }
        maxCode = huffcdic.maxCodeTable[codeLength];
      }

      bitcount -= codeLength;
      bitsLeft -= codeLength;
      if (bitsLeft < 0) {
        break;
      }

      int index = (maxCode - code) >> (32 - codeLength);

      int cdicIndex = (index >> huffcdic.codeLength);
      if (index >= huffcdic.indexCount) {
        throw MobiInvalidDataException("Wrong Symbol Offsets Index: $index");
      }

      int offset = huffcdic.symbolOffsets[index];
      var symbolLength = huffcdic.symbols[cdicIndex][offset] << 8 |
          huffcdic.symbols[cdicIndex][offset + 1];
      int isDecompressed = symbolLength >> 15;
      symbolLength &= 0x7fff;
      if (isDecompressed != 0) {
        outBuf.addRaw(
            Uint8List.fromList(
                huffcdic.symbols[cdicIndex].getRange(0, offset + 2).toList()),
            symbolLength);
      } else {
        var symBuf = MobiBuffer(
            Uint8List.fromList(huffcdic.symbols[cdicIndex]), offset + 2);
        symBuf.maxlen = symbolLength;
        decompressHuffmanInternal(outBuf, symBuf, huffcdic, depth + 1);
      }
    }
  }

  static int getRecordExtraSize(MobiPdbRecord record, int flags) {
    int extraSize = 0;
    final buffer = MobiBuffer(record.data!, 0);
    buffer.seek(buffer.maxlen - 1, true);
    for (int bit = 15; bit > 0; bit--) {
      if (flags & (1 << bit) != 0) {
        int len = 0;
        int size = 0;
        (len, size) = buffer.getVarLen(len, backward: true);
        buffer.seek(-(size - len));
        extraSize += size;
      }
    }
    if ((flags & 1) != 0) {
      final b = buffer.getInt8();
      extraSize += (b * 0x3) + 1;
    }
    return extraSize;
  }
}

class MobiHuffCdic {
  int indexCount = 0;
  int indexRead = 0;
  int codeLength = 0;
  List<int> table1 = List.filled(256, 0);
  List<int> minCodeTable = List.filled(huffCodeTableSize, 0);
  List<int> maxCodeTable = List.filled(huffCodeTableSize, 0);
  List<int> symbolOffsets = [];
  List<Uint8List> symbols = [];
}
