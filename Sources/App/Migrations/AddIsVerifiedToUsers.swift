import Fluent

struct AddIsVerifiedToUsers2: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("users")
            .field("is_verified", .bool, .required, .custom("DEFAULT FALSE"))
            .update()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("users")
            .deleteField("is_verified")
            .update()
    }
}



struct CreateVerificationToken2: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("verification_tokens")
            .id()
            .field("token", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id"))
            .field("expires_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("verification_tokens").delete()
    }
}
