import SwiftUI

/// Springs are critically damped unless a gesture carried momentum into them.
enum MetroMotion {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 1)
    static let press = Animation.spring(response: 0.18, dampingFraction: 1)
    static let release = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let fade = Animation.easeInOut(duration: 0.2)

    /// Parallax speeds relative to the content scroll.
    static let backgroundParallax: CGFloat = 0.3
    static let titleParallax: CGFloat = 0.5
}
