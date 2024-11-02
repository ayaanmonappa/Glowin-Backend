//
//  File.swift
//  
//
//  Created by Ayaan Monappa on 5/8/24.
//

import Vapor

struct ExternalRecipeController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let external = routes.grouped("external")
        external.get("recipes", use: fetchRecipes)
    }

    func fetchRecipes(req: Request) throws -> EventLoopFuture<ClientResponse> {
        let query = try req.query.get(String.self, at: "query")
        let calories = try req.query.get(String.self, at: "calories")
        let protein = try req.query.get(String.self, at: "protein")
        let fat = try req.query.get(String.self, at: "fat")
        let carbs = try req.query.get(String.self, at: "carbs")

        let url = URI(string: "https://api.edamam.com/api/recipes/v2?type=public&q=\(query)&app_id=03dc14dc&app_key=27e3611519adb7798beee482c698a12d&calories=\(calories)&nutrients[PROCNT]=\(protein)&nutrients[FAT]=\(fat)&nutrients[CHOCDF]=\(carbs)")

        return req.client.get(url)
    }
}



