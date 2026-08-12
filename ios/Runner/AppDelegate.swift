import AVFoundation
import Flutter
import Photos
import ReplayKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let simulatorRecorder = SimulatorScreenRecorder()
  private let faceTrackingProcessor = FaceTrackingProcessor()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SpeakUpScreenRecording"
    ) else { return }
    let channel = FlutterMethodChannel(
      name: "com.speakup.app/screen_recording",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let recorder = RPScreenRecorder.shared()
      switch call.method {
      case "needsSeparateAudio":
        #if targetEnvironment(simulator)
        result(true)
        #else
        result(false)
        #endif
      case "start":
        #if targetEnvironment(simulator)
        guard let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap({ $0.windows })
          .first(where: { $0.isKeyWindow })
        else {
          result(FlutterError(code: "no_window", message: "The app window is not ready for recording.", details: nil))
          return
        }
        self.simulatorRecorder.start(window: window) { error in
          if let error {
            result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
        #else
        guard recorder.isAvailable else {
          result(FlutterError(code: "unavailable", message: "Screen recording is unavailable on this device.", details: nil))
          return
        }
        recorder.startRecording(withMicrophoneEnabled: true) { error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
        #endif
      case "stop":
        #if targetEnvironment(simulator)
        self.simulatorRecorder.stop { url, error in
          if let error {
            result(FlutterError(code: "stop_failed", message: error.localizedDescription, details: nil))
          } else {
            result(url?.path)
          }
        }
        #else
        guard #available(iOS 14.0, *) else {
          result(FlutterError(code: "unsupported", message: "Saving screen recordings requires iOS 14 or newer.", details: nil))
          return
        }
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("speakup-\(UUID().uuidString).mov")
        recorder.stopRecording(withOutput: url) { error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "stop_failed", message: error.localizedDescription, details: nil))
            } else if
              !FileManager.default.fileExists(atPath: url.path)
              || ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) == 0
            {
              result(FlutterError(code: "empty_recording", message: "The screen recording did not produce a playable video.", details: nil))
            } else {
              result(url.path)
            }
          }
        }
        #endif
      case "save":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(code: "missing_path", message: "The recorded video path is missing.", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "missing_file", message: "The recorded video file is no longer available.", details: nil))
          return
        }
        let saveToPhotos: () -> Void = {
          PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
          } completionHandler: { success, error in
            DispatchQueue.main.async {
              if success {
                result(nil)
              } else {
                result(FlutterError(code: "save_failed", message: error?.localizedDescription ?? "Could not save the video.", details: nil))
              }
            }
          }
        }
        if #available(iOS 14.0, *) {
          PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
              DispatchQueue.main.async {
                result(FlutterError(code: "photos_denied", message: "Please allow SpeakUp to add videos to Photos in Settings.", details: nil))
              }
              return
            }
            saveToPhotos()
          }
        } else {
          PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
              DispatchQueue.main.async {
                result(FlutterError(code: "photos_denied", message: "Please allow SpeakUp to add videos to Photos in Settings.", details: nil))
              }
              return
            }
            saveToPhotos()
          }
        }
      case "discard":
        if
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        {
          try? FileManager.default.removeItem(atPath: path)
        }
        result(nil)
      case "discardActive":
        #if targetEnvironment(simulator)
        self.simulatorRecorder.discard()
        result(nil)
        #else
        if recorder.isRecording {
          recorder.discardRecording { result(nil) }
        } else {
          result(nil)
        }
        #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let audioChannel = FlutterMethodChannel(
      name: "com.speakup.app/audio_extraction",
      binaryMessenger: registrar.messenger()
    )
    audioChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "extractWav":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["videoPath"] as? String
        else {
          result(FlutterError(code: "missing_path", message: "The video path is missing.", details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let wavPath = try self.extractAudioToWav(videoPath: path)
            DispatchQueue.main.async { result(wavPath) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "audio_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      case "deleteAudio":
        if
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        {
          try? FileManager.default.removeItem(atPath: path)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let faceChannel = FlutterMethodChannel(
      name: "com.speakup.app/face_tracking",
      binaryMessenger: registrar.messenger()
    )
    faceChannel.setMethodCallHandler { call, result in
      guard call.method == "processFrame" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.faceTrackingProcessor.process(arguments: call.arguments) { values in
        result(values)
      }
    }
  }

  private func extractAudioToWav(videoPath: String) throws -> String {
    let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(
        domain: "SpeakUpAudio",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The recording did not contain an audio track."]
      )
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]
    )
    guard reader.canAdd(output) else {
      throw NSError(
        domain: "SpeakUpAudio",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The recording audio could not be decoded."]
      )
    }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "SpeakUpAudio", code: 3) }
    var pcm = Data()
    while let sample = output.copyNextSampleBuffer() {
      if let block = CMSampleBufferGetDataBuffer(sample) {
        let length = CMBlockBufferGetDataLength(block)
        var bytes = [UInt8](repeating: 0, count: length)
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)
        pcm.append(contentsOf: bytes)
      }
      CMSampleBufferInvalidate(sample)
    }
    guard !pcm.isEmpty else {
      throw reader.error ?? NSError(
        domain: "SpeakUpAudio",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "The recording audio was empty."]
      )
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("speakup-audio-\(UUID().uuidString).wav")
    var wav = Data()
    func appendASCII(_ text: String) { wav.append(text.data(using: .ascii)!) }
    func appendLE16(_ value: UInt16) {
      var little = value.littleEndian
      wav.append(Data(bytes: &little, count: 2))
    }
    func appendLE32(_ value: UInt32) {
      var little = value.littleEndian
      wav.append(Data(bytes: &little, count: 4))
    }
    appendASCII("RIFF")
    appendLE32(UInt32(36 + pcm.count))
    appendASCII("WAVEfmt ")
    appendLE32(16)
    appendLE16(1)
    appendLE16(1)
    appendLE32(16_000)
    appendLE32(32_000)
    appendLE16(2)
    appendLE16(16)
    appendASCII("data")
    appendLE32(UInt32(pcm.count))
    wav.append(pcm)
    try wav.write(to: url, options: .atomic)
    return url.path
  }
}
