//
//  Measure.swift
//  C6-Test
//
//  Created by 정희균 on 9/27/25.
//

import Foundation

struct Measure: Identifiable {
  let id: UUID = UUID()
  var notes: [NoteWithDuration]
}
