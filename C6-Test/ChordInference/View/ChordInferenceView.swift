//
//  ChordInferenceView.swift
//  C6-Test
//
//  Created by 정희균 on 9/27/25.
//

import CoreML
import SwiftUI
import Tonic

struct ChordInferenceView: View {
  @State private var chordInferenceService: ChordInferenceService?
  @State private var error: Error?

  @State private var measures: [Measure] =
    (0..<4).map { _ in Measure(notes: []) }
  @State private var chords: [Chord]?

  var body: some View {
    VStack {
      VStack {
        ForEach($measures) { $measure in
          MeasureView(measure: $measure)
        }
      }
      .padding()
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))

      if let chords {
        VStack {
          ForEach(chords.indices, id: \.self) { index in
            if chords.indices.contains(index) {
              let chord = chords[index]
              HStack {
                Text(chord.root.description)
                Text(chord.type.description)
              }
            }
          }
        }
      }

      Button("Predict") {
        do {
          self.chords = try chordInferenceService?.inference(measures: measures)
        } catch {
          self.error = error
        }
      }
      .buttonStyle(.glassProminent)
    }
    .onAppear {
      if self.chordInferenceService == nil {
        do {
          self.chordInferenceService = try MLChordInferenceService()
        } catch {
          self.error = error
        }
      }
    }
    .alert("Error", isPresented: .constant(self.error != nil)) {
      Button(String(describing: self.error)) {
        self.error = nil
      }
    }
  }
}

#Preview {
  ChordInferenceView()
}

struct MeasureView: View {
  @Binding var measure: Measure

  @State private var selectedNote: Tonic.Note = .C
  @State private var selectedNoteDuration: NoteDuration = .quarter

  private let availableNotes: [Tonic.Note] = [
    .C,
    .Cs,
    .D,
    .Ds,
    .E,
    .F,
    .Fs,
    .G,
    .Gs,
    .A,
    .As,
    .B,
  ]

  var body: some View {
    VStack {
      HStack {
        if measure.notes.isEmpty {
          Text(Tonic.NoteClass.C.description)
            .hidden()
            .accessibilityHidden(true)
        } else {
          ForEach(measure.notes) { note in
            Text(note.note.description)
              .contextMenu {
                Button("Delete") {
                  measure.notes.removeAll(where: { $0.id == note.id })
                }
              }
          }
        }
      }
      HStack {
        Picker(selection: $selectedNote) {
          ForEach(availableNotes, id: \.self) { note in
            Text(note.description)
              .tag(note)
          }
        } label: {
          Text("Note")
        }

        Picker(selection: $selectedNoteDuration) {
          ForEach(NoteDuration.allCases, id: \.self) { noteDuration in
            Text(noteDuration.description)
              .tag(noteDuration)
          }
        } label: {
          Text("Note Duration")
        }

        Button("Add") {
          let note = NoteWithDuration(
            note: selectedNote,
            duration: selectedNoteDuration
          )
          measure.notes.append(note)
        }
      }
    }
    .padding()
  }
}
