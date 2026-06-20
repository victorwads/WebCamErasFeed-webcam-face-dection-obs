# CameraDirector

CameraDirector is a native macOS app built with Swift, SwiftUI and XcodeGen. It captures still frames from multiple RTSP cameras through FFmpeg, runs Apple Vision face detection, overlays detected faces on the previews and prepares camera selection decisions for OBS scene switching.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- FFmpeg available locally
- OBS Studio with obs-websocket v5 enabled for scene control

## Install XcodeGen

```bash
brew install xcodegen
```

## Install FFmpeg

```bash
brew install ffmpeg
```

The app automatically searches for FFmpeg in these locations:

- `/opt/homebrew/bin/ffmpeg`
- `/usr/local/bin/ffmpeg`
- `/usr/bin/ffmpeg`

## Generate the Xcode Project

```bash
xcodegen generate
open CameraDirector.xcodeproj
```

## Build From the Command Line

```bash
xcodebuild -project CameraDirector.xcodeproj -scheme CameraDirector -configuration Debug build
```

## OBS WebSocket Setup

1. Open OBS Studio.
2. Go to `Tools > WebSocket Server Settings`.
3. Enable the server.
4. Keep the default host `127.0.0.1` and port `4455`, or update the app settings accordingly.
5. Set a password if desired and use the same password in CameraDirector.

## Prepare OBS Scenes

Create one OBS scene per camera and use the exact scene names in the app:

- `Desk Scene`
- `Wide Scene`
- `Closeup Scene`

Each camera definition should point to the exact OBS scene name that should become live when that camera wins.

## Example RTSP URL

With go2rtc, a typical RTSP URL can look like this:

```text
rtsp://localhost:8554/camera_c300
```

## How to Run

1. Generate the project with XcodeGen.
2. Open `CameraDirector.xcodeproj`.
3. Run the app from Xcode.
4. In `Settings`, add one or more cameras.
5. Set the capture interval.
6. Optionally enable OBS integration and connect.
7. Click `Save and Apply`.
8. Open `Monitoring` to inspect frames, detected faces and the selected camera.

## Current Limitations

- The first version captures periodic still frames instead of continuous video playback.
- OBS reconnection is basic and does not yet implement advanced retry backoff.
- Scene validation is limited to scene list refresh and manual scene switching.
- Selection stability uses fixed timing values tuned for a simple first release.
- Camera preview quality depends on RTSP stream health and FFmpeg responsiveness.
