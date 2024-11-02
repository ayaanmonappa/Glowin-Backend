import Fluent
import SendGridKit
import Vapor

struct UserController2: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("check-username", use: checkUsername)
             users.get("check-email", use: checkEmail)
     
    
             // Password reset routes
        users.post("request-password-reset", use: requestPasswordReset)
                users.post("perform-password-reset", use: performPasswordReset)
        
        let protected = users.grouped(UserToken.authenticator(), User.guardMiddleware())
        users.get(":userId", use: getUserAttribute)
        users.post("create", use: create)
        users.post("login", use: login)
        protected.post("updateAge", use: updateAge)
        protected.post("updateGoal", use: updateGoal)
        protected.post("updateBodyType", use: updateBodyType) // New route for updating body type
        protected.post("updateLastGoalGeneration", use: updateLastGoalGeneration) // New route for updating last goal generation
        protected.post("updateActivityLevel", use: updateActivityLevel)
        protected.get("goal", use: getGoal)
        protected.get("profile", use: getProfile)
        users.get("verify-email", ":token", use: verifyEmail)
    
    }
    
    func requestPasswordReset(req: Request) async throws -> HTTPStatus {
        let emailRequest = try req.content.decode(EmailRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == emailRequest.email)
            .first()
        else {
            throw Abort(.notFound, reason: "Email not found.")
        }

        try await sendPasswordResetEmail(req: req, user: user)
        return .ok
    }


    func performPasswordReset(req: Request) throws -> EventLoopFuture<Response> {
        let resetRequest = try req.content.decode(PasswordResetRequest.self)
        
        return PasswordResetToken.query(on: req.db)
            .filter(\.$token == resetRequest.token)
            .filter(\.$expiresAt > Date())
            .first()
            .unwrap(or: Abort(.notFound, reason: "Invalid or expired reset token"))
            .flatMap { token in
                User.find(token.$user.id, on: req.db)
                    .unwrap(or: Abort(.notFound, reason: "User not found"))
                    .flatMapThrowing { user in
                        user.password = try Bcrypt.hash(resetRequest.newPassword)
                        return user
                    }
                    .flatMap { user in
                        user.save(on: req.db).flatMap {
                            token.delete(on: req.db)
                        }
                    }
            }
            .map { _ in
                let htmlContent = """
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Password Reset Successful</title>
                    <style>
                        body { font-family: Arial, sans-serif; text-align: center; color: #333; background-color: #f9f9f9; }
                        h1 { color: #4CAF50; }
                        .button { margin-top: 20px; padding: 10px 20px; color: #fff; background-color: #4CAF50; border: none; border-radius: 5px; text-decoration: none; }
                    </style>
                </head>
                <body>
                    <h1>Password Reset Successfully!</h1>
                    <p>Your password has been reset. You can now return to the app and log in with your new password.</p>
                    <a class="button" href="glowinapp://reset-success">Return to App</a>
                </body>
                </html>
                """
                let response = Response(status: .ok, headers: ["Content-Type": "text/html"], body: .init(string: htmlContent))
                return response
            }
    }



        func sendPasswordResetEmail(req: Request, user: User) async throws {
            guard let sendgridClient = req.application.sendgridClient else {
                throw Abort(.internalServerError, reason: "SendGrid client not configured")
            }

            let resetToken = UUID().uuidString
            let expiresAt = Date().addingTimeInterval(60 * 60)

            let token = PasswordResetToken(token: resetToken, userID: user.id!, expiresAt: expiresAt)
            try await token.save(on: req.db)

            let resetURL = "https://8174-219-74-229-42.ngrok-free.app/reset-password?token=\(resetToken)"

            let email = SendGridEmail(
                personalizations: [
                    Personalization(to: [EmailAddress(email: user.email)], subject: "Password Reset Request")
                ],
                from: EmailAddress(email: "support@glowinapp.com"),
                content: [
                    ["type": "text/html", "value": "<p>Click <a href=\"\(resetURL)\">here</a> to reset your password.</p>"]
                ]
            )

            try await sendgridClient.send(email: email)
        }
    
    
    // GET /users/profile
       func getProfile(req: Request) throws -> EventLoopFuture<UserProfileResponse> {
           let user = try req.auth.require(User.self)
           let userID = try user.requireID()
           
           return User.find(userID, on: req.db).unwrap(or: Abort(.notFound)).map { user in
               return UserProfileResponse(
                   username: user.username,
                   email: user.email,
                   age: user.age,
                   activityLevel: user.activityLevel,
                   bodyType: user.bodyType,
                   goal: user.goal,
                   lastGoalGeneration: user.lastGoalGeneration
               )
           }
       }
   }

func checkEmail(req: Request) throws -> EventLoopFuture<HTTPStatus> {
    req.logger.info("Incoming request to check email.")
    
    // Check if the query parameter is correctly captured
    guard let email = req.query[String.self, at: "email"] else {
        req.logger.error("Missing or invalid 'email' query parameter.")
        throw Abort(.badRequest, reason: "Email is required.")
    }
    
    req.logger.info("Captured email parameter: \(email)")

    // Proceed with checking the email
    return User.query(on: req.db)
        .filter(\.$email == email)
        .first()
        .map { user in
            if user != nil {
                req.logger.info("Email \(email) is already registered.")
                return .conflict  // Email already exists
            } else {
                req.logger.info("Email \(email) is available.")
                return .ok  // Email is available
            }
        }
}




// GET /users/check-username
func checkUsername(req: Request) throws -> EventLoopFuture<HTTPStatus> {
    guard let username = req.query[String.self, at: "username"] else {
        print("Username parameter missing or invalid")
        throw Abort(.badRequest, reason: "Username is required.")
    }
    print("Received username: \(username)")
    
    return User.query(on: req.db)
        .filter(\.$username == username)
        .first()
        .map { user in
            if user != nil {
                print("Username already taken")
                return .conflict  // 409 Conflict: Username already exists
            } else {
                print("Username available")
                return .ok  // 200 OK: Username is available
            }
        }
}


    
    // POST /users/updateActivityLevel
      func updateActivityLevel(req: Request) throws -> EventLoopFuture<HTTPStatus> {
          let user = try req.auth.require(User.self)
          let updateRequest = try req.content.decode(UpdateActivityLevelRequest.self)
          
          user.activityLevel = updateRequest.activityLevel
          return user.save(on: req.db).transform(to: .ok)
      }
  
    // GET /users/:userId
    func getUserAttribute(req: Request) throws -> EventLoopFuture<String> {
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let attributeName = req.query[String.self, at: "attribute"] else {
            throw Abort(.badRequest)
        }

        return User.query(on: req.db)
            .filter(\.$id == userId)
            .first()
            .flatMapThrowing { user -> String in
                guard let user = user else {
                    throw Abort(.notFound)
                }

                switch attributeName {
                case "username":
                    return user.username
                case "email":
                    return user.email
                case "gender":
                    return user.gender
                case "age":
                    return String(user.age)
                case "goal":
                    return user.goal ?? "No goal set"
                case "bodyType":
                    return user.bodyType ?? "No body type set"
                case "lastGoalGeneration":
                    return user.lastGoalGeneration?.description ?? "No last goal generation date set"
                default:
                    throw Abort(.badRequest)
                }
            }
    }
  func create(req: Request) throws -> EventLoopFuture<HTTPStatus> {
     let userInput = try req.content.decode(UserInput.self)
     
     // Validation of username and email
     guard userInput.username.count <= 25, !userInput.username.contains(" ") else {
         throw Abort(.badRequest, reason: "Username must be less than 25 characters and contain no spaces.")
     }
     
     let emailPredicate = NSPredicate(format: "SELF MATCHES %@", "[A-Z0-9a-z._%+-]+@[A-Z0-9a-z.-]+\\.[A-Za-z]{2,64}")
     guard emailPredicate.evaluate(with: userInput.email) else {
         throw Abort(.badRequest, reason: "Invalid email format.")
     }
     
     // Create the user instance with `isVerified` set to false
     let user = User(
         username: userInput.username,
         email: userInput.email,
         password: try Bcrypt.hash(userInput.password),
         gender: userInput.gender,
         age: userInput.age
     )
     
     return User.query(on: req.db)
         .group(.or) { or in
             or.filter(\.$username == user.username)
             or.filter(\.$email == user.email)
         }
         .first()
         .flatMapThrowing { existingUser -> User in
             if let existingUser = existingUser {
                 if existingUser.username == user.username {
                     throw Abort(.badRequest, reason: "Username already exists.")
                 }
                 if existingUser.email == user.email {
                     throw Abort(.badRequest, reason: "Email already exists.")
                 }
             }
             return user
         }
         .flatMap { user in
             user.save(on: req.db).flatMap { _ in
                 req.eventLoop.makeFutureWithTask {
                     try await sendVerificationEmail(req: req, user: user)
                 }.transform(to: .created)
             }
         }
 }




    // MARK: - Send Verification Email
    

func sendVerificationEmail(req: Request, user: User) async throws {
    // Ensure `sendgridClient` is available
    guard let sendgridClient = req.application.sendgridClient else {
        throw Abort(.internalServerError, reason: "SendGrid client not configured")
    }

    // Create a new verification token for the user
    let verificationToken = UUID().uuidString
    let expiresAt = Date().addingTimeInterval(60 * 60 * 24) // Token valid for 24 hours

    // Save the token to the database
    let token = VerificationToken(token: verificationToken, userID: user.id!, expiresAt: expiresAt)
    try await token.save(on: req.db)

    // Construct the verification URL
    let verifyURL = "https://8174-219-74-229-42.ngrok-free.app/users/verify-email/\(verificationToken)"
    
    // Create the email content
    let email = SendGridEmail(
        personalizations: [
            Personalization(to: [EmailAddress(email: user.email)], subject: "Verify your email address")
        ],
        from: EmailAddress(email: "support@glowinapp.com"),
        content: [
            ["type": "text/html", "value": "<p>Please verify your email by clicking <a href=\"\(verifyURL)\">here</a>.</p>"]
        ]
    )

    // Send the email asynchronously
    try await sendgridClient.send(email: email)
}

    // MARK: - Email Verification Endpoint
    
func verifyEmail(req: Request) throws -> EventLoopFuture<Response> {
    guard let token = req.parameters.get("token") else {
        throw Abort(.badRequest, reason: "Invalid or missing token.")
    }
    
    return VerificationToken.query(on: req.db)
        .filter(\.$token == token)
        .filter(\.$expiresAt > Date())
        .first()
        .unwrap(or: Abort(.notFound, reason: "Invalid or expired token."))
        .flatMap { token in
            User.find(token.$user.id, on: req.db)
                .unwrap(or: Abort(.notFound, reason: "User not found for this token."))
                .flatMap { user in
                    user.isVerified = true
                    return user.save(on: req.db).flatMap {
                        token.delete(on: req.db)
                    }
                }
        }
        .map { _ in
            let htmlContent = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Email Verified</title>
                <style>
                    body { font-family: Arial, sans-serif; text-align: center; color: #333; background-color: #f9f9f9; }
                    h1 { color: #4CAF50; }
                    .button { margin-top: 20px; padding: 10px 20px; color: #fff; background-color: #4CAF50; border: none; border-radius: 5px; text-decoration: none; }
                </style>
            </head>
            <body>
                <h1>Email Verified Successfully!</h1>
                <p>Your email has been verified. You can now return to the app to continue using your account.</p>
                <a class="button" href="glowinapp://verify-success">Return to App</a>
            </body>
            </html>
            """
            let response = Response(status: .ok, headers: ["Content-Type": "text/html"], body: .init(string: htmlContent))
            return response
        }
}




    // POST /users/login
    func login(req: Request) throws -> EventLoopFuture<UserToken> {
        let loginRequest = try req.content.decode(LoginRequest.self)
        return User.query(on: req.db)
            .filter(\.$username == loginRequest.username)
            .first()
            .flatMapThrowing { user -> User in
                guard let user = user else {
                    throw Abort(.notFound, reason: "Invalid username or password.")
                }
                let verified = try Bcrypt.verify(loginRequest.password, created: user.password)
                guard verified else {
                    throw Abort(.unauthorized, reason: "Invalid username or password.")
                }
                // Check if the user is verified
                guard user.isVerified else {
                    throw Abort(.forbidden, reason: "Please verify your email before logging in.")
                }
                return user
            }.flatMap { user in
                do {
                    let token = try UserToken.generate(for: user)
                    return token.save(on: req.db).map { token }
                } catch {
                    return req.eventLoop.makeFailedFuture(error)
                }
            }
    }


    // POST /users/updateAge
    func updateAge(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let updateRequest = try req.content.decode(UpdateAgeRequest.self)
        
        user.age = updateRequest.age
        return user.save(on: req.db).transform(to: .ok)
    }
    
    // POST /users/updateGoal
    func updateGoal(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let updateRequest = try req.content.decode(UpdateGoalRequest.self)
        
        user.goal = updateRequest.goal
        return user.save(on: req.db).transform(to: .ok)
    }

    // POST /users/updateBodyType
    func updateBodyType(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let updateRequest = try req.content.decode(UpdateBodyTypeRequest.self)
        
        user.bodyType = updateRequest.bodyType
        return user.save(on: req.db).transform(to: .ok)
    }

    // POST /users/updateLastGoalGeneration
    func updateLastGoalGeneration(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let updateRequest = try req.content.decode(UpdateLastGoalGenerationRequest.self)
        
        user.lastGoalGeneration = updateRequest.lastGoalGeneration
        return user.save(on: req.db).transform(to: .ok)
    }
    
    

    // GET /users/goal
    func getGoal(req: Request) throws -> EventLoopFuture<UpdateGoalRequest> {
        let user = try req.auth.require(User.self)
        let goalResponse = UpdateGoalRequest(goal: user.goal ?? "")
        return req.eventLoop.makeSucceededFuture(goalResponse)
    }


// Helper Structs
struct LoginRequest: Content {
    let username: String
    let password: String
}

struct UpdateAgeRequest: Content {
    let age: Int
}

struct UpdateGoalRequest: Content {
    let goal: String
}

struct UpdateBodyTypeRequest: Content {
    let bodyType: String
}

struct UpdateLastGoalGenerationRequest: Content {
    let lastGoalGeneration: Date?
}

struct UpdateActivityLevelRequest: Content {
    let activityLevel: String
}

struct UserProfileResponse: Content {
    let username: String
    let email: String
    let age: Int?
    let activityLevel: String?
    let bodyType: String?
    let goal: String?
    let lastGoalGeneration: Date?
}
struct UserInput: Content {
    let username: String
    let email: String
    let password: String
    let gender: String
    let age: Int
}

struct EmailRequest: Content {
    let email: String
}

struct PasswordResetRequest: Content {
    let token: String
    let newPassword: String
}
