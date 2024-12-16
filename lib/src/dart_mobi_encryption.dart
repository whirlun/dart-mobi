import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mobi/src/dart_mobi_const.dart';
import 'package:dart_mobi/src/dart_mobi_data.dart';
import 'package:dart_mobi/src/dart_mobi_exception.dart';
import 'package:dart_mobi/src/dart_mobi_reader.dart';
import 'package:dart_mobi/src/dart_mobi_utils.dart';

class EncryptionUtils {
  static List<String> checkSumDrmPid(String? pid) {
    final map = 'ABCDEFGHIJKLMNPQRSTUVWXYZ123456789'.split('');
    var crc = ~crc32(pid);
    crc ^= (crc >> 16);
    List<String> res = [];
    for (int i = 0; i < 2; i++) {
      final b = crc & 0xff;
      final pos = (b / map.length).floor() ^ (b % map.length);
      res.add(map[pos % map.length]);
      crc >>= 8;
    }
    return res;
  }

  static int checkSumDrmKey(String key) {
    int sum = 0;
    for (int i = 0; i < key.length; i++) {
      sum += key.codeUnitAt(i);
    }
    return sum;
  }

  static void initDrmKey(MobiData data, List<int> key) {
    data.drm ??= MobiDrm();
    data.drm!.key = key;
  }

  static bool verifyDrmKey(String? pid) {
    final checkSum = checkSumDrmPid(pid);
    if (checkSum.toString() == pid?.substring(pidSize - 2)) {
      return true;
    }
    return false;
  }

  static void setDrmKey(MobiData data, String? pid) {
    if (pid != null) {
      if (pid.length != pidSize) {
        throw MobiInvalidPidException();
      }
      if (!verifyDrmKey(pid)) {
        throw MobiInvalidPidException();
      }
      if (!isEncrypted(data)) {
        addCookie(data, pid, 0, mobiNotSet);
        return;
      }
    }
    if (data.record0header?.encryptionType == mobiEncryptionV1) {
      // MOBI encryption V1 doesn't need PID
      pid = null;
    }
    var key = getDrmKey(pid, data);
    initDrmKey(data, key);
    if (data.record0header!.encryptionType! > 1) {
      addCookie(data, pid, 0, mobiNotSet);
    }
  }

  static addCookie(MobiData data, String? pid, int from, int to) {
    if (from > to) {
      throw MobiInvalidParameterException("from must be less than to");
    }
    data.drm ??= MobiDrm();
    if (data.drm!.cookiesCount >= vouchersCountMax) {
      throw MobiInvalidParameterException(
          "cookiesCount must be less than vouchersCountMax");
    }
    var cookie = DrmCookie(pid, from, to);
    data.drm!.cookies.add(cookie);
    data.drm!.cookiesCount++;
  }

  static List<int> getMobiKeyV1(MobiData data) {
    final rec = data.mobiPdbRecord!;
    int mobiVersion = getFileVersion(data);
    MobiBuffer buffer;
    if (mobiVersion > 1) {
      if (data.mobiHeader?.headerSize == null) {
        throw MobiInvalidDataException("MobiHeader is not loaded");
      }
      int offset = 0;
      if (mobiVersion > 2) {
        offset = 12;
      }
      buffer = MobiBuffer(rec.data!,
          data.mobiHeader!.headerSize! + record0HeaderLength + offset);
    } else {
      buffer = MobiBuffer(rec.data!, 14);
    }
    final encodedKey = buffer.getStringAsByte(keySize);
    return decryptPk1(encodedKey, keySize, internalReaderKeyV1);
  }

  static List<int> decryptPk1(Uint8List encodedData, int length, String key) {
    List<int> keyList = key.codeUnits;
    List<int> res = [];
    for (int i = 0; i < length; i++) {
      final inter = assemblyPk1(keyList);
      final cfc = inter >> 8;
      final cfd = inter & 0xff;
      var c = encodedData[i];
      c ^= (cfc ^ cfd);
      for (int j = 0; j < keySize; j++) {
        keyList[j] ^= c;
      }
      res.add(c);
    }
    return res;
  }

  static List<int> encryptPk1(Uint8List data, int length, String key) {
    List<int> keyList = key.codeUnits;
    List<int> res = [];
    for (int i = 0; i < length; i++) {
      final inter = assemblyPk1(keyList);
      final cfc = inter >> 8;
      final cfd = inter & 0xff;
      var c = data[i];
      for (int j = 0; j < keySize; j++) {
        keyList[j] ^= c;
      }
      c ^= (cfc ^ cfd);
      res.add(c);
    }
    return res;
  }

  static int assemblyPk1(List<int> key) {
    MobiPk1 pk1 = MobiPk1();
    pk1.x1a0[0] = (key[0] * 256) + key[1];
    int inter = pk1Code(pk1, 0);
    for (int i = 1; i < (keySize / 2).floor(); i++) {
      pk1.x1a0[i] = pk1.x1a0[i - 1] ^ ((key[i * 2] * 256) + key[i * 2 + 1]);
      inter ^= pk1Code(pk1, i);
    }
    return inter;
  }

  static int pk1Code(MobiPk1 pk1, int i) {
    int dx = pk1.x1a2 + i;
    int ax = pk1.x1a0[i];
    int cx = 0x015a;
    int bx = 0x4e35;
    int temp = ax;
    ax = pk1.si;
    pk1.si = temp;
    temp = ax;
    ax = dx;
    dx = temp;
    if (ax != 0) {
      ax *= bx;
    }
    temp = ax;
    ax = cx;
    cx = temp;
    if (ax != 0) {
      ax *= pk1.si;
      cx += ax;
    }
    temp = ax;
    ax = pk1.si;
    pk1.si = temp;
    ax *= bx;
    dx *= cx;
    ax += 1;
    pk1.x1a2 = dx;
    pk1.x1a0[i] = ax;
    return ax ^ dx;
  }

  static List<int> getMobiKeyV2(String? pid, MobiData data) {
    String? deviceKey;
    if (pid != null) {
      final pidKey = Uint8List.fromList(pid.codeUnits + "\\0".codeUnits);
      deviceKey = String.fromCharCodes(
          encryptPk1(pidKey, keySize, internalReaderKeyV1));
    }
    List<MobiVoucher> drms = getVouchers(data);
    bool keyExpired = false;
    for (var drm in drms) {
      int tries = 2;
      while (tries != 0) {
        final tryKey = (tries == 2) ? deviceKey : internalReaderKey;
        final tryType = (tries == 2) ? 1 : 3;
        if (tryKey != null && drm.checksum == checkSumDrmKey(tryKey)) {
          final cookie = decryptPk1(drm.cookie, cookieSize, tryKey);
          final ret = verifyCookie(drm.verification, cookie, tryType);
          if (ret == VerificationResult.success) {
            return cookie.sublist(8, 24);
          }
          if (ret == VerificationResult.expired) {
            keyExpired = true;
          }
        }
        tries--;
      }
    }
    if (keyExpired) {
      throw MobiDrmKeyNotFoundException();
    } else {
      throw MobiDrmKeyNotFoundException();
    }
  }

  static List<int> getDrmKey(String? pid, MobiData data) {
    if (data.record0header?.encryptionType == mobiEncryptionV1) {
      return getMobiKeyV1(data);
    } else {
      return getMobiKeyV2(pid, data);
    }
  }

  static VerificationResult verifyCookie(
      int drmVerification, List<int> cookie, int keyType) {
    final verification = get32BE(cookie.sublist(0, 4));
    final flags = get32BE(cookie.sublist(4, 8));
    if (verification == drmVerification && (flags & 0x1f) == keyType) {
      final to = get32BE(cookie.sublist(24, 28));
      final from = get32BE(cookie.sublist(28, 32));
      if (drmIsExpired(from, to)) {
        return VerificationResult.expired;
      }
      return VerificationResult.success;
    }
    return VerificationResult.keyNotFound;
  }

  static bool drmIsExpired(int from, int to) {
    if (from == 0 || to == mobiNotSet) {
      return false;
    }
    final now = (DateTime.now().millisecondsSinceEpoch / 60000).floor();
    if (now < from || now > to) {
      return true;
    }
    return false;
  }

  static List<MobiVoucher> getVouchers(MobiData data) {
    final offset = data.mobiHeader!.drmOffset!;
    final count = data.mobiHeader!.drmCount!;
    final size = data.mobiHeader!.drmSize!;

    if (offset == mobiNotSet || count == 0) {
      return [];
    }

    final rec = data.mobiPdbRecord!;
    if (offset + size > rec.size!) {
      return [];
    }
    final buffer = MobiBuffer(rec.data!, offset);
    List<MobiVoucher> drms =
        List.generate(data.mobiHeader!.drmCount!, (int i) => MobiVoucher());
    for (int i = 0; i < count; i++) {
      drms[i].verification = buffer.getInt32();
      drms[i].size = buffer.getInt32();
      drms[i].type = buffer.getInt32();
      drms[i].checksum = buffer.getInt32();
      buffer.seek(3);
      drms[i].cookie = buffer.getStringAsByte(cookieSize);
    }
    return drms;
  }

  static bool hasDrmKey(MobiData data) {
    return data.drm != null && data.drm?.key != null;
  }

  static bool isEncrypted(MobiData data) {
    return (isMobiPocket(data) ||
        isTextRead(data)) &&
        data.record0header?.encryptionType == mobiEncryptionV1 ||
        data.record0header?.encryptionType == mobiEncryptionV2;
  }

  static List<int> decryptBuffer(
      Uint8List data, MobiData mobiData, int length) {
    final drm = mobiData.drm;
    return decryptPk1(data, length, String.fromCharCodes(drm!.key!));
  }

  // port from mz_crc32 https://github.com/richgel999/miniz/blob/1ff82be7d67f5c2f8b5497f538eea247861e0717/miniz.c#L70
  static int crc32(String? pid, [int crc = 0xffffffff]) {
    crc = ~crc;
    if (pid == null) {
      return 0;
    }
    List<int> data = utf8.encode(pid);

    for (int i = 0; i < data.length; i++) {
      int c = data[i];
      crc = (crc >> 4) ^ s_crc32[(crc & 0xF) ^ (c & 0xF)];
      crc = (crc >> 4) ^ s_crc32[(crc & 0xF) ^ (c >> 4)];
    }
    return ~crc;
  }

  static const s_crc32 = [
    0,
    0x1db71064,
    0x3b6e20c8,
    0x26d930ac,
    0x76dc4190,
    0x6b6b51f4,
    0x4db26158,
    0x5005713c,
    0xedb88320,
    0xf00f9344,
    0xd6d6a3e8,
    0xcb61b38c,
    0x9b64c2b0,
    0x86d3d2d4,
    0xa00ae278,
    0xbdbdf21c
  ];
}

class DrmCookie {
  String? pid;
  int validFrom;
  int validTo;
  DrmCookie(this.pid, this.validFrom, this.validTo);
}

class MobiDrm {
  List<int>? key;
  int cookiesCount = 0;
  List<DrmCookie> cookies = [];
}

class MobiPk1 {
  int si = 0;
  int x1a2 = 0;
  List<int> x1a0 = List.filled(8, 0);
}

class MobiVoucher {
  int verification = 0;
  int size = 0;
  int type = 0;
  int checksum = 0;
  Uint8List cookie = Uint8List(cookieSize);
}

enum VerificationResult {
  success,
  expired,
  keyNotFound;
}
