import Flutter
import ImageIO
import Vision

final class FaceTrackingProcessor {
  private let queue = DispatchQueue(
    label: "com.speakup.face-tracking",
    qos: .userInteractive
  )

  func process(arguments: Any?, completion: @escaping ([String: Any]) -> Void) {
    guard
      let values = arguments as? [String: Any],
      let data = values["bytes"] as? FlutterStandardTypedData,
      let width = values["width"] as? Int,
      let height = values["height"] as? Int,
      let bytesPerRow = values["bytesPerRow"] as? Int
    else {
      completion(["detected": false])
      return
    }
    let frontCamera = values["frontCamera"] as? Bool ?? true
    queue.async {
      guard let buffer = self.pixelBuffer(
        data: data.data,
        width: width,
        height: height,
        sourceBytesPerRow: bytesPerRow
      ) else {
        DispatchQueue.main.async { completion(["detected": false]) }
        return
      }
      let orientation: CGImagePropertyOrientation = frontCamera
        ? .leftMirrored
        : .right
      let request = VNDetectFaceLandmarksRequest()
      request.revision = VNDetectFaceLandmarksRequestRevision3
      do {
        try VNImageRequestHandler(
          cvPixelBuffer: buffer,
          orientation: orientation
        ).perform([request])
        guard let face = request.results?.max(by: {
          $0.boundingBox.width < $1.boundingBox.width
        }) else {
          DispatchQueue.main.async { completion(["detected": false]) }
          return
        }
        let result = self.values(for: face)
        DispatchQueue.main.async { completion(result) }
      } catch {
        DispatchQueue.main.async { completion(["detected": false]) }
      }
    }
  }

  private func pixelBuffer(
    data: Data,
    width: Int,
    height: Int,
    sourceBytesPerRow: Int
  ) -> CVPixelBuffer? {
    var optionalBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    guard CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &optionalBuffer
    ) == kCVReturnSuccess, let buffer = optionalBuffer else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let destination = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let copyCount = min(sourceBytesPerRow, destinationBytesPerRow)
    data.withUnsafeBytes { sourceBytes in
      guard let source = sourceBytes.baseAddress else { return }
      for row in 0..<height {
        memcpy(
          destination.advanced(by: row * destinationBytesPerRow),
          source.advanced(by: row * sourceBytesPerRow),
          copyCount
        )
      }
    }
    return buffer
  }

  private func values(for face: VNFaceObservation) -> [String: Any] {
    let leftEye = openness(face.landmarks?.leftEye)
    let rightEye = openness(face.landmarks?.rightEye)
    let mouthOpen = openness(face.landmarks?.innerLips, multiplier: 3.2)
    let outerLips = bounds(face.landmarks?.outerLips)
    let smile: Double
    if let outerLips {
      let ratio = outerLips.width / max(outerLips.height, 0.001)
      smile = clamp((ratio - 2.0) / 2.3)
    } else {
      smile = 0
    }
    let radians35 = 35.0 * .pi / 180.0
    let radians30 = 30.0 * .pi / 180.0
    return [
      "detected": true,
      "yaw": clamp((face.yaw?.doubleValue ?? 0) / radians35, min: -1),
      "pitch": clamp((face.pitch?.doubleValue ?? 0) / radians30, min: -1),
      "roll": clamp((face.roll?.doubleValue ?? 0) / radians35, min: -1),
      "leftEye": leftEye,
      "rightEye": rightEye,
      "mouthOpen": mouthOpen,
      "smile": smile,
    ]
  }

  private func openness(
    _ region: VNFaceLandmarkRegion2D?,
    multiplier: Double = 5.2
  ) -> Double {
    guard let bounds = bounds(region) else { return 1 }
    return clamp((bounds.height / max(bounds.width, 0.001)) * multiplier)
  }

  private func bounds(_ region: VNFaceLandmarkRegion2D?) -> CGRect? {
    guard let region, region.pointCount > 1 else { return nil }
    let points = region.normalizedPoints
    var minX = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxY = -CGFloat.greatestFiniteMagnitude
    for index in 0..<region.pointCount {
      minX = min(minX, points[index].x)
      maxX = max(maxX, points[index].x)
      minY = min(minY, points[index].y)
      maxY = max(maxY, points[index].y)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private func clamp(_ value: Double, min minimum: Double = 0) -> Double {
    Swift.min(Swift.max(value, minimum), 1)
  }
}
