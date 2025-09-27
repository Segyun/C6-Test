//
//  KeyDetector.swift
//  C6-Test
//
//  Created by 정희균 on 9/24/25.
//

import Foundation
import Playgrounds

class KeyDetector {

  // Krumhansl-Kessler 키 프로파일 (C Major, C Minor 기준)
  private let majorProfile: [Double] = [
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
  ]
  private let minorProfile: [Double] = [
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
  ]

  // 12개 크로마 클래스 (C, C#, D, D#, E, F, F#, G, G#, A, A#, B)
  private let noteNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
  ]
  private let keyNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
  ]

  // 입력 멜로디를 크로마 벡터로 변환
  func createChromaVector(from notes: [String]) -> [Double] {
    var chromaVector = Array(repeating: 0.0, count: 12)

    for note in notes {
      // 음높이를 12 크로마 클래스로 변환
      let normalizedNote = normalizeNote(note)
      if let index = noteNames.firstIndex(of: normalizedNote) {
        chromaVector[index] += 1.0
      }
    }

    return chromaVector
  }

  // 음 이름 정규화 (예: Db -> C#, 옥타브 제거)
  private func normalizeNote(_ note: String) -> String {
    let baseNote = String(
      note.prefix(while: { !$0.isNumber && $0 != "♯" && $0 != "♭" })
    )

    // 플랫을 샵으로 변환
    let flatToSharp: [String: String] = [
      "Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#",
    ]

    return flatToSharp[baseNote] ?? baseNote
  }

  // 키 프로파일을 해당 키로 회전
  private func rotateProfile(_ profile: [Double], by steps: Int) -> [Double] {
    let normalizedSteps = ((steps % 12) + 12) % 12
    return Array(profile[normalizedSteps...])
      + Array(profile[..<normalizedSteps])
  }

  // 두 벡터 간의 피어슨 상관계수 계산
  private func correlation(_ x: [Double], _ y: [Double]) -> Double {
    let n = Double(x.count)
    let sumX = x.reduce(0, +)
    let sumY = y.reduce(0, +)
    let sumXY = zip(x, y).map(*).reduce(0, +)
    let sumXX = x.map { $0 * $0 }.reduce(0, +)
    let sumYY = y.map { $0 * $0 }.reduce(0, +)

    let numerator = n * sumXY - sumX * sumY
    let denominator = sqrt(
      (n * sumXX - sumX * sumX) * (n * sumYY - sumY * sumY)
    )

    return denominator == 0 ? 0 : numerator / denominator
  }

  // 키 추정 메인 함수
  func detectKey(from melody: [String]) -> (key: String, confidence: Double) {
    let chromaVector = createChromaVector(from: melody)

    var bestKey = "C Major"
    var highestCorrelation = -1.0

    // 모든 메이저 키 검사
    for i in 0..<12 {
      let rotatedProfile = rotateProfile(majorProfile, by: i)
      let correlation = correlation(chromaVector, rotatedProfile)

      if correlation > highestCorrelation {
        highestCorrelation = correlation
        bestKey = "\(keyNames[i]) Major"
      }
    }

    // 모든 마이너 키 검사
    for i in 0..<12 {
      let rotatedProfile = rotateProfile(minorProfile, by: i)
      let correlation = correlation(chromaVector, rotatedProfile)

      if correlation > highestCorrelation {
        highestCorrelation = correlation
        bestKey = "\(keyNames[i]) Minor"
      }
    }

    return (bestKey, highestCorrelation)
  }

  // 상위 N개 키 후보 반환
  func detectTopKeys(from melody: [String], count: Int = 3) -> [(
    key: String, confidence: Double
  )] {
    let chromaVector = createChromaVector(from: melody)
    var keyScores: [(String, Double)] = []

    // 모든 메이저 키
    for i in 0..<12 {
      let rotatedProfile = rotateProfile(majorProfile, by: i)
      let correlation = correlation(chromaVector, rotatedProfile)
      keyScores.append(("\(keyNames[i]) Major", correlation))
    }

    // 모든 마이너 키
    for i in 0..<12 {
      let rotatedProfile = rotateProfile(minorProfile, by: i)
      let correlation = correlation(chromaVector, rotatedProfile)
      keyScores.append(("\(keyNames[i]) Minor", correlation))
    }

    return keyScores.sorted { $0.1 > $1.1 }.prefix(count).map {
      (key: $0.0, confidence: $0.1)
    }
  }
}

#Playground {
  // 사용 예시
  let detector = KeyDetector()

  // 멜로디 입력 (도레미파솔라시도)
  let melody = ["C", "C", "E", "E", "B", "B", "E", "E", "B", "B", "E", "E", "A", "A", "F", "A"]

  // 키 추정
  let result = detector.detectKey(from: melody)
  print("추정된 키: \(result.key)")
  print("신뢰도: \(String(format: "%.3f", result.confidence))")

  // 상위 3개 키 후보
  let topKeys = detector.detectTopKeys(from: melody, count: 3)
  print("\n상위 키 후보들:")
  for (index, keyResult) in topKeys.enumerated() {
    print(
      "\(index + 1). \(keyResult.key): \(String(format: "%.3f", keyResult.confidence))"
    )
  }

}
