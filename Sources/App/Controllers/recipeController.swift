import Vapor
import Fluent

// Wrapper struct for Recipe List including nextLink for pagination
struct RecipeList: Content {
    let meals: [RecipeResponse.Hit.Recipe]
    let nextLink: String?  // Send the next link back to the frontend
}

// Global variables to store all fetched batches of recipes and the fetching state
var cachedRecipes: [RecipeResponse.Hit.Recipe] = []
var isFetchingComplete: Bool = false  // Indicates if all batches have been fetched
var currentBatchCount: Int = 0  // Track the number of batches fetched

struct RecipeController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let recipeRoutes = routes.grouped("recipes")
        let protected = recipeRoutes.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get(use: startFetchingRecipes)  // First call to fetch all recipes
        protected.get("status", use: fetchStatus)  // Frontend polls for fetching status
    }

    // Start fetching recipes asynchronously
    func startFetchingRecipes(req: Request) throws -> HTTPStatus {
        guard let user = try? req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }

        let userID = try user.requireID()
        print("Starting recipe fetch for userID: \(userID)")

        // Reset cache and fetching state
        cachedRecipes.removeAll()
        isFetchingComplete = false
        currentBatchCount = 0

        // Kick off background process
        Measurement.query(on: req.db)
            .filter(\Measurement.$user.$id == userID)
            .sort(\.$date, .descending)
            .first()
            .unwrap(or: Abort(.notFound, reason: "No measurements found for userID: \(userID)"))
            .flatMap { measurement in
                let goalType = self.determineGoalType(from: user.goal?.lowercased() ?? "")
                let (mealCaloricRange, mealMacroDistribution) = self.calculateNutritionalRequirements(for: user, measurement: measurement, goalType: goalType)

                print("Goal: \(goalType), Caloric Range: \(mealCaloricRange)")

                // Fetch the first batch and begin the background fetching process
                return self.fetchPaginatedRecipes(caloricRange: mealCaloricRange, macroDistribution: mealMacroDistribution, req: req, from: 0, to: 20)
                    .flatMap { response in
                        cachedRecipes = response.meals  // Cache the first batch
                        if let nextLink = response.nextLink {
                            return self.fetchRemainingBatches(application: req.application, nextLink: nextLink)
                        } else {
                            isFetchingComplete = true
                            return req.eventLoop.makeSucceededFuture(())

                        }
                    }
            }
            .whenComplete { result in
                switch result {
                case .success:
                    print("Recipe fetching complete.")
                    isFetchingComplete = true
                case .failure(let error):
                    print("Failed to fetch recipes: \(error)")
                    isFetchingComplete = true  // Mark complete to stop polling even on failure
                }
            }

        // Immediately return a response indicating the process has started
        return .accepted
    }

    // Polling endpoint for the frontend to check status and retrieve results
    func fetchStatus(req: Request) throws -> EventLoopFuture<RecipeList> {
        if isFetchingComplete {
            return req.eventLoop.makeSucceededFuture(RecipeList(meals: cachedRecipes, nextLink: nil))  // Return final results
        } else {
            return req.eventLoop.makeSucceededFuture(RecipeList(meals: [], nextLink: "Fetching in progress..."))
        }
    }

    // Fetch remaining batches with a 15-second delay between requests, stop after 5 batches
    private func fetchRemainingBatches(application: Application, nextLink: String) -> EventLoopFuture<Void> {
        guard let url = URL(string: nextLink), currentBatchCount < 3 else {
            print("Reached the batch limit or invalid nextLink.")
            isFetchingComplete = true
            return application.eventLoopGroup.next().makeSucceededVoidFuture()
        }

        currentBatchCount += 1  // Increment the batch count
        let promise = application.eventLoopGroup.next().makePromise(of: Void.self)
        print("Fetching next batch with nextLink: \(nextLink), batch \(currentBatchCount)")

        // Schedule the next batch fetch with a delay
        application.eventLoopGroup.next().scheduleTask(in: .seconds(15)) {
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    print("Error fetching next batch: \(error)")
                    promise.fail(error)
                    return
                }

                guard let data = data else {
                    print("No data received from next batch")
                    promise.fail(Abort(.badRequest, reason: "No data received"))
                    return
                }

                do {
                    let decodedResponse = try JSONDecoder().decode(RecipeResponse.self, from: data)
                    let recipes = decodedResponse.hits.map { $0.recipe }
                    cachedRecipes.append(contentsOf: recipes)  // Append to cache
                    let nextLink = decodedResponse._links?.next?.href

                    if let nextLink = nextLink {
                        // Continue fetching the next batch
                        self.fetchRemainingBatches(application: application, nextLink: nextLink)
                            .cascade(to: promise)
                    } else {
                        // All batches are fetched
                        print("All batches fetched.")
                        promise.succeed(())
                    }
                } catch {
                    print("Failed to decode next batch: \(error)")
                    promise.fail(error)
                }
            }.resume()
        }

        return promise.futureResult
    }

    // Helper method to fetch paginated recipes
    private func fetchPaginatedRecipes(
        caloricRange: String,
        macroDistribution: (proteinRange: String, fatRange: String, carbRange: String),
        req: Request,
        from: Int,
        to: Int
    ) -> EventLoopFuture<RecipeList> {
        var urlComponents = URLComponents(string: "https://api.edamam.com/api/recipes/v2")!
        urlComponents.queryItems = [
            URLQueryItem(name: "type", value: "public"),
            URLQueryItem(name: "app_id", value: "03dc14dc"),
            URLQueryItem(name: "app_key", value: "27e3611519adb7798beee482c698a12d"),
            URLQueryItem(name: "calories", value: caloricRange),
            URLQueryItem(name: "nutrients[PROCNT]", value: macroDistribution.proteinRange),
            URLQueryItem(name: "nutrients[FAT]", value: macroDistribution.fatRange),
            URLQueryItem(name: "nutrients[CHOCDF]", value: macroDistribution.carbRange),
            URLQueryItem(name: "from", value: "\(from)"),
            URLQueryItem(name: "to", value: "\(to)")
        ]

        let url = urlComponents.url!
        print("Requesting URL: \(url)")

        return fetchData(from: url, on: req.eventLoop).flatMapThrowing { data in
            do {
                let decodedResponse = try JSONDecoder().decode(RecipeResponse.self, from: data)
                let nextLink = decodedResponse._links?.next?.href
                let recipes = decodedResponse.hits.map { $0.recipe }
                print("Successfully fetched \(recipes.count) recipes.")
                return RecipeList(meals: recipes, nextLink: nextLink)
            } catch {
                print("Failed to decode response: \(error)")
                throw error
            }
        }
    }

    // Fetch data using URLSession
    private func fetchData(from url: URL, on eventLoop: EventLoop) -> EventLoopFuture<Data> {
        let promise = eventLoop.makePromise(of: Data.self)
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching data: \(error)")
                promise.fail(error)
                return
            }
            guard let data = data else {
                print("No data received.")
                promise.fail(Abort(.badRequest, reason: "No data received"))
                return
            }
            promise.succeed(data)
        }.resume()
        return promise.futureResult
    }

    // Helper methods for goal and nutritional requirement calculation
    private func determineGoalType(from goal: String) -> String {
        if goal.contains("lose") || goal.contains("fat") || goal.contains("weight") {
            return "lose fat"
        } else if goal.contains("gain") || goal.contains("muscle") {
            return "gain muscle"
        } else if goal.contains("maintain") {
            return "maintenance"
        } else {
            return "maintenance"  // Default to maintenance if no specific goal is provided
        }
    }
    
    // Calculate nutritional requirements based on user profile and goal.
    private func calculateNutritionalRequirements(
        for user: User,
        measurement: Measurement,
        goalType: String
    ) -> (String, (proteinRange: String, fatRange: String, carbRange: String)) {
        let bmr = calculateBMR(gender: user.gender, weight: measurement.weight, height: measurement.height, age: user.age)
        let tdee = calculateTDEE(bmr: bmr, activityLevel: user.activityLevel ?? "Moderately Active")

        var mealCaloricRange = ""
        var mealMacroDistribution = (proteinRange: "", fatRange: "", carbRange: "")

        switch goalType {
        case "lose fat":
            mealCaloricRange = "\(Int((tdee - 500) * 0.25) - 200)-\(Int((tdee - 500) * 0.35) + 200)"
            mealMacroDistribution = (
                proteinRange: "\(Int((measurement.weight * 1.6)/4) - 10)-\(Int((measurement.weight * 2.2)/4) + 10)",
                fatRange: "\(Int((measurement.weight * 0.5)/4) - 5)-\(Int((measurement.weight * 1.0)/4) + 5)",
                carbRange: "25-50"
            )
        case "gain muscle":
            // Adjusted caloric range with a slightly higher base and wider tolerance
            mealCaloricRange = "\(Int((tdee + 250) * 0.25) - 200)-\(Int((tdee + 250) * 0.35) + 200)"

            mealMacroDistribution = (
                // Widening protein range slightly while maintaining adequate levels
                proteinRange: "\(Int((measurement.weight * 1.5)/4) - 10)-\(Int((measurement.weight * 2.5)/4) + 10)",

                // Expanding fat range to capture recipes with moderate fats
                fatRange: "\(Int((measurement.weight * 0.4)/4) - 10)-\(Int((measurement.weight * 1.4)/4) + 10)",

                // Allowing more flexibility in carbs based on weight threshold
                carbRange: measurement.weight > 200 ? "45-110" : "30-75"
            )

        case "maintenance":
            mealCaloricRange = "\(Int(tdee * 0.25) - 100)-\(Int(tdee * 0.30) + 100)+100"
            mealMacroDistribution = (
                proteinRange: "\(Int((measurement.weight * 1.2)/4) - 5)-\(Int((measurement.weight * 1.6)/4) + 5)",
                fatRange: "\(Int((measurement.weight * 0.8)/4) - 5)-\(Int((measurement.weight * 1.2)/4) + 5)",
                carbRange: "40-70"
            )
        default:
            mealCaloricRange = "\(Int(tdee * 0.25))-\(Int(tdee * 0.35))"
            mealMacroDistribution = (
                proteinRange: "20-30",
                fatRange: "10-20",
                carbRange: "45-65"
            )
        }
        print("Goal Type: \(goalType)")
        print("Caloric Range: \(mealCaloricRange)")
        print("Protein Range: \(mealMacroDistribution.proteinRange)")
        print("Fat Range: \(mealMacroDistribution.fatRange)")
        print("Carb Range: \(mealMacroDistribution.carbRange)")
        return (mealCaloricRange, mealMacroDistribution)
    }

    // BMR calculation based on gender, weight, height, and age.
    private func calculateBMR(gender: String, weight: Double, height: Double, age: Int) -> Double {
        if gender.lowercased() == "male" {
            return 88.362 + (13.397 * weight) + (4.799 * height) - (5.677 * Double(age))
        } else {
            return 447.593 + (9.247 * weight) + (3.098 * height) - (4.330 * Double(age))
        }
    }

    // TDEE calculation based on activity level.
    private func calculateTDEE(bmr: Double, activityLevel: String) -> Double {
        let activityMultiplier: Double
        switch activityLevel.lowercased() {
        case "sedentary": activityMultiplier = 1.2
        case "lightly active": activityMultiplier = 1.375
        case "moderately active": activityMultiplier = 1.55
        case "very active": activityMultiplier = 1.725
        case "super active": activityMultiplier = 1.9
        default: activityMultiplier = 1.55
        }
        return bmr * activityMultiplier
    }
}
