import Foundation

public extension NSNotification.Name {

    static let ConversationDidChange = NSNotification.Name("one.mixin.services.sqlite.messages.changed")

    static let ContactsDidChange = NSNotification.Name("one.mixin.services.contacts.changed")

    static let UserDidChange = NSNotification.Name("one.mixin.services.user.changed")

    static let AppDidChange = NSNotification.Name("one.mixin.services.app.changed")

    static let SyncMessageDidAppear = NSNotification.Name("one.mixin.services.sync.message")

    static let ParticipantDidChange = NSNotification.Name("one.mixin.services.participant.changed")

    static let AssetsDidChange = NSNotification.Name("one.mixin.services.assets.changed")

    static let AssetVisibleDidChange = NSNotification.Name("one.mixin.services.asset.visible.changed")

    static let SnapshotDidChange = NSNotification.Name("one.mixin.services.snapshot.changed")

    static let AddressDidChange = NSNotification.Name("one.mixin.services.addresses.changed")

    static let DefaultAddressDidChange = NSNotification.Name("one.mixin.services.addresses.default.changed")

    static let FavoriteStickersDidChange = NSNotification.Name("one.mixin.services.favorite.stickers.changed")
    
    static let StickerUsedAtDidUpdate = NSNotification.Name("one.mixin.services.sticker.usedat.changed")
    
    static let StorageUsageDidChange = NSNotification.Name("one.mixin.services.storage.changed")
    
    static let HiddenAssetsDidChange = NSNotification.Name("one.mixin.services.hidden.assets.changed")

    static let BackupDidChange = NSNotification.Name("one.mixin.services.backup.changed")

    static let UserSessionDidChange = NSNotification.Name("one.mixin.services.session.changed")

    static let NetworkDidChange = NSNotification.Name("one.mixin.services.network.changed")
}

public struct ConversationChange {
    
    public let conversationId: String
    public let action: Action
    
    public enum Action {
        case reload
        case update(conversation: ConversationItem)
        case updateConversation(conversation: ConversationResponse)
        case updateConversationStatus(status: ConversationStatus)
        case updateGroupIcon(iconUrl: String)
        case updateMessage(messageId: String)
        case updateMessageStatus(messageId: String, newStatus: MessageStatus)
        case updateMessageMentionStatus(messageId: String, newStatus: MessageMentionStatus)
        case updateMediaStatus(messageId: String, mediaStatus: MediaStatus)
        case updateUploadProgress(messageId: String, progress: Double)
        case updateDownloadProgress(messageId: String, progress: Double)
        case updateMediaContent(messageId: String, message: Message)
        case startedUpdateConversation
        case recallMessage(messageId: String)
    }
    
    public init(conversationId: String, action: ConversationChange.Action) {
        self.conversationId = conversationId
        self.action = action
    }
    
}
