import Alamofire
import MixinServices

final class PhoneContactAPI: BaseAPI {
    
    static let shared = PhoneContactAPI()
    
    enum url {
        static let contacts = "contacts"
    }
    
    func upload(contacts: [PhoneContact], completion: ((BaseAPI.Result<Empty>) -> Void)? = nil) {
        let parameters = contacts.map({ ["phone": $0.phoneNumber, "full_name": $0.fullName] }).toParameters()
        request(method: .post, url: url.contacts, parameters: parameters, encoding: JSONArrayEncoding()) { (result) in
            completion?(result)
        }
    }
    
}
