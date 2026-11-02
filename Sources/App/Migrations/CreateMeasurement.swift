
import Fluent

struct CreateMeasurement: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("measurements")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("weight", .double, .required)
            .field("height", .double, .required)
            .field("bicep", .double, .required)
            .field("calf", .double, .required)
            .field("waist", .double, .required)
            .field("thigh", .double, .required)
            .field("chest", .double, .required)
            .field("date", .date, .required)
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("measurements").delete()
    }
}

