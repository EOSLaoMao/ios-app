import Foundation
import WCDBSwift

public struct User: BaseCodable {
    
    public static let tableName: String = "users"
    
    public let userId: String
    public let fullName: String?
    public let biography: String?
    public let identityNumber: String
    public let avatarUrl: String?
    public var phone: String? = nil
    public var isVerified: Bool? = nil
    public var muteUntil: String? = nil
    public var appId: String? = nil
    public let createdAt: String?
    public let relationship: String
    public var isScam: Bool = false
    
    public var app: App? = nil
    
    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = User
        case userId = "user_id"
        case fullName = "full_name"
        case biography = "biography"
        case identityNumber = "identity_number"
        case avatarUrl = "avatar_url"
        case phone
        case isVerified = "is_verified"
        case muteUntil = "mute_until"
        case appId = "app_id"
        case relationship
        case createdAt = "created_at"
        case isScam = "is_scam"
        
        public static let objectRelationalMapping = TableBinding(CodingKeys.self)
        public static var columnConstraintBindings: [CodingKeys: ColumnConstraintBinding]? {
            return [
                userId: ColumnConstraintBinding(isPrimary: true)
            ]
        }
        public static var indexBindings: [IndexBinding.Subfix: IndexBinding]? {
            return [
                "_identity_number_indexs": IndexBinding(indexesBy: identityNumber),
                "_app_indexs": IndexBinding(indexesBy: appId)
            ]
        }
    }
    
    static let systemUser = "00000000-0000-0000-0000-000000000000"
    
    public static func createSystemUser() -> User {
        return User(userId: systemUser, fullName: "0", biography: "", identityNumber: "0", avatarUrl: nil, phone: nil, isVerified: false, muteUntil: nil, appId: nil, createdAt: nil, relationship: "", app: nil)
    }
    
    public static func createUser(from user: UserResponse) -> User {
        return User(userId: user.userId, fullName: user.fullName, biography: user.biography, identityNumber: user.identityNumber, avatarUrl: user.avatarUrl, phone: user.phone, isVerified: user.isVerified, muteUntil: user.muteUntil, appId: user.app?.appId, createdAt: user.createdAt, relationship: user.relationship.rawValue, isScam: user.isScam, app: user.app)
    }
    
    public static func createUser(from account: Account) -> User {
        return User(userId: account.user_id, fullName: account.full_name, biography: account.biography, identityNumber: account.identity_number, avatarUrl: account.avatar_url, phone: account.phone, isVerified: false, muteUntil: nil, appId: nil, createdAt: account.created_at, relationship: Relationship.ME.rawValue, app: nil)
    }
    
}
