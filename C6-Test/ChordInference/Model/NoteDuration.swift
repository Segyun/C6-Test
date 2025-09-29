//
//  NoteDuration.swift
//  C6-Test
//
//  Created by 정희균 on 9/27/25.
//

enum NoteDuration: Float, CaseIterable, CustomStringConvertible {
  case dottedWhole = 1.5
  case whole = 1.0
  case dottedHalf = 0.75
  case half = 0.5
  case dottedQuarter = 0.375
  case quarter = 0.25
  case dottedEighth = 0.1875
  case eighth = 0.125
  case dottedSixteenth = 0.09375
  case sixteenth = 0.0625

  var description: String {
    switch self {
    case .dottedWhole:
      "점온음표"
    case .whole:
      "온음표"
    case .dottedHalf:
      "점2분음표"
    case .half:
      "2분음표"
    case .dottedQuarter:
      "점4분음표"
    case .quarter:
      "4분음표"
    case .dottedEighth:
      "점8분음표"
    case .eighth:
      "8분음표"
    case .dottedSixteenth:
      "점16분음표"
    case .sixteenth:
      "16분음표"
    }
  }

  var fractionString: String {
    switch self {
    case .dottedWhole:
      "1."
    case .whole:
      "1"
    case .dottedHalf:
      "1/2."
    case .half:
      "1/2"
    case .dottedQuarter:
      "1/4."
    case .quarter:
      "1/4"
    case .dottedEighth:
      "1/8."
    case .eighth:
      "1/8"
    case .dottedSixteenth:
      "1/16."
    case .sixteenth:
      "1/16"
    }
  }
}
