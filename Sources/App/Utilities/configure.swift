import Fluent
import Vapor
import FluentPostgresDriver
import SendGridKit

public func configure(_ app: Application) throws {
    // Database configuration
    
    app.databases.use(.postgres(
           hostname: Environment.get("DATABASE_HOST") ?? "localhost",
           port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
           username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
           password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
           database: Environment.get("DATABASE_NAME") ?? "vapor_database"
       ), as: .psql)
    
    
    let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        ContentConfiguration.global.use(encoder: encoder, for: .json)
        ContentConfiguration.global.use(decoder: decoder, for: .json)
    
 
   
    // SendGrid setup
       if let sendgridAPIKey = Environment.get("SENDGRID_API_KEY") {
           app.logger.info("SendGrid API Key is successfully loaded.")
           app.sendgridClient = SendGridClient(httpClient: app.http.client.shared, apiKey: sendgridAPIKey)
       } else {
           app.logger.error("SendGrid API key not found in environment variables.")
           throw Abort(.internalServerError, reason: "SendGrid API key is missing.")
       }

    // Migrations
    app.logger.info("Adding migrations...")
    app.migrations.add(CreateUser2())
    app.migrations.add(CreatePasswordResetToken())
    app.migrations.add(CreateMeasurement())
    app.migrations.add(CreateUserToken())
   // app.migrations.add(CreateFavoriteRecipe())
    app.migrations.add(CreateGeneratedGoal1())
    app.migrations.add(AddFieldsToUsers())
    app.migrations.add(AddActivityLevelToUsers())
    app.migrations.add(AddIsVerifiedToUsers2())
    app.migrations.add(CreateVerificationToken2())


    app.logger.info("Starting migrations...")
    try app.autoMigrate().wait()
    app.logger.info("Migrations completed.")
    
    

    // Register routes
    try routes(app)
}
