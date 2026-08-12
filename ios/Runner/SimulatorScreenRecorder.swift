import AVFoundation
import Flutter
import UIKit

/// ReplayKit doesn't reliably emit a movie in the iOS Simulator. This recorder
/// renders the app window into an H.264 movie so the complete Flutter layout can
/// still be saved and inspected while developing in the simulator.
final class SimulatorScreenRecorder: NSObject {
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var displayLink: CADisplayLink?
  private var startedAt: CFTimeInterval = 0
  private var outputURL: URL?
  private weak var window: UIWindow?
  private var outputSize = CGSize.zero
  private var lastFrameTime: CFTimeInterval = 0

  var isRecording: Bool { displayLink != nil }

  func start(window: UIWindow, completion: @escaping (Error?) -> Void) {
    discard()
    self.window = window

    let targetWidth = 720
    let aspect = window.bounds.height / max(window.bounds.width, 1)
    let rawHeight = Int((CGFloat(targetWidth) * aspect).rounded())
    let targetHeight = rawHeight.isMultiple(of: 2) ? rawHeight : rawHeight + 1
    outputSize = CGSize(width: targetWidth, height: targetHeight)

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("speakup-simulator-\(UUID().uuidString).mov")
    do {
      let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
      let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: targetWidth,
        AVVideoHeightKey: targetHeight,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 4_000_000,
          AVVideoExpectedSourceFrameRateKey: 15,
          AVVideoMaxKeyFrameIntervalKey: 30,
        ],
      ]
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
      input.expectsMediaDataInRealTime = true
      guard writer.canAdd(input) else {
        throw RecorderError.cannotAddVideoInput
      }
      writer.add(input)
      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: targetWidth,
        kCVPixelBufferHeightKey as String: targetHeight,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: attributes
      )
      guard writer.startWriting() else {
        throw writer.error ?? RecorderError.cannotStartWriter
      }
      writer.startSession(atSourceTime: .zero)
      self.writer = writer
      self.input = input
      self.adaptor = adaptor
      outputURL = url
      startedAt = CACurrentMediaTime()
      lastFrameTime = 0
      let link = CADisplayLink(target: self, selector: #selector(captureFrame(_:)))
      link.preferredFramesPerSecond = 15
      link.add(to: .main, forMode: .common)
      displayLink = link
      completion(nil)
    } catch {
      discard()
      completion(error)
    }
  }

  func stop(completion: @escaping (URL?, Error?) -> Void) {
    displayLink?.invalidate()
    displayLink = nil
    guard let writer, let input, let url = outputURL else {
      completion(nil, RecorderError.notRecording)
      return
    }
    input.markAsFinished()
    writer.finishWriting { [weak self] in
      DispatchQueue.main.async {
        let error = writer.error
        let valid = writer.status == .completed
          && FileManager.default.fileExists(atPath: url.path)
          && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        self?.writer = nil
        self?.input = nil
        self?.adaptor = nil
        self?.outputURL = valid ? url : nil
        completion(valid ? url : nil, error ?? (valid ? nil : RecorderError.emptyMovie))
      }
    }
  }

  func discard() {
    displayLink?.invalidate()
    displayLink = nil
    writer?.cancelWriting()
    if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    writer = nil
    input = nil
    adaptor = nil
    outputURL = nil
  }

  @objc private func captureFrame(_ link: CADisplayLink) {
    guard
      link.timestamp - lastFrameTime >= (1.0 / 15.0),
      let window,
      let input,
      input.isReadyForMoreMediaData,
      let adaptor,
      let pool = adaptor.pixelBufferPool
    else { return }
    lastFrameTime = link.timestamp
    var optionalBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
          let buffer = optionalBuffer
    else { return }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let base = CVPixelBufferGetBaseAddress(buffer),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: base,
        width: Int(outputSize.width),
        height: Int(outputSize.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return }

    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(origin: .zero, size: outputSize))
    context.translateBy(x: 0, y: outputSize.height)
    context.scaleBy(
      x: outputSize.width / window.bounds.width,
      y: -outputSize.height / window.bounds.height
    )
    window.layer.render(in: context)
    let time = CMTime(
      seconds: max(link.timestamp - startedAt, 0),
      preferredTimescale: 600
    )
    adaptor.append(buffer, withPresentationTime: time)
  }
}

private enum RecorderError: LocalizedError {
  case cannotAddVideoInput
  case cannotStartWriter
  case notRecording
  case emptyMovie

  var errorDescription: String? {
    switch self {
    case .cannotAddVideoInput: "Could not configure the simulator video encoder."
    case .cannotStartWriter: "Could not start the simulator video encoder."
    case .notRecording: "No simulator recording is active."
    case .emptyMovie: "The simulator did not produce a playable video."
    }
  }
}
