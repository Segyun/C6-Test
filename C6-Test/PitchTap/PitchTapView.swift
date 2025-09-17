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

  var body: some View {
    VStack(spacing: 16) {
      Text("Pitch")
        .font(.title.bold())
      Text(viewModel.noteName)
        .font(.system(size: 48, weight: .semibold, design: .rounded))

      VStack {
        Text("Frequency: \(String(format: "%.1f", viewModel.frequency)) Hz")
        Text("Amplitude: \(String(format: "%.4f", viewModel.amplitude))")
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
