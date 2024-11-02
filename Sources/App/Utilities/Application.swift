import Vapor
import SendGridKit

extension Application {
    struct SendGridServiceKey: StorageKey {
        typealias Value = SendGridClient
    }

    var sendgridClient: SendGridClient? {
        get {
            self.storage[SendGridServiceKey.self]
        }
        set {
            self.storage[SendGridServiceKey.self] = newValue
        }
    }
}
