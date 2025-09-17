//
//  SwiftF0RealtimeRunner.swift
//  C6-Test
//
//  Created by 정희균 on 9/15/25.
//

import AVFoundation
import Accelerate
import Foundation
import OnnxRuntimeBindings

// MARK: - 실시간 마이크 → swift-f0(ONNX) 스트리밍 러너
final class SwiftF0RealtimeRunner {

  // ===== Public API =====
  struct Config {
    var sampleRate: Double = 16_000  // swift-f0 가정 샘플레이트
    var chunkSeconds: Double = 2.0  // 한 번에 추론할 길이(초) — 예: 2초
    var overlapSeconds: Double = 0.5  // 인접 청크와 겹침(추론 안정)
  }

  var onResult: (([Float], [Float], Double) -> Void)?
  // 콜백: (f0Hz[], confidence[], startTimeSec)
  //  - f0Hz/confidence 길이는 프레임 수(hop=256 샘플 → 약 62.5fps)
  //  - startTimeSec: 해당 청크의 스트림 시작 시간(초)

  init(
    modelName: String = "swiftf0",
    modelExt: String = "onnx",
    config: Config = .init()
  ) throws {
    self.config = config
    self.ort = try ORTEnv(loggingLevel: .warning)
    self.session = try Self.makeSession(
      env: ort,
      modelName: modelName,
      ext: modelExt
    )
    (self.inputName, self.outputNames) = try Self.getIONames(session)
    self.chunkSamples = Int(config.sampleRate * config.chunkSeconds)
    self.overlapSamples = Int(config.sampleRate * config.overlapSeconds)
    self.effectiveStep = max(1, chunkSamples - overlapSamples)
  }

  func start() throws {
    try configureAudioSession()  // 카테고리, 샘플레이트, I/O 버퍼 설정
    try startEngineTap()  // inputNode tap 설치
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
  }

  // ===== Internals =====
  private let config: Config
  private let engine = AVAudioEngine()
  private let ort: ORTEnv
  private let session: ORTSession
  private let inputName: String
  private let outputNames: [String]

  // 리샘플러(마이크 포맷 → 16kHz 모노 Float32)
  private var converter: AVAudioConverter?
  // 링 버퍼(16kHz 모노 Float32 누적)
  private var ring = [Float]()
  private var streamSamplesElapsed: Int = 0

  private let chunkSamples: Int
  private let overlapSamples: Int
  private let effectiveStep: Int

  private static func makeSession(env: ORTEnv, modelName: String, ext: String)
    throws -> ORTSession
  {
    let so = try ORTSessionOptions()
    // CoreML EP 등록 (ANE/GPU/CPU, MLProgram 권장)
    let coreml = ORTCoreMLExecutionProviderOptions()
    coreml.createMLProgram = true
    coreml.onlyAllowStaticInputShapes = false
    coreml.enableOnSubgraphs = false
    coreml.useCPUOnly = false
    try so.appendCoreMLExecutionProvider(with: coreml)  // iOS에서 Core ML EP 사용  [oai_citation:3‡ONNX Runtime](https://onnxruntime.ai/docs/get-started/with-obj-c.html?utm_source=chatgpt.com)
    guard let url = Bundle.main.url(forResource: modelName, withExtension: ext)
    else {
      throw NSError(
        domain: "SwiftF0",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "ONNX model not found"]
      )
    }
    return try ORTSession(env: env, modelPath: url.path, sessionOptions: so)
  }

  private static func getIONames(_ s: ORTSession) throws -> (String, [String]) {
    guard let in0 = try s.inputNames().first else {
      throw NSError(
        domain: "SwiftF0",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid IO names"]
      )
    }
    let out0 = try s.outputNames()
    return (in0, out0)
  }

  private func configureAudioSession() throws {
    // 마이크 + 스피커 동시 (에코 취소 등은 앱 특성에 맞게 옵션 조정)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
    )
    try session.setPreferredSampleRate(config.sampleRate)
    try session.setActive(true)
    // 사용 카테고리/옵션 및 샘플레이트는 Apple 문서 권장 패턴을 따름  [oai_citation:4‡Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord?utm_source=chatgpt.com)
  }

  private func startEngineTap() throws {
    let input = engine.inputNode
    let hwFormat = input.inputFormat(forBus: 0)  // 디바이스 마이크 포맷(예: 44.1k/48k, mono/stereo)

    // 16kHz 모노 Float32 타깃 포맷
    guard
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: config.sampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw NSError(
        domain: "SwiftF0",
        code: -3,
        userInfo: [NSLocalizedDescriptionKey: "Failed to make target format"]
      )
    }
    converter = AVAudioConverter(from: hwFormat, to: target)  // 샘플레이트/채널 변환기 (공식 TN 패턴)  [oai_citation:5‡Apple Developer](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions?utm_source=chatgpt.com)

    // 엔진 시작 및 탭 설치
    engine.prepare()
    try engine.start()

    // 주의: 탭 설치는 Apple 가이드대로 inputNode에 format 지정  [oai_citation:6‡Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap%28onbus%3Abuffersize%3Aformat%3Ablock%3A%29?utm_source=chatgpt.com)
    input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) {
      [weak self] (buffer, time) in
      guard let self else { return }
      self.feed(buffer: buffer, fromFormat: hwFormat, to: target)
    }
  }

  private func feed(
    buffer: AVAudioPCMBuffer,
    fromFormat: AVAudioFormat,
    to target: AVAudioFormat
  ) {
    guard let converter else { return }
    // 입력 버퍼를 한 번에 변환 (TN3136 패턴: convert(to:withInputFrom:))  [oai_citation:7‡Apple Developer](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions?utm_source=chatgpt.com)
    let ratio = target.sampleRate / fromFormat.sampleRate
    let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard
      let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames)
    else { return }

    var inputProvided = false
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      if inputProvided {
        outStatus.pointee = .noDataNow
        return nil
      } else {
        outStatus.pointee = .haveData
        inputProvided = true
        return buffer
      }
    }

    do {
      try converter.convert(to: out, error: nil, withInputFrom: inputBlock)
    } catch { return }

    guard let ch = out.floatChannelData else { return }
    let count = Int(out.frameLength)
    // 링 버퍼에 16kHz 모노 float 샘플을 누적
    ring.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
    streamSamplesElapsed += count

    // 충분히 쌓이면 (chunkSamples 단위로, overlap 고려) 추론 실행
    while ring.count >= chunkSamples {
      // 현재 청크 시작까지의 스트림 시간(초)
      let startTimeSec =
        Double(streamSamplesElapsed - ring.count) / config.sampleRate
      let chunk = Array(ring[0..<chunkSamples])
      runONNX(samples: chunk, startTimeSec: startTimeSec)
      // overlap을 남기고 step만큼 버림
      ring.removeFirst(effectiveStep)
    }
  }

  private func runONNX(samples: [Float], startTimeSec: Double) {
    // swift-f0의 ONNX 입력은 (에러 로그로 보아) 랭크 2 [1, numSamples] 형태
    // → 2D 텐서로 구성 (배치 1, 길이 N).  [oai_citation:8‡ONNX Runtime](https://onnxruntime.ai/docs/get-started/with-obj-c.html?utm_source=chatgpt.com)
    let shape: [NSNumber] = [1, NSNumber(value: samples.count)]
    let byteCount = samples.count * MemoryLayout<Float>.size
    let data = NSMutableData(
      bytes: UnsafeMutablePointer(mutating: samples),
      length: byteCount
    )
    guard
      let inVal = try? ORTValue(
        tensorData: data,
        elementType: .float,
        shape: shape
      )
    else { return }

    do {
      let out = try session.run(
        withInputs: [inputName: inVal],
        outputNames: Set(outputNames),
        runOptions: nil
      )
      guard let outputName = outputNames.first else { return }
      guard let outVal = out[outputName],
        let raw = try? outVal.tensorData() as Data
      else { return }
      let floats = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

      if let confName = outputNames.last, let confVal = out[confName],
        let confRaw = try? confVal.tensorData() as Data
      {
        let conf = confRaw.withUnsafeBytes {
          Array($0.bindMemory(to: Float.self))
        }

        onResult?(floats, conf, startTimeSec)
      } else {
        onResult?(
          floats,
          Array(repeating: 1, count: floats.count),
          startTimeSec
        )
      }
    } catch {
      // 추론 실패 무시(스트리밍 지속)
    }
  }
}
