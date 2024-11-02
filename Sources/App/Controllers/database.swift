import Vapor
import Fluent
import PostgresKit

struct DatabaseController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let database = routes.grouped("database")
        database.get("tables", use: listTables)
    }

    func listTables(req: Request) -> EventLoopFuture<[String]> {
        let sql = req.db as! PostgresDatabase
        return sql.query("SELECT tablename FROM pg_tables WHERE schemaname = 'public';").flatMapThrowing { result in
            result.rows.compactMap { row in
                row.column("tablename")?.string
            }
        }
    }
}
