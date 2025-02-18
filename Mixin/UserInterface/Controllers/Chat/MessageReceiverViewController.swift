import UIKit
import AVFoundation
import MixinServices

class MessageReceiverViewController: PeerViewController<[MessageReceiver], CheckmarkPeerCell, MessageReceiverSearchResult> {
    
    override class var showSelectionsOnTop: Bool {
        true
    }
    
    private var messageContent: MessageContent!
    private var selections = [MessageReceiver]() {
        didSet {
            container?.rightButton.isEnabled = selections.count > 0
        }
    }
    
    class func instance(content: MessageContent) -> UIViewController {
        let vc = MessageReceiverViewController()
        vc.messageContent = content
        return ContainerViewController.instance(viewController: vc, title: Localized.ACTION_SHARE_TO)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.allowsMultipleSelection = true
        collectionView.dataSource = self
    }
    
    override func catalog(users: [UserItem]) -> (titles: [String], models: [[MessageReceiver]]) {
        var contacts = [UserItem]()
        var apps = [UserItem]()
        for user in users {
            if user.isBot {
                apps.append(user)
            } else {
                contacts.append(user)
            }
        }
        let contactReceivers = contacts.map(MessageReceiver.init)
        let appReceivers = apps.map(MessageReceiver.init)
        let conversations = ConversationDAO.shared.conversationList()
            .compactMap(MessageReceiver.init)
        let titles = [R.string.localizable.chat_forward_chats(),
                      R.string.localizable.chat_forward_contacts(),
                      R.string.localizable.chat_forward_apps()]
        return (titles, [conversations, contactReceivers, appReceivers])
    }
    
    override func search(keyword: String) {
        queue.operations
            .filter({ $0 != initDataOperation })
            .forEach({ $0.cancel() })
        let op = BlockOperation()
        let receivers = self.models
        op.addExecutionBlock { [unowned op, weak self] in
            guard self != nil, !op.isCancelled else {
                return
            }
            let uniqueReceivers = Set(receivers.flatMap({ $0 }))
            let searchResults = uniqueReceivers
                .filter { $0.matches(lowercasedKeyword: keyword) }
                .map { MessageReceiverSearchResult(receiver: $0, keyword: keyword) }
            DispatchQueue.main.sync {
                guard let weakSelf = self, !op.isCancelled else {
                    return
                }
                weakSelf.searchingKeyword = keyword
                weakSelf.searchResults = searchResults
                weakSelf.tableView.reloadData()
                weakSelf.reloadTableViewSelections()
            }
        }
        queue.addOperation(op)
    }
    
    override func configure(cell: CheckmarkPeerCell, at indexPath: IndexPath) {
        if isSearching {
            cell.render(result: searchResults[indexPath.row])
        } else {
            cell.render(receiver: models[indexPath.section][indexPath.row])
        }
    }
    
    override func reloadTableViewSelections() {
        super.reloadTableViewSelections()
        if isSearching {
            for (index, result) in searchResults.enumerated() {
                guard selections.contains(result.receiver) else {
                    continue
                }
                let indexPath = IndexPath(row: index, section: 0)
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        } else {
            for section in 0..<models.count {
                for indexPath in receiverIndexPathsWhichMatchSelections(of: section) {
                    tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                }
            }
        }
    }
    
    // MARK: - UITableViewDataSource
    override func numberOfSections(in tableView: UITableView) -> Int {
        return isSearching ? 1 : models.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? searchResults.count : models[section].count
    }
    
    // MARK: - UITableViewDelegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let receiver = messageReceiver(at: indexPath)
        selections.append(receiver)
        let indexPath = IndexPath(item: selections.count - 1, section: 0)
        collectionView.insertItems(at: [indexPath])
        if !isSearching {
            var counterSections = Array(0..<numberOfSections(in: tableView))
            counterSections.removeAll(where: { $0 == indexPath.section })
            let indexPaths = counterSections.flatMap(receiverIndexPathsWhichMatchSelections)
            for indexPath in indexPaths {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }
        setCollectionViewHidden(false, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let receiver = messageReceiver(at: indexPath)
        if let index = selections.firstIndex(of: receiver) {
            selections.remove(at: index)
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.deleteItems(at: [indexPath])
        }
        if !isSearching {
            var counterSections = Array(0..<numberOfSections(in: tableView))
            counterSections.removeAll(where: { $0 == indexPath.section })
            for section in counterSections {
                let enumeratedReceivers = models[section].enumerated()
                if let (row, _) = enumeratedReceivers.first(where: { $1.conversationId == receiver.conversationId }) {
                    let indexPath = IndexPath(row: row, section: section)
                    tableView.deselectRow(at: indexPath, animated: false)
                }
            }
        }
        setCollectionViewHidden(selections.isEmpty, animated: true)
    }
    
}

extension MessageReceiverViewController: ContainerViewControllerDelegate {
    
    func textBarRightButton() -> String? {
        return R.string.localizable.action_send()
    }
    
    func barRightButtonTappedAction() {
        container?.rightButton.isBusy = true
        let content = self.messageContent!
        let selections = self.selections
        DispatchQueue.global().async { [weak self] in
            for receiver in selections {
                let messages = MessageReceiverViewController.makeMessages(content: content, to: receiver.conversationId)
                guard !messages.isEmpty else {
                    continue
                }
                switch receiver.item {
                case .group:
                    for msg in messages {
                        SendMessageService.shared.sendMessage(message: msg, ownerUser: nil, isGroupMessage: true)
                    }
                case .user(let user):
                    for msg in messages {
                        SendMessageService.shared.sendMessage(message: msg, ownerUser: user, isGroupMessage: false)
                    }
                }
            }
            DispatchQueue.main.async {
                self?.popToConversationWithLastSelection()
            }
        }
    }
    
}

extension MessageReceiverViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        selections.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.selected_peer, for: indexPath)!
        let receiver = selections[indexPath.row]
        cell.render(receiver: receiver)
        cell.delegate = self
        return cell
    }
    
}

extension MessageReceiverViewController: SelectedPeerCellDelegate {
    
    func selectedPeerCellDidSelectRemove(_ cell: UICollectionViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else {
            return
        }
        let deselected = selections[indexPath.row]
        if isSearching {
            if let item = searchResults.map({ $0.receiver }).firstIndex(of: deselected) {
                let indexPath = IndexPath(item: item, section: 0)
                tableView.deselectRow(at: indexPath, animated: true)
                tableView(tableView, didDeselectRowAt: indexPath)
            }
        } else {
            for section in 0..<models.count {
                let members = models[section]
                if let item = members.firstIndex(of: deselected) {
                    let indexPath = IndexPath(item: item, section: section)
                    tableView.deselectRow(at: indexPath, animated: true)
                    tableView(tableView, didDeselectRowAt: indexPath)
                    break
                }
            }
        }
    }
    
}

extension MessageReceiverViewController {
    
    private func messageReceiver(at indexPath: IndexPath) -> MessageReceiver {
        if isSearching {
            return searchResults[indexPath.row].receiver
        } else {
            return models[indexPath.section][indexPath.row]
        }
    }
    
    private func receiverIndexPathsWhichMatchSelections(of section: Int) -> [IndexPath] {
        assert(!isSearching)
        var indexPaths = [IndexPath]()
        for (row, receiver) in models[section].enumerated() where selections.contains(receiver) {
            indexPaths.append(IndexPath(row: row, section: section))
        }
        return indexPaths
    }
    
    private func popToConversationWithLastSelection() {
        if let receiver = selections.last {
            let vc: ConversationViewController
            switch receiver.item {
            case .group(let conversation):
                vc = ConversationViewController.instance(conversation: conversation)
            case .user(let user):
                vc = ConversationViewController.instance(ownerUser: user)
            }
            navigationController?.pushViewController(withBackRoot: vc)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
}

extension MessageReceiverViewController {
    
    enum MessageContent {
        case messages([MessageItem])
        case contact(String)
        case photo(UIImage)
        case text(String)
        case video(URL)
        case appCard(AppCardData)
    }
    
    static func makeMessages(content: MessageContent, to conversationId: String) -> [Message] {
        switch content {
        case .messages(let messages):
            let date = Date()
            let counter = Counter(value: -1)
            return messages.compactMap({ (original) -> Message? in
                let interval = TimeInterval(counter.advancedValue) / millisecondsPerSecond
                let createdAt = date.addingTimeInterval(interval).toUTCString()
                return makeMessage(message: original, to: conversationId, createdAt: createdAt)
            })
        case .contact(let userId):
            return [makeMessage(userId: userId, to: conversationId)].compactMap({ $0 })
        case .photo(let image):
            return [makeMessage(image: image, to: conversationId)].compactMap({ $0 })
        case .text(let text):
            return [makeMessage(text: text, to: conversationId)].compactMap({ $0 })
        case .video(let url):
            return [makeMessage(videoUrl: url, to: conversationId)].compactMap({ $0 })
        case .appCard(let appCard):
            return [makeMessage(appCard: appCard, to: conversationId)].compactMap({ $0 })
        }
    }
    
    // Copy media file in case of deletion or recalling
    static func mediaUrl(from message: MessageItem, with newMessageId: String) -> String? {
        guard let category = AttachmentContainer.Category(messageCategory: message.category), let mediaUrl = message.mediaUrl else {
            return message.mediaUrl
        }
        
        let fromUrl = AttachmentContainer.url(for: category, filename: mediaUrl)
        guard FileManager.default.fileExists(atPath: fromUrl.path) else {
            return message.mediaUrl
        }
        let filename = newMessageId + "." + fromUrl.pathExtension
        let toUrl = AttachmentContainer.url(for: category, filename: filename)
        try? FileManager.default.copyItem(at: fromUrl, to: toUrl)
        
        if message.category.hasSuffix("_VIDEO") {
            let fromThumbnailUrl = AttachmentContainer.url(for: .videos, filename: mediaUrl.substring(endChar: ".") + ExtensionName.jpeg.withDot)
            let targetThumbnailUrl = AttachmentContainer.url(for: .videos, filename: newMessageId + ExtensionName.jpeg.withDot)
            try? FileManager.default.copyItem(at: fromThumbnailUrl, to: targetThumbnailUrl)
        }
        
        return toUrl.lastPathComponent
    }
    
    static func makeMessage(message: MessageItem, to conversationId: String, createdAt: String) -> Message? {
        var newMessage = Message.createMessage(category: message.category,
                                               conversationId: conversationId,
                                               createdAt: createdAt,
                                               userId: myUserId)
        if message.category.hasSuffix("_TEXT") || message.category.hasSuffix("_POST") || message.category.hasSuffix("_LOCATION") || message.category == MessageCategory.APP_CARD.rawValue {
            newMessage.content = message.content
        } else if message.category.hasSuffix("_IMAGE") {
            newMessage.thumbImage = message.thumbImage
            newMessage.mediaSize = message.mediaSize
            newMessage.mediaWidth = message.mediaWidth
            newMessage.mediaHeight = message.mediaHeight
            newMessage.mediaMimeType = message.mediaMimeType
            newMessage.mediaUrl = mediaUrl(from: message, with: newMessage.messageId)
            newMessage.mediaStatus = MediaStatus.PENDING.rawValue
        } else if message.category.hasSuffix("_DATA") {
            newMessage.name = message.name
            newMessage.mediaSize = message.mediaSize
            newMessage.mediaMimeType = message.mediaMimeType
            newMessage.mediaUrl = mediaUrl(from: message, with: newMessage.messageId)
            newMessage.mediaStatus = MediaStatus.PENDING.rawValue
        } else if message.category.hasSuffix("_AUDIO") {
            newMessage.mediaSize = message.mediaSize
            newMessage.mediaMimeType = message.mediaMimeType
            newMessage.mediaUrl = mediaUrl(from: message, with: newMessage.messageId)
            newMessage.mediaWaveform = message.mediaWaveform
            newMessage.mediaDuration = message.mediaDuration
            newMessage.mediaStatus = MediaStatus.PENDING.rawValue
        } else if message.category.hasSuffix("_VIDEO") {
            newMessage.thumbImage = message.thumbImage
            newMessage.mediaSize = message.mediaSize
            newMessage.mediaWidth = message.mediaWidth
            newMessage.mediaHeight = message.mediaHeight
            newMessage.mediaMimeType = message.mediaMimeType
            newMessage.mediaUrl = mediaUrl(from: message, with: newMessage.messageId)
            newMessage.mediaStatus = MediaStatus.PENDING.rawValue
            newMessage.mediaDuration = message.mediaDuration
        } else if message.category.hasSuffix("_STICKER") {
            newMessage.mediaUrl = message.mediaUrl
            newMessage.stickerId = message.stickerId
            newMessage.mediaStatus = MediaStatus.PENDING.rawValue
            let transferData = TransferStickerData(stickerId: message.stickerId, name: nil, albumId: nil)
            newMessage.content = try! JSONEncoder().encode(transferData).base64EncodedString()
        } else if message.category.hasSuffix("_CONTACT") {
            guard let sharedUserId = message.sharedUserId else {
                return nil
            }
            newMessage.sharedUserId = sharedUserId
            let transferData = TransferContactData(userId: sharedUserId)
            newMessage.content = try! JSONEncoder().encode(transferData).base64EncodedString()
        } else if message.category.hasSuffix("_LIVE"), let width = message.mediaWidth, let height = message.mediaHeight, let mediaUrl = message.mediaUrl, let thumbUrl = message.thumbUrl {
            newMessage.mediaWidth = message.mediaWidth
            newMessage.mediaHeight = message.mediaHeight
            newMessage.mediaUrl = message.mediaUrl
            newMessage.thumbUrl = message.thumbUrl
            let liveData = TransferLiveData(width: width, height: height, thumbUrl: thumbUrl, url: mediaUrl)
            newMessage.content = try! JSONEncoder.default.encode(liveData).base64EncodedString()
        } else {
            return nil
        }
        return newMessage
    }
    
    static func makeMessage(userId: String, to conversationId: String) -> Message? {
        var message = Message.createMessage(category: MessageCategory.SIGNAL_CONTACT.rawValue,
                                            conversationId: conversationId,
                                            userId: myUserId)
        message.sharedUserId = userId
        let transferData = TransferContactData(userId: userId)
        message.content = try! JSONEncoder().encode(transferData).base64EncodedString()
        return message
    }

    static func makeMessage(appCard: AppCardData, to conversationId: String) -> Message? {
        var message = Message.createMessage(category: MessageCategory.APP_CARD.rawValue,
                                            conversationId: conversationId,
                                            userId: myUserId)
        message.content = try! JSONEncoder().encode(appCard).base64EncodedString()
        return message
    }
    
    static func makeMessage(image: UIImage, to conversationId: String) -> Message? {
        var message = Message.createMessage(category: MessageCategory.SIGNAL_IMAGE.rawValue,
                                            conversationId: conversationId,
                                            userId: myUserId)
        let filename = message.messageId + ExtensionName.jpeg.withDot
        let path = AttachmentContainer.url(for: .photos, filename: filename)
        guard image.saveToFile(path: path), FileManager.default.fileSize(path.path) > 0, image.size.width > 0, image.size.height > 0 else {
            showAutoHiddenHud(style: .error, text: MixinServices.Localized.TOAST_OPERATION_FAILED)
            return nil
        }
        message.thumbImage = image.base64Thumbnail()
        message.mediaSize = FileManager.default.fileSize(path.path)
        message.mediaWidth = Int(image.size.width)
        message.mediaHeight = Int(image.size.height)
        message.mediaMimeType = "image/jpeg"
        message.mediaUrl = filename
        message.mediaStatus = MediaStatus.PENDING.rawValue
        return message
    }
    
    static func makeMessage(text: String, to conversationId: String) -> Message {
        var message = Message.createMessage(category: MessageCategory.SIGNAL_TEXT.rawValue,
                                            conversationId: conversationId,
                                            userId: myUserId)
        message.content = text
        return message
    }
    
    static func makeMessage(videoUrl: URL, to conversationId: String) -> Message? {
        let asset = AVAsset(url: videoUrl)
        guard asset.duration.isValid, let videoTrack = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        var message = Message.createMessage(category: MessageCategory.SIGNAL_VIDEO.rawValue,
                                            conversationId: conversationId,
                                            userId: myUserId)
        let filename = videoUrl.lastPathComponent.substring(endChar: ".")
        let thumbnailFilename = filename + ExtensionName.jpeg.withDot
        if let thumbnail = UIImage(withFirstFrameOfVideoAtURL: videoUrl) {
            let thumbnailURL = AttachmentContainer.url(for: .videos, filename: thumbnailFilename)
            thumbnail.saveToFile(path: thumbnailURL)
            message.thumbImage = thumbnail.base64Thumbnail()
        } else {
            return nil
        }
        message.mediaDuration = Int64(asset.duration.seconds * millisecondsPerSecond)
        let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        message.mediaWidth = Int(abs(size.width))
        message.mediaHeight = Int(abs(size.height))
        message.mediaSize = FileManager.default.fileSize(videoUrl.path)
        message.mediaMimeType = FileManager.default.mimeType(ext: videoUrl.pathExtension)
        message.mediaUrl = videoUrl.lastPathComponent
        message.mediaStatus = MediaStatus.PENDING.rawValue
        return message
    }
    
}
