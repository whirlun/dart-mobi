import 'dart:typed_data';

import 'package:dart_mobi/src/dart_mobi_compression.dart';
import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';
import 'package:dart_mobi/src/dart_mobi_exception.dart';
import 'package:dart_mobi/src/dart_mobi_reader.dart';
import 'package:dart_mobi/src/dart_mobi_utils.dart';

extension RawmlParser on MobiData {
  MobiRawml parseOpt(bool parseToc, bool parseDict, bool reconstruct) {
    final maxLen = getMaxTextSize(this);
    if (maxLen == mobiNotSet) {
      throw MobiInvalidDataException("Text Length Too Long");
    }

    int length = maxLen;
    MobiRawml rawml = MobiRawml();
    final rawRawml = getRawml(length);
    if (existsFdst(this)) {
      if (mobiHeader?.fdstSectionCount != null &&
          mobiHeader!.fdstSectionCount! > 1) {
        rawml.fdst = DartMobiReader.readFdst(this);
      }
    }
    reconstructFlow(rawml, rawRawml, length);
    reconstructResources(this, rawml);
    final offset = getKf8Offset(this);
    if (existsSkelIndx(this) && existsFragIndx(this)) {
      final indxRecordNumber = mobiHeader!.fragmentIndex! + offset;
      MobiIndx skelMeta = MobiIndx();
      parseIndex(this, skelMeta, indxRecordNumber);
      rawml.skel = skelMeta;
    }
  }

  parseIndex(MobiData data, MobiIndx indx, int indxRecordNumber) {
    MobiTagx tagx = MobiTagx();
    MobiOrdt ordt = MobiOrdt();
    var record = DartMobiReader.getRecordBySeqNumber(
        data.mobiPdbRecord!, indxRecordNumber);
    if (record == null) {
      throw MobiInvalidDataException("Index Record Not Found");
    }
    parseIndx(record, indx, tagx, ordt);
    int count = indx.entriesCount;
    indx.entriesCount = 0;
    while (count-- != 0) {
      record = record!.next;
      if (record == null) {
        throw MobiInvalidDataException("Index Record Not Found");
      }
      parseIndx(record, indx, tagx, ordt);
    }
    if (indx.entriesCount != indx.totalEntriesCount) {
      throw MobiInvalidDataException("Index Entries Count Mismatch");
    }
    if (indx.cncxRecordsCount != 0) {
      indx.cncxRecord = record!.next;
    }
  }

  void parseIndx(
      MobiPdbRecord indxRecord, MobiIndx indx, MobiTagx tagx, MobiOrdt ordt) {
    MobiBuffer buf = MobiBuffer(indxRecord.data!, 0);
    final indxMagic = buf.getString(4);
    final headerLength = buf.getInt32();
    if (indxMagic != "INDX" ||
        headerLength == 0 ||
        headerLength > indxRecord.size!) {
      throw MobiInvalidDataException("Corrputed Indx Record");
    }
    buf.seek(4);
    final type = buf.getInt32();
    buf.seek(4);
    final idxtOffset = buf.getInt32();
    final entriesCount = buf.getInt32();
    if (entriesCount > indxRecordMaxCnt) {
      throw MobiInvalidDataException("Too Many Entries in Indx Record");
    }
    if (buf.matchMagicOffset("TAGX", headerLength) &&
        indx.totalEntriesCount == 0) {
      buf.maxlen = headerLength;
      MobiEncoding encoding = MobiEncoding.UTF8;
      var encodingValue = buf.getInt32();
      if (encodingValue == mobiNotSet) {
        encoding = MobiEncoding.CP1252;
      } else {
        encoding = MobiEncoding.fromValue(encodingValue);
      }
      buf.seek(4);
      final totalEntriesCount = buf.getInt32();
      if (totalEntriesCount > indxTotalMaxCnt) {
        throw MobiInvalidDataException("Too Many Entries in Indx Record");
      }
      var ordtOffset = buf.getInt32();
      if (ordtOffset + ordtRecordMaxCnt + 4 > indxRecord.size!) {
        ordtOffset = 0;
      }
      var ligtOffset = buf.getInt32();
      var ligtEntriesCount = buf.getInt32();
      if (ligtOffset + 4 * ligtEntriesCount + 4 > indxRecord.size!) {
        ligtOffset = 0;
        ligtEntriesCount = 0;
      }
      final cncxRecordsCount = buf.getInt32();
      if (cncxRecordsCount > cncxRecordMaxCnt) {
        throw MobiInvalidDataException("Too Many Entries in CNCX Record");
      }
      var ordtType = 0;
      var ordtEntriesCount = 0;
      var ordt1Offset = 0;
      var ordt2Offset = 0;
      var indexNameOffset = 0;
      var indexNameLength = 0;
      if (headerLength >= 180) {
        buf.setPos(164);
        ordtType = buf.getInt32();
        ordtEntriesCount = buf.getInt32();
        ordt1Offset = buf.getInt32();
        ordt2Offset = buf.getInt32();
        final entrySize = (ordtType == 0) ? 1 : 2;
        if (ordt1Offset + entrySize * ordtEntriesCount > indxRecord.size! ||
            ordt2Offset + 2 * ordtEntriesCount > indxRecord.size!) {
          ordtEntriesCount = 0;
          ordt1Offset = 0;
          ordt2Offset = 0;
        }
        indexNameOffset = buf.getInt32();
        indexNameLength = buf.getInt32();
      }
      buf.maxlen = indxRecord.size!;
      buf.setPos(headerLength);
      parseTagx(buf, tagx);
      if (ordtEntriesCount > 0) {
        ordt.offsetsCount = ordtEntriesCount;
        ordt.type = ordtType;
        ordt.ordt1Pos = ordt1Offset;
        ordt.ordt2Pos = ordt2Offset;
        parseOrdt(buf, ordt);
      }
      if (indexNameOffset > 0 && indexNameLength > 0) {
        if (indexNameLength <= headerLength - indexNameOffset &&
            indexNameLength < indxNameSizeMax) {
          buf.setPos(indexNameOffset);
          final name = buf.getString(indexNameLength);
          indx.orthIndexName = name;
        }
      }
      indx.encoding = encoding;
      indx.type = type;
      indx.entriesCount = entriesCount;
      indx.totalEntriesCount = totalEntriesCount;
      if (ligtEntriesCount != 0 && buf.matchMagicOffset("LIGT", ligtOffset)) {
        ligtOffset = 0;
        ligtEntriesCount = 0;
      }
      indx.ligtOffset = ligtOffset;
      indx.ligtEntriesCount = ligtEntriesCount;
      indx.ordtOffset = ordtOffset;
      indx.cncxRecordsCount = cncxRecordsCount;
    } else {
      if (idxtOffset == 0) {
        throw MobiInvalidDataException("Missing IDXT offset");
      }
      if (idxtOffset + 2 * entriesCount + 4 > indxRecord.size!) {
        throw MobiInvalidDataException("IDXT Record Too Long");
      }
      buf.setPos(idxtOffset);
      MobiIdxt idxt = MobiIdxt();
      parseIdxt(buf, idxt, entriesCount);
      if (entriesCount > 0) {
        int i = 0;
        indx.entries = List.generate(entriesCount, (int i) => MobiIndexEntry());
        while (i < entriesCount) {}
      }
    }
  }

  void parseIndexEntry(MobiIndx indx, MobiIdxt idxt, MobiTagx tagx,
      MobiOrdt ordt, MobiBuffer buf, int currNumber) {
    final entryOffset = indx.entriesCount;
    final entryLength = idxt.offsets[currNumber + 1] - idxt.offsets[currNumber];
    buf.setPos(idxt.offsets[currNumber]);
    int entryNumber = currNumber + entryOffset;
    if (entryNumber >= indx.totalEntriesCount) {
      throw MobiInvalidDataException("Too Many Entries in Indx Record");
    }
    final maxlen = buf.maxlen;
    if (buf.offset + entryLength > maxlen) {
      throw MobiInvalidDataException("Index Entry Too Long");
    }
    buf.maxlen = buf.offset + entryLength;
    int labelLength = buf.getInt8();
    if (labelLength > entryLength) {
      throw MobiInvalidDataException("Label Length Too Long");
    }
    var label = "";
    if (ordt.ordt2.isNotEmpty) {
      label = getStringOrdt(ordt, buf, labelLength);
      labelLength = label.length;
    } else {
      label = indxGetLabel(buf, labelLength, indx.ligtEntriesCount != 0);
    }
    indx.entries[entryNumber].label = label;
    int controlBytesOffset = buf.offset;
    buf.seek(tagx.controlByteCount);
    indx.entries[entryNumber].tagsCount = 0;
    indx.entries[entryNumber].tags = [];
    if (tagx.tagsCount > 0) {
      List<MobiPtagx> ptagx = [];
      int ptagxCount = 0;
      int len = 0;
      int i = 0;
      while (i < tagx.tagsCount) {
        if (tagx.tags[i].controlByte == 1) {
          controlBytesOffset++;
          i++;
          continue;
        }
        int value = buf.data[controlBytesOffset] & tagx.tags[i].bitMask;
        if (value != 0) {
          int valueCount = mobiNotSet;
          int valueBytes = mobiNotSet;
          if (value == tagx.tags[i].bitMask) {
            if (mobiBigCount(tagx.tags[i].bitMask) > 1) {
              len = 0;
              (len, valueBytes) = buf.getVarLen(len);
            } else {
              valueCount = 1;
            }
          } else {
            int mask = tagx.tags[i].bitMask;
            while ((mask & 1) == 0) {
              mask >>= 1;
              value >>= 1;
            }
            valueCount = value;
          }
          ptagx[ptagxCount].tag = tagx.tags[i].tag;
          ptagx[ptagxCount].tagValueCount = tagx.tags[i].valuesCount;
          ptagx[ptagxCount].valueCount = valueCount;
          ptagx[ptagxCount].valueBytes = valueBytes;
          ptagxCount++;
        }
        i++;
      }
      indx.entries[entryNumber].tags =
          List.generate(tagx.tagsCount, (i) => MobiIndexTag());
      i = 0;
      int valueBytes = 0;
      while (i < ptagxCount) {
        int tagValuesCount = 0;
        List<int> tagValues = [];
        if (ptagx[i].valueCount != mobiNotSet) {
          int count = ptagx[i].valueCount * ptagx[i].tagValueCount;
          while (count-- != 0 && tagValuesCount < indxTagValuesMax) {
            len = 0;
            (len, valueBytes) = buf.getVarLen(len);
            tagValues[tagValuesCount++] = valueBytes;
          }
        } else {
          len = 0;
          while (
              len < ptagx[i].valueBytes && tagValuesCount < indxTagValuesMax) {
            (len, valueBytes) = buf.getVarLen(len);
            tagValues[tagValuesCount++] = valueBytes;
          }
        }
        if (tagValuesCount != 0) {
          indx.entries[entryNumber].tags[i].tagValues = tagValues;
        } else {
          indx.entries[entryNumber].tags[i].tagValues = [];
        }
        indx.entries[entryNumber].tags[i].tagId = ptagx[i].tag;
        indx.entries[entryNumber].tags[i].tagValuesCount = tagValuesCount;
        indx.entries[entryNumber].tagsCount++;
        i++;
      }
    }
  }

  String indxGetLabel(MobiBuffer buf, int length, bool hasLigatures) {
    Uint8List output = Uint8List(indxLabelSizeMax + 1);
    int outputPtr = 0;
    if (buf.offset + length > buf.maxlen) {
      throw MobiInvalidDataException("Index Entry Too Long");
    }
    int replacement = 0x3f;
    int outputLength = 0;
    int i = 0;
    while (i < length && outputLength < indxLabelSizeMax) {
      int c = buf.getInt8();
      i++;
      if (c == 0) {
        c = replacement;
      }
      if (c <= 5 && hasLigatures) {
        int c2 = buf.getInt8();
        c = ligtureToCp1252(c, c2);
        if (c == 0) {
          buf.seek(-1);
          c = replacement;
        } else {
          i++;
        }
      }
      output[outputPtr] = c;
      outputPtr++;
      outputLength++;
    }
    return String.fromCharCodes(output.sublist(0, outputLength));
  }

  String getStringOrdt(MobiOrdt ordt, MobiBuffer buf, int length) {
    int i = 0;
    int outputLength = 0;
    int outputPtr = 0;
    Uint8List output = Uint8List.fromList(List.filled(indxLabelSizeMax + 1, 0));
    final bytemask = 0xbf;
    final bytemark = 0x80;
    final uniReplacement = 0xfffd;
    final surrogateOffset = 0x35fdc00;
    final initByte = [0x00, 0x00, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc];
    while (i < length) {
      int offset = 0;
      int n = 0;
      (n, offset) = ordtGetBuffer(ordt, buf, offset);
      i += n;
      int codePoint = ordtLookup(ordt, offset);
      if (codePoint <= 5) {
        (n, offset) = ordtGetBuffer(ordt, buf, offset);
        int codePoint2 = ordtLookup(ordt, offset);
        codePoint = ligatureToUtf16(codePoint, codePoint2);
        if (codePoint == uniReplacement) {
          buf.seek(-n);
        } else {
          i += n;
        }
      }
      if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
        (n, offset) = ordtGetBuffer(ordt, buf, offset);
        int codePoint2 = ordtLookup(ordt, offset);
        if (codePoint2 >= 0xdc00 && codePoint2 <= 0xdfff) {
          codePoint = (codePoint << 10) + codePoint2 + surrogateOffset;
          i += n;
        } else {
          buf.seek(-n);
          codePoint = uniReplacement;
        }
      }
      if ((codePoint >= 0xdc00 && codePoint <= 0xdfff) ||
          (codePoint >= 0xfdd0 && codePoint <= 0xfdef) ||
          (codePoint & 0xfffe) == 0xfffe ||
          codePoint == 0) {
        codePoint = uniReplacement;
      }
      int bytes;
      if (codePoint < 0x80) {
        bytes = 1;
      } else if (codePoint < 0x800) {
        bytes = 2;
      } else if (codePoint < 0x10000) {
        bytes = 3;
      } else if (codePoint < 0x110000) {
        bytes = 4;
      } else {
        bytes = 3;
        codePoint = uniReplacement;
      }
      if (outputLength + bytes > indxLabelSizeMax) {
        break;
      }
      outputPtr += bytes;
      switch (bytes) {
        case 4:
          outputPtr--;
          output[outputPtr] = (codePoint | bytemark) & bytemask;
          codePoint >>= 6;
          continue byte3;
        byte3:
        case 3:
          outputPtr--;
          output[outputPtr] = (codePoint | bytemark) & bytemask;
          codePoint >>= 6;
          continue byte2;
        byte2:
        case 2:
          outputPtr--;
          output[outputPtr] = (codePoint | bytemark) & bytemask;
          codePoint >>= 6;
          continue byte1;
        byte1:
        case 1:
          outputPtr--;
          output[outputPtr] = codePoint | initByte[bytes];
          break;
      }
      outputPtr += bytes;
      outputLength += bytes;
    }
    return String.fromCharCodes(output.sublist(0, outputLength));
  }

  (int, int) ordtGetBuffer(MobiOrdt ordt, MobiBuffer buf, int offset) {
    int i = 0;
    if (ordt.type == 1) {
      offset = buf.getInt8();
      i++;
    } else {
      offset = buf.getInt16();
      i += 2;
    }
    return (i, offset);
  }

  int ordtLookup(MobiOrdt ordt, int offset) {
    int utf16;
    if (offset < ordt.offsetsCount) {
      utf16 = ordt.ordt2[offset];
    } else {
      utf16 = offset;
    }
    return utf16;
  }

  void parseIdxt(MobiBuffer buf, MobiIdxt idxt, int entriesCount) {
    final idxtOffset = buf.offset;
    final magic = buf.getString(4);
    if (magic != "IDXT") {
      throw MobiInvalidDataException("Invalid IDXT Magic");
    }
    int i = 0;
    while (i < entriesCount) {
      idxt.offsets.add(buf.getInt16());
      i++;
    }
    idxt.offsets.add(idxtOffset);
    idxt.offsetsCount = i;
  }

  void parseOrdt(MobiBuffer buf, MobiOrdt ordt) {
    buf.setPos(ordt.ordt1Pos);
    if (buf.matchMagic("ORDT")) {
      buf.seek(4);
      if (ordt.offsetsCount + buf.offset > buf.maxlen) {
        throw MobiInvalidDataException("ORDT1 Record Too Long");
      }
      int i = 0;
      while (i < ordt.offsetsCount) {
        ordt.ordt1.add(buf.getInt8());
        i++;
      }
    }
    buf.setPos(ordt.ordt2Pos);
    if (buf.matchMagic("ORDT")) {
      buf.seek(4);
      if (ordt.offsetsCount * 2 + buf.offset > buf.maxlen) {
        throw MobiInvalidDataException("ORDT2 Record Too Long");
      }
      int i = 0;
      while (i < ordt.offsetsCount) {
        ordt.ordt2.add(buf.getInt16());
        i++;
      }
    }
  }

  void parseTagx(MobiBuffer buf, MobiTagx tagx) {
    buf.seek(4);
    var tagxRecordLength = buf.getInt32();
    if (tagxRecordLength < 12) {
      throw MobiInvalidDataException("Indx Record Too Short");
    }
    tagx.controlByteCount = buf.getInt32();
    tagxRecordLength -= 12;
    if (tagxRecordLength + buf.offset > buf.maxlen) {
      throw MobiInvalidDataException("Indx Record Too Long");
    }
    final tagxDataLength = tagxRecordLength / 4;
    var controlByteCount = 0;
    int i = 0;
    while (i < tagxDataLength) {
      tagx.tags.add(TagxTags());
      tagx.tags[i].tag = buf.getInt8();
      tagx.tags[i].valuesCount = buf.getInt8();
      tagx.tags[i].bitMask = buf.getInt8();
      final controlByte = buf.getInt8();
      if (controlByte != 0) {
        controlByteCount++;
      }
      tagx.tags[i].controlByte = controlByte;
      i++;
    }
    if (tagx.controlByteCount != controlByteCount) {
      throw MobiInvalidDataException("Wrong count of control bytes");
    }
    tagx.tagsCount = i;
  }

  void reconstructFlow(MobiRawml rawml, Uint8List text, int length) {
    if (rawml.fdst != null) {
      rawml.flow = MobiPart();
      var curr = rawml.flow;
      final sectionCount = rawml.fdst!.fdstSectionCount;
      for (int i = 0; i < sectionCount; i++) {
        if (i > 0) {
          curr!.next = MobiPart();
          curr = curr.next;
        }
        final sectionStart = rawml.fdst!.fdstSectionStarts[i];
        final sectionEnd = rawml.fdst!.fdstSectionEnds[i];
        final sectionSize = sectionEnd - sectionStart;
        if (sectionStart + sectionSize > length) {
          throw MobiInvalidDataException(
              "Wrong fdst section size $sectionSize");
        }
        final sectionData =
            text.sublist(sectionStart, sectionStart + sectionSize);
        curr!.uid = i;
        curr.data = sectionData;
        curr.fileType = determineFlowPartType(rawml, i);
        curr.size = sectionSize;
        curr.next = null;
        i++;
      }
    } else {
      rawml.flow = MobiPart();
      var curr = rawml.flow;
      var sectionSize = 0;
      var sectionType = MobiFileType.html;
      var sectionData = Uint8List(0);
      if (text.sublist(0, 4) == "%MOP".codeUnits) {
        sectionSize = length;
        sectionType = MobiFileType.pdf;
        sectionData = processReplica(text, sectionSize);
      } else {
        sectionSize = length;
        sectionData = text;
      }
      curr!.uid = 0;
      curr.data = sectionData;
      curr.fileType = sectionType;
      curr.size = sectionSize;
      curr.next = null;
    }
  }

  void reconstructResources(MobiData data, MobiRawml rawml) {
    var firstResSeqNumber = getFirstResourceRecord(data);
    if (firstResSeqNumber == mobiNotSet) {
      firstResSeqNumber = 0;
    }
    var currRecord = DartMobiReader.getRecordBySeqNumber(
        data.mobiPdbRecord!, firstResSeqNumber);
    if (currRecord == null) {
      print("First resource record not found. Skipping $firstResSeqNumber");
      return;
    }
    int i = 0;
    MobiPart? head;
    while (currRecord != null) {
      final fileType = determineResourceType(currRecord);
      if (fileType == MobiFileType.unknown) {
        currRecord = currRecord.next;
        i++;
        continue;
      }
      if (fileType == MobiFileType.break_) {
        break;
      }
      final currPart = MobiPart();
      currPart.data = currRecord.data;
      currPart.size = currRecord.size!;
      currPart.uid = i++;
      currPart.next = null;

      if (fileType == MobiFileType.font) {
        addFontResource(currPart);
      } else if (fileType == MobiFileType.audio) {
        addAudioResource(currPart);
      } else if (fileType == MobiFileType.video) {
        addVideoResource(currPart);
      } else {
        currPart.fileType = fileType;
      }
      currRecord = currRecord.next;

      if (head != null) {
        head.next = currPart;
        head = currPart;
      } else {
        rawml.resources = currPart;
        head = currPart;
      }
    }
  }

  Uint8List processReplica(Uint8List text, int length) {
    MobiBuffer buf = MobiBuffer(text, 12);
    final pdfOffset = buf.getInt32();
    final pdfLength = buf.getInt32();
    if (pdfLength > length) {
      throw MobiInvalidDataException("PDF size from replica is too long");
    }
    buf.setPos(pdfOffset);
    final pdf = buf.getRaw(pdfLength);
    return pdf;
  }

  MobiFileType determineFlowPartType(MobiRawml rawml, int partNumber) {
    if (partNumber == 0 || isRawmlKf8(rawml)) {
      return MobiFileType.html;
    }
    if (partNumber > 9999) {
      return MobiFileType.unknown;
    }
    if (rawml.flow?.data == null) {
      throw MobiInvalidDataException("No flow data");
    }
    final target = "kindle:flow:${partNumber.toString().padLeft(4, "0")}?mime=";
    final result = findAttrValue(
        rawml.flow!.data!, 0, rawml.flow!.size, MobiFileType.html, target);
    if (result.start != null) {
      if (result.value == "text/css") {
        return MobiFileType.css;
      }
      if (result.value == "image/svg+xml") {
        return MobiFileType.svg;
      }
    }
    return MobiFileType.unknown;
  }

  MobiFileType determineResourceType(MobiPdbRecord record) {
    if (record.size! < 4) {
      return MobiFileType.unknown;
    }
    final jpgMagic = "\xff\xd8\xff";
    final gifMagic = "\x47\x49\x46\x38";
    final pngMagic = "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a";
    final bmpMagic = "\x42\x4d";
    final fontMagic = "FONT";
    final autioMagic = "AUDI";
    final videoMagic = "VIDE";
    final boundaryMagic = "BOUNDARY";
    final eofMagic = "\xe9\x8e\r\n";
    if (record.data!.sublist(0, 3) == jpgMagic.codeUnits) {
      return MobiFileType.jpg;
    }
    if (record.data!.sublist(0, 4) == gifMagic.codeUnits) {
      return MobiFileType.gif;
    }
    if (record.data!.sublist(0, 8) == pngMagic.codeUnits) {
      return MobiFileType.png;
    }
    if (record.data!.sublist(0, 4) == fontMagic.codeUnits) {
      return MobiFileType.font;
    }
    if (record.data!.sublist(0, 8) == boundaryMagic.codeUnits) {
      return MobiFileType.break_;
    }
    if (record.data!.sublist(0, 4) == eofMagic.codeUnits) {
      return MobiFileType.break_;
    }
    if (record.data!.sublist(0, 2) == bmpMagic.codeUnits) {
      final buf = MobiBuffer(record.data!, 2);
      final size = buf.getInt32Le();
      if (record.size! == size) {
        return MobiFileType.bmp;
      }
    } else if (record.data!.sublist(0, 4) == autioMagic.codeUnits) {
      return MobiFileType.audio;
    } else if (record.data!.sublist(0, 4) == videoMagic.codeUnits) {
      return MobiFileType.video;
    }
    return MobiFileType.unknown;
  }

  MobiResult findAttrValue(Uint8List flowData, int start, int end,
      MobiFileType type, String needle) {
    final result = MobiResult();
    final needleLength = needle.length;
    if (needleLength > mobiAttrNameMaxSize) {
      throw MobiInvalidParameterException("needle is too long");
    }
    if (start + needleLength >= end) {
      return MobiResult();
    }
    var tagOpen = 0;
    var tagClose = 0;
    if (type == MobiFileType.css) {
      tagOpen = "{".codeUnitAt(0);
      tagClose = "}".codeUnitAt(0);
    } else {
      tagOpen = "<".codeUnitAt(0);
      tagClose = ">".codeUnitAt(0);
    }
    var lastBorder = tagClose;
    int i = 0;
    while (i < end) {
      if (flowData[i] == tagOpen || flowData[i] == tagClose) {
        lastBorder = flowData[i];
      }
      if (i + needleLength <= end &&
          String.fromCharCodes(flowData.sublist(i, i + needleLength), 0) ==
              needle) {
        if (lastBorder != tagOpen) {
          i += needleLength;
          continue;
        }
        while (i > start &&
            flowData[i] != " ".codeUnitAt(0) &&
            flowData[i] != tagOpen &&
            flowData[i] != "=".codeUnitAt(0) &&
            flowData[i] != "(".codeUnitAt(0)) {
          i--;
        }
        result.isUrl = flowData[i] == "(".codeUnitAt(0);
        result.start = i;
        int j = 0;
        while (i < end &&
            flowData[i] != " ".codeUnitAt(0) &&
            flowData[i] != tagClose &&
            flowData[i] != ")".codeUnitAt(0) &&
            j < mobiAttrValueMaxSize) {
          result.value += String.fromCharCode(flowData[i]);
          i++;
          j++;
        }
        if (i <= end &&
            flowData[i - 1] == "/".codeUnitAt(0) &&
            flowData[i] == ">".codeUnitAt(0)) {
          i--;
          j--;
        }
        result.end = i;
        return result;
      }
      i++;
    }
    return result;
  }

  Uint8List getRawml(int length) {
    if (record0header!.textLength! > length) {
      throw MobiInvalidParameterException(
          "Text Length in Record 0 is Longer Than Declared Length");
    }
    return CompressionUtils.decompressContent(this);
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
  List<MobiIndexEntry> entries = [];
  String orthIndexName = "";
}

class MobiIndexEntry {
  String label = "";
  int tagsCount = 0;
  List<MobiIndexTag> tags = [];
}

class MobiIndexTag {
  int tagId = 0;
  int tagValuesCount = 0;
  List<int> tagValues = [];
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
  break_
}

class MobiResult {
  int? start;
  int? end;
  String value = "";
  bool isUrl = false;
}

class TagxTags {
  int tag = 0;
  int valuesCount = 0;
  int bitMask = 0;
  int controlByte = 0;
}

class MobiTagx {
  List<TagxTags> tags = [];
  int tagsCount = 0;
  int controlByteCount = 0;
}

class MobiOrdt {
  List<int> ordt1 = [];
  List<int> ordt2 = [];
  int type = 0;
  int ordt1Pos = 0;
  int ordt2Pos = 0;
  int offsetsCount = 0;
}

class MobiIdxt {
  List<int> offsets = [];
  int offsetsCount = 0;
}

class MobiPtagx {
  int tag = 0;
  int tagValueCount = 0;
  int valueCount = 0;
  int valueBytes = 0;
}
