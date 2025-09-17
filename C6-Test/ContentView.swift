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
        NavigationLink("Swift-F0") {
          SwiftF0View()
        }
        NavigationLink("AudioKit PitchTap") {
          PitchTapView()
        }
      }
      .navigationTitle("C6 Test")
    }
  }
}

#Preview {
  ContentView()
}
