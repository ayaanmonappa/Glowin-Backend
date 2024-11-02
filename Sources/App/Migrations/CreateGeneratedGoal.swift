//
//  File.swift
//  
//
//  Created by Ayaan Monappa on 26/7/24.
//

import Fluent

struct CreateGeneratedGoal1: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("generated_goals")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("measurement_type", .string, .required)
            .field("goal_value", .double, .required)
            .field("target_date", .date, .required)
            .field("date_generated", .datetime, .required, .sql(.default("NOW()")))
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("generated_goals").delete()
    }
}

