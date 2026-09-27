import SwiftUI

@MainActor @Observable
final class ImageDissolve {
    var blurRadius: Double = 0
    var opacity: Double = 1

    func begin(duration: Double, radius: Double) {
        withAnimation(.smooth(duration: duration)) {
            blurRadius = radius
        }
        withAnimation(.smooth(duration: duration * 0.85).delay(duration * 0.15)) {
            opacity = 0
        }
    }
}
