//
//  SwiftF0View.swift
//  C6-Test
//
//  Created by 정희균 on 9/17/25.
//

import Charts
import SwiftUI

@Observable
final class PitchTrackerViewModel {
  private var runner: SwiftF0RealtimeRunner?

  private(set) var f0: [Float] = []
  private(set) var conf: [Float] = []
  private(set) var note: String = ""

  func start() {
    do {
      runner = try SwiftF0RealtimeRunner()
      runner?.onResult = { f0, conf, t0 in
        //        self.f0.append(contentsOf: f0)
        self.conf.append(contentsOf: conf)

        var result = [Float]()
        var notes = [String: Int]()
        for (f0, conf) in zip(f0, conf) {
          if conf > 0.95 {
            result.append(f0)

            let note = self.frequencyToNoteName(frequency: f0)
            notes["\(note.note)\(note.octave)", default: 0] += 1
          } else {
            result.append(0)
          }
        }

        self.f0.append(contentsOf: result)

        if let maximumNote = notes.values.max() {
          self.note =
            notes.filter({ $0.value == maximumNote }).map({ $0.key }).first
            ?? "?"
        }
      }
      try runner?.start()
    } catch {
      print("start error:", error)
    }
  }

  func stop() { runner?.stop() }

  private let noteNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
  ]

  func frequencyToNoteName(frequency: Float) -> (note: String, octave: Int) {
    // MIDI note number 공식 (A4=440Hz, noteNumber 69)
    let noteNumber = Int(round(12 * log2(frequency / 440.0) + 69))
    let noteIndex = noteNumber % 12
    let octave = (noteNumber / 12) - 1
    let noteName = noteNames[noteIndex]
    return (noteName, octave)
  }
}

struct SwiftF0View: View {
  @State private var vm = PitchTrackerViewModel()

  var body: some View {
    VStack {
      Chart(Array(vm.f0.enumerated()), id: \.0) { index, f0 in
        BarMark(
          x: .value("time", index),
          y: .value("f0", f0),
        )
      }
      .animation(.default, value: vm.f0)

      Chart(Array(vm.conf.enumerated()), id: \.0) { index, conf in
        BarMark(
          x: .value("time", index),
          y: .value("conf", conf),
        )
      }
      .animation(.default, value: vm.conf)

      GlassEffectContainer {
        Text(vm.note)
          .font(.title)
          .bold()
          .padding()
          .glassEffect()

        HStack {
          Button("Start") {
            vm.start()
          }
          Button("Stop") {
            vm.stop()
          }
        }
        .buttonStyle(.glassProminent)
      }
    }
    .padding()
  }
}

#Preview {
  SwiftF0View()
}
