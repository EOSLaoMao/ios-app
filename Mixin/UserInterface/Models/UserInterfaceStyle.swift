import Foundation

@objc enum UserInterfaceStyle: Int {
    
    static var current: UserInterfaceStyle {
        if #available(iOS 12.0, *) {
            let style = UIScreen.main.traitCollection.userInterfaceStyle
            return UserInterfaceStyle(style: style)
        } else {
            return .light
        }
    }
    
    case light, dark
    
    @available(iOS 12.0, *)
    init(style: UIUserInterfaceStyle) {
        switch style {
        case .unspecified, .light:
            self = .light
        case .dark:
            self = .dark
        @unknown default:
            self = .light
        }
    }
    
    @available(iOS 12.0, *)
    var uiUserInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
}
