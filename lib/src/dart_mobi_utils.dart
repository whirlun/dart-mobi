import 'dart:typed_data';

import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';

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
  if (m.record0header != null &&
      m.record0header!.textRecordSize! > record0TextSizeMax) {
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

void removeZeros(Uint8List buffer, int len) {}
