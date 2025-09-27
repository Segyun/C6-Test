//
//  NoteWithDuration.swift
//  C6-Test
//
//  Created by 정희균 on 9/27/25.
//

import Foundation
import Tonic

struct NoteWithDuration: Identifiable {
  let id: UUID = UUID()
  let note: Tonic.Note
  let duration: NoteDuration
}
