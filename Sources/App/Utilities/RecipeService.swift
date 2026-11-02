import Foundation
import Vapor

class RecipeService {
    private let baseURL = "https://api.edamam.com/api/recipes/v2"
    private let appID = "03dc14dc"
    private let appKey = "27e3611519adb7798beee482c698a12d"

    func fetchRecipes(
        req: Request,
        calories: String? = nil,
        protein: String? = nil,
        fat: String? = nil,
        carbs: String? = nil,
        mealTypes: [String]? = nil,
        healthLabels: [String]? = nil,
        from: Int = 0,
        to: Int = 20
    ) -> EventLoopFuture<(recipes: [RecipeResponse.Hit.Recipe], nextLink: String?)> {

        let promise = req.eventLoop.makePromise(of: (recipes: [RecipeResponse.Hit.Recipe], nextLink: String?).self)

        var urlComponents = URLComponents(string: baseURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "type", value: "public"),
            URLQueryItem(name: "app_id", value: appID),
            URLQueryItem(name: "app_key", value: appKey),
            URLQueryItem(name: "from", value: "\(from)"),
            URLQueryItem(name: "to", value: "\(to)")
        ]

        if let calories = calories { urlComponents?.queryItems?.append(URLQueryItem(name: "calories", value: calories)) }
        if let protein = protein { urlComponents?.queryItems?.append(URLQueryItem(name: "nutrients[PROCNT]", value: protein)) }
        if let fat = fat { urlComponents?.queryItems?.append(URLQueryItem(name: "nutrients[FAT]", value: fat)) }
        if let carbs = carbs { urlComponents?.queryItems?.append(URLQueryItem(name: "nutrients[CHOCDF]", value: carbs)) }
        if let mealTypes = mealTypes {
            for mealType in mealTypes {
                urlComponents?.queryItems?.append(URLQueryItem(name: "mealType", value: mealType))
            }
        }
        if let healthLabels = healthLabels {
            for label in healthLabels {
                urlComponents?.queryItems?.append(URLQueryItem(name: "health", value: label))
            }
        }

        guard let url = urlComponents?.url else {
            print("Invalid URL")
            return req.eventLoop.makeFailedFuture(NSError(domain: "InvalidURL", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }

        print("Requesting recipes with URL: \(url)")

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching data: \(error)")
                promise.fail(error)
                return
            }

            guard let data = data else {
                print("No data received from server.")
                promise.fail(NSError(domain: "NoData", code: 400, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }

            print("Raw data received from backend: \(String(data: data, encoding: .utf8) ?? "nil")")  // Add debugging for raw data

            do {
                print("Raw data received from API: \(String(data: data, encoding: .utf8) ?? "nil")")  // Log raw data

                let decodedResponse = try JSONDecoder().decode(RecipeResponse.self, from: data)
                let recipes = decodedResponse.hits.map { $0.recipe }
                let nextLink = decodedResponse._links?.next?.href

                print("Successfully decoded \(recipes.count) recipes")
                promise.succeed((recipes: recipes, nextLink: nextLink))
            } catch let DecodingError.keyNotFound(key, context) {
                print("Decoding error: Key '\(key.stringValue)' not found - \(context.debugDescription)")
                promise.fail(Abort(.internalServerError, reason: "Failed to decode API response"))
            } catch {
                print("Unexpected error during decoding: \(error)")
                promise.fail(error)
            }
        }
        task.resume()
        return promise.futureResult
    }
}
