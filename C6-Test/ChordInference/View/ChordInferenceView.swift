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
    ZStack {
      VStack {
        ForEach($measures) { $measure in
          MeasureView(measure: $measure)
        }
      }

      HStack {
        if let chords {
          HStack {
            ForEach(chords.indices, id: \.self) { index in
              if chords.indices.contains(index) {
                let chord = chords[index]
                Text(chord.description)
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
                  .contentTransition(.numericText())
                  .padding(4)
                  .padding(.horizontal, 4)
                  .background(.quaternary, in: Capsule())
              }
            }
          }

          Spacer()
        }

        Button("Predict") {
          do {
            let chords = try chordInferenceService?.inference(
              measures: measures
            )
            withAnimation {
              self.chords = chords
            }
          } catch {
            self.error = error
          }
        }
        .buttonStyle(.glassProminent)
      }
      .padding()
      .glassEffect(self.chords == nil ? .identity : .regular, in: Capsule())
      .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .bottomTrailing
      )
    }
    .padding()
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
    HStack {
      ForEach($measure.notes) { $note in
        NoteView(note: $note) {
          measure.notes.removeAll(where: { $0.id == note.id })
        }
      }

      Spacer()

      Button {
        let note = NoteWithDuration(
          note: .C,
          duration: .quarter
        )
        withAnimation {
          measure.notes.append(note)
        }
      } label: {
        Image(systemName: "plus")
          .padding(8)
          .background(.tertiary, in: Circle())
      }
    }
    .padding()
    .background(.quinary, in: Capsule())
  }
}

struct NoteView: View {
  @Binding var note: NoteWithDuration
  let removeAction: () -> Void

  @State private var previousNote: Tonic.Note
  @State private var previousDuration: NoteDuration

  @State private var isEditorPresented: Bool = false
  @Namespace private var namespace

  init(note: Binding<NoteWithDuration>, removeAction: @escaping () -> Void = {})
  {
    self._note = note
    self.removeAction = removeAction

    self.previousNote = note.wrappedValue.note
    self.previousDuration = note.wrappedValue.duration
  }

  var body: some View {
    Text("\(note.note.description)-\(note.duration.fractionString)")
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .contentTransition(.numericText())
      .padding(4)
      .padding(.horizontal, 4)
      .background(.quaternary, in: Capsule())
      .onTapGesture {
        isEditorPresented = true
      }
      .gesture(
        DragGesture(minimumDistance: 10)
          .onChanged { value in
            let verticalGap = Int(value.translation.height / 10)

            if let note = getNote(self.previousNote, gap: verticalGap) {
              withAnimation {
                self.note.note = note
              }
            }

            let horizontalGap = Int(value.translation.width / 10)

            if let duration = getDuration(
              self.previousDuration,
              gap: horizontalGap
            ) {
              withAnimation {
                self.note.duration = duration
              }
            }
          }
          .onEnded { value in
            self.previousNote = note.note
            self.previousDuration = note.duration
          }
      )
      .matchedTransitionSource(id: "EDITOR", in: namespace)
      .popover(isPresented: $isEditorPresented) {
        VStack {
          Picker("Note", selection: $note.note) {
            ForEach(availableNotes, id: \.self) { note in
              Text(note.description)
                .tag(note)
            }
          }
          Picker("Duration", selection: $note.duration) {
            ForEach(NoteDuration.allCases, id: \.self) { duration in
              Text(duration.description)
                .tag(duration)
            }
          }
          Button("Remove") {
            removeAction()
          }
          .buttonStyle(.glassProminent)
        }
        .padding()
        .presentationCompactAdaptation(.popover)
        .navigationTransition(.zoom(sourceID: "EDITOR", in: namespace))
      }
      .sensoryFeedback(.selection, trigger: isEditorPresented)
  }

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

  private func getNote(_ note: Tonic.Note, gap: Int) -> Tonic.Note? {
    guard let index = availableNotes.firstIndex(of: note) else { return nil }

    let count = availableNotes.count
    let targetIndex = (((count + index + gap) % count) + count) % count

    guard availableNotes.indices.contains(targetIndex) else { return nil }

    let target = availableNotes[targetIndex]

    return target
  }

  private func getDuration(_ duration: NoteDuration, gap: Int) -> NoteDuration?
  {
    let noteDurations = NoteDuration.allCases

    guard let index = noteDurations.firstIndex(of: duration) else { return nil }

    let count = noteDurations.count
    let targetIndex = (((count + index + gap) % count) + count) % count

    guard noteDurations.indices.contains(targetIndex) else { return nil }

    let target = noteDurations[targetIndex]

    return target
  }
}
