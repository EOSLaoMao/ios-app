import Foundation
import UIKit
import Alamofire
import MixinServices

class UrlWindow {
    
    class func checkUrl(url: URL, fromWeb: Bool = false, clearNavigationStack: Bool = true) -> Bool {
        if let mixinURL = MixinURL(url: url) {
            switch mixinURL {
            case let .codes(code):
                return checkCodesUrl(code, clearNavigationStack: clearNavigationStack)
            case .pay:
                return checkPayUrl(query: url.getKeyVals())
            case .withdrawal:
                return checkWithdrawal(url: url)
            case .address:
                return checkAddress(url: url)
            case let .users(id):
                return checkUser(id, clearNavigationStack: clearNavigationStack)
            case .snapshots:
                return checkSnapshot(url: url)
            case let .apps(userId):
                return checkApp(url: url, userId: userId)
            case let .transfer(id):
                return checkTransferUrl(id, clearNavigationStack: clearNavigationStack)
            case .send:
                return checkSendUrl(url: url)
            case let .device(id, publicKey):
                LoginConfirmWindow.instance(id: id, publicKey: publicKey).presentView()
                return true
            case .upgradeDesktop:
                UIApplication.currentActivity()?.alert(R.string.localizable.desktop_upgrade())
                return true
            case .unknown:
                return false
            }
        } else if let url = MixinInternalURL(url: url) {
            switch url {
            case let .identityNumber(number):
                return checkUser(identityNumber: number)
            }
        } else {
            return false
        }
    }

    class func checkApp(url: URL, userId: String) -> Bool {
        guard !userId.isEmpty, UUID(uuidString: userId) != nil else {
            return false
        }

        let isOpenApp = url.getKeyVals()["action"] == "open"

        DispatchQueue.global().async {
            var appItem = AppDAO.shared.getApp(ofUserId: userId)
            var userItem = UserDAO.shared.getUser(userId: userId)
            var refreshUser = true
            if appItem == nil || userItem == nil {
                switch UserAPI.shared.showUser(userId: userId) {
                case let .success(response):
                    refreshUser = false
                    userItem = UserItem.createUser(from: response)
                    appItem = response.app
                    UserDAO.shared.updateUsers(users: [response])
                case let .failure(error):
                    DispatchQueue.main.async {
                        if error.code == 404 {
                            showAutoHiddenHud(style: .error, text: R.string.localizable.app_not_found())
                        } else {
                            showAutoHiddenHud(style: .error, text: error.localizedDescription)
                        }
                    }
                    return
                }
            }

            guard let user = userItem else {
                return
            }

            guard let app = appItem else {
                DispatchQueue.main.async {
                    showAutoHiddenHud(style: .error, text: R.string.localizable.app_not_found())
                }
                return
            }

            let conversationId = ConversationDAO.shared.makeConversationId(userId: user.userId, ownerUserId: myUserId)

            DispatchQueue.main.async {
                if isOpenApp {
                    guard let parent = UIApplication.homeNavigationController?.visibleViewController else {
                        return
                    }
                    let userInfo = ["source": "UrlWindow", "identityNumber": app.appNumber]
                    reporter.report(event: .openApp, userInfo: userInfo)
                    DispatchQueue.main.async {
                        MixinWebViewController.presentInstance(with: .init(conversationId: conversationId, app: app), asChildOf: parent)
                    }
                } else {
                    let vc = UserProfileViewController(user: user)
                    vc.updateUserFromRemoteAfterReloaded = refreshUser
                    UIApplication.homeContainerViewController?.present(vc, animated: true, completion: nil)
                }
            }
        }
        return true
    }

    class func checkSnapshot(url: URL) -> Bool {
        let snapshotId: String? = (url.pathComponents.count > 1 ? url.pathComponents[1] : nil).uuidString
        let traceId: String? = url.getKeyVals()["trace"].uuidString

        guard !snapshotId.isNilOrEmpty || !traceId.isNilOrEmpty else {
            return false
        }

        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)
        DispatchQueue.global().async {
            var snapshotItem: SnapshotItem?
            if let traceId = traceId  {
                snapshotItem = SnapshotDAO.shared.getSnapshot(traceId: traceId)
                if snapshotItem == nil {
                    switch SnapshotAPI.shared.snapshot(traceId: traceId) {
                    case let .success(snapshot):
                        snapshotItem = SnapshotDAO.shared.saveSnapshot(snapshot: snapshot)
                    case let .failure(error):
                        DispatchQueue.main.async {
                            if error.code == 404 {
                                hud.set(style: .error, text: R.string.localizable.snapshot_not_found())
                            } else {
                                hud.set(style: .error, text: error.localizedDescription)
                            }
                            hud.scheduleAutoHidden()
                        }
                        return
                    }
                }
            } else if let snapshotId = snapshotId {
                snapshotItem = SnapshotDAO.shared.getSnapshot(snapshotId: snapshotId)
                if snapshotItem == nil {
                    switch SnapshotAPI.shared.snapshot(snapshotId: snapshotId) {
                    case let .success(snapshot):
                        snapshotItem = SnapshotDAO.shared.saveSnapshot(snapshot: snapshot)
                    case let .failure(error):
                        DispatchQueue.main.async {
                            if error.code == 404 {
                                hud.set(style: .error, text: R.string.localizable.snapshot_not_found())
                            } else {
                                hud.set(style: .error, text: error.localizedDescription)
                            }
                            hud.scheduleAutoHidden()
                        }
                        return
                    }
                }
            }

            guard let snapshot = snapshotItem, let assetItem = syncAsset(assetId: snapshot.assetId, hud: hud) else {
                return
            }

            if snapshot.type == SnapshotType.transfer.rawValue, let opponentId = snapshot.opponentId {
                if !UserDAO.shared.isExist(userId: opponentId) {
                    if case let .success(response) = UserAPI.shared.showUser(userId: opponentId) {
                        UserDAO.shared.updateUsers(users: [response])
                    }
                }
            }
            
            DispatchQueue.main.async {
                hud.hide()
                let vc = TransactionViewController.instance(asset: assetItem, snapshot: snapshot)
                UIApplication.homeNavigationController?.pushViewController(vc, animated: true)
            }
        }
        return true
    }

    class func checkUser(_ userId: String, clearNavigationStack: Bool) -> Bool {
        guard !userId.isEmpty, UUID(uuidString: userId) != nil else {
            return false
        }

        DispatchQueue.global().async {
            var userItem = UserDAO.shared.getUser(userId: userId)
            var updateUserFromRemoteAfterReloaded = true
            if userItem == nil {
                switch UserAPI.shared.showUser(userId: userId) {
                case let .success(response):
                    updateUserFromRemoteAfterReloaded = false
                    userItem = UserItem.createUser(from: response)
                    UserDAO.shared.updateUsers(users: [response])
                case let .failure(error):
                    DispatchQueue.main.async {
                        if error.code == 404 {
                            showAutoHiddenHud(style: .error, text: Localized.CONTACT_SEARCH_NOT_FOUND)
                        } else {
                            showAutoHiddenHud(style: .error, text: error.localizedDescription)
                        }
                    }
                    return
                }
            }

            guard let user = userItem, user.isCreatedByMessenger else {
                return
            }

            DispatchQueue.main.async {
                let vc = UserProfileViewController(user: user)
                vc.updateUserFromRemoteAfterReloaded = updateUserFromRemoteAfterReloaded
                UIApplication.homeContainerViewController?.present(vc, animated: true, completion: nil)
            }
        }
        return true
    }
    
    class func checkUser(identityNumber: String) -> Bool {
        guard !identityNumber.isEmpty else {
            return false
        }
        DispatchQueue.global().async {
            var userItem = UserDAO.shared.getUser(identityNumber: identityNumber)
            var updateUserFromRemoteAfterReloaded = true
            if userItem == nil {
                switch UserAPI.shared.search(keyword: identityNumber) {
                case let .success(response):
                    updateUserFromRemoteAfterReloaded = false
                    userItem = UserItem.createUser(from: response)
                    UserDAO.shared.updateUsers(users: [response])
                case let .failure(error):
                    DispatchQueue.main.async {
                        if error.code == 404 {
                            showAutoHiddenHud(style: .error, text: Localized.CONTACT_SEARCH_NOT_FOUND)
                        } else {
                            showAutoHiddenHud(style: .error, text: error.localizedDescription)
                        }
                    }
                    return
                }
            }
            guard let user = userItem, user.isCreatedByMessenger else {
                return
            }
            DispatchQueue.main.async {
                let vc = UserProfileViewController(user: user)
                vc.updateUserFromRemoteAfterReloaded = updateUserFromRemoteAfterReloaded
                UIApplication.homeContainerViewController?.present(vc, animated: true, completion: nil)
            }
        }
        return true
    }
    
    class func checkTransferUrl(_ userId: String, clearNavigationStack: Bool) -> Bool {
        guard !userId.isEmpty, UUID(uuidString: userId) != nil, userId != myUserId else {
            return false
        }

        DispatchQueue.global().async {
            var userItem = UserDAO.shared.getUser(userId: userId)
            if userItem == nil {
                switch UserAPI.shared.showUser(userId: userId) {
                case let .success(response):
                    userItem = UserItem.createUser(from: response)
                    UserDAO.shared.updateUsers(users: [response])
                case let .failure(error):
                    DispatchQueue.main.async {
                        if error.code == 404 {
                            showAutoHiddenHud(style: .error, text: Localized.CONTACT_SEARCH_NOT_FOUND)
                        } else {
                            showAutoHiddenHud(style: .error, text: error.localizedDescription)
                        }
                    }
                    return
                }
            }

            guard let user = userItem else {
                return
            }

            DispatchQueue.main.async {
                let vc = TransferOutViewController.instance(asset: nil, type: .contact(user))
                if clearNavigationStack {
                    UIApplication.homeNavigationController?.pushViewController(withBackRoot: vc)
                } else {
                    UIApplication.homeNavigationController?.pushViewController(vc, animated: true)
                }
            }
        }
        return true
    }

    class func checkWithdrawal(url: URL) -> Bool {
        guard LoginManager.shared.account?.has_pin ?? false else {
            UIApplication.homeNavigationController?.pushViewController(WalletPasswordViewController.instance(walletPasswordType: .initPinStep1, dismissTarget: nil), animated: true)
            return true
        }
        let query = url.getKeyVals()
        guard let assetId = query["asset"], let amount = query["amount"], let traceId = query["trace"], let addressId = query["address"] else {
            return false
        }
        guard !assetId.isEmpty && UUID(uuidString: assetId) != nil && !traceId.isEmpty && UUID(uuidString: traceId) != nil && !addressId.isEmpty && UUID(uuidString: addressId) != nil && !amount.isEmpty else {
            return false
        }
        var memo = query["memo"]
        if let urlDecodeMemo = memo?.removingPercentEncoding {
            memo = urlDecodeMemo
        }

        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)
        DispatchQueue.global().async {
            guard let asset = syncAsset(assetId: assetId, hud: hud) else {
                return
            }
            guard let chainAsset = syncAsset(assetId: asset.chainId, hud: hud) else {
                return
            }
            var address = AddressDAO.shared.getAddress(addressId: addressId)
            if address == nil {
                switch WithdrawalAPI.shared.address(addressId: addressId) {
                case let .success(remoteAddress):
                    AddressDAO.shared.insertOrUpdateAddress(addresses: [remoteAddress])
                    address = remoteAddress
                case let .failure(error):
                    DispatchQueue.main.async {
                        if error.code == 404 {
                            hud.set(style: .error, text: R.string.localizable.address_not_found())
                        } else {
                            hud.set(style: .error, text: error.localizedDescription)
                        }
                        hud.scheduleAutoHidden()
                    }
                    return
                }
            }

            hud.safeHide()

            guard let addr = address else {
                return
            }

            DispatchQueue.main.async {
                PayWindow.instance().render(asset: asset, action: .withdraw(trackId: traceId, address: addr, chainAsset: chainAsset, fromWeb: true), amount: amount, memo: memo ?? "").presentPopupControllerAnimated()
            }
        }

        return true
    }

    class func checkPayUrl(url: String) -> Bool {
        guard ["bitcoin:", "bitcoincash:", "bitcoinsv:", "ethereum:", "litecoin:", "dash:", "ripple:", "zcash:", "horizen:", "monero:", "binancecoin:", "stellar:", "dogecoin:"].contains(where: url.lowercased().hasPrefix) else {
            return false
        }
        guard let components = URLComponents(string: url.lowercased()) else {
            return false
        }
        return checkPayUrl(query: components.getKeyVals())
    }

    class func checkPayUrl(query: [String: String]) -> Bool {
        guard LoginManager.shared.account?.has_pin ?? false else {
            UIApplication.homeNavigationController?.pushViewController(WalletPasswordViewController.instance(walletPasswordType: .initPinStep1, dismissTarget: nil), animated: true)
            return true
        }
        guard let recipientId = query["recipient"], let assetId = query["asset"], let amount = query["amount"] else {
            return false
        }
        guard !recipientId.isEmpty && UUID(uuidString: recipientId) != nil && !assetId.isEmpty && UUID(uuidString: assetId) != nil && !amount.isEmpty && amount.isNumeric else {
            return false
        }

        let traceId = query["trace"].uuidString ?? UUID().uuidString.lowercased()
        var memo = query["memo"]
        if let urlDecodeMemo = memo?.removingPercentEncoding {
            memo = urlDecodeMemo
        }

        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)
        PaymentAPI.shared.payments(assetId: assetId, opponentId: recipientId, amount: amount, traceId: traceId) { (result) in
            switch result {
            case let .success(payment):
                DispatchQueue.global().async {
                    if let chainAsset = AssetDAO.shared.getAsset(assetId: payment.asset.chainId) ?? syncAsset(assetId: payment.asset.chainId, hud: hud) {
                        DispatchQueue.main.async {
                            hud.hide()
                            let asset = AssetItem(asset: payment.asset, chainIconUrl: chainAsset.iconUrl, chainName: chainAsset.name, chainSymbol: chainAsset.symbol)
                            let error = payment.status == PaymentStatus.paid.rawValue ? Localized.TRANSFER_PAID : ""
                            PayWindow.instance().render(asset: asset, action: .transfer(trackId: traceId, user: UserItem.createUser(from: payment.recipient), fromWeb: true), amount: amount, memo: memo ?? "", error: error).presentPopupControllerAnimated()
                        }
                    } else {
                        DispatchQueue.main.async {
                            hud.set(style: .error, text: R.string.localizable.asset_not_found())
                            hud.scheduleAutoHidden()
                        }
                    }
                }
            case let .failure(error):
                hud.set(style: .error, text: error.localizedDescription)
                hud.scheduleAutoHidden()
            }
        }
        return true
    }

    class func checkAddress(url: URL) -> Bool {
        guard LoginManager.shared.account?.has_pin ?? false else {
            UIApplication.homeNavigationController?.pushViewController(WalletPasswordViewController.instance(walletPasswordType: .initPinStep1, dismissTarget: nil), animated: true)
            return true
        }
        let query = url.getKeyVals()
        guard let assetId = query["asset"], !assetId.isEmpty, UUID(uuidString: assetId) != nil else {
            return false
        }

        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)
        DispatchQueue.global().async {
            guard var asset = syncAsset(assetId: assetId, hud: hud) else {
                return
            }

            while asset.destination.isEmpty {
                switch AssetAPI.shared.asset(assetId: asset.assetId) {
                case let .success(remoteAsset):
                    guard !remoteAsset.destination.isEmpty else {
                        Thread.sleep(forTimeInterval: 2)
                        continue
                    }
                    guard let localAsset = AssetDAO.shared.saveAsset(asset: remoteAsset) else {
                        hud.safeHide()
                        return
                    }
                    asset = localAsset
                case let .failure(error):
                    DispatchQueue.main.async {
                        hud.set(style: .error, text: error.localizedDescription)
                        hud.scheduleAutoHidden()
                    }
                    return
                }
            }

            var addressRequest: AddressRequest?
            var address: Address?

            let addressAction: AddressView.action
            if let action = query["action"]?.lowercased(), "delete" == action {
                guard let addressId = query["address"], !addressId.isEmpty && UUID(uuidString: addressId) != nil else {
                    hud.safeHide()
                    return
                }

                addressAction = .delete
                address = AddressDAO.shared.getAddress(addressId: addressId)
                if address == nil {
                    switch WithdrawalAPI.shared.address(addressId: addressId) {
                    case let .success(remoteAddress):
                        AddressDAO.shared.insertOrUpdateAddress(addresses: [remoteAddress])
                        address = remoteAddress
                    case let .failure(error):
                        DispatchQueue.main.async {
                            if error.code == 404 {
                                hud.set(style: .error, text: R.string.localizable.address_not_found())
                            } else {
                                hud.set(style: .error, text: error.localizedDescription)
                            }
                            hud.scheduleAutoHidden()
                        }
                        return
                    }
                }
            } else {
                guard let label = query["label"], let destination = query["destination"], !label.isEmpty, !destination.isEmpty else {
                    hud.safeHide()
                    return
                }

                let tag = query["tag"] ?? ""

                addressRequest = AddressRequest(assetId: assetId, destination: destination, tag: tag, label: label, pin: "")
                address = AddressDAO.shared.getAddress(assetId: assetId, destination: destination, tag: tag)
                addressAction = address == nil ? .add : .update
            }

            DispatchQueue.main.async {
                hud.hide()
                AddressWindow.instance().presentPopupControllerAnimated(action: addressAction, asset: asset, addressRequest: addressRequest, address: address, dismissCallback: nil)
            }
        }
        return true
    }

    class func checkSendUrl(url: URL) -> Bool {
        let query = url.getKeyVals()
        guard let text = query["text"], !text.isEmpty else {
            return false
        }
        
        let vc = MessageReceiverViewController.instance(content: .text(text))
        UIApplication.homeNavigationController?.pushViewController(vc, animated: true)

        return true
    }

}

extension UrlWindow {

    private static func checkCodesUrl(_ codeId: String, clearNavigationStack: Bool) -> Bool {
        guard !codeId.isEmpty, UUID(uuidString: codeId) != nil else {
            return false
        }

        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.mainWindow)

        UserAPI.shared.codes(codeId: codeId) { (result) in
            switch result {
            case let .success(code):
                if let user = code.user {
                    presentUser(user: user, hud: hud)
                } else if let authorization = code.authorization {
                    presentAuthorization(authorization: authorization, hud: hud)
                } else if let conversation = code.conversation {
                    presentConversation(conversation: conversation, codeId: codeId, hud: hud)
                } else if let multisig = code.multisig {
                    presentMultisig(multisig: multisig, hud: hud)
                } else if let payment = code.payment {
                    presentPayment(payment: payment, hud: hud)
                } else {
                    hud.hide()
                }
            case let .failure(error):
                if error.code == 404 {
                    hud.set(style: .error, text: Localized.CODE_RECOGNITION_FAIL_TITLE)
                } else {
                    hud.set(style: .error, text: error.localizedDescription)
                }
                hud.scheduleAutoHidden()
            }
        }
        return true
    }

    private static func syncAsset(assetId: String, hud: Hud) -> AssetItem? {
        var asset = AssetDAO.shared.getAsset(assetId: assetId)
        if asset == nil {
            switch AssetAPI.shared.asset(assetId: assetId) {
            case let .success(assetItem):
                asset = AssetDAO.shared.saveAsset(asset: assetItem)
            case let .failure(error):
                DispatchQueue.main.async {
                    if error.code == 404 {
                        hud.set(style: .error, text: R.string.localizable.asset_not_found())
                    } else {
                        hud.set(style: .error, text: error.localizedDescription)
                    }
                    hud.scheduleAutoHidden()
                }
                return nil
            }
        }

        if asset == nil {
            DispatchQueue.main.async {
                hud.set(style: .error, text: R.string.localizable.asset_not_found())
                hud.scheduleAutoHidden()
            }
        }

        return asset
    }

    private static func presentMultisig(multisig: MultisigResponse, hud: Hud) {
        DispatchQueue.global().async {
            guard let asset = syncAsset(assetId: multisig.assetId, hud: hud) else {
                return
            }

            let senders = multisig.senders
            let receivers = multisig.receivers
            var senderUsers = [UserResponse]()
            var receiverUsers = [UserResponse]()
            switch UserAPI.shared.showUsers(userIds: multisig.senders + multisig.receivers) {
            case let .success(users):
                senderUsers = users.filter { senders.contains($0.userId) }
                receiverUsers = users.filter { receivers.contains($0.userId) }
            case let .failure(error):
                DispatchQueue.main.async {
                    hud.set(style: .error, text: error.localizedDescription)
                    hud.scheduleAutoHidden()
                }
                return
            }

            var error = ""
            if multisig.action == MultisigAction.sign.rawValue && multisig.state == MultisigState.signed.rawValue {
                error = R.string.localizable.multisig_state_signed()
            } else if multisig.action == MultisigAction.unlock.rawValue && multisig.state == MultisigState.unlocked.rawValue {
                error = R.string.localizable.multisig_state_unlocked()
            }

            DispatchQueue.main.async {
                hud.hide()
                PayWindow.instance().render(asset: asset, action: .multisig(multisig: multisig, senders: senderUsers, receivers: receiverUsers), amount: multisig.amount, memo: "", error: error).presentPopupControllerAnimated()
            }
        }
    }

    private static func presentPayment(payment: PaymentCodeResponse, hud: Hud) {
        DispatchQueue.global().async {
            guard let asset = AssetDAO.shared.getAsset(assetId: payment.assetId) else {
                DispatchQueue.main.async {
                    hud.set(style: .error, text: R.string.localizable.asset_not_found())
                    hud.scheduleAutoHidden()
                }
                return
            }

            let receivers = payment.receivers
            var receiverUsers = [UserResponse]()
            switch UserAPI.shared.showUsers(userIds: payment.receivers) {
            case let .success(users):
                receiverUsers = users.filter { receivers.contains($0.userId) }
            case let .failure(error):
                DispatchQueue.main.async {
                    hud.set(style: .error, text: error.localizedDescription)
                    hud.scheduleAutoHidden()
                }
                return
            }

            let error = payment.status == PaymentStatus.paid.rawValue ? Localized.TRANSFER_PAID : ""

            DispatchQueue.main.async {
                hud.hide()
                PayWindow.instance().render(asset: asset, action: .payment(payment: payment, receivers: receiverUsers), amount: payment.amount, memo: "", error: error).presentPopupControllerAnimated()
            }
        }
    }

    private static func presentUser(user: UserResponse, hud: Hud) {
        DispatchQueue.global().async {
            UserDAO.shared.updateUsers(users: [user])

            DispatchQueue.main.async {
                hud.hide()
                let user = UserItem.createUser(from: user)
                let vc = UserProfileViewController(user: user)
                UIApplication.homeContainerViewController?.present(vc, animated: true, completion: nil)
            }
        }
    }

    private static func presentAuthorization(authorization: AuthorizationResponse, hud: Hud) {
        DispatchQueue.global().async {
            let assets = AssetDAO.shared.getAvailableAssets()

            DispatchQueue.main.async {
                hud.hide()
                AuthorizationWindow.instance().render(authInfo: authorization, assets: assets).presentPopupControllerAnimated()
            }
        }
    }

    private static func presentConversation(conversation: ConversationResponse, codeId: String, hud: Hud) {
        DispatchQueue.global().async {
            let subParticipants = conversation.participants.prefix(4)
            let accountUserId = myUserId
            let conversationId = conversation.conversationId
            let isMember = conversation.participants.first(where: { $0.userId == accountUserId }) != nil
            let userIds = subParticipants.map{ $0.userId }
            var participants = [ParticipantUser]()
            switch UserAPI.shared.showUsers(userIds: userIds) {
            case let .success(users):
                participants = users.map {
                    ParticipantUser(conversationId: conversationId, user: $0)
                }
            case let .failure(error):
                DispatchQueue.main.async {
                    hud.set(style: .error, text: error.localizedDescription)
                    hud.scheduleAutoHidden()
                }
                return
            }
            var creatorUser = UserDAO.shared.getUser(userId: conversation.creatorId)
            if creatorUser == nil {
                switch UserAPI.shared.showUser(userId: conversation.creatorId) {
                case let .success(user):
                    creatorUser = UserItem.createUser(from: user)
                case let .failure(error):
                    DispatchQueue.main.async {
                        hud.set(style: .error, text: error.localizedDescription)
                        hud.scheduleAutoHidden()
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                hud.hide()
                let vc = GroupProfileViewController(response: conversation, codeId: codeId, participants: participants, isMember: isMember)
                UIApplication.homeContainerViewController?.present(vc, animated: true, completion: nil)
            }
        }
    }
}
