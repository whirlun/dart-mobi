abstract class MobiException implements Exception {
  final String message;

  MobiException(this.message);

  @override
  String toString() => message;
}

class MobiBufferOverflowException extends MobiException {
  MobiBufferOverflowException() : super("Buffer Overflow");
}

class MobiInvalidDataException extends MobiException {
  final String addtionalMessage;
  MobiInvalidDataException(this.addtionalMessage)
      : super("Invalid Data: $addtionalMessage");
}

class MobiUnsupportedTypeException extends MobiException {
  final String? type;
  MobiUnsupportedTypeException(this.type)
      : super("Unsupported file Type: $type");
}

class MobiInvalidPidException extends MobiException {
  MobiInvalidPidException() : super("Invalid Pid");
}

class MobiInvalidParameterException extends MobiException {
  final String addtionalMessage;
  MobiInvalidParameterException(this.addtionalMessage)
      : super("Invalid Parameter: $addtionalMessage");
}

class MobiDrmExpiredException extends MobiException {
  MobiDrmExpiredException() : super("DRM Key Expired");
}

class MobiDrmKeyNotFoundException extends MobiException {
  MobiDrmKeyNotFoundException() : super("DRM Key Not Found");
}

class MobiFileEncryptedException extends MobiException {
  MobiFileEncryptedException() : super("File is Encrypted");
}
