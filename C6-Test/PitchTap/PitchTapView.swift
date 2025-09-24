//
//  PitchTapView.swift
//  C6-Test
//
//  Created by 정희균 on 9/17/25.
//

import AVFoundation
import SwiftUI

struct PitchTapView: View {
  @State private var viewModel = PitchTapViewModel()

  @State private var scrollPosition: ScrollPosition = ScrollPosition()

  var body: some View {
    VStack(spacing: 16) {
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(), count: 4)) {
          ForEach(viewModel.notes) { note in
            VStack {
              Text(note.note)
              Text(String(format: "%.1f", note.length))
            }
            .id(note.id)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.secondary, in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .scrollPosition($scrollPosition)
      .onChange(of: viewModel.notes) { oldValue, newValue in
        if let last = viewModel.notes.last {
          scrollPosition.scrollTo(id: last.id)
        }
      }
      .animation(.default, value: scrollPosition)

      Text("Pitch")
        .font(.title.bold())
      Text(viewModel.noteName)
        .font(.system(size: 48, weight: .semibold, design: .rounded))

      VStack {
        Text("Frequency: \(String(format: "%.1f", viewModel.frequency)) Hz")
        Text("Amplitude: \(String(format: "%.4f", viewModel.amplitude))")
        Text("TimeGap: \(String(describing: viewModel.timeGap))")
      }
      .font(.callout)
      .foregroundStyle(.secondary)

      HStack {
        Button("Start") {
          viewModel.start()
        }
        Button("Stop") {
          viewModel.stop()
        }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
    .onAppear {
      // 마이크 권한 요청
      AVAudioApplication.requestRecordPermission { granted in
        if !granted { print("⚠️ Microphone permission denied") }
      }
    }
  }
}

#Preview {
  PitchTapView()
}
