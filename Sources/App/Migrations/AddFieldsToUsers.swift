//
//  File.swift
//  
//
//  Created by Ayaan Monappa on 29/7/24.
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

