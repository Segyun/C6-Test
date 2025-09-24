//
//  PitchTapViewModel.swift
//  C6-Test
//
//  Created by 정희균 on 9/20/25.
//

import AVFAudio
import AudioKit
import AudioKitEX
import SoundpipeAudioKit
import Tonic

@Observable
class Note: Identifiable, Equatable {
  let id: UUID = UUID()
  var note: String
  var length: TimeInterval

  init(note: String, length: TimeInterval) {
    self.note = note
    self.length = length
  }

  static func == (lhs: Note, rhs: Note) -> Bool {
    return lhs.id == rhs.id
      && lhs.note == rhs.note
      && lhs.length == rhs.length
  }
}

@Observable
final class PitchTapViewModel {
  private(set) var frequency: AUValue = 0  // Hz
  private(set) var amplitude: AUValue = 0  // 0.0 ~ 1.0
  private(set) var noteName: String = "—"

  private let engine = AudioEngine()
  private var pitchTap: PitchTap?
  private var silence: Fader?  // 출력은 무음 처리 (하울링 방지)

  // 잡음/무성 구간 필터링 임계값
  private let minAmplitude: AUValue = 0.01

  private(set) var timeGap: TimeInterval = 0.0
  private var previousTime: Date = Date()

  private(set) var notes: [Note] = []
  private var previousNoteName: String = "-"
  private var previousNoteTime: TimeInterval = 0.0

  init() {
    // 오디오 세션 구성
    configureSession()

    guard let input = engine.input else {
      print("⚠️ No audio input available")
      return
    }

    // 출력은 무음으로 연결해 피드백 방지
    let fader = Fader(input, gain: 0)
    engine.output = fader
    self.silence = fader

    // PitchTap 설치 (업데이트 주기 50ms)
    self.pitchTap = PitchTap(input) { [weak self] pitch, amp in
      guard let self else { return }
      // 콜백은 오디오 스레드 → UI 반영은 메인 큐에서
      if let f = pitch.first, let a = amp.first {
        if a > self.minAmplitude && f > 0 {
          //          Task { @MainActor in
          self.frequency = f
          self.amplitude = a
          self.noteName = Self.hzToNoteName(frequency: f)
          //          }
        } else {
          //          Task { @MainActor in
          self.frequency = 0
          self.amplitude = a
          self.noteName = "—"
          //          }
        }

        self.timeGap = Date().timeIntervalSince(self.previousTime)

        if self.previousNoteName == self.noteName {
          self.previousNoteTime += self.timeGap
        } else {
          if self.previousNoteTime > 0.05 {
            if let lastNote = self.notes.last,
              self.previousNoteName == "—",
              lastNote.note == self.previousNoteName
            {
              self.notes.last?.length += self.previousNoteTime
            } else {
              self.notes.append(
                Note(note: self.previousNoteName, length: self.previousNoteTime)
              )
            }
          }
          self.previousNoteName = self.noteName
          self.previousNoteTime = 0.0
        }

        self.previousTime = Date()
      }
    }
  }

  func start() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      pitchTap?.start()  // tap 먼저 시작
      try engine.start()  // 엔진 시작
      print("🎤 Pitch tracking started")
    } catch {
      print("Audio start error: \(error)")
    }
  }

  func stop() {
    pitchTap?.stop()
    engine.stop()
    try? AVAudioSession.sharedInstance().setActive(false)
    print("🛑 Pitch tracking stopped")
  }

  // MARK: - Helpers

  private func configureSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .measurement,  // AEC/AGC 최소화
        options: [.defaultToSpeaker, .allowBluetoothHFP]
      )
      try session.setPreferredSampleRate(48_000)
      try session.setPreferredIOBufferDuration(0.005)  // 낮게 잡아 응답성 ↑
    } catch {
      print("Session config error: \(error)")
    }
  }

  // Hz -> 음이름 (A4=440 기준), 예: "A4 (440.0Hz)"
  static func hzToNoteName(frequency f: AUValue) -> String {
    guard f > 0 else { return "—" }
    let noteNames = [
      "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]
    let midi = Int(round(69 + 12 * log2(Double(f) / 440.0)))
    let name = noteNames[(midi % 12 + 12) % 12]
    let octave = midi / 12 - 1
    return "\(name)\(octave)"
  }

  static func hzToNote(frequency f: AUValue) -> Tonic.Note? {
    guard f > 0 else { return nil }
    let noteNames = [
      "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ]
    let midi = Int(round(69 + 12 * log2(Double(f) / 440.0)))
    return Tonic.Note(pitch: Pitch(intValue: midi), key: Key.c)
  }
}
