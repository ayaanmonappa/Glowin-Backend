import Vapor

// Recipe Response structure conforming to Content
struct RecipeResponse: Content {
    struct Hit: Content {
        struct Recipe: Content, Identifiable {
            var id: String { url } // Using URL as the unique ID
            let label: String
            let image: String?
            let url: String
            let calories: Double
            let totalWeight: Double
            let yield: Double? // Optional yield for serving size
            let totalTime: Double? // Optional total time
            let dietLabels: [String]
            let healthLabels: [String]
            let cautions: [String]
            let ingredientLines: [String]
            let mealType: [String]
            let totalNutrients: Nutrients? // Optional to handle cases where nutrients may not be present

            struct Nutrients: Content {
                let ENERC_KCAL: NutrientDetail? // Calories
                let FAT: NutrientDetail?        // Fat
                let CHOCDF: NutrientDetail?     // Carbs
                let PROCNT: NutrientDetail?     // Protein

                struct NutrientDetail: Content {
                    let label: String
                    let quantity: Double
                    let unit: String
                }
            }
        }
        let recipe: Recipe
    }
    let hits: [Hit]
    struct Links: Content {
        struct Next: Content {
            let href: String
        }
        let next: Next?
    }
    let _links: Links?
}
