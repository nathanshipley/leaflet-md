import Foundation

enum PreviewMarginPreset: String, CaseIterable, Identifiable {
    case tight
    case normal
    case wide
    case extraWide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tight:
            return "Tight"
        case .normal:
            return "Normal"
        case .wide:
            return "Wide"
        case .extraWide:
            return "Extra Wide"
        }
    }

    var minimumPadding: String {
        switch self {
        case .tight:
            return "10px"
        case .normal:
            return "16px"
        case .wide:
            return "26px"
        case .extraWide:
            return "36px"
        }
    }

    var fluidPadding: String {
        switch self {
        case .tight:
            return "2vw"
        case .normal:
            return "4vw"
        case .wide:
            return "6vw"
        case .extraWide:
            return "8vw"
        }
    }

    var maximumPadding: String {
        switch self {
        case .tight:
            return "24px"
        case .normal:
            return "45px"
        case .wide:
            return "80px"
        case .extraWide:
            return "120px"
        }
    }
}
