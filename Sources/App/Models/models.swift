import Vapor

struct WorkoutDay: Content {
    let dayName: String
    let exercises: [WorkoutExercise]
}

struct WorkoutExercise: Content {
    var id: UUID?
    let name: String
    let target: String
    let equipment: String
    let gifUrl: String?
    let recommendedReps: String

    init(name: String, target: String, equipment: String, gifUrl: String?, recommendedReps: String) {
        self.name = name
        self.target = target
        self.equipment = equipment
        self.gifUrl = gifUrl
        self.recommendedReps = recommendedReps
    }
}


struct ExerciseResponse: Content {
    let bodyPart: String
    let equipment: String
    let gifUrl: String
    let id: String
    let name: String
    let target: String
    let secondaryMuscles: [String]
    let instructions: [String]
}
