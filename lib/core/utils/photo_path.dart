/// A product photo is either a cloud URL (already uploaded) or the path of a
/// file on this device that has not been uploaded yet.
bool isRemotePhotoPath(String? path) =>
    path != null && (path.startsWith('http://') || path.startsWith('https://'));

/// True when [path] points at a device-local file awaiting upload.
bool isPendingLocalPhotoPath(String? path) =>
    path != null && path.isNotEmpty && !isRemotePhotoPath(path);

