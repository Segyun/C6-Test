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
  @State private var model: ChordInference?
  @State private var error: Error?

  @State private var measures: [Measure] = (0..<4).map { _ in Measure(notes: [])
  }
  @State private var predictions: [ChordPrediction]?

  var body: some View {
    VStack {
      VStack {
        ForEach($measures) { $measure in
          MeasureView(measure: $measure)
        }
      }
      .padding()
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))

      if let predictions {
        VStack {
          ForEach(predictions) { prediction in
            let root = prediction.bestRoot
            let type = prediction.bestType

            HStack {
              Text("\(root.name)(\(root.probability.formatted()))")
              Text("\(type.name)(\(type.probability.formatted()))")
            }
          }
        }
      }

      Button("Predict") {
        do {
          var melodyRaw: [Int] = []
          var maskRaw: [Int] = []
          for measure in measures {
            melodyRaw.append(contentsOf: measure.convertToMelodyRaw())
            maskRaw.append(contentsOf: measure.convertToMaskRaw())
          }

          print(melodyRaw)
          print(maskRaw)

          self.predictions = try predict(melodyRaw: melodyRaw, maskRaw: maskRaw)
        } catch {
          self.error = error
        }
      }
      .buttonStyle(.glassProminent)
    }
    .onAppear {
      if self.model == nil {
        do {
          self.model = try ChordInference()
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

  private enum PredictionError: Error {
    case modelIsNotInitialized
  }

  private func predict(
    melodyRaw: [Int],
    maskRaw: [Int]
  ) throws -> [ChordPrediction] {
    guard let model else {
      print("Model is not loaded yet.")
      throw PredictionError.modelIsNotInitialized
    }

    let melody = try MLMultiArray(shape: [1, 64], dataType: .int32)
    for i in 0..<melody.shape[1].intValue {
      melody[i] = melodyRaw[i] as NSNumber
    }

    let mask = try MLMultiArray(shape: [1, 64], dataType: .int32)
    for i in 0..<mask.shape[1].intValue {
      mask[i] = maskRaw[i] as NSNumber
    }

    let input = ChordInferenceInput(melody: melody, mask: mask)
    let output = try model.prediction(input: input)

    let predictions = decodeOutput(output)

    return predictions
  }

  // 루트와 코드 타입 이름 매핑
  private let noteNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
  ]
  private let chordTypeNames = [
    0: "maj", 1: "min", 2: "maj7", 3: "min7",
    4: "7", 5: "sus2", 6: "sus4", 7: "dim",
    8: "aug", 9: "min6", 10: "maj6",
  ]

  // MLMultiArray → [Float]
  private func flatten(_ array: MLMultiArray) -> [Float] {
    (0..<array.count).map { Float(truncating: array[$0]) }
  }

  // 특정 마디(row)의 logits → softmax 확률
  private func softmaxRow(_ row: [Float]) -> [Float] {
    let maxVal = row.max() ?? 0
    let exps = row.map { expf($0 - maxVal) }
    let sum = exps.reduce(0, +)
    return exps.map { $0 / sum }
  }

  struct ChordPrediction: Identifiable {
    let id: UUID = UUID()
    let barIndex: Int
    let bestRoot: (name: String, probability: Float)
    let bestType: (name: String, probability: Float)
    let rootTopK: [(name: String, probability: Float)]
    let typeTopK: [(name: String, probability: Float)]
  }

  func decodeOutput(_ output: ChordInferenceOutput, topK: Int = 1)
    -> [ChordPrediction]
  {
    let rootShape = output.root_logits.shape.map { Int(truncating: $0) }
    let numBars = rootShape[1]
    let numRootClasses = rootShape.last ?? 0
    let numTypeClasses = output.type_logits.shape.last?.intValue ?? 0

    let rootValues = flatten(output.root_logits)
    let typeValues = flatten(output.type_logits)

    func rowSlice(values: [Float], row: Int, cols: Int) -> [Float] {
      let start = row * cols
      return Array(values[start..<start + cols])
    }

    return (0..<numBars).map { bar in
      let rootRow = rowSlice(values: rootValues, row: bar, cols: numRootClasses)
      let typeRow = rowSlice(values: typeValues, row: bar, cols: numTypeClasses)

      let rootProbs = softmaxRow(rootRow)
      let typeProbs = softmaxRow(typeRow)

      func topKIndices(probs: [Float], k: Int) -> [Int] {
        Array(
          probs.enumerated().sorted(by: { $0.element > $1.element }).prefix(k)
            .map(\.offset)
        )
      }

      let rootIndices = topKIndices(
        probs: rootProbs,
        k: min(topK, numRootClasses)
      )
      let typeIndices = topKIndices(
        probs: typeProbs,
        k: min(topK, numTypeClasses)
      )

      let rootTop = rootIndices.map { idx in
        (name: noteNames[idx % noteNames.count], probability: rootProbs[idx])
      }
      let typeTop = typeIndices.map { idx in
        (name: chordTypeNames[idx] ?? "unknown", probability: typeProbs[idx])
      }

      return ChordPrediction(
        barIndex: bar,
        bestRoot: rootTop[0],
        bestType: typeTop[0],
        rootTopK: rootTop,
        typeTopK: typeTop
      )
    }
  }
}

#Preview {
  ChordInferenceView()
}

struct Measure: Identifiable {
  enum NoteName: Int, CaseIterable, CustomStringConvertible {
    case C = 0
    case CSharp = 1
    case D = 2
    case DSharp = 3
    case E = 4
    case F = 5
    case FSharp = 6
    case G = 7
    case GSharp = 8
    case A = 9
    case ASharp = 10
    case B = 11

    var description: String {
      switch self {
      case .C:
        "C"
      case .CSharp:
        "C#"
      case .D:
        "D"
      case .DSharp:
        "D#"
      case .E:
        "E"
      case .F:
        "F"
      case .FSharp:
        "F#"
      case .G:
        "G"
      case .GSharp:
        "G#"
      case .A:
        "A"
      case .ASharp:
        "A#"
      case .B:
        "B"
      }
    }

    func convertToMidiNoteNumber(octave: Int = 4) -> Int {
      return 12 + (octave * 12) + self.rawValue
    }
  }

  enum NoteDuration: Int, CaseIterable, CustomStringConvertible {
    case whole = 16
    case half = 8
    case quarter = 4
    case eighth = 2
    case sixteenth = 1

    var description: String {
      switch self {
      case .whole:
        "온음표"
      case .half:
        "2분음표"
      case .quarter:
        "4분음표"
      case .eighth:
        "8분음표"
      case .sixteenth:
        "16분음표"
      }
    }
  }

  struct Note: Identifiable {
    let id: UUID = UUID()
    var name: NoteName
    var duration: NoteDuration
  }

  let id: UUID = UUID()
  var notes: [Note]
  var isValid: Bool {
    let totalDuration: Int = notes.reduce(0) { $0 + $1.duration.rawValue }
    return totalDuration <= 64
  }

  func convertToMelodyRaw() -> [Int] {
    var result: [Int] = Array(repeating: 0, count: 16)

    var currentIndex = 0
    for note in notes {
      for index in 0..<note.duration.rawValue {
        if result.indices.contains(currentIndex + index) {
          result[currentIndex + index] = note.name.convertToMidiNoteNumber()
        }
      }
      currentIndex += note.duration.rawValue
    }

    return result
  }

  func convertToMaskRaw() -> [Int] {
    return self.convertToMelodyRaw().map({ $0 > 0 ? 1 : 0 })
  }
}

struct MeasureView: View {
  @Binding var measure: Measure

  @State private var selectedNoteName: Measure.NoteName = .C
  @State private var selectedNoteDuration: Measure.NoteDuration = .quarter

  var body: some View {
    VStack {
      HStack {
        if measure.notes.isEmpty {
          Text(Measure.NoteName.C.description)
            .hidden()
            .accessibilityHidden(true)
        } else {
          ForEach(measure.notes) { note in
            Text(note.name.description)
              .contextMenu {
                Button("Delete") {
                  measure.notes.removeAll(where: { $0.id == note.id })
                }
              }
          }
        }
      }
      HStack {
        Picker(selection: $selectedNoteName) {
          ForEach(Measure.NoteName.allCases, id: \.self) { noteName in
            Text(noteName.description)
              .tag(noteName)
          }
        } label: {
          Text("Note Name")
        }

        Picker(selection: $selectedNoteDuration) {
          ForEach(Measure.NoteDuration.allCases, id: \.self) { noteDuration in
            Text(noteDuration.description)
              .tag(noteDuration)
          }
        } label: {
          Text("Note Duration")
        }

        Button("Add") {
          let note = Measure.Note(
            name: selectedNoteName,
            duration: selectedNoteDuration
          )
          measure.notes.append(note)
        }
      }
    }
    .padding()
  }
}
