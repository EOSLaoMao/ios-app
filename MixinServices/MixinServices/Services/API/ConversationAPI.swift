import Foundation
import Alamofire

public class ConversationAPI : BaseAPI {
    
    public static let shared = ConversationAPI()
    
    private enum url {
        static let conversations = "conversations"
        static func conversations(id: String) -> String {
            return "conversations/\(id)"
        }
        
        static func participants(id: String, action: ParticipantAction) -> String {
            return "conversations/\(id)/participants/\(action.rawValue)"
        }
        
        static func exit(id: String) -> String {
            return "conversations/\(id)/exit"
        }
        
        static func join(codeId: String) -> String {
            return "conversations/\(codeId)/join"
        }
        
        static func mute(conversationId: String) -> String {
            return "conversations/\(conversationId)/mute"
        }
        
        static func reset(conversationId: String) -> String {
            return "conversations/\(conversationId)/rotate"
        }
        
    }
    
    public func createConversation(conversation: ConversationRequest, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        request(method: .post, url: url.conversations, parameters: conversation.toParameters(), encoding: EncodableParameterEncoding<ConversationRequest>(), completion: completion)
    }
    
    public func createConversation(conversation: ConversationRequest) -> BaseAPI.Result<ConversationResponse> {
        return request(method: .post, url: url.conversations, parameters: conversation.toParameters(), encoding: EncodableParameterEncoding<ConversationRequest>())
    }
    
    public func getConversation(conversationId: String) -> BaseAPI.Result<ConversationResponse> {
        return request(method: .get, url: url.conversations(id: conversationId))
    }
    
    public func exitConversation(conversationId: String, completion: @escaping (BaseAPI.Result<Empty>) -> Void) {
        request(method: .post, url: url.exit(id: conversationId), completion: completion)
    }
    
    public func joinConversation(codeId: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        request(method: .post, url: url.join(codeId: codeId), completion: completion)
    }
    
    public func addParticipant(conversationId: String, participantUserIds: [String], completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        let parameters = participantUserIds.map({ ["user_id": $0, "role": ""] }).toParameters()
        request(method: .post, url: url.participants(id: conversationId, action: ParticipantAction.ADD), parameters: parameters, encoding: JSONArrayEncoding(), completion: completion)
    }
    
    public func removeParticipant(conversationId: String, userId: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        let parameters = [["user_id": userId, "role": ""]].toParameters()
        request(method: .post, url: url.participants(id: conversationId, action: ParticipantAction.REMOVE), parameters: parameters, encoding: JSONArrayEncoding(), completion: completion)
    }
    
    public func adminParticipant(conversationId: String, userId: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        let parameters = [["user_id": userId, "role": ParticipantRole.ADMIN.rawValue]].toParameters()
        request(method: .post, url: url.participants(id: conversationId, action: ParticipantAction.ROLE), parameters: parameters, encoding: JSONArrayEncoding(), completion: completion)
    }

    public func dismissAdminParticipant(conversationId: String, userId: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        let parameters = [["user_id": userId, "role": ""]].toParameters()
        request(method: .post, url: url.participants(id: conversationId, action: ParticipantAction.ROLE), parameters: parameters, encoding: JSONArrayEncoding(), completion: completion)
    }
    
    public func updateGroupName(conversationId: String, name: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        let conversationRequest = ConversationRequest(conversationId: conversationId, name: name, category: nil, participants: nil, duration: nil, announcement: nil)
        request(method: .post, url: url.conversations(id: conversationId), parameters: conversationRequest.toParameters(), encoding: EncodableParameterEncoding<ConversationRequest>(), completion: completion)
    }
    
    public func updateGroupAnnouncement(conversationId: String, announcement: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        let conversationRequest = ConversationRequest(conversationId: conversationId, name: nil, category: nil, participants: nil, duration: nil, announcement: announcement)
        request(method: .post, url: url.conversations(id: conversationId), parameters: conversationRequest.toParameters(), encoding: EncodableParameterEncoding<ConversationRequest>(), completion: completion)
    }
    
    public func mute(conversationId: String, conversationRequest: ConversationRequest, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        request(method: .post, url: url.mute(conversationId: conversationId), parameters: conversationRequest.toParameters(), encoding: EncodableParameterEncoding<ConversationRequest>(), completion: completion)
    }
    
    public func updateCodeId(conversationId: String, completion: @escaping (BaseAPI.Result<ConversationResponse>) -> Void) {
        request(method: .post, url: url.reset(conversationId: conversationId), completion: completion)
    }
    
}
