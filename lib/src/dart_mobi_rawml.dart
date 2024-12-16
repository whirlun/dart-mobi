import 'dart:typed_data';

import 'package:collection/collection.dart';
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
      final indxRecordNumber = mobiHeader!.skeletonIndex! + offset;
      MobiIndx skelMeta = MobiIndx();
      parseIndex(this, skelMeta, indxRecordNumber);
      rawml.skel = skelMeta;
    }
    if (existsFragIndx(this)) {
      MobiIndx fragMeta = MobiIndx();
      final indxRecordNumber = mobiHeader!.fragmentIndex! + offset;
      parseIndex(this, fragMeta, indxRecordNumber);
      rawml.frag = fragMeta;
    }
    if (parseToc) {
      if (existsGuideIndx(this)) {
        MobiIndx guideMeta = MobiIndx();
        final indxRecordNumber = mobiHeader!.guideIndex! + offset;
        parseIndex(this, guideMeta, indxRecordNumber);
        rawml.guide = guideMeta;
      }
      if (existsNcx(this)) {
        MobiIndx ncxMeta = MobiIndx();
        final indxRecordNumber = mobiHeader!.ncxIndex! + offset;
        parseIndex(this, ncxMeta, indxRecordNumber);
        rawml.ncx = ncxMeta;
      }
    }

    if (parseDict && isDictionary(this)) {
      MobiIndx orthData = MobiIndx();
      final indxRecordNumber = mobiHeader!.orthographicIndex! + offset;
      parseIndex(this, orthData, indxRecordNumber);
      rawml.orth = orthData;
      if (existsInfl(this)) {
        MobiIndx inflData = MobiIndx();
        final indxRecordNumber = mobiHeader!.inflectionIndex! + offset;
        parseIndex(this, inflData, indxRecordNumber);
        rawml.infl = inflData;
      }
    }
    reconstructParts(rawml);
    if (reconstruct) {
      reconstructLinks(rawml);
      if (mobiIsKf8(this)) {}
    }
    if (getEncoding(this) == MobiEncoding.CP1252) {
      // convert to utf8
    }
    return rawml;
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
        while (i < entriesCount) {
          parseIndexEntry(indx, idxt, tagx, ordt, buf, i);
          i++;
        }
        indx.entriesCount += entriesCount;
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
      List<MobiPtagx> ptagx = List.generate(tagx.tagsCount, (i) => MobiPtagx());
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
            tagValues.add(valueBytes);
            tagValuesCount++;
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
    buf.maxlen = maxlen;
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

  int getIndxEntryTagValue(MobiIndexEntry entry, int tagId, int tagIndex) {
    int i = 0;
    while (i < entry.tagsCount) {
      if (entry.tags[i].tagId == tagId) {
        if (tagIndex < entry.tags[i].tagValuesCount) {
          return entry.tags[i].tagValues[tagIndex];
        }
        break;
      }
      i++;
    }
    throw MobiInvalidDataException("Tag not found in entry");
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
      final eq = ListEquality().equals;
      if (eq(text.sublist(0, 4), "%MOP".codeUnits)) {
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

  void reconstructParts(MobiRawml rawml) {
    if (rawml.flow == null) {
      throw MobiInvalidDataException("No flow data");
    }
    MobiBuffer buf = MobiBuffer(rawml.flow!.data!, 0);
    rawml.markup = MobiPart();
    var curr = rawml.markup;
    if (rawml.skel == null || rawml.skel?.entriesCount == 0) {
      curr!.uid = 0;
      curr.size = buf.maxlen;
      curr.data = buf.data;
      curr.fileType = rawml.flow!.fileType;
      curr.next = null;
      return;
    }
    if (rawml.frag == null) {
      throw MobiInvalidDataException("No fragment data");
    }
    int i = 0;
    int j = 0;
    int currPosition = 0;
    int totalFragmentsCount = rawml.frag!.totalEntriesCount;
    while (i < rawml.skel!.entriesCount) {
      MobiIndexEntry entry = rawml.skel!.entries[i];
      int fragmentsCount = getIndxEntryTagValue(entry, 1, 0);
      if (fragmentsCount > totalFragmentsCount) {
        throw MobiInvalidDataException("Too many fragments");
      }
      totalFragmentsCount -= fragmentsCount;
      int skelPosition = getIndxEntryTagValue(entry, 6, 0);
      int skelLength = getIndxEntryTagValue(entry, 6, 1);
      if (skelPosition + skelLength > buf.maxlen) {
        throw MobiInvalidDataException("Skel data too long");
      }
      buf.setPos(skelPosition);
      final fragBuffer = buf.getRaw(skelLength);
      MobiFragment? firstFragment = MobiFragment.create(
          BigInt.from(0), fragBuffer, BigInt.from(skelLength));
      MobiFragment currFragment = firstFragment;
      while (fragmentsCount-- != 0) {
        entry = rawml.frag!.entries[j];
        int insertPosition = int.parse(entry.label);
        if (insertPosition < currPosition) {
          throw MobiInvalidDataException("Invalid fragment position");
        }
        int fileNumber = getIndxEntryTagValue(entry, 3, 0);
        if (fileNumber != i) {
          throw MobiInvalidDataException(
              "SKEL part number and fragment sequence number don't match");
        }
        int fragLength = getIndxEntryTagValue(entry, 6, 1);
        insertPosition -= currPosition;
        if (skelLength < insertPosition) {
          insertPosition = skelLength;
        }
        var fragBuffer = buf.getRaw(fragLength);
        currFragment = currFragment.insert(BigInt.from(insertPosition),
            fragBuffer, BigInt.from(fragLength), insertPosition);
        skelLength += fragLength;
        j++;
      }
      Uint8List skelText = Uint8List(skelLength);
      int ptr = 0;
      while (firstFragment != null) {
        if (firstFragment.fragment.isNotEmpty) {
          skelText.setRange(
              ptr, ptr + firstFragment.size.toInt(), firstFragment.fragment);
          ptr += firstFragment.size.toInt();}
        firstFragment = firstFragment.next;
      }
      if (i > 0) {
        curr!.next = MobiPart();
        curr = curr.next;
      }
      curr!.uid = i;
      curr.size = skelLength;
      curr.data = skelText;
      curr.fileType = MobiFileType.html;
      curr.next = null;
      currPosition += skelLength;
      i++;
    }
  }

  void reconstructLinks(MobiRawml rawml) {
    if (isRawmlKf8(rawml)) {
      reconstructLinksKf8(rawml);
    } else {
      reconstructLinksKf7(rawml);
    }
  }

  void reconstructLinksKf7(MobiRawml rawml) {}

  void reconstructLinksKf8(MobiRawml rawml) {
    NewData? partData;
    NewData? curData;
    List<MobiPart> parts = [rawml.markup!, rawml.flow!.next!];
    for (int i = 0; i < parts.length; i++) {
      MobiPart? part = parts[i];
      while (part != null) {
        if (part.data == null || part.size == 0) {
          part = part.next;
          continue;
        }
        Uint8List dataIn = part.data!;
        int dataInPtr = 0;
        MobiFragment? first;
        MobiFragment cur = MobiFragment();
        int partSize = 0;
        MobiAttrType prefAttr = MobiAttrType.attrId;
        while (true) {
          var result = searchLinksKf8(dataIn, 0, dataIn.length, part.fileType);
          if (result.start == null) {
            break;
          }
          var value = result.value;
          var dataCur = result.start!;
          int size = dataCur;
          var target = "kindle:pos:fid:";
          String link = "";
          if (value.contains(target)) {
            (link, prefAttr) = posfidToLink(
                rawml, Uint8List.fromList(target.codeUnits), prefAttr);
          } else if (value.contains("kindle:flow:")) {
            target = "kindle:flow";
            link = flowToLink(rawml, Uint8List.fromList(target.codeUnits));
          } else if (value.contains("kindle:embed:")) {
            target = "kindle:embed";
            link = embedToLink(rawml, Uint8List.fromList(target.codeUnits));
          }
          if (target != "" && link != "") {
            cur = cur.add(BigInt.from(dataInPtr), dataIn, BigInt.from(size));
            first ??= cur;
            partSize += cur.size.toInt();
            cur = cur.add(
                BigInt.parse("18446744073709551615"),
                Uint8List.fromList(
                    (result.isUrl ? link.substring(1, link.length - 1) : link)
                        .codeUnits),
                BigInt.from(result.isUrl ? link.length - 2 : link.length));
            partSize += cur.size.toInt();
            dataIn = dataIn.sublist(result.end!);
            dataInPtr = result.end!;
          }
        }
        if (first != null) {
          if (part.size < dataInPtr) {
            throw MobiInvalidDataException("Invalid part size");
          }
          int size = part.size - dataInPtr;
          cur = cur.add(BigInt.from(dataInPtr), dataIn, BigInt.from(size));
          partSize += cur.size.toInt();
          if (curData == null) {
            curData = NewData();
            partData = curData;
          } else {
            curData.next = NewData();
            curData = curData.next;
          }
          curData!.partGroup = i;
          curData.partUid = part.uid;
          curData.list = first;
          curData.size = partSize;
        }
        part = part.next;
      }
    }
    for (int i = 0; i < 2; i++) {
      MobiPart? part = parts[i];
      while (part != null) {
        if (partData != null &&
            part.uid == partData.partUid &&
            i == partData.partGroup) {
          MobiFragment? fragData = partData.list;
          Uint8List dataOut = Uint8List(0);
          while (fragData != null) {
            dataOut.addAll(fragData.fragment);
            fragData = fragData.next;
          }
          part.data = dataOut;
          part.size = partData.size;
          partData = partData.next;
        }
        part = part.next;
      }
    }
  }

  (String, MobiAttrType) posfidToLink(
      MobiRawml rawml, Uint8List value, MobiAttrType prefAttr) {
    if (value.length < "kindle:pos:fid:0000:off:0000000000".length) {
      return ("", prefAttr);
    }
    int valuePtr = "kindle:pos:fid:".length;
    if (value[valuePtr + 4] != ":".codeUnitAt(0)) {
      return ("", prefAttr);
    }
    Uint8List strFid = value.sublist(valuePtr, valuePtr + 4);
    valuePtr += "0001:off:".length;
    Uint8List strOff = value.sublist(valuePtr, valuePtr + 10);
    int posOff = base32Decode(strOff);
    int posFid = base32Decode(strFid);
    var (partId, id, prefAttr2) =
        getIdByPosOff(rawml, posFid, posOff, prefAttr);
    if (posOff != 0) {
      var link = "\"part${partId.toString().padLeft(5, '0')}.html#$id\"";
      if (link.length > mobiAttrValueMaxSize) {
        return ("", prefAttr2);
      } else {
        return (link, prefAttr2);
      }
    } else {
      return ("\"part${partId.toString().padLeft(5, '0')}.html\"", prefAttr2);
    }
  }

  String flowToLink(MobiRawml rawml, Uint8List value) {
    if (value.length < "kindle:flow:0000?mime=".length) {
      return "";
    }
    int valuePtr = "kindle:flow:".length;
    if (value[valuePtr + 4] != "?".codeUnits[0]) {
      return "";
    }
    var strFid = value.sublist(4, 8);
    MobiPart? flow = getFlowByFid(rawml, strFid);
    if (flow == null) {
      return "";
    }
    MobiFileMeta meta = getFileMetaByType(flow.fileType);
    String extension = meta.extension;
    return "\"flow${flow.uid.toString().padLeft(5, "0")}.$extension\"";
  }

  String embedToLink(MobiRawml rawml, Uint8List value) {
    int valuePtr = 0;
    while (value[valuePtr] != '"'.codeUnits[0] ||
        value[valuePtr] != "'".codeUnits[0] ||
        value[valuePtr] != ' '.codeUnits[0]) {
      valuePtr++;
    }
    if (value.length < "kindle:embed:0000".length) {
      return "";
    }
    valuePtr == "kindle:embed:".length;
    var strFid = value.sublist(valuePtr, valuePtr + 4);
    var partId = base32Decode(strFid);
    partId--;
    MobiPart? resource = getResourceByUid(rawml, partId);
    if (resource == null) {
      return "";
    }
    MobiFileMeta meta = getFileMetaByType(resource.fileType);
    String extension = meta.extension;
    return "\"resource${partId.toString().padLeft(5, "0")}.$extension\"";
  }

  MobiPart? getFlowByFid(MobiRawml rawml, Uint8List fid) {
    int partId = base32Decode(fid);
    return getFlowByUid(rawml, partId);
  }

  MobiPart? getFlowByUid(MobiRawml rawml, int uid) {
    MobiPart? part = rawml.flow;
    while (part != null) {
      if (part.uid == uid) {
        return part;
      }
      part = part.next;
    }
    return null;
  }

  (int, String, MobiAttrType) getIdByPosOff(
      MobiRawml rawml, int posFid, int posOff, MobiAttrType prefAttr) {
    var (offset, fileNumber) = getOffSetByPosOff(rawml, posFid, posOff);
    MobiPart html = getPartByUid(rawml, fileNumber);
    var (id, prefAttr2) = getIdByOffset(html, offset, prefAttr);
    return (fileNumber, id, prefAttr2);
  }

  (int, int) getOffSetByPosOff(MobiRawml rawml, int posFid, int posOff) {
    if (rawml.frag == null || rawml.skel == null) {
      throw MobiInvalidDataException("No fragment or skel data");
    }
    if (posFid >= rawml.skel!.entriesCount) {
      throw MobiInvalidDataException("Entry for $posFid does not exist");
    }
    MobiIndexEntry entry = rawml.skel!.entries[posFid];
    int offset = int.parse(entry.label);
    int fileNr = getIndxEntryTagValue(entry, 3, 0);
    if (fileNr >= rawml.skel!.entriesCount) {
      throw MobiInvalidDataException("Entry for $fileNr does not exist");
    }
    MobiIndexEntry skelEntry = rawml.skel!.entries[fileNr];
    int skelPos = getIndxEntryTagValue(skelEntry, 6, 0);
    offset -= skelPos;
    offset += posOff;
    return (offset, fileNr);
  }

  (String, MobiAttrType) getIdByOffset(
      MobiPart html, int offset, MobiAttrType prefAttr) {
    if (offset > html.size) {
      throw MobiInvalidDataException("Offset $offset is out of range");
    }
    Uint8List data = html.data!.sublist(offset);
    int length = html.size - offset;
    var (off, id) = getAttributeValue(data, length, prefAttr.toString(), true);
    if (off == 2147483647) {
      final optAttr = (prefAttr == MobiAttrType.attrId)
          ? MobiAttrType.attrName
          : MobiAttrType.attrId;
      var (off, id) = getAttributeValue(data, length, optAttr.toString(), true);
      if (off == 2147483647) {
        return ("", prefAttr);
      } else {
        return (id, optAttr);
      }
    }
    return (id, prefAttr);
  }

  (int, String) getAttributeValue(
      Uint8List data, int size, String attribute, bool onlyQuoted) {
    int length = size;
    int attrLength = attribute.length;
    String value = "";
    if (attrLength > attrNameMaxSize) {
      return (2147483647, "");
    }
    String attr = "$attribute=";
    attrLength++;
    if (size < attrLength) {
      return (2147483647, "");
    }
    int dataPtr = 0;
    int lastBorder = 0;
    final eq = ListEquality().equals;
    do {
      if (data[dataPtr] == '<'.codeUnits[0] ||
          data[dataPtr] == '>'.codeUnits[0]) {
        lastBorder = data[dataPtr];
      }
      if (length > attrLength + 1 &&
          eq(data.sublist(dataPtr, attrLength), attr.codeUnits)) {
        int offset = size - length;
        if (lastBorder == '>'.codeUnits[0]) {
          dataPtr += attrLength;
          length -= attrLength - 1;
          continue;
        }
        if (offset > 0) {
          if (data.last != '<'.codeUnits[0] && data.last != ' '.codeUnits[0]) {
            dataPtr += attrLength;
            length -= attrLength - 1;
            continue;
          }
        }
        dataPtr += attrLength;
        length -= attrLength;
        int separator = 0;
        if (data[dataPtr] != '\''.codeUnits[0] &&
            data[dataPtr] != '"'.codeUnits[0]) {
          if (onlyQuoted) {
            continue;
          }
          separator = ' '.codeUnits[0];
        } else {
          separator = data[dataPtr];
          dataPtr++;
          length--;
        }
        int j = 0;
        for (j = 0;
            j < mobiAttrValueMaxSize &&
                length != 0 &&
                data[dataPtr] != separator &&
                data[dataPtr] != '>'.codeUnits[0];
            j++) {
          value += String.fromCharCode(data[dataPtr]);
          length--;
        }
        if (length != 0 &&
            data[dataPtr - 1] == '/'.codeUnits[0] &&
            data[dataPtr] == '>'.codeUnits[0]) {
          value = value.substring(0, value.length - 1);
        }
        return (size - length - j, value);
      }
      dataPtr++;
    } while (--length != 0);
    return (2147483647, "");
  }

  MobiPart getPartByUid(MobiRawml rawml, int uid) {
    if (rawml.markup == null) {
      throw MobiInvalidDataException("No markup data");
    }
    MobiPart? curr = rawml.markup;
    while (curr != null) {
      if (curr.uid == uid) {
        return curr;
      }
      curr = curr.next;
    }
    throw MobiInvalidDataException("Part with uid $uid not found");
  }

  MobiResult searchLinksKf8(
      Uint8List data, int start, int end, MobiFileType type) {
    return findAttrValue(data, start, end, type, "kindle:");
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
    final eq = ListEquality().equals;
    if (eq(record.data!.sublist(0, 3), jpgMagic.codeUnits)) {
      return MobiFileType.jpg;
    }
    if (eq(record.data!.sublist(0, 4), gifMagic.codeUnits)) {
      return MobiFileType.gif;
    }
    if (record.size! >= 8 &&
        eq(record.data!.sublist(0, 8), pngMagic.codeUnits)) {
      return MobiFileType.png;
    }
    if (eq(record.data!.sublist(0, 4), fontMagic.codeUnits)) {
      return MobiFileType.font;
    }
    if (record.size! >= 8 &&
        eq(record.data!.sublist(0, 8), boundaryMagic.codeUnits)) {
      return MobiFileType.break_;
    }
    if (eq(record.data!.sublist(0, 4), eofMagic.codeUnits)) {
      return MobiFileType.break_;
    }
    if (record.size! >= 6 &&
        eq(record.data!.sublist(0, 2), bmpMagic.codeUnits)) {
      final buf = MobiBuffer(record.data!, 2);
      final size = buf.getInt32Le();
      if (record.size! == size) {
        return MobiFileType.bmp;
      }
    } else if (eq(record.data!.sublist(0, 4), autioMagic.codeUnits)) {
      return MobiFileType.audio;
    } else if (eq(record.data!.sublist(0, 4), videoMagic.codeUnits)) {
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

class MobiFragment {
  BigInt rawOffset = BigInt.from(0);
  Uint8List fragment = Uint8List(0);
  BigInt size = BigInt.from(0);
  MobiFragment? next;

  MobiFragment();
  MobiFragment.create(this.rawOffset, this.fragment, this.size);

  MobiFragment add(BigInt rawOffset, Uint8List fragment, BigInt size) {
    next = MobiFragment();
    next!.rawOffset = rawOffset;
    next!.fragment = fragment;
    next!.size = size;
    return next!;
  }

  MobiFragment insert(
      BigInt rawOffset, Uint8List data, BigInt size, int offset) {
    final SIZEMAX = BigInt.parse("18446744073709551615");
    MobiFragment? curr = this;
    MobiFragment? prev;
    while (curr != null) {
      if (curr.rawOffset != SIZEMAX &&
          curr.rawOffset <= BigInt.from(offset) &&
          curr.rawOffset + curr.size >= BigInt.from(offset)) {
        break;
      }
      prev = curr;
      curr = curr.next;
    }
    if (curr == null) {
      throw MobiInvalidDataException("Offset not found");
    }
    MobiFragment newFrag = MobiFragment.create(rawOffset, data, size);
    MobiFragment newFrag2 = MobiFragment();
    if (curr.rawOffset == BigInt.from(offset)) {
      if (prev != null) {
        prev.next = newFrag;
        newFrag.next = curr;
      } else {
        MobiFragment temp = curr;
        curr.rawOffset = newFrag.rawOffset;
        curr.fragment = newFrag.fragment;
        curr.size = newFrag.size;
        curr.next = newFrag;
        newFrag.rawOffset = temp.rawOffset;
        newFrag.fragment = temp.fragment;
        newFrag.size = temp.size;
        newFrag.next = temp.next;
        return curr;
      }
    } else if (curr.rawOffset + curr.size == BigInt.from(offset)) {
      newFrag.next = curr.next;
      curr.next = newFrag;
    } else {
      var relOffset = BigInt.from(offset) - curr.rawOffset;
      newFrag2.next = curr.next;
      newFrag2.size = curr.size - relOffset;
      newFrag2.rawOffset = curr.rawOffset;
      newFrag2.fragment = curr.fragment.sublist(relOffset.toInt());
      curr.next = newFrag;
      curr.size = relOffset;
      newFrag.next = newFrag2;
    }
    if (rawOffset != SIZEMAX) {
      curr = newFrag.next;
      while (curr != null) {
        if (curr.rawOffset != SIZEMAX) {
          curr.rawOffset += newFrag.size;
        }
        curr = curr.next;
      }
    }
    return newFrag;
  }
}

class NewData {
  int partGroup = 0;
  int partUid = 0;
  MobiFragment? list;
  int size = 0;
  NewData? next;
}

enum MobiAttrType {
  attrId,
  attrName;

  @override
  String toString() {
    return this == attrId ? "id" : "name";
  }
}

class MobiFileMeta {
  MobiFileType? fileType;
  String extension = "";
  String mimeType = "";
}
