//
//  BasicPitchViewModel.swift
//  C6-Test
//
//  Created by 정희균 on 9/22/25.
//

import AVFAudio
import AudioToolbox
import CoreML
import Foundation
import OSLog

// ---------------------------------------------------------
// MARK: - 간단한 노트 이벤트 모델
// ---------------------------------------------------------
struct NoteEvent {
  var pitch: UInt8  // MIDI note number
  var startSec: Double
  var endSec: Double
  var velocity: UInt8
}

// ---------------------------------------------------------
// MARK: - Basic Pitch 추론 러너 (Core ML)
//  - 입력: 22_050 Hz, mono Float32 PCM 버퍼 (프레임 N)
//  - 출력: 간단화된 "피치 확률 맵"을 가정한 후처리 스텁
// ---------------------------------------------------------
final class BasicPitchRunner {
  private var model: nmp
  private let sampleRate: Double = 22_050
  private let windowSamples = 43_844
  private let frames = 172
  private let pitches = 88
  private let hopSec: Double = 1.988390022675737 / 172.0  // ≈ 0.01156

  init() throws {
    self.model = try nmp()
  }

  func predictNotes(from mono22050: [Float]) throws -> [NoteEvent] {
    // 1) 입력 길이 맞추기 (부족하면 0패딩, 넘치면 자르기)
    var inputBuf = mono22050
    if inputBuf.count < windowSamples {
      inputBuf.append(
        contentsOf: repeatElement(0, count: windowSamples - inputBuf.count)
      )
    } else if inputBuf.count > windowSamples {
      inputBuf = Array(inputBuf.prefix(windowSamples))
    }

    // 2) MLMultiArray 생성 (shape [1, 43844, 1])
    let input = try MLMultiArray(
      shape: [1, NSNumber(value: windowSamples), 1],
      dataType: .float32
    )
    for i in 0..<windowSamples { input[i] = NSNumber(value: inputBuf[i]) }

    // 3) 추론
    let out = try model.prediction(input_2: input)

    // 4) 출력 텐서 꺼내기
    let identity = out.Identity
    print(out.Identity_1)
    // shape: [1, 172, 264] 라 가정 → flat index: t*264 + c
    let strideC = 264

    // 5) 간단 임계값/히스테리시스로 노트 묶기
    let actThresh: Float = 0.5
    let velScale: (Float) -> UInt8 = {
      UInt8(max(1, min(127, Int($0 * 127.0))))
    }

    var active: [(pitch: Int, startT: Int, vel: UInt8)] = []
    var notes: [NoteEvent] = []

    for t in 0..<frames {
      // 온셋/오프셋을 보조로 쓰고 싶다면:
      // let onsetProb(p)  = identity[t*264 + 88 + p].floatValue
      // let offsetProb(p) = identity[t*264 + 176 + p].floatValue

      for p in 0..<pitches {
        let act = identity[t * strideC + p].floatValue  // activation
        let isOn = act >= actThresh

        if isOn {
          // 아직 활성화 안 된 피치면 시작
          if !active.contains(where: { $0.pitch == p }) {
            active.append((pitch: p, startT: t, vel: velScale(act)))
          }
        } else {
          // 활성화 중이던 피치면 종료
          if let idx = active.firstIndex(where: { $0.pitch == p }) {
            let a = active.remove(at: idx)
            let startSec = Double(a.startT) * hopSec
            let endSec = Double(t) * hopSec
            notes.append(
              NoteEvent(
                pitch: UInt8(21 + p),  // MIDI 21(A0) 기준 88키 매핑 가정
                startSec: startSec,
                endSec: max(startSec + 0.03, endSec),
                velocity: a.vel
              )
            )
          }
        }
      }
    }
    // tail flush
    for a in active {
      let startSec = Double(a.startT) * hopSec
      let endSec = Double(frames) * hopSec
      notes.append(
        NoteEvent(
          pitch: UInt8(21 + a.pitch),
          startSec: startSec,
          endSec: endSec,
          velocity: a.vel
        )
      )
    }
    return notes
  }
}

// ---------------------------------------------------------
// MARK: - 오디오 캡처 + 22.05kHz 모노 리샘플
//  - inputNode는 포맷 고정이므로 탭으로 뽑아와 AVAudioConverter로 다운샘플
// ---------------------------------------------------------
final class MicCapture {
  private let engine = AVAudioEngine()
  private let log = Logger(subsystem: "BasicPitchDemo", category: "Mic")

  private let targetSR: Double = 22_050
  private let targetFormat: AVAudioFormat
  private var converter: AVAudioConverter!

  private let queue = DispatchQueue(label: "MicCaptureQueue")
  private var bufferSec: [Float] = []  // 누적 버퍼(초 단위 길이로 생각)

  var onChunk: (([Float]) -> Void)?

  init?() {
    guard
      let fmt = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSR,
        channels: 1,
        interleaved: false
      )
    else { return nil }
    self.targetFormat = fmt
  }

  func start() throws {
    let input = engine.inputNode
    let inputFormat = input.inputFormat(forBus: 0)

    converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    try AVAudioSession.sharedInstance().setCategory(
      .playAndRecord,
      mode: .measurement,
      options: [.defaultToSpeaker, .allowBluetoothHFP]
    )
    try AVAudioSession.sharedInstance().setActive(true)

    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
      [weak self] (buffer, _) in
      guard let self = self else { return }
      self.queue.async {
        self.processBuffer(buffer, from: inputFormat)
      }
    }
    try engine.start()
    log.info(
      "Mic started: input \(inputFormat.sampleRate) Hz -> \(self.targetSR) Hz"
    )
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
  }

  private func processBuffer(
    _ buffer: AVAudioPCMBuffer,
    from inFormat: AVAudioFormat
  ) {
    guard let converter = converter else { return }

    var newBufferData = [Float]()
    let capacity = AVAudioFrameCount(
      Double(buffer.frameLength) * (targetSR / inFormat.sampleRate) + 512
    )
    guard
      let outBuf = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: capacity
      )
    else { return }

    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }
    do {
      var error: NSError? = nil
      let status = converter.convert(
        to: outBuf,
        error: &error,
        withInputFrom: inputBlock
      )
      if status == .haveData || status == .inputRanDry {
        let frameLen = Int(outBuf.frameLength)
        if let ch = outBuf.floatChannelData?[0] {
          newBufferData.append(
            contentsOf: UnsafeBufferPointer(start: ch, count: frameLen)
          )
        }
      }
      if let e = error {
        log.error("Converter error: \(e.localizedDescription)")
      }
    }

    // 0.5초 단위로 청크 콜백(예: 11025샘플씩)
    bufferSec.append(contentsOf: newBufferData)
    let chunkSamples = Int(targetSR * 0.5)
    while bufferSec.count >= chunkSamples {
      let chunk = Array(bufferSec.prefix(chunkSamples))
      bufferSec.removeFirst(chunkSamples)
      onChunk?(chunk)
    }
  }
}

// ---------------------------------------------------------
// MARK: - MIDI 저장 유틸
// ---------------------------------------------------------
enum MIDIWriter {
  static func writeMIDINotes(
    _ notes: [NoteEvent],
    to url: URL,
    ppq: UInt32 = 480,  // ticks per quarter note
    tempoBPM: Double = 120.0,
    timeSignatureNumerator nn: UInt8 = 4,
    timeSignatureDenominator dd: UInt8 = 4
  ) throws {
    var sequence: MusicSequence?
    NewMusicSequence(&sequence)
    guard let seq = sequence else {
      throw NSError(domain: "MIDIWriter", code: -1, userInfo: nil)
    }

    var track: MusicTrack?
    MusicSequenceNewTrack(seq, &track)
    guard let musicTrack = track else {
      throw NSError(domain: "MIDIWriter", code: -2, userInfo: nil)
    }

    // Tempo track
    var tempoTrack: MusicTrack?
    MusicSequenceGetTempoTrack(seq, &tempoTrack)
    if let tt = tempoTrack {
      var tempoEvent = ExtendedTempoEvent(bpm: tempoBPM)
      MusicTrackNewExtendedTempoEvent(tt, 0, tempoEvent.bpm)
    }

    // Add time signature meta event
    if let tt = tempoTrack {
      try addTimeSignatureMetaEvent(
        to: tt,
        time: 0,
        numerator: nn,
        denominator: dd,
        clocksPerClick: 24,
        notated32ndsPerBeat: 8
      )
    }

    // Helper: 초 → 비트(Quarter 노트) 변환
    func secondsToBeats(_ seconds: Double) -> MusicTimeStamp {
      return MusicTimeStamp(seconds * (tempoBPM / 60.0))
    }

    // Note 이벤트 삽입 (beat 단위 타임스탬프 사용)
    for n in notes {
      let startBeat = secondsToBeats(n.startSec)
      let durationBeat = secondsToBeats(n.endSec - n.startSec)
      var msg = MIDINoteMessage(
        channel: 0,
        note: n.pitch,
        velocity: n.velocity,
        releaseVelocity: 0,
        duration: Float32(max(0.05, durationBeat))
      )
      MusicTrackNewMIDINoteEvent(musicTrack, startBeat, &msg)
    }

    // 저장 - PPQ 지정
    let status = MusicSequenceFileCreate(
      seq,
      url as CFURL,
      .midiType,
      .eraseFile,
      Int16(ppq)
    )
    guard status == noErr else {
      throw NSError(
        domain: NSOSStatusErrorDomain,
        code: Int(status),
        userInfo: nil
      )
    }
  }

  static func addTimeSignatureMetaEvent(
    to track: MusicTrack,
    time: MusicTimeStamp,
    numerator nn: UInt8,
    denominator dd: UInt8,
    clocksPerClick cc: UInt8 = 24,
    notated32ndsPerBeat bb: UInt8 = 8
  ) throws {
    guard let denominatorPow2 = powerOfTwoExponent(of: dd) else {
      throw NSError(
        domain: "MIDIWriter",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Denominator must be power of 2"]
      )
    }

    let payload: [UInt8] = [nn, UInt8(denominatorPow2), cc, bb]
    let headerSize = MemoryLayout<MIDIMetaEvent>.size
    let totalSize = headerSize + payload.count - 1

    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: totalSize,
      alignment: MemoryLayout<UInt8>.alignment
    )
    raw.initializeMemory(as: UInt8.self, repeating: 0, count: totalSize)
    let metaPtr = raw.bindMemory(to: MIDIMetaEvent.self, capacity: 1)

    metaPtr.pointee.metaEventType = 0x58
    metaPtr.pointee.unused1 = 0
    metaPtr.pointee.unused2 = 0
    metaPtr.pointee.unused3 = 0
    metaPtr.pointee.dataLength = UInt32(payload.count)

    let dataStart = raw.advanced(by: headerSize - 1)
    payload.withUnsafeBytes { src in
      dataStart.copyMemory(from: src.baseAddress!, byteCount: payload.count)
    }

    let status = MusicTrackNewMetaEvent(track, time, metaPtr)
    raw.deallocate()
    if status != noErr {
      throw NSError(
        domain: NSOSStatusErrorDomain,
        code: Int(status),
        userInfo: nil
      )
    }
  }

  static func powerOfTwoExponent(of value: UInt8) -> Int? {
    if value == 0 { return nil }
    var v = value
    var exp = 0
    while v > 1 {
      if v % 2 != 0 { return nil }
      v /= 2
      exp += 1
    }
    return exp
  }
}

// ---------------------------------------------------------
// MARK: - ViewModel: 모든 걸 연결
// ---------------------------------------------------------
@Observable
final class BasicPitchViewModel {
  private let mic = MicCapture()!
  private let runner = try! BasicPitchRunner()

  private var collected: [Float] = []
  private let targetSR: Double = 22_050

  private(set) var notes: [NoteEvent] = []

  init() {
    // 2초 단위로 추론(데모 목적)
    mic.onChunk = { [weak self] chunk in
      guard let self = self else { return }
      self.collected += chunk
      let need = Int(self.targetSR * 2.0)
      if self.collected.count >= need {
        let slice = Array(self.collected.prefix(need))
        self.collected.removeFirst(need)
        self.runModel(on: slice)
      }
    }
  }

  func start() throws { try mic.start() }
  func stop() { mic.stop() }

  private func runModel(on audio: [Float]) {
    do {
      let notes = try runner.predictNotes(from: audio)
      self.notes = notes

      // 매 호출마다 결과를 쌓아가거나, 즉시 MIDI 파일로 덮어쓰기
      //      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
      //        "basicpitch_demo.mid"
      //      )
      //      try MIDIWriter.writeMIDINotes(notes, to: tmp, tempoBPM: 100.0)
      //      print("Wrote MIDI to: \(tmp.path)")
    } catch {
      print("Prediction/MIDI write error: \(error)")
    }
  }
}
