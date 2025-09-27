//
//  ChordInferenceService.swift
//  C6-Test
//
//  Created by 정희균 on 9/27/25.
//

import CoreML
import Foundation
import Tonic

protocol ChordInferenceService {
  func inference(measures: [Measure]) throws -> [Chord]
}

final class MLChordInferenceService: ChordInferenceService {
  private let chordInference: ChordInference

  init() throws {
    self.chordInference = try ChordInference()
  }

  func inference(measures: [Measure]) throws -> [Chord] {
    let input = try convertToInput(forMeasures: measures)
    let output = try chordInference.prediction(input: input)
    let chords = convertToChords(forOutput: output)

    return chords
  }

  private func convertToInput(forMeasures measures: [Measure]) throws
    -> ChordInferenceInput
  {
    var melodyRaw = Array(repeating: 0, count: 64)
    for (i, measure) in measures.prefix(4).enumerated() {
      var currentIndex = 0
      for note in measure.notes {
        for _ in 0..<Int(16 * note.duration.rawValue) {
          melodyRaw[i * 16 + currentIndex] = Int(note.note.noteNumber)
          currentIndex += 1
        }
      }
    }

    let melody = try MLMultiArray(shape: [1, 64], dataType: .int32)
    let mask = try MLMultiArray(shape: [1, 64], dataType: .int32)

    for index in 0..<64 {
      melody[index] = melodyRaw[index] as NSNumber
      mask[index] = melodyRaw[index] != 0 ? 1 : 0
    }

    return ChordInferenceInput(melody: melody, mask: mask)
  }

  private func convertToChords(forOutput output: ChordInferenceOutput)
    -> [Chord]
  {
    let rootShape = output.root_logits.shape
    let typeShape = output.type_logits.shape

    let numBars = rootShape[1].intValue
    let numRootClasses = rootShape.last?.intValue ?? 0
    let numTypeClasses = typeShape.last?.intValue ?? 0

    let rootValues = flatten(output.root_logits)
    let typeValues = flatten(output.type_logits)

    func rowSlice(values: [Float], row: Int, cols: Int) -> [Float] {
      let start = row * cols
      return Array(values[start..<start + cols])
    }

    let chords = (0..<numBars).map { bar in
      let rootRow = rowSlice(values: rootValues, row: bar, cols: numRootClasses)
      let typeRow = rowSlice(values: typeValues, row: bar, cols: numTypeClasses)

      let rootProbs = softmaxRow(rootRow)
      let typeProbs = softmaxRow(typeRow)

      let rootIndices = rootProbs.enumerated().sorted(by: {
        $0.element > $1.element
      }).map(\.offset)
      let typeIndices = typeProbs.enumerated().sorted(by: {
        $0.element > $1.element
      }).map(\.offset)

      let root = noteClasses[rootIndices.first ?? 0] ?? .C
      let type = chordTypeNames[typeIndices.first ?? 0] ?? .major

      let chord = Chord(root, type: type)

      return chord
    }

    return chords
  }

  private let noteClasses: [Int: Tonic.NoteClass] = [
    0: .C,
    1: .Cs,
    2: .D,
    3: .Ds,
    4: .E,
    5: .F,
    6: .Fs,
    7: .G,
    8: .Gs,
    9: .A,
    10: .As,
    11: .B,
  ]

  private let chordTypeNames: [Int: Tonic.ChordType] = [
    0: .major,
    1: .minor,
    2: .maj7,
    3: .min7,
    4: .dom7,
    5: .sus2,
    6: .sus4,
    7: .dim,
    8: .aug,
    9: .min6,
    10: .maj6,
  ]

  private func flatten(_ array: MLMultiArray) -> [Float] {
    (0..<array.count).map { Float(truncating: array[$0]) }
  }

  private func softmaxRow(_ row: [Float]) -> [Float] {
    let maxVal = row.max() ?? 0
    let exps = row.map { expf($0 - maxVal) }
    let sum = exps.reduce(0, +)
    return exps.map { $0 / sum }
  }
}
