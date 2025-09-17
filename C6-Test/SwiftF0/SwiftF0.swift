//
//  SwiftF0.swift
//  C6-Test
//
//  Created by 정희균 on 9/15/25.
//

import AVFoundation
import Accelerate
import OnnxRuntimeBindings
import Foundation

enum AudioLoadError: Error { case open, convert, buffer }

struct AudioLoader {
  static func loadPCM16kMono(url: URL) throws -> [Float] {
    guard let file = try? AVAudioFile(forReading: url) else { throw AudioLoadError.open }
    let inFmt = file.processingFormat
    guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: 16_000, channels: 1,
                                     interleaved: false) else { throw AudioLoadError.convert }
    guard let conv = AVAudioConverter(from: inFmt, to: outFmt) else { throw AudioLoadError.convert }

    let cap = AVAudioFrameCount(file.length)
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: cap) else { throw AudioLoadError.buffer }
    try file.read(into: inBuf)

    // 변환
    let ratio = outFmt.sampleRate / inFmt.sampleRate
    let outFrames = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1024
    guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outFrames) else { throw AudioLoadError.buffer }

    var done = false
    try conv.convert(to: outBuf, error: nil) { _, outStatus in
      if done { outStatus.pointee = .noDataNow; return nil }
      outStatus.pointee = .haveData; done = true; return inBuf
    }
    guard let ch = outBuf.floatChannelData else { throw AudioLoadError.buffer }
    return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
  }
}

// MARK: - vDSP STFT(1024/Hann, hop=256) → magnitude spectrogram
struct STFT {
  static func spectrogram(signal: [Float], fftSize: Int = 1024, hop: Int = 256) -> [[Float]] {
    let N = fftSize
    let half = N / 2
    let win = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: N, isHalfWindow: false)
    var setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(N), .FORWARD)!
    defer { vDSP_DFT_DestroySetup(setup) }

    // 프레임 분할
    guard signal.count >= N else { return [] }
    let frameCount = (signal.count - N) / hop + 1
    var spec = [[Float]]()
    spec.reserveCapacity(frameCount)

    var inReal = [Float](repeating: 0, count: N)
    var inImag = [Float](repeating: 0, count: N)
    var outReal = [Float](repeating: 0, count: N)
    var outImag = [Float](repeating: 0, count: N)

    for i in 0..<frameCount {
      let start = i * hop
      // windowing
      vDSP_vmul(Array(signal[start..<start+N]), 1, win, 1, &inReal, 1, vDSP_Length(N))
      // zero imag
      vDSP_vclr(&inImag, 1, vDSP_Length(N))
      // FFT
      vDSP_DFT_Execute(setup, inReal, inImag, &outReal, &outImag)
      // 0..half magnitude
      var mag = [Float](repeating: 0, count: half + 1)
      vDSP.hypot(outReal[0...half], outImag[0...half], result: &mag[0...half])
      spec.append(mag)
    }
    return spec
  }
}

final class SwiftF0OnnxRunner {
  private let env = try! ORTEnv(loggingLevel: .warning)
  private let session: ORTSession
  private let inputName: String
  private let outputName: String

  init() throws {
    let so = try ORTSessionOptions()
    // Core ML EP 사용(ANE/GPU 가속)
    let coreml = ORTCoreMLExecutionProviderOptions()
    coreml.createMLProgram = true
    try so.appendCoreMLExecutionProvider(with: coreml)

    guard let url = Bundle.main.url(forResource: "swiftf0", withExtension: "onnx") else {
      throw NSError(domain: "SwiftF0", code: -1, userInfo: [NSLocalizedDescriptionKey: "swiftf0.onnx not found"])
    }
    session = try ORTSession(env: env, modelPath: url.path, sessionOptions: so)

    // 입출력 이름 확인
    inputName = try session.inputNames().first ?? "input_audio"
    outputName = try session.outputNames().first ?? "output"
  }

  func runOnFile(url: URL) throws -> (pitchHz: [Float], confidence: [Float]) {
    // 1) 오디오 로드(16kHz mono Float32)
    var pcm = try AudioLoader.loadPCM16kMono(url: url)

    // (선택) 클리핑/정규화
    // vDSP.clip(pcm, to: -1...1, result: &pcm)

    // 2) ONNX 입력: [1, numSamples]  ← ★ 랭크 2로 맞춤
    let shape: [NSNumber] = [1, NSNumber(value: pcm.count)]
    let byteCount = pcm.count * MemoryLayout<Float>.size
    let data = NSMutableData(bytes: &pcm, length: byteCount)
    let inVal = try ORTValue(tensorData: data, elementType: .float, shape: shape)

    // (선택) 모델이 기대하는 입력 이름이 'input_audio' 인지 확인
    // print("Input name:", inputName)

    // 3) 추론
    let outs = try session.run(withInputs: [inputName: inVal],
                               outputNames: [outputName], runOptions: nil)
    guard let outVal = outs[outputName] else {
      throw NSError(domain: "SwiftF0", code: -2, userInfo: [NSLocalizedDescriptionKey: "No output"])
    }

    // 4) 출력 파싱
    // SwiftF0 Py패키지의 결과는 (pitch_hz, confidence, timestamps 등)인데,
    // ONNX의 실제 출력 shape/의미는 모델 버전에 따라 다를 수 있습니다.
    // 우선 float 배열만 꺼내고, shape는 ORTTypeInfo로 확인하여 맞추세요.
    let buf = try outVal.tensorData() as Data
    let floats = buf.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

    // 예시: [2, T] (0: pitch_hz, 1: confidence) 라고 가정한 간단 파서
    // 실제 shape는 아래 "I/O 점검 코드"로 출력해서 정확히 맞추세요.
    if floats.count % 2 == 0 {
      let T = floats.count / 2
      let pitch = Array(floats[0..<T])
      let conf  = Array(floats[T..<(2*T)])
      return (pitch, conf)
    } else {
      // 분포(logits)라면 softmax→기대값으로 Hz를 만들기
      // (모델 정의에 맞춰 구현 필요)
      return (floats, Array(repeating: 1.0, count: floats.count))
    }
  }

  /// 디버그: 모델의 예상 입력/출력 타입과 shape를 로그로 본다.
//  func dumpIODescriptions() {
//    do {
//      let inputs = try session.inputNames()
//      let outputs = try session.outputNames()
//      for name in inputs {
//        if let info = try? session.inputTypeInfo(for: name),
//           let tinfo = info.tensorTypeAndShapeInfo {
//          print("[IN] \(name) elem=\(tinfo.elementType) shape=\(tinfo.shape)")
//        }
//      }
//      for name in outputs {
//        if let info = try? session.outputTypeInfo(for: name),
//           let tinfo = info.tensorTypeAndShapeInfo {
//          print("[OUT] \(name) elem=\(tinfo.elementType) shape=\(tinfo.shape)")
//        }
//      }
//    } catch { print("dumpIODescriptions error:", error) }
//  }
}
