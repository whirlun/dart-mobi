import 'package:dart_mobi/src/dart_mobi_rawml.dart';

const palmdbNameLength = 32;
const record0HeaderLength = 16;
const compressionNone = 1;
const compressionPalmDoc = 2;
const compressionHuffCdic = 17480;
const mobiHeaderMagic = "MOBI";
const mobiHeaderV2Size = 0x18;
const mobiHeaderV3Size = 0x74;
const mobiHeaderV4Size = 0xd0;
const mobiHeaderV5Size = 0xe4;
const mobiHeaderV6Size = 0xe4;
const mobiHeaderV6ExtSize = 0xe8;
const mobiHeaderV7Size = 0xe4;
const mobiTitleSizeMax = 1024;
const mobiEncryptionV1 = 1;
const mobiEncryptionV2 = 2;
const pidSize = 10;
const mobiNotSet = 0xffffffff;
const exthMagic = "EXTH";
const exthMaxCount = 1024;
const boundaryMagic = "BOUNDARY";
const vouchersCountMax = 1024;
const huffMagic = "HUFF";
const huffHeaderLen = 24;
const huffCodeLenMax = 16;
const cdicMagic = "CDIC";
const cdicHeaderLen = 16;
const keySize = 16;
const internalReaderKeyV1 = "QDCVEPMU675RUBSZ";
const internalReaderKey =
    "\x72\x38\x33\xb0\xb4\xf2\xe3\xca\xdf\x09\x01\xd6\xe2\xe0\x3f\x96";
const cookieSize = 32;
const record0TextSizeMax = 4096;
const rawTextSizeMax = 0xfffffff;
const huffCodeTableSize = 33;
const huffmanMaxDepth = 20;
const mobiAttrNameMaxSize = 150;
const mobiAttrValueMaxSize = 150;
const fontHeaderLen = 24;
const fontSizeMax = 50 * 1024 * 1024;
const mobiFontObfuscatedBufferCount = 52;
const mediaHeaderLen = 12;
const indxRecordMaxCnt = 10000;
const mobiCp1252 = 1252;
const indxTotalMaxCnt = indxRecordMaxCnt * 0xffff;
const ordtRecordMaxCnt = 256;
const cncxRecordMaxCnt = 0xf;
const indxNameSizeMax = 0xff;
const indxLabelSizeMax = 1000;
const indxTagValuesMax = 100;
const attrNameMaxSize = 150;
const mobiFileMeta = {
  MobiFileType.html: {"ext": "html", "mime": "application/xhtml+xml"},
  MobiFileType.css: {"ext": "css", "mime": "text/css"},
  MobiFileType.svg: {"ext": "svg", "mime": "image/svg+xml"},
  MobiFileType.jpg: {"ext": "jpg", "mime": "image/jpeg"},
  MobiFileType.gif: {"ext": "gif", "mime": "image/gif"},
  MobiFileType.png: {"ext": "png", "mime": "image/png"},
  MobiFileType.bmp: {"ext": "bmp", "mime": "image/bmp"},
  MobiFileType.otf: {"ext": "otf", "mime": "application/vnd.ms-opentype"},
  MobiFileType.ttf: {"ext": "ttf", "mime": "application/x-font-truetype"},
  MobiFileType.mp3: {"ext": "mp3", "mime": "audio/mpeg"},
  MobiFileType.mpg: {"ext": "mpg", "mime": "video/mpeg"},
  MobiFileType.pdf: {"ext": "pdf", "mime": "application/pdf"},
  MobiFileType.opf: {"ext": "opf", "mime": "application/oebps-package+xml"},
  MobiFileType.ncx: {"ext": "ncx", "mime": "application/x-dtbncx+xml"},
  MobiFileType.unknown: {"ext": "dat", "mime": "application/unknown"},
};
