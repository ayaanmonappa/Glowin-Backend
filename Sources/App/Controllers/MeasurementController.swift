import Fluent
import Vapor

struct MeasurementController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let measurements = routes.grouped("measurements")
        let protected = measurements.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get(use: index)
        protected.post(use: create)
        protected.put(":id", use: update)
    }

    // GET /measurements
    func index(req: Request) throws -> EventLoopFuture<[Measurement.Public]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return Measurement.query(on: req.db)
            .filter(\.$user.$id == userID)
            .all()
            .map { measurements in
                return measurements.map { $0.toPublic() }
            }
    }

    // POST /measurements
    func create(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard let userID = user.id else {
            throw Abort(.unauthorized, reason: "User ID not found.")
        }
        let measurementCreate = try req.content.decode(Measurement.Create.self)
        let measurement = Measurement(
            id: nil,
            userID: userID,
            weight: measurementCreate.weight,
            height: measurementCreate.height,
            bicep: measurementCreate.bicep,
            calf: measurementCreate.calf,
            waist: measurementCreate.waist,
            thigh: measurementCreate.thigh,
            chest: measurementCreate.chest,
            date: measurementCreate.date
        )
        return measurement.save(on: req.db).transform(to: .ok)
    }

    // PUT /measurements/:id
    func update(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard let userID = user.id else {
            throw Abort(.unauthorized, reason: "User ID not found.")
        }
        let updateRequest = try req.content.decode(Measurement.Create.self)
        guard let measurementID = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid measurement ID.")
        }

        return Measurement.query(on: req.db)
            .filter(\.$id == measurementID)
            .filter(\.$user.$id == userID)
            .first()
            .unwrap(or: Abort(.notFound))
            .flatMap { measurement in
                measurement.weight = updateRequest.weight
                measurement.height = updateRequest.height
                measurement.bicep = updateRequest.bicep
                measurement.calf = updateRequest.calf
                measurement.waist = updateRequest.waist
                measurement.thigh = updateRequest.thigh
                measurement.chest = updateRequest.chest
                measurement.date = updateRequest.date
                return measurement.save(on: req.db).transform(to: .ok)
            }
    }
}
