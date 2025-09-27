//
//  ScoreEditorView.swift
//  C6-Test
//
//  Created by 정희균 on 9/24/25.
//

import SwiftUI

enum ScoreEditor {
  enum Pitch: String, CaseIterable {
    case C, CSharp, D, DSharp, E, F, FSharp, G, GSharp, A, ASharp, B
  }

  struct Note: Identifiable, Hashable {
    let id: UUID = UUID()
    let pitch: Pitch
    let octave: Int
    let beat: Double
    let duration: Double
  }

  struct Chord {
    let name: String
    let root: Pitch
    let pitches: Set<Note>
  }
}

struct ScoreEditorView: View {
  @State private var notes: [ScoreEditor.Note] = [
    ScoreEditor.Note(pitch: .C, octave: 4, beat: 0.0, duration: 1.0),
    ScoreEditor.Note(pitch: .C, octave: 5, beat: 0.0, duration: 1.0),
    ScoreEditor.Note(pitch: .D, octave: 4, beat: 0.0, duration: 1.5),
    ScoreEditor.Note(pitch: .E, octave: 4, beat: 0.0, duration: 2.0),
    ScoreEditor.Note(pitch: .F, octave: 4, beat: 0.0, duration: 1.0),
    ScoreEditor.Note(pitch: .G, octave: 4, beat: 0.0, duration: 1.0),
    ScoreEditor.Note(pitch: .A, octave: 4, beat: 0.0, duration: 1.0),
    ScoreEditor.Note(pitch: .B, octave: 4, beat: 0.0, duration: 1.0),
  ]

  @State private var selectedPitch: ScoreEditor.Pitch = .C
  @State private var selectedOctave: Int = 4
  @State private var selectedDuration: Double = 1.0

  var body: some View {
    VStack {
      ScoreView(notes: $notes)

      HStack {
        Picker("Pitch", selection: $selectedPitch) {
          ForEach(ScoreEditor.Pitch.allCases, id: \.self) { pitch in
            Text(pitch.rawValue)
              .tag(pitch)
          }
        }

        Picker("Duration", selection: $selectedDuration) {
          Text("16분음표")
            .tag(0.25)
          Text("8분음표")
            .tag(0.5)
          Text("점8분음표")
            .tag(0.75)
          Text("4분음표")
            .tag(1.0)
          Text("점4분음표")
            .tag(1.5)
          Text("2분음표")
            .tag(2.0)
        }

        Button("추가") {
          let note = ScoreEditor.Note(
            pitch: selectedPitch,
            octave: selectedOctave,
            beat: 0.0,
            duration: selectedDuration
          )

          notes.append(
            note
          )
        }
      }
      .padding()
      .glassEffect()
    }
    .padding()
  }
}

struct ScoreView: View {
  @Binding var notes: [ScoreEditor.Note]

  var body: some View {
    ScrollView(.horizontal) {
      HStack {
        HStack {
          Text("g")
            .font(.custom("Musisync", size: 72))
          Text("$")
            .font(.custom("Musisync", size: 52))
        }
        .padding(.horizontal)
        ForEach(notes) { note in
          NoteView(note: note)
            .contextMenu {
              Button("삭제", role: .destructive) {
                notes.removeAll(where: { $0.id == note.id })
              }
            }
        }
      }
      .background {
        VStack {
          ForEach(0..<5) { i in
            Rectangle()
              .fill()
              .frame(height: 1)
              .offset(y: 8)
          }
        }
      }
    }
  }
}

struct NoteView: View {
  let note: ScoreEditor.Note

  var body: some View {
    VStack {
      HStack {
        durationToNoteText(note.duration)
          .offset(y: pitchToOffset(note.pitch) - CGFloat(note.octave - 4) * 32)
          .overlay {
            switch note.pitch {
            case .CSharp, .DSharp, .FSharp, .GSharp, .ASharp:
              Text("B")
                .font(.custom("Musisync", size: 64))
                .offset(x: 8)
            default:
              EmptyView()
            }
          }
        Spacer()
          .frame(width: 10 * note.duration / 0.25, alignment: .leading)
      }
    }
  }

  private func durationToNoteText(_ duration: Double) -> Text {
    var noteName: String = ""

    if duration <= 0.25 {
      noteName = "s"
    } else if duration <= 0.5 {
      noteName = "e"
    } else if duration <= 0.75 {
      noteName = "i"
    } else if duration <= 1.0 {
      noteName = "q"
    } else if duration <= 1.5 {
      noteName = "j"
    } else if duration <= 2.0 {
      noteName = "h"
    } else if duration <= 3.0 {
      noteName = "d"
    }

    return Text(noteName)
      .font(.custom("Musisync", size: 64))
  }

  private func pitchToOffset(_ pitch: ScoreEditor.Pitch) -> CGFloat {
    switch pitch {
    case .C:
      return 12
    case .CSharp:
      return 12
    case .D:
      return 8
    case .DSharp:
      return 8
    case .E:
      return 4
    case .F:
      return 0
    case .FSharp:
      return 0
    case .G:
      return -4
    case .GSharp:
      return -4
    case .A:
      return -10
    case .ASharp:
      return -10
    case .B:
      return -14
    }
  }
}

#Preview {
  ScoreEditorView()
}
