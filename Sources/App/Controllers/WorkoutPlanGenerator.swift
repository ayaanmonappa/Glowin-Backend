import Foundation
import Vapor
import Fluent

struct WorkoutPlanGenerator {
    func generateWorkoutPlan(for user: User, req: Request, days: Int) -> EventLoopFuture<[WorkoutDay]> {
        do {
            let userID = try user.requireID()
            req.logger.info("Fetching measurements for user ID: \(userID)")

            return Measurement.query(on: req.db)
                .filter(\.$user.$id == userID)
                .sort(\.$date, .descending)
                .first()
                .flatMap { measurement in
                    guard let measurement = measurement else {
                        req.logger.warning("No measurements found for user ID: \(userID)")
                        return req.eventLoop.future(error: Abort(.notFound, reason: "No measurements found."))
                    }
                    req.logger.info("Measurement found: \(measurement)")
                    return self.createWorkoutSplit(for: user, measurement: measurement, days: days, req: req)
                }
        } catch {
            req.logger.error("Failed to fetch user ID: \(error)")
            return req.eventLoop.future(error: error)
        }
    }

    private func createWorkoutSplit(for user: User, measurement: Measurement, days: Int, req: Request) -> EventLoopFuture<[WorkoutDay]> {
        req.logger.info("Creating workout split for goal: \(user.goal ?? "Unknown") and days: \(days)")

        let split: EventLoopFuture<[WorkoutDay]> = {
            switch user.goal?.lowercased() {
            case "gain muscle":
                return generateMuscleGainSplit(days: days, req: req)
            case "lose fat/weight":
                return generateWeightLossSplit(days: days, req: req)
            case "maintenance":
                return generateMaintenanceSplit(days: days, req: req)
            default:
                return generateGeneralFitnessSplit(days: days, req: req)
            }
        }()

        return split.flatMapError { error in
            req.logger.error("Failed to create workout split: \(error.localizedDescription)")
            return req.eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "Failed to create workout split: \(error.localizedDescription)"))
        }
    }

    // MARK: - Workout Split Generation

    private func generateMuscleGainSplit(days: Int, req: Request) -> EventLoopFuture<[WorkoutDay]> {
        req.logger.info("Generating Muscle Gain Split for \(days) days")
        let muscleGainSplits = getMuscleGainSplits(days: days)
        return fetchExercisesForSplit(workoutDays: muscleGainSplits, req: req)
    }

    private func generateWeightLossSplit(days: Int, req: Request) -> EventLoopFuture<[WorkoutDay]> {
        req.logger.info("Generating Weight Loss Split for \(days) days")
        let weightLossSplits = getWeightLossSplits(days: days)
        return fetchExercisesForSplit(workoutDays: weightLossSplits, req: req)
    }

    private func generateMaintenanceSplit(days: Int, req: Request) -> EventLoopFuture<[WorkoutDay]> {
        req.logger.info("Generating Maintenance Split for \(days) days")
        let maintenanceSplits = getMaintenanceSplits(days: days)
        return fetchExercisesForSplit(workoutDays: maintenanceSplits, req: req)
    }

    private func generateGeneralFitnessSplit(days: Int, req: Request) -> EventLoopFuture<[WorkoutDay]> {
        req.logger.info("Generating General Fitness Split for \(days) days")
        let fitnessSplits = getGeneralFitnessSplits(days: days)
        return fetchExercisesForSplit(workoutDays: fitnessSplits, req: req)
    }

    // MARK: - Exercise Fetching

    private func fetchExercisesForSplit(workoutDays: [WorkoutDayStructure], req: Request) -> EventLoopFuture<[WorkoutDay]> {
        var workoutPlan = [WorkoutDay]()
        var futures: [EventLoopFuture<Void>] = []

        for dayStructure in workoutDays {
            futures.append(fetchExercises(for: dayStructure.exercises, req: req).map { exercises in
                let workoutDay = WorkoutDay(dayName: dayStructure.dayName, exercises: exercises)
                req.logger.info("Generated workout day: \(workoutDay.dayName) with \(exercises.count) exercises")
                workoutPlan.append(workoutDay)
            })
        }

        return EventLoopFuture.andAllComplete(futures, on: req.eventLoop).map {
            req.logger.info("Workout plan generation complete with \(workoutPlan.count) days")
            return workoutPlan
        }
    }

    private func fetchExercises(for exerciseStructures: [WorkoutExerciseStructure], req: Request) -> EventLoopFuture<[WorkoutExercise]> {
        let futures = exerciseStructures.map { exerciseStructure in
            fetchExerciseDetails(for: exerciseStructure.id, req: req).map { exerciseDetails in
                WorkoutExercise(
                    name: exerciseDetails["name"] as? String ?? exerciseStructure.name,
                    target: exerciseDetails["target"] as? String ?? "Not provided",
                    equipment: exerciseDetails["equipment"] as? String ?? "Not provided",
                    gifUrl: exerciseDetails["gifUrl"] as? String ?? exerciseStructure.gifUrl,
                    recommendedReps: "\(exerciseStructure.reps) reps x \(exerciseStructure.sets) sets"
                )
            }
        }

        return futures.flatten(on: req.eventLoop)
    }

 private func fetchExerciseDetails(for id: String, req: Request) -> EventLoopFuture<[String: Any]> {
         let url = URI(string: "https://exercisedb.p.rapidapi.com/exercises/exercise/\(id)")

         var headers = HTTPHeaders()
         headers.add(name: "x-rapidapi-key", value: "dc95d8c1ccmsha9321c40b2a5c53p1ea1a7jsna8fbcf8b921e")
         headers.add(name: "x-rapidapi-host", value: "exercisedb.p.rapidapi.com")

         let clientRequest = ClientRequest(
             method: .GET,
             url: url,
             headers: headers
         )

         return req.client.send(clientRequest).flatMapThrowing { response in
             guard response.status == .ok, var buffer = response.body else {
                 req.logger.error("Failed to fetch exercise details for ID: \(id)")
                 throw Abort(.badRequest, reason: "Failed to fetch exercise details.")
             }

             let data = buffer.readData(length: buffer.readableBytes) ?? Data()
             if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                 return json
             } else {
                 throw Abort(.badRequest, reason: "Invalid response data.")
             }
         }.flatMapErrorThrowing { error in
             req.logger.error("Error fetching exercise details: \(error.localizedDescription)")
             return [:]  // Return an empty dictionary on error
         }
     }


    // MARK: - Workout Splits Data

    private func getMuscleGainSplits(days: Int) -> [WorkoutDayStructure] {
        switch days {
        case 3:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body & HIIT", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0128", name: "Battle Ropes", sets: 5, reps: 30, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body & Core", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: Cardio & Core", exercises: [
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil), // Running has no ID and no GIF
                    WorkoutExerciseStructure(id: "0175", name: "Cable Kneeling Crunch", sets: 3, reps: 20, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2466", name: "Mountain Climbers", sets: 3, reps: 20, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2963", name: "Captain Chair Leg Raise", sets: 3, reps: 15, gifUrl: nil)
                ])
            ]
        case 4:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 10, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: HIIT", exercises: [
                    WorkoutExerciseStructure(id: "0128", name: "Battle Ropes", sets: 5, reps: 30, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0524", name: "Kettlebell Swings", sets: 4, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "missing-id", name: "Box Jumps", sets: 3, reps: 15, gifUrl: nil), // Box Jumps has no GIF
                    WorkoutExerciseStructure(id: "1201", name: "Dumbbell Burpee", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 4: Core", exercises: [
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0846", name: "Russian Twists", sets: 3, reps: 20, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2963", name: "Captain Chair Leg Raise", sets: 3, reps: 15, gifUrl: nil)
                ])
            ]
        default:
            return []
        }
    }

    private func getWeightLossSplits(days: Int) -> [WorkoutDayStructure] {
        switch days {
        case 3:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body & HIIT", exercises: [
                    WorkoutExerciseStructure(id: "0128", name: "Battle Ropes", sets: 5, reps: 30, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1201", name: "Dumbbell Burpee", sets: 4, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 10, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body & Cardio", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil) // Running has no ID and no GIF
                ]),
                WorkoutDayStructure(dayName: "Day 3: Full Body Circuit", exercises: [
                    WorkoutExerciseStructure(id: "0524", name: "Kettlebell Swings", sets: 4, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "missing-id", name: "Box Jumps", sets: 3, reps: 15, gifUrl: nil), // Box Jumps has no GIF
                    WorkoutExerciseStructure(id: "1201", name: "Dumbbell Burpee", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0651", name: "Pull-Ups", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3305", name: "Barbell Thrusters", sets: 3, reps: 12, gifUrl: nil)
                ])
            ]
        case 4:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: Cardio & HIIT", exercises: [
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil), // Running has no ID and no GIF
                    WorkoutExerciseStructure(id: "1201", name: "Dumbbell Burpee", sets: 4, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0128", name: "Battle Ropes", sets: 5, reps: 30, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 4: Core & Full Body Circuit", exercises: [
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0846", name: "Russian Twists", sets: 3, reps: 20, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2963", name: "Captain Chair Leg Raise", sets: 3, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0524", name: "Kettlebell Swings", sets: 4, reps: 15, gifUrl: nil)
                ])
            ]
        default:
            return []
        }
    }

    private func getMaintenanceSplits(days: Int) -> [WorkoutDayStructure] {
        switch days {
        case 3:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: Cardio & Core", exercises: [
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil), // Running has no ID and no GIF
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0846", name: "Russian Twists", sets: 3, reps: 20, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2963", name: "Captain Chair Leg Raise", sets: 3, reps: 15, gifUrl: nil)
                ])
            ]
        case 4:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: Cardio", exercises: [
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil), // Running has no ID and no GIF
                    WorkoutExerciseStructure(id: "0128", name: "Battle Ropes", sets: 5, reps: 30, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1201", name: "Dumbbell Burpee", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 4: Full Body Circuit", exercises: [
                    WorkoutExerciseStructure(id: "0524", name: "Kettlebell Swings", sets: 4, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "missing-id", name: "Box Jumps", sets: 3, reps: 15, gifUrl: nil), // Box Jumps has no GIF
                    WorkoutExerciseStructure(id: "3305", name: "Barbell Thrusters", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil)
                ])
            ]
        default:
            return []
        }
    }

    private func getGeneralFitnessSplits(days: Int) -> [WorkoutDayStructure] {
        switch days {
        case 3:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: Cardio & Core", exercises: [
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil), // Running has no ID and no GIF
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0846", name: "Russian Twists", sets: 3, reps: 20, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2963", name: "Captain Chair Leg Raise", sets: 3, reps: 15, gifUrl: nil)
                ])
            ]
        case 4:
            return [
                WorkoutDayStructure(dayName: "Day 1: Upper Body", exercises: [
                    WorkoutExerciseStructure(id: "0025", name: "Bench Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "3547", name: "Overhead Shoulder Press", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0027", name: "Bent-Over Rows", sets: 3, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1755", name: "Tricep Dips", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 2: Lower Body", exercises: [
                    WorkoutExerciseStructure(id: "0043", name: "Squats", sets: 4, reps: 10, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0157", name: "Deadlifts", sets: 3, reps: 8, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0336", name: "Lunges", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "0739", name: "Leg Press", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 3: Cardio", exercises: [
                    WorkoutExerciseStructure(id: "running", name: "Running", sets: 1, reps: 30, gifUrl: nil), // Running has no ID and no GIF
                    WorkoutExerciseStructure(id: "0128", name: "Battle Ropes", sets: 5, reps: 30, gifUrl: nil),
                    WorkoutExerciseStructure(id: "1201", name: "Dumbbell Burpee", sets: 3, reps: 12, gifUrl: nil)
                ]),
                WorkoutDayStructure(dayName: "Day 4: Full Body Circuit", exercises: [
                    WorkoutExerciseStructure(id: "0524", name: "Kettlebell Swings", sets: 4, reps: 15, gifUrl: nil),
                    WorkoutExerciseStructure(id: "missing-id", name: "Box Jumps", sets: 3, reps: 15, gifUrl: nil), // Box Jumps has no GIF
                    WorkoutExerciseStructure(id: "3305", name: "Barbell Thrusters", sets: 3, reps: 12, gifUrl: nil),
                    WorkoutExerciseStructure(id: "2135", name: "Planks", sets: 3, reps: 60, gifUrl: nil)
                ])
            ]
        default:
            return []
        }
    }

    struct WorkoutDayStructure {
        let dayName: String
        let exercises: [WorkoutExerciseStructure]
    }

    struct WorkoutExerciseStructure {
        let id: String
        let name: String
        let sets: Int
        let reps: Int
        let gifUrl: String?
    }
}
