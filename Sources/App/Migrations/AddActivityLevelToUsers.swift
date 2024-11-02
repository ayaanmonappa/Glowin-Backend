import Fluent

struct AddActivityLevelToUsers: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("users")
            .field("activity_level", .string)
            .update()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("users")
            .deleteField("activity_level")
            .update()
    }
}
