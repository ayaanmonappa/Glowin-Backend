//
//  File.swift
//  
//

import Fluent

struct AddFieldsToUsers: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users")
            .field("bodyType", .string)
            .field("lastGoalGeneration", .datetime)
            .update()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users")
            .deleteField("bodyType")
            .deleteField("lastGoalGeneration")
            .update()
    }
}

