import Fluent

struct CreatePasswordResetToken: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("password_reset_tokens")
            .id()
            .field("token", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("password_reset_tokens").delete()
    }
}
