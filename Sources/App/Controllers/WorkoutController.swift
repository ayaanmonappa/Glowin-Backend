import Vapor

struct WorkoutController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let workouts = routes.grouped("workouts")
        let protected = workouts.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.post("generate", use: generateWorkoutPlan)
    }

    func generateWorkoutPlan(req: Request) throws -> EventLoopFuture<[WorkoutDay]> {
        let user = try req.auth.require(User.self)
        
        guard let activityLevel = user.activityLevel,
                   let goal = user.goal,
                   let bodyType = user.bodyType else {
                 throw Abort(.badRequest, reason: "Please complete your profile with activity level, goal, and body type before generating a workout plan.")
             }

        // Ensure all necessary fields are filled
        guard let activityLevel = user.activityLevel,
              let goal = user.goal,
              let bodyType = user.bodyType else {
            throw Abort(.badRequest, reason: "Please complete your profile with activity level, goal, and body type before generating a workout plan.")
        }

        guard let days = try? req.query.get(Int.self, at: "days") else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Number of days is required as a query parameter."))
        }

        let generator = WorkoutPlanGenerator()

        return generator.generateWorkoutPlan(for: user, req: req, days: days)
            .flatMapErrorThrowing { error in
                throw Abort(.internalServerError, reason: "Failed to generate workout plan: \(error.localizedDescription)")
            }
    }
}
