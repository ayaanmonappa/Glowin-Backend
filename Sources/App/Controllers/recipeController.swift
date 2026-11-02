import Vapor
import Fluent

// Wrapper struct for Recipe List including nextLink for pagination
struct RecipeList: Content {
    let meals: [RecipeResponse.Hit.Recipe]
    let nextLink: String?  // Send the next link back to the frontend
}

struct RecipeController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let recipeRoutes = routes.grouped("recipes")
        let protected = recipeRoutes.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get(use: fetchRecipes)
    }

    func fetchRecipes(req: Request) throws -> EventLoopFuture<RecipeList> {
        guard let user = try? req.auth.get(User.self) else {
            throw Abort(.unauthorized)
        }

        let userID = try user.requireID()
        print("Fetching recipes for userID: \(userID)")

        return Measurement.query(on: req.db)
            .filter(\Measurement.$user.$id == userID)
            .sort(\.$date, .descending)
            .first()
            .unwrap(or: Abort(.notFound, reason: "No measurements found for userID: \(userID)"))
            .flatMap { measurement in
                let goalType = RecipeController.determineGoalType(from: user.goal?.lowercased() ?? "")
                let (mealCaloricRange, mealMacroDistribution) = RecipeController.calculateNutritionalRequirements(for: user, measurement: measurement, goalType: goalType)

                return self.fetchAllRecipes(
                    caloricRange: mealCaloricRange,
                    macroDistribution: mealMacroDistribution,
                    req: req
                )
            }
    }

 private func fetchAllRecipes(
        caloricRange: String,
        macroDistribution: (proteinRange: String, fatRange: String, carbRange: String),
        req: Request
    ) -> EventLoopFuture<RecipeList> {
        let eventLoop = req.eventLoop
        var allRecipes: [RecipeResponse.Hit.Recipe] = []
        let maxRecipes = 100  // Set the maximum number of recipes

        // Recursive function to fetch all pages
        func fetchNextBatch(nextLink: String?) -> EventLoopFuture<Void> {
            guard let nextLink = nextLink, let url = URL(string: nextLink) else {
                return eventLoop.makeSucceededVoidFuture()
            }
            if allRecipes.count >= maxRecipes {
                print("Reached maximum limit of \(maxRecipes) recipes.")
                return eventLoop.makeSucceededVoidFuture()
            }

            return self.fetchData(from: url, on: eventLoop)
                .flatMapThrowing { data -> (recipes: [RecipeResponse.Hit.Recipe], nextLink: String?) in
                    do {
                        let decodedResponse = try JSONDecoder().decode(RecipeResponse.self, from: data)
                        let recipes = decodedResponse.hits.map { $0.recipe }
                        let nextLink = decodedResponse._links?.next?.href
                        return (recipes, nextLink)
                    } catch {
                        // Log the raw data for debugging
                        if let rawResponse = String(data: data, encoding: .utf8) {
                            print("Raw Response: \(rawResponse)")
                        }
                        throw error
                    }
                }
                .flatMap { result in
                    allRecipes.append(contentsOf: result.recipes)
                    // Ensure we don't exceed the maximum number of recipes
                    if allRecipes.count >= maxRecipes {
                        allRecipes = Array(allRecipes.prefix(maxRecipes))
                        return eventLoop.makeSucceededVoidFuture()
                    }
                    return fetchNextBatch(nextLink: result.nextLink)
                }
        }

        // Build the initial URL
        var urlComponents = URLComponents(string: "https://api.edamam.com/api/recipes/v2")!
        urlComponents.queryItems = [
            URLQueryItem(name: "type", value: "public"),
            URLQueryItem(name: "app_id", value: "03dc14dc"),
            URLQueryItem(name: "app_key", value: "27e3611519adb7798beee482c698a12d"),
            URLQueryItem(name: "calories", value: caloricRange),
            URLQueryItem(name: "nutrients[PROCNT]", value: macroDistribution.proteinRange),
            URLQueryItem(name: "nutrients[FAT]", value: macroDistribution.fatRange),
            URLQueryItem(name: "nutrients[CHOCDF]", value: macroDistribution.carbRange),
            URLQueryItem(name: "from", value: "0"),
            URLQueryItem(name: "to", value: "20")
        ]

        if let url = urlComponents.url {
            print("Initial Request URL: \(url)")
        }

        return fetchData(from: urlComponents.url!, on: eventLoop)
            .flatMapThrowing { data -> (recipes: [RecipeResponse.Hit.Recipe], nextLink: String?) in
                do {
                    let decodedResponse = try JSONDecoder().decode(RecipeResponse.self, from: data)
                    let recipes = decodedResponse.hits.map { $0.recipe }
                    let nextLink = decodedResponse._links?.next?.href
                    return (recipes, nextLink)
                } catch {
                    // Log the raw response on error
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        print("Raw Response: \(rawResponse)")
                    }
                    throw error
                }
            }
            .flatMap { result in
                allRecipes.append(contentsOf: result.recipes)
                return fetchNextBatch(nextLink: result.nextLink)
            }
            .map {
                if allRecipes.count > maxRecipes {
                    allRecipes = Array(allRecipes.prefix(maxRecipes))
                }
                return RecipeList(meals: allRecipes, nextLink: nil)
            }
    }


 private func fetchData(from url: URL, on eventLoop: EventLoop) -> EventLoopFuture<Data> {
        print("Fetching data from URL: \(url)")
        let promise = eventLoop.makePromise(of: Data.self)
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
                promise.fail(error)
                return
            }
            if let response = response as? HTTPURLResponse {
                print("Response Status Code: \(response.statusCode)")
            }
            if let data = data {
                if let rawResponse = String(data: data, encoding: .utf8) {
                    print("Raw Response Data: \(rawResponse)")
                }
                promise.succeed(data)
            } else {
                promise.fail(Abort(.badRequest, reason: "No data received"))
            }
        }.resume()
        return promise.futureResult
    }


    // Helper methods for goal and nutritional requirement calculation
    static func determineGoalType(from goal: String) -> String {
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

    static func calculateNutritionalRequirements(
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
            mealCaloricRange = "\(Int((tdee + 250) * 0.25) - 200)-\(Int((tdee + 250) * 0.35) + 200)"
            mealMacroDistribution = (
                proteinRange: "\(Int((measurement.weight * 1.5)/4) - 10)-\(Int((measurement.weight * 2.5)/4) + 10)",
                fatRange: "\(Int((measurement.weight * 0.4)/4) - 10)-\(Int((measurement.weight * 1.4)/4) + 10)",
                carbRange: measurement.weight > 200 ? "45-110" : "30-75"
            )
        case "maintenance":
            mealCaloricRange = "\(Int(tdee * 0.25) - 100)-\(Int(tdee * 0.30) + 100)"
            mealMacroDistribution = (
                proteinRange: "\(Int((measurement.weight * 1.2) / 4) - 5)-\(Int((measurement.weight * 1.6) / 4) + 5)",
                fatRange: "\(Int((measurement.weight * 0.8) / 4) - 5)-\(Int((measurement.weight * 1.2) / 4) + 5)",
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
        return (mealCaloricRange, mealMacroDistribution)
    }

    static func calculateBMR(gender: String, weight: Double, height: Double, age: Int) -> Double {
        if gender.lowercased() == "male" {
            return 88.362 + (13.397 * weight) + (4.799 * height) - (5.677 * Double(age))
        } else {
            return 447.593 + (9.247 * weight) + (3.098 * height) - (4.330 * Double(age))
        }
    }

    static func calculateTDEE(bmr: Double, activityLevel: String) -> Double {
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
