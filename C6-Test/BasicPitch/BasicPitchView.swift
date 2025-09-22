//
//  BasicPitchView.swift
//  C6-Test
//
//  Created by 정희균 on 9/22/25.
//

import SwiftUI

struct BasicPitchView: View {
  @State private var viewModel: BasicPitchViewModel = BasicPitchViewModel()
  
  var body: some View {
    VStack {
      ScrollView(.horizontal) {
        LazyHStack {
          ForEach(viewModel.notes, id: \.startSec) { note in
            VStack {
              Text(midiNoteNumberToName(Int(note.pitch)))
              Text(note.velocity.formatted())
              Text(note.startSec.formatted())
              Text(note.endSec.formatted())
            }
          }
        }
      }
      
      HStack {
        Button("Start") {
          do {
            try viewModel.start()
          } catch {
            print("Error: \(error)")
          }
        }
        Button("Stop") {
          viewModel.stop()
        }
      }
      .buttonStyle(.borderedProminent)
      
      ShareLink(item: FileManager.default.temporaryDirectory.appendingPathComponent(
        "basicpitch_demo.mid"
      ))
    }
  }
  
  func midiNoteNumberToName(_ note: Int) -> String {
      let names = ["C", "C#", "D", "D#", "E", "F",
                   "F#", "G", "G#", "A", "A#", "B"]
      let pitchClass = note % 12
      let octave = (note / 12) - 1
      return "\(names[pitchClass])\(octave)"
  }
}

#Preview {
  BasicPitchView()
}
