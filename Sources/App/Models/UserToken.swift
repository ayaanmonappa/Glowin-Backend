import Fluent
import Vapor

final class UserToken: Model, Content {
    static let schema = "user_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "value")
    var value: String

    @Parent(key: "user_id")
    var user: User

    init() {}

    init(id: UUID? = nil, value: String, userID: UUID) {
        self.id = id
        self.value = value
        self.$user.id = userID
    }

    static func generate(for user: User) throws -> UserToken {
        let random = [UInt8].random(count: 16).base64
        return try UserToken(value: random, userID: user.requireID())
    }
}

extension UserToken: ModelTokenAuthenticatable {
    static let valueKey = \UserToken.$value
    static let userKey = \UserToken.$user

    var isValid: Bool {
        true
    }
}
