# CameraDirector

CameraDirector is a native macOS app built with Swift, SwiftUI and XcodeGen. It monitors multiple camera sources, keeps a persistent capture session per enabled source, runs Apple Vision face detection on the latest frames and can drive OBS scene switching from the live results.

## Architecture

The original implementation started a fresh FFmpeg process every time the analysis timer fired. That meant reconnecting to RTSP, waiting for a decodable frame, extracting one image and shutting the process down again.

The current architecture is persistent:

- RTSP sources use one long-lived FFmpeg process per enabled camera.
- Local webcams use one long-lived `AVCaptureSession` per enabled camera.
- Each session keeps only the most recent frame in memory.
- The monitoring scheduler consumes the latest frame at the configured interval.
- Vision analyzes only new frames and never starts FFmpeg itself.

## Source Types

Each camera can use one of these source types:

- `Network Stream`: RTSP stream captured through a persistent FFmpeg subprocess.
- `Local Camera`: macOS webcam captured through AVFoundation.

Both source types still participate in face detection, camera scoring and OBS scene switching.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- FFmpeg installed locally for RTSP sources
- OBS Studio with obs-websocket v5 enabled if you want scene control

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

## Run Tests

```bash
xcodebuild -project CameraDirector.xcodeproj -scheme CameraDirector test
```

If the environment blocks `testmanagerd`, the build still validates the test target compilation, but the XCTest execution itself may fail outside a normal macOS developer session.

## Capture Interval

`Capture Interval` is the analysis cadence, not a per-frame FFmpeg restart delay.

The app converts the interval into capture FPS for RTSP sessions:

```swift
fps = min(10.0, max(0.1, 1.0 / captureInterval))
```

Examples:

- `0.1 s` -> `10 FPS`
- `0.5 s` -> `2 FPS`
- `1.0 s` -> `1 FPS`
- `5.0 s` -> `0.2 FPS`
- `10.0 s` -> `0.1 FPS`

## RTSP Capture

For network streams, the app starts one persistent FFmpeg process per enabled source and keeps it alive while monitoring remains active.

Key points:

- Video only, first video stream only
- Audio ignored
- Fixed analysis resolution `640x360`
- Raw `bgra` frames over `stdout`
- Partial chunk parsing supported
- Automatic reconnect with backoff when FFmpeg exits or the stream stalls
- VideoToolbox requested first, with software fallback if hardware decoding fails

Typical command shape:

```text
-hide_banner
-loglevel warning
-rtsp_transport tcp
-hwaccel videotoolbox
-i STREAM_URL
-map 0:v:0
-an
-vf fps=DESIRED_FPS,scale=640:360
-pix_fmt bgra
-f rawvideo
pipe:1
```

## Local Webcam Capture

Local cameras do not use FFmpeg in the first path.

The app uses:

- `AVCaptureDevice`
- `AVCaptureSession`
- `AVCaptureDeviceInput`
- `AVCaptureVideoDataOutput`
- `AVCaptureVideoDataOutputSampleBufferDelegate`

The UI shows:

- available local devices
- permission status
- refresh button
- warning when the configured webcam no longer exists

## Camera Permission

Local webcams require macOS camera permission.

The project includes `NSCameraUsageDescription`, and the app requests permission through:

```swift
AVCaptureDevice.requestAccess(for: .video)
```

## OBS WebSocket Setup

1. Open OBS Studio.
2. Go to `Tools > WebSocket Server Settings`.
3. Enable the server.
4. Keep the default host `127.0.0.1` and port `4455`, or update the app settings.
5. Set a password if desired and use the same password in CameraDirector.

## Prepare OBS Scenes

Create one OBS scene per camera and use the exact scene names in the app:

- `Desk Scene`
- `Wide Scene`
- `Closeup Scene`

Local webcams also use `sceneName`, so they can participate in automatic switching exactly like RTSP sources.

## Example RTSP URL

With go2rtc, a typical RTSP URL can look like this:

```text
rtsp://127.0.0.1:8554/camera_c300
```

## How to Run

1. Generate the project with XcodeGen.
2. Open `CameraDirector.xcodeproj`.
3. Run the app from Xcode.
4. In `Settings`, add one or more sources.
5. Choose `Network Stream` or `Local Camera`.
6. Set the capture interval.
7. Optionally enable OBS integration and connect.
8. Click `Save and Apply`.
9. Open `Monitoring` to inspect frames, diagnostics, detected faces and the selected camera.

## Diagnostics

Useful commands when validating RTSP sessions:

```bash
pgrep -fl ffmpeg
ps aux | grep ffmpeg
```

Expected behavior:

- one persistent FFmpeg process per enabled RTSP camera
- no new FFmpeg process for every analysis tick
- stable PID while the stream is healthy

The monitoring cards also show:

- source type
- session mode
- configured FPS
- last frame sequence
- frame age
- restart count
- reconnecting state
- VideoToolbox usage or fallback
- FFmpeg PID when applicable

## Reconnection Behavior

When an RTSP session stops producing frames or FFmpeg exits unexpectedly, the app:

1. marks the session as reconnecting
2. terminates the dead process
3. retries with backoff

Backoff sequence:

- `1 s`
- `2 s`
- `5 s`
- `10 s`

The backoff resets after healthy frames arrive again.

## HEVC Notes

HEVC streams often depend on keyframes and hardware decode availability. The persistent architecture avoids reconnecting on every analysis tick, which greatly reduces startup latency and keyframe churn, but behavior can still vary depending on:

- stream stability
- GOP size
- HEVC encoder behavior
- VideoToolbox compatibility on the current Mac

If hardware decoding fails, the app automatically retries without `-hwaccel videotoolbox`.

## CPU and GPU Expectations

- RTSP decode may use GPU acceleration through VideoToolbox when available.
- Software fallback increases CPU usage.
- Local webcam capture uses AVFoundation and CI-based conversion.
- The app keeps only the newest frame per source, which reduces memory pressure compared with queueing many frames.

## Current Limitations

- UI updates still happen on the analysis cadence rather than a separate render loop.
- Local camera capture prefers a near-`640x360` path, but the exact native device resolution may vary.
- The direct `xcodebuild test` run can depend on the host environment allowing XCTest services.
