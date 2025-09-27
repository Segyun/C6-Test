//
//  NoteDuration.swift
//  C6-Test
//
//  Created by 정희균 on 9/27/25.
//

enum NoteDuration: Float, CaseIterable, CustomStringConvertible {
  case whole = 1.0
  case dottedWhole = 1.5
  case half = 0.5
  case dottedHalf = 0.75
  case quarter = 0.25
  case dottedQuarter = 0.375
  case eighth = 0.125
  case dottedEighth = 0.1875
  case sixteenth = 0.0625
  case dottedSixteenth = 0.09375

  var description: String {
    switch self {
    case .whole:
      "온음표"
    case .dottedWhole:
      "점온음표"
    case .half:
      "2분음표"
    case .dottedHalf:
      "점2분음표"
    case .quarter:
      "4분음표"
    case .dottedQuarter:
      "점4분음표"
    case .eighth:
      "8분음표"
    case .dottedEighth:
      "점8분음표"
    case .sixteenth:
      "16분음표"
    case .dottedSixteenth:
      "점16분음표"
    }
  }
}
