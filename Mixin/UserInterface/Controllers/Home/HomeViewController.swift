import UIKit
import AVFoundation
import StoreKit
import WCDBSwift
import MixinServices

class HomeViewController: UIViewController {
    
    static var hasTriedToRequestReview = false
    static var showChangePhoneNumberTips = false
    
    @IBOutlet weak var navigationBarView: UIView!
    @IBOutlet weak var searchContainerView: UIView!
    @IBOutlet weak var circlesContainerView: UIView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var guideView: UIView!
    @IBOutlet weak var guideLabel: UILabel!
    @IBOutlet weak var guideButton: UIButton!
    @IBOutlet weak var connectingView: ActivityIndicatorView!
    @IBOutlet weak var titleButton: HomeTitleButton!
    @IBOutlet weak var bulletinContentView: UIView!
    @IBOutlet weak var bulletinTitleLabel: UILabel!
    @IBOutlet weak var bulletinDescriptionView: UILabel!
    @IBOutlet weak var bottomBarView: UIView!
    @IBOutlet weak var leftAppButton: UIButton!
    @IBOutlet weak var rightAppButton: UIButton!
    
    @IBOutlet weak var bulletinWrapperViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var bulletinContentTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var searchContainerTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var bottomNavigationBottomConstraint: NSLayoutConstraint!
    
    private let dragDownThreshold: CGFloat = 80
    private let dragDownIndicator = DragDownIndicator()
    private let feedback = UISelectionFeedbackGenerator()
    private let messageCountPerPage = 30

    private var conversations = [ConversationItem]()
    private var needRefresh = true
    private var refreshing = false
    private var beginDraggingOffset: CGFloat = 0
    private var searchViewController: SearchViewController!
    private var searchContainerBeginTopConstant: CGFloat!
    private var loadMoreMessageThreshold = 10
    private var leftAppAction: (() -> Void)?
    private var rightAppAction: (() -> Void)?
    private var isEditingRow = false
    
    private var isBulletinViewHidden = false {
        didSet {
            layoutBulletinView()
        }
    }
    private var topLeftTitle: String {
        AppGroupUserDefaults.User.circleName ?? R.string.localizable.app_name()
    }
    
    private lazy var circlesViewController = R.storyboard.home.circles()!
    private lazy var deleteAction = UITableViewRowAction(style: .destructive, title: Localized.MENU_DELETE, handler: tableViewCommitDeleteAction)
    private lazy var pinAction: UITableViewRowAction = {
        let action = UITableViewRowAction(style: .normal, title: Localized.HOME_CELL_ACTION_PIN, handler: tableViewCommitPinAction)
        action.backgroundColor = .theme
        return action
    }()
    private lazy var unpinAction: UITableViewRowAction = {
        let action = UITableViewRowAction(style: .normal, title: Localized.HOME_CELL_ACTION_UNPIN, handler: tableViewCommitPinAction)
        action.backgroundColor = .theme
        return action
    }()
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let vc = (segue.destination as? UINavigationController)?.viewControllers.first as? SearchViewController {
            searchViewController = vc
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleButton.setTitle(topLeftTitle, for: .normal)
        isBulletinViewHidden = true
        updateBulletinView()
        searchContainerBeginTopConstant = searchContainerTopConstraint.constant
        searchViewController.cancelButton.addTarget(self, action: #selector(hideSearch), for: .touchUpInside)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        tableView.tableFooterView = UIView()
        dragDownIndicator.bounds.size = CGSize(width: 40, height: 40)
        dragDownIndicator.center = CGPoint(x: tableView.frame.width / 2, y: -40)
        tableView.addSubview(dragDownIndicator)
        updateHomeApps()
        NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange(_:)), name: .ConversationDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange(_:)), name: MessageDAO.didInsertMessageNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange(_:)), name: MessageDAO.didRedecryptMessageNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange(_:)), name: .UserDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidChange(_:)), name: .AppDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(circleConversationDidChange(_:)), name: CircleConversationDAO.circleConversationsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(webSocketDidConnect(_:)), name: WebSocketService.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(webSocketDidDisconnect(_:)), name: WebSocketService.didDisconnectNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncStatusChange), name: .SyncMessageDidAppear, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: ReceiveMessageService.groupConversationParticipantDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(circleNameDidChange), name: AppGroupUserDefaults.User.circleNameDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateHomeApps), name: AppGroupUserDefaults.User.homeAppIdsDidChangeNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationManager.shared.registerForRemoteNotificationsIfAuthorized()
            CallService.shared.registerForPushKitNotificationsIfAvailable()
        }
        Logger.write(log: "HomeViewController...viewDidLoad...applicationState:\(UIApplication.shared.applicationStateString)")
        if UIApplication.shared.applicationState == .active {
            ConcurrentJobQueue.shared.addJob(job: RefreshAccountJob())
            ConcurrentJobQueue.shared.addJob(job: RefreshStickerJob())
            ConcurrentJobQueue.shared.addJob(job: CleanUpUnusedAttachmentJob())
            if AppGroupUserDefaults.User.hasRecoverMedia {
                ConcurrentJobQueue.shared.addJob(job: RecoverMediaJob())
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if needRefresh {
            fetchConversations()
        }
        checkServerStatus()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if RELEASE
        requestAppStoreReviewIfNeeded()
        #endif
        if HomeViewController.showChangePhoneNumberTips {
            HomeViewController.showChangePhoneNumberTips = false
            let alert = UIAlertController(title: R.string.localizable.emergency_change_number_tip(), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: R.string.localizable.action_later(), style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: R.string.localizable.dialog_button_change(), style: .default, handler: { (_) in
                let vc = VerifyPinNavigationController(rootViewController: ChangeNumberVerifyPinViewController())
                self.present(vc, animated: true, completion: nil)
            }))
            present(alert, animated: true, completion: nil)
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        dragDownIndicator.center.x = tableView.frame.width / 2
        layoutBulletinView()
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let bottom = bottomBarView.frame.height - view.safeAreaInsets.bottom
        tableView.contentInset.bottom = bottom
        if view.safeAreaInsets.bottom < 1 {
            bottomNavigationBottomConstraint.constant = 24
            bottomBarView.layoutIfNeeded()
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        DispatchQueue.main.async(execute: layoutBulletinView)
    }
    
    @IBAction func showSearchAction() {
        searchViewController.prepareForReuse()
        searchContainerTopConstraint.constant = 0
        UIView.animate(withDuration: 0.2, animations: {
            self.navigationBarView.alpha = 0
            self.searchContainerView.alpha = 1
            self.view.layoutIfNeeded()
        }) { (_) in
            self.searchViewController.searchTextField.becomeFirstResponder()
        }
    }
    
    @IBAction func contactsAction(_ sender: Any) {
        navigationController?.pushViewController(ContactViewController.instance(), animated: true)
    }
    
    @IBAction func guideAction(_ sender: Any) {
        if let circleId = AppGroupUserDefaults.User.circleId, let name = AppGroupUserDefaults.User.circleName {
            let editor = CircleEditorViewController.instance(name: name, circleId: circleId, isNewCreatedCircle: false)
            present(editor, animated: true, completion: nil)
        } else {
            let vc = ContactViewController.instance()
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    @IBAction func bulletinContinueAction(_ sender: Any) {
        UIApplication.openAppSettings()
    }
    
    @IBAction func bulletinDismissAction(_ sender: Any) {
        AppGroupUserDefaults.notificationBulletinDismissalDate = Date()
        UIView.animate(withDuration: 0.3) {
            self.isBulletinViewHidden = true
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func toggleCircles(_ sender: Any) {
        if circlesContainerView.isHidden {
            if circlesViewController.parent == nil {
                circlesViewController.view.frame = circlesContainerView.bounds
                circlesViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addChild(circlesViewController)
                circlesContainerView.addSubview(circlesViewController.view)
                circlesViewController.didMove(toParent: self)
            }
            circlesViewController.setTableViewVisible(false, animated: false, completion: nil)
            circlesContainerView.isHidden = false
            circlesViewController.setTableViewVisible(true, animated: true, completion: nil)
        } else {
            circlesViewController.setTableViewVisible(false, animated: true, completion: {
                self.circlesContainerView.isHidden = true
            })
        }
    }
    
    @IBAction func showAppsAction(_ sender: Any) {
        let vc = HomeAppsViewController.instance()
        vc.presentAsChild(of: self)
    }
    
    @IBAction func leftAppAction(_ sender: Any) {
        leftAppAction?()
    }
    
    @IBAction func rightAppAction(_ sender: Any) {
        rightAppAction?()
    }
    
    @objc func applicationDidBecomeActive(_ sender: Notification) {
        updateBulletinView()
        fetchConversations()
    }
    
    @objc func dataDidChange(_ sender: Notification) {
        guard view?.isVisibleInScreen ?? false else {
            needRefresh = true
            return
        }
        fetchConversations()
    }

    @objc func appDidChange(_ notification: Notification) {
        guard let appId = notification.object as? String, !appId.isEmpty else {
            return
        }
        guard AppGroupUserDefaults.User.homeAppIds.contains(appId) else {
            return
        }

        updateHomeApps()
    }
    
    @objc func circleConversationDidChange(_ notification: Notification) {
        guard let circleId = notification.userInfo?[CircleConversationDAO.circleIdUserInfoKey] as? String else {
            return
        }
        guard circleId == AppGroupUserDefaults.User.circleId else {
            return
        }
        setNeedsRefresh()
    }
    
    @objc func webSocketDidConnect(_ notification: Notification) {
        connectingView.stopAnimating()
        titleButton.setTitle(topLeftTitle, for: .normal)
    }
    
    @objc func webSocketDidDisconnect(_ notification: Notification) {
        connectingView.startAnimating()
        titleButton.setTitle(R.string.localizable.dialog_progress_connect(), for: .normal)
    }
    
    @objc func syncStatusChange(_ notification: Notification) {
        guard let progress = notification.object as? Int else {
            return
        }

        if progress >= 100 {
            if WebSocketService.shared.isRealConnected {
                titleButton.setTitle(topLeftTitle, for: .normal)
                connectingView.stopAnimating()
            } else {
                titleButton.setTitle(R.string.localizable.dialog_progress_connect(), for: .normal)
                connectingView.startAnimating()
                WebSocketService.shared.connectIfNeeded()
            }
        } else if WebSocketService.shared.isRealConnected {
            let title = Localized.CONNECTION_HINT_PROGRESS(progress)
            titleButton.setTitle(title, for: .normal)
            connectingView.startAnimating()
        }
    }
    
    @objc func groupConversationParticipantDidChange(_ notification: Notification) {
        guard let conversationId = notification.userInfo?[ReceiveMessageService.UserInfoKey.conversationId] as? String else {
            return
        }
        let job = RefreshGroupIconJob(conversationId: conversationId)
        ConcurrentJobQueue.shared.addJob(job: job)
    }
    
    @objc func hideSearch() {
        searchViewController.willHide()
        searchContainerTopConstraint.constant = searchContainerBeginTopConstant
        UIView.animate(withDuration: 0.2) {
            self.navigationBarView.alpha = 1
            self.searchContainerView.alpha = 0
            self.view.layoutIfNeeded()
        }
        view.endEditing(true)
    }
    
    @objc func circleNameDidChange() {
        titleButton.setTitle(topLeftTitle, for: .normal)
    }

    func dismissAppsWindow() {
        if let homeApps = children.compactMap({ $0 as? HomeAppsViewController }).first {
            homeApps.dismissAsChild(completion: nil)
        }
    }
    
    @objc func updateHomeApps() {
        func setImage(with app: HomeApp, to button: UIButton) {
            button.setImage(app.categoryIcon, for: .normal)
            switch app {
            case .embedded(let app):
                if button == leftAppButton {
                    leftAppAction = app.action
                } else if button == rightAppButton {
                    rightAppAction = app.action
                }
            case .external:
                break
            }
        }
        
        func action(for app: HomeApp) -> (() -> Void) {
            switch app {
            case .embedded(let app):
                return app.action
            case .external(let user):
                return {
                    ConcurrentJobQueue.shared.addJob(job: RefreshUserJob(userIds: [user.userId]))
                    if let app = user.app {
                        let userInfo = ["source": "Home", "identityNumber": app.appNumber]
                        reporter.report(event: .openApp, userInfo: userInfo)
                        MixinWebViewController.presentInstance(with: .init(conversationId: "", app: app), asChildOf: self)
                    } else {
                        reporter.report(error: MixinError.missingApp)
                    }
                }
            }
        }
        
        DispatchQueue.global().async {
            let apps = AppGroupUserDefaults.User.homeAppIds.compactMap(HomeApp.init).prefix(2)
            DispatchQueue.main.async {
                if let left = apps.first {
                    setImage(with: left, to: self.leftAppButton)
                    self.leftAppAction = action(for: left)
                    self.leftAppButton.alpha = 1
                } else {
                    self.leftAppButton.alpha = 0
                }
                if apps.count == 2 {
                    let app = apps[1]
                    setImage(with: app, to: self.rightAppButton)
                    self.rightAppAction = action(for: app)
                    self.rightAppButton.alpha = 1
                } else {
                    self.rightAppButton.alpha = 0
                }
            }
        }
    }
    
    func setNeedsRefresh() {
        needRefresh = true
        fetchConversations()
    }
    
    func showCamera(asQrCodeScanner: Bool) {
        let vc = CameraViewController.instance()
        vc.asQrCodeScanner = asQrCodeScanner
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            navigationController?.pushViewController(vc, animated: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { [weak self](granted) in
                guard granted else {
                    return
                }
                DispatchQueue.main.async {
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            })
        case .denied, .restricted:
            alertSettings(Localized.PERMISSION_DENIED_CAMERA)
        @unknown default:
            alertSettings(Localized.PERMISSION_DENIED_CAMERA)
        }
    }
    
}

extension HomeViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: R.reuseIdentifier.conversation, for: indexPath)!
        cell.render(item: conversations[indexPath.row])
        return cell
    }
    
}

extension HomeViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let conversation = conversations[indexPath.row]
        if conversation.status == ConversationStatus.START.rawValue {
            let job = CreateConversationJob(conversationId: conversation.conversationId)
            ConcurrentJobQueue.shared.addJob(job: job)
        } else {
            conversation.unseenMessageCount = 0
            let vc = ConversationViewController.instance(conversation: conversation)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isEditingRow = true
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isEditingRow = false
        fetchConversations()
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let conversation = conversations[indexPath.row]
        if conversation.pinTime == nil {
            return [deleteAction, pinAction]
        } else {
            return [deleteAction, unpinAction]
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard conversations.count >= messageCountPerPage else {
            return
        }
        guard indexPath.row > conversations.count - loadMoreMessageThreshold else {
            return
        }
        guard !refreshing else {
            needRefresh = true
            return
        }

        fetchConversations()
    }
    
}

extension HomeViewController: UIScrollViewDelegate {
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        beginDraggingOffset = scrollView.contentOffset.y
        feedback.prepare()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y <= -dragDownThreshold && !dragDownIndicator.isHighlighted {
            dragDownIndicator.isHighlighted = true
            feedback.selectionChanged()
        } else if scrollView.contentOffset.y > -dragDownThreshold && dragDownIndicator.isHighlighted {
            dragDownIndicator.isHighlighted = false
        }
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if tableView.contentOffset.y <= -dragDownThreshold {
            showSearchAction()
        } else {
            hideSearch()
        }
    }
    
}

extension HomeViewController {
    
    private func checkServerStatus() {
        guard LoginManager.shared.isLoggedIn else {
            return
        }
        guard !WebSocketService.shared.isConnected else {
            return
        }
        AccountAPI.shared.me { [weak self](result) in
            guard let weakSelf = self else {
                return
            }
            if case let .failure(error) = result, error.code == 10006 {
                weakSelf.alert(Localized.TOAST_UPDATE_TIPS)
            }
        }
    }
    
    private func fetchConversations() {
        guard LoginManager.shared.isLoggedIn else {
            return
        }
        guard !refreshing else {
            needRefresh = true
            return
        }
        refreshing = true
        needRefresh = false

        DispatchQueue.main.async {
            if AppGroupUserDefaults.User.circleId == nil {
                self.titleButton.showsTopRightDot = false
            }
            let limit = (self.tableView.indexPathsForVisibleRows?.first?.row ?? 0) + self.messageCountPerPage

            DispatchQueue.global().async { [weak self] in
                let circleId = AppGroupUserDefaults.User.circleId
                let conversations = ConversationDAO.shared.conversationList(limit: limit, circleId: circleId)
                let groupIcons = conversations.filter({ $0.isNeedCachedGroupIcon() })
                for conversation in groupIcons {
                    ConcurrentJobQueue.shared.addJob(job: RefreshGroupIconJob(conversationId: conversation.conversationId))
                }
                let hasUnreadMessagesOutsideCircle: Bool = {
                    if let id = circleId {
                        return ConversationDAO.shared.hasUnreadMessage(outsideCircleWith: id)
                    } else {
                        return false
                    }
                }()
                DispatchQueue.main.async {
                    guard self?.tableView != nil, !(self?.isEditingRow ?? false) else {
                         self?.refreshing = false
                        return
                    }
                    self?.conversations = conversations
                    self?.tableView.reloadData()
                    self?.titleButton.showsTopRightDot = hasUnreadMessagesOutsideCircle
                    self?.updateGuideView()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.33, execute: {
                        self?.refreshing = false
                        if self?.needRefresh ?? false {
                            self?.fetchConversations()
                        }
                    })
                }
            }
        }
    }
    
    private func updateGuideView() {
        guard conversations.isEmpty else {
            guideView.isHidden = true
            return
        }
        if AppGroupUserDefaults.User.circleId == nil {
            guideLabel.text = R.string.localizable.home_start_messaging_guide()
            guideButton.setTitle(R.string.localizable.home_start_messaging(), for: .normal)
        } else {
            guideLabel.text = R.string.localizable.circle_no_conversation_hint()
            guideButton.setTitle(R.string.localizable.circle_no_conversation_action(), for: .normal)
        }
        guideView.isHidden = false
    }
    
    private func tableViewCommitPinAction(action: UITableViewRowAction, indexPath: IndexPath) {
        let dao = ConversationDAO.shared
        let conversation = conversations[indexPath.row]
        let destinationIndex: Int
        if conversation.pinTime == nil {
            let pinTime = Date().toUTCString()
            conversation.pinTime = pinTime
            dao.updateConversation(with: conversation.conversationId,
                                   inCirleOf: AppGroupUserDefaults.User.circleId,
                                   pinTime: pinTime)
            conversations.remove(at: indexPath.row)
            destinationIndex = 0
        } else {
            conversation.pinTime = nil
            dao.updateConversation(with: conversation.conversationId,
                                   inCirleOf: AppGroupUserDefaults.User.circleId,
                                   pinTime: nil)
            conversations.remove(at: indexPath.row)
            destinationIndex = conversations.firstIndex(where: { $0.pinTime == nil && $0.createdAt < conversation.createdAt }) ?? conversations.count
        }
        conversations.insert(conversation, at: destinationIndex)
        let destinationIndexPath = IndexPath(row: destinationIndex, section: 0)
        tableView.moveRow(at: indexPath, to: destinationIndexPath)
        if let cell = tableView.cellForRow(at: destinationIndexPath) as? ConversationCell {
            cell.render(item: conversation)
        }
        tableView.setEditing(false, animated: true)
    }
    
    private func tableViewCommitDeleteAction(action: UITableViewRowAction, indexPath: IndexPath) {
        let conversation = conversations[indexPath.row]
        let alc = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alc.addAction(UIAlertAction(title: R.string.localizable.group_menu_clear(), style: .destructive, handler: { [weak self](action) in
            self?.clearChatAction(indexPath: indexPath)
        }))

        if conversation.category == ConversationCategory.GROUP.rawValue && conversation.status != ConversationStatus.QUIT.rawValue {
            alc.addAction(UIAlertAction(title: R.string.localizable.group_menu_exit(), style: .destructive, handler: { [weak self](action) in
                self?.exitGroupAction(indexPath: indexPath)
            }))
        } else {
            alc.addAction(UIAlertAction(title: R.string.localizable.group_menu_delete(), style: .destructive, handler: { [weak self](action) in
                self?.deleteChatAction(indexPath: indexPath)
            }))
        }

        alc.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        self.present(alc, animated: true, completion: nil)
        tableView.setEditing(false, animated: true)
    }

    private func deleteChatAction(indexPath: IndexPath) {
        let conversation = conversations[indexPath.row]
        let conversationId = conversation.conversationId
        let alert: UIAlertController
        if conversation.category == ConversationCategory.GROUP.rawValue {
            alert = UIAlertController(title: R.string.localizable.profile_delete_group_chat_hint(conversation.name), message: nil, preferredStyle: .actionSheet)
        } else {
            alert = UIAlertController(title: R.string.localizable.profile_delete_contact_chat_hint(conversation.ownerFullName), message: nil, preferredStyle: .actionSheet)
        }
        alert.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: R.string.localizable.group_menu_delete(), style: .destructive, handler: { (_) in
            self.tableView.beginUpdates()
            self.conversations.remove(at: indexPath.row)
            self.tableView.deleteRows(at: [indexPath], with: .fade)
            self.tableView.endUpdates()
            DispatchQueue.global().async {
                ConversationDAO.shared.deleteChat(conversationId: conversationId)
            }
        }))
        present(alert, animated: true, completion: nil)
    }
    
    private func clearChatAction(indexPath: IndexPath) {
        let conversation = conversations[indexPath.row]
        let conversationId = conversation.conversationId
        let alert: UIAlertController
        if conversation.category == ConversationCategory.GROUP.rawValue {
            alert = UIAlertController(title: R.string.localizable.profile_clear_group_chat_hint(conversation.name), message: nil, preferredStyle: .actionSheet)
        } else {
            alert = UIAlertController(title: R.string.localizable.profile_clear_contact_chat_hint(conversation.ownerFullName), message: nil, preferredStyle: .actionSheet)
        }
        alert.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: R.string.localizable.group_menu_clear(), style: .destructive, handler: { (_) in
            self.tableView.beginUpdates()
            self.conversations[indexPath.row].contentType = MessageCategory.UNKNOWN.rawValue
            self.conversations[indexPath.row].unseenMessageCount = 0
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
            self.tableView.endUpdates()
            DispatchQueue.global().async {
                ConversationDAO.shared.clearChat(conversationId: conversationId)
            }
        }))
        present(alert, animated: true, completion: nil)
    }

    private func exitGroupAction(indexPath: IndexPath) {
        let conversation = conversations[indexPath.row]
        let conversationId = conversation.conversationId
        let alert = UIAlertController(title: R.string.localizable.profile_exit_group_hint(conversation.name), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: R.string.localizable.group_menu_exit(), style: .destructive, handler: { (_) in
            let hud = Hud()
            hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)
            ConversationAPI.shared.exitConversation(conversationId: conversationId) { [weak self](result) in
                switch result {
                case .success:
                    hud.hide()
                    self?.conversations[indexPath.row].status = ConversationStatus.QUIT.rawValue
                    DispatchQueue.global().async {
                        ConversationDAO.shared.exitGroup(conversationId: conversationId)
                    }
                case let .failure(error):
                    if error.code == 404 || error.code == 403 {
                        hud.hide()
                        self?.conversations[indexPath.row].status = ConversationStatus.QUIT.rawValue
                        DispatchQueue.global().async {
                            ConversationDAO.shared.exitGroup(conversationId: conversationId)
                        }
                    } else {
                        hud.set(style: .error, text: error.localizedDescription)
                        hud.scheduleAutoHidden()
                    }
                }
            }
        }))
        present(alert, animated: true, completion: nil)
    }
    
    private func requestAppStoreReviewIfNeeded() {
        guard let firstLaunchDate = AppGroupUserDefaults.firstLaunchDate else {
            return
        }
        let sevenDays: Double = 7 * 24 * 60 * 60
        let shouldRequestReview = !HomeViewController.hasTriedToRequestReview
            && AppGroupUserDefaults.User.hasPerformedTransfer
            && -firstLaunchDate.timeIntervalSinceNow > sevenDays
        if shouldRequestReview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                SKStoreReviewController.requestReview()
            })
        }
        HomeViewController.hasTriedToRequestReview = true
    }
    
    private func layoutBulletinView() {
        if isBulletinViewHidden {
            bulletinWrapperViewHeightConstraint.constant = 0
            bulletinContentView.alpha = 0
        } else {
            UIView.performWithoutAnimation(bulletinContentView.layoutIfNeeded)
            bulletinWrapperViewHeightConstraint.constant = bulletinContentTopConstraint.constant + bulletinContentView.frame.height
            bulletinContentView.alpha = 1
        }
    }
    
    private func updateBulletinView() {
        UNUserNotificationCenter.current().getNotificationSettings { (settings) in
            let shouldHideBulletin: Bool
            if settings.authorizationStatus == .denied {
                if let date = AppGroupUserDefaults.notificationBulletinDismissalDate {
                    let notificationAuthorizationAlertingPeriod: TimeInterval = 2 * 24 * 60 * 60
                    shouldHideBulletin = -date.timeIntervalSinceNow < notificationAuthorizationAlertingPeriod
                } else {
                    shouldHideBulletin = false
                }
            } else {
                shouldHideBulletin = true
            }
            DispatchQueue.main.async {
                self.isBulletinViewHidden = shouldHideBulletin
                if self.view.window != nil {
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
    
}
