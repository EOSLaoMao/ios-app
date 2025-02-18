import Foundation

public class DarwinNotificationManager {

    public static let shared = DarwinNotificationManager()

    private let darwinNotifyCenter = CFNotificationCenterGetDarwinNotifyCenter()
    private var selfAsOpaquePointer: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private init() {
        if isAppExtension {
            AppGroupUserDefaults.isProcessingMessagesInAppExtension = false
            CFNotificationCenterAddObserver(darwinNotifyCenter, selfAsOpaquePointer, { (_, _, _, _, _) in
                AppGroupUserDefaults.isProcessingMessagesInAppExtension = ReceiveMessageService.shared.isProcessingMessagesInAppExtension
            }, checkStatusInAppExtensionDarwinNotificationName.rawValue, nil, .deliverImmediately)
		} else {
            CFNotificationCenterAddObserver(darwinNotifyCenter, selfAsOpaquePointer, { (_, _, _, _, _) in
				NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange)
            }, conversationDidChangeInMainAppDarwinNotificationName.rawValue, nil, .deliverImmediately)
		}
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(darwinNotifyCenter, selfAsOpaquePointer)
    }

    func checkAppExtensionStatus() {
        CFNotificationCenterPostNotification(darwinNotifyCenter, checkStatusInAppExtensionDarwinNotificationName, nil, nil, true)
    }

	func notifyConversationDidChangeInMainApp() {
		CFNotificationCenterPostNotification(darwinNotifyCenter, conversationDidChangeInMainAppDarwinNotificationName, nil, nil, true)
	}
}
