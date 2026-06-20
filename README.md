# CameraDirector

CameraDirector is a native macOS app built with Swift, SwiftUI and XcodeGen. It monitors multiple video sources, captures the latest frame from each provider, runs Apple Vision face detection, scores the cameras and can switch OBS scenes automatically through obs-websocket v5.

## Provider Architecture

The original app was centered on a frame-capture layer tied closely to FFmpeg sessions. The current architecture is provider-based:

- `FrameProvider` is the single contract used by monitoring, Vision, scoring and OBS.
- `FrameProviderCoordinator` owns active providers and applies configuration incrementally.
- `CapturedFrame` is the common frame model used everywhere after capture.
- `FrameProviderStatus` is the common runtime status model used by monitoring and diagnostics.

The shared contract is:

```swift
protocol FrameProvider: Sendable {
    var id: UUID { get }
    var configuration: CameraDefinition { get }

    func start() async throws
    func stop() async
    func getSnapshot() async throws -> CapturedFrame
    func latestFrame() async -> CapturedFrame?
    func getStatus() async -> FrameProviderStatus
}
```

The rest of the app does not need to know whether a frame came from FFmpeg, a WebView window or a local webcam.

## Supported Providers

Each camera/source can use one of these provider types:

- `FFmpeg RTSP`
- `WebView WebRTC`
- `Local Camera`

`CameraDefinition` preserves backward compatibility with older saved data that used the previous `sourceType` field. Legacy records migrate automatically to `providerType = .ffmpeg`.

## Capture Flow

### FFmpeg RTSP

- one persistent FFmpeg subprocess per enabled RTSP source
- latest BGRA frame kept in memory
- `getSnapshot()` returns the latest frame immediately
- automatic reconnect and VideoToolbox fallback remain enabled

### WebView WebRTC

This is the new flow for go2rtc WebRTC pages:

```text
go2rtc WebRTC URL
-> WKWebView
-> borderless NSWindow
-> OBS Window Capture
-> ScreenCaptureKit
-> latest CapturedFrame
-> Vision
```

Important details:

- each WebView source owns a dedicated borderless `NSWindow`
- the window title is stable, for example `WebCamErasFeed — Camera C300`
- `WKWebView.takeSnapshot()` is not used as the main path
- frames come from `ScreenCaptureKit`, not from WebKit snapshots
- the embedded media is muted and autoplay is requested
- `getSnapshot()` returns the latest frame already received by `ScreenCaptureKit`

### Local Camera

- one persistent `AVCaptureSession` per enabled local camera
- `AVCaptureVideoDataOutput` with `alwaysDiscardsLateVideoFrames = true`
- latest frame only, no preview queue buildup

## Why `WKWebView.takeSnapshot()` Is Not Used

WebRTC video inside a `WKWebView` can be rendered in accelerated layers. A WebKit snapshot can return:

- black frames
- stale frames
- missing video content

For that reason the WebView provider renders the page normally in a native window, and `ScreenCaptureKit` captures the final window surface.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [FFmpeg](https://ffmpeg.org/) installed locally for RTSP sources
- OBS Studio with obs-websocket v5 enabled if automatic scene switching is desired

## Install XcodeGen

```bash
brew install xcodegen
```

## Install FFmpeg

```bash
brew install ffmpeg
```

The app automatically searches for FFmpeg in:

- `/opt/homebrew/bin/ffmpeg`
- `/usr/local/bin/ffmpeg`
- `/usr/bin/ffmpeg`

## Generate the Project

```bash
xcodegen generate
open CameraDirector.xcodeproj
```

## Build

```bash
xcodebuild -project CameraDirector.xcodeproj -scheme CameraDirector -configuration Debug build
```

## Test

```bash
xcodebuild -project CameraDirector.xcodeproj -scheme CameraDirector -configuration Debug test
```

## Capture Interval

`Capture Interval` is the analysis cadence used by monitoring and Vision.

The app converts it to provider FPS with:

```swift
fps = min(10.0, max(0.1, 1.0 / captureInterval))
```

Examples:

- `0.1 s` -> `10 FPS`
- `0.5 s` -> `2 FPS`
- `1.0 s` -> `1 FPS`
- `5.0 s` -> `0.2 FPS`
- `10.0 s` -> `0.1 FPS`

## go2rtc WebRTC Example

Example page URL:

```text
http://127.0.0.1:1984/webrtc.html?src=camera_c300&media=video
```

Use `media=video` so the embedded page stays video-only.

## How to Add a WebView Source

1. Open `Settings`.
2. Add a new source.
3. Choose `WebView WebRTC` as `Provider Type`.
4. Fill:
   - `Name`
   - `OBS Scene Name`
   - `WebRTC Page URL`
   - `Window Width`
   - `Window Height`
5. Click `Open Window`.
6. Confirm that the dedicated window shows the camera stream.
7. Click `Save and Apply`.

The monitoring provider will then attach `ScreenCaptureKit` to that same window.

## Screen Recording Permission

The WebView provider may require Screen Recording permission depending on the capture path available on the current macOS version and environment.

If the app reports a permission error:

1. Open `System Settings`
2. Open `Privacy & Security`
3. Open `Screen Recording`
4. Enable access for `CameraDirector`
5. Restart the app if needed

The monitoring cards surface this as a provider error instead of failing silently.

## Local Camera Permission

Local webcam providers use AVFoundation and require camera permission.

The app includes:

```text
NSCameraUsageDescription
```

and requests access through:

```swift
AVCaptureDevice.requestAccess(for: .video)
```

## OBS Setup

### WebSocket

1. Open OBS Studio.
2. Go to `Tools > WebSocket Server Settings`.
3. Enable the server.
4. Use host `127.0.0.1` and port `4455`, or match the app settings.
5. Configure a password if desired.

### Scenes

Create one OBS scene per camera/source and use the exact scene names in CameraDirector.

### WebView Window Capture

For each WebView source:

1. Open the corresponding CameraDirector WebView window.
2. In OBS, create or open the scene for that camera.
3. Add `Window Capture`.
4. Select the CameraDirector window by its title.
5. Disable cursor capture.
6. Keep the CameraDirector window alive.

CameraDirector can then keep controlling which OBS scene is active through obs-websocket.

## Monitoring Diagnostics

The monitoring cards now show provider-level diagnostics such as:

- provider type
- provider state
- latest frame timestamp
- frame sequence
- frame age
- restart count
- FFmpeg PID
- VideoToolbox usage
- WebView navigation state
- window visibility state
- ScreenCaptureKit status
- loaded URL
- permission errors

## Useful Commands

For RTSP validation:

```bash
pgrep -fl ffmpeg
ps aux | grep ffmpeg
```

Expected behavior:

- one persistent FFmpeg process per enabled RTSP source
- stable PID while the stream is healthy
- no new FFmpeg process on every monitoring cycle

## Face Detection and Selection

All providers feed the same pipeline:

```text
FrameProvider
-> CapturedFrame
-> Vision
-> FaceDetectionResult
-> CameraSelectionEngine
-> OBS
```

Automatic selection still uses lexicographic priority:

1. more faces
2. larger face
3. larger total face area
4. keep current camera on ties when possible

## Known Limitations

- WebView window position persistence is still basic compared with size persistence.
- The WebView provider depends on the page rendering correctly inside `WKWebView`.
- Some WebRTC pages may still require source-specific tuning in go2rtc.
- ScreenCaptureKit behavior can vary depending on macOS permissions and compositor state.
- FFmpeg HEVC sources may still depend on stream quality, GOP structure and hardware decode compatibility.
- The test host may still emit harmless system-service warnings from macOS when launching the app bundle under XCTest.
