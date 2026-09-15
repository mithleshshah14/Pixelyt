# Pixelyt

An app to remove unnecessary information from your image.

Pixelyt strips all hidden metadata from a photo — GPS location, camera
make/model, serial number, software tags, thumbnails, and everything else —
while keeping the one thing worth keeping: **when the photo was taken**.

## Features

- Pick a photo (or take one with the camera), clean it, then save the
  cleaned copy to your gallery or share it.
- **Android only:** Pixelyt can register itself as a photo source for other
  apps. When any app asks you to pick a photo to upload, you can choose
  Pixelyt from the system chooser — it shows your gallery, and whichever
  photo you tap is cleaned before being handed back to the requesting app.

## Getting started

```
flutter pub get
flutter run
```

Requires the Flutter SDK. See `pubspec.yaml` for dependencies.
