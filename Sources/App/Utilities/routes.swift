import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async throws in
        try await req.view.render("index", ["title": "Hello Vapor!"])
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }
    
    app.get("reset-password") { req -> Response in
            req.fileio.streamFile(at: req.application.directory.resourcesDirectory + "Views/reset-password.html")
        }

    try app.register(collection: UserController2())
    let protected = app.grouped(UserToken.authenticator(), User.guardMiddleware())
    try protected.register(collection: MeasurementController())
    try app.register(collection: DatabaseController())
    try app.register(collection: RecipeController())
    try app.register(collection: WorkoutController())
    try app.register(collection: GoalGenerationController()) 
}
