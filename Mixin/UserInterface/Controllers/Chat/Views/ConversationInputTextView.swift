import UIKit
import MixinServices

class ConversationInputTextView: UITextView {
    
    weak var overrideNext: UIResponder?
    
    override var next: UIResponder? {
        if let responder = overrideNext {
            return responder
        } else {
            return super.next
        }
    }
    
    // Return the token between Mention.prefix and the caret
    // token is separated with space
    var inputingMentionTokenRange: NSRange? {
        guard !text.isEmpty else {
            return nil
        }
        guard let selectedTextRange = selectedTextRange else {
            return nil
        }
        guard let rangeBeforeCaret = textRange(from: beginningOfDocument, to: selectedTextRange.start) else {
            return nil
        }
        guard let stringBeforeCaret = text(in: rangeBeforeCaret) else {
            return nil
        }
        for (index, char) in stringBeforeCaret.enumerated().reversed() {
            if char == " " {
                return nil
            } else if char == Mention.prefix {
                let start = stringBeforeCaret.index(stringBeforeCaret.startIndex, offsetBy: index.advanced(by: 1))
                let end = stringBeforeCaret.endIndex
                return NSRange(start..<end, in: stringBeforeCaret)
            }
        }
        return nil
    }
    
    var inputingMentionToken: String? {
        if let range = inputingMentionTokenRange {
            return (text as NSString).substring(with: range)
        } else {
            return nil
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if overrideNext != nil {
            return false
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }
    
    func replaceInputingMentionToken(with user: UserItem) {
        let replacement = "\(Mention.prefix)\(user.identityNumber)\(Mention.suffix)"
        guard !text.isEmpty else {
            text = replacement
            return
        }
        guard let selectedTextRange = selectedTextRange else {
            return
        }
        guard let rangeBeforeCaret = textRange(from: beginningOfDocument, to: selectedTextRange.start) else {
            return
        }
        guard let stringBeforeCaret = text(in: rangeBeforeCaret) else {
            return
        }
        for (index, char) in stringBeforeCaret.reversed().enumerated() {
            if char == " " {
                return
            } else if char == Mention.prefix {
                guard let start = position(from: rangeBeforeCaret.end, offset: -index - 1) else {
                    return
                }
                let replacedRange = NSRange(location: offset(from: beginningOfDocument, to: start),
                                            length: index + 1)
                let mutable = attributedText.mutableCopy() as! NSMutableAttributedString
                mutable.mutableString.replaceCharacters(in: replacedRange, with: replacement)
                let replacementRange = NSRange(location: replacedRange.location,
                                               length: (replacement as NSString).length - 1)
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.theme,
                    .mentionLength: replacementRange.length
                ]
                mutable.addAttributes(attrs, range: replacementRange)
                attributedText = (mutable.copy() as! NSAttributedString)
                delegate?.textViewDidChange?(self)
            }
        }
    }
    
}
