//
//  ContentView.swift
//  C6-Test
//
//  Created by 정희균 on 9/15/25.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      List {
        NavigationLink("AudioKit PitchTap") {
          PitchTapView()
        }
        NavigationLink("Basic Pitch") {
          BasicPitchView()
        }
        NavigationLink("Score Editor") {
          ScoreEditorView()
        }
        NavigationLink("Chord Inference") {
          ChordInferenceView()
        }
      }
      .navigationTitle("C6 Test")
    }
  }
}

#Preview {
  ContentView()
}
