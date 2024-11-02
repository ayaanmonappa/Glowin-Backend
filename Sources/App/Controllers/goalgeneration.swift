import Vapor
import Fluent

struct GoalGenerationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let goals = routes.grouped("goals")
        let protected = goals.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.post("generate", use: generateGoals)
        protected.get(use: getGoals)
    }

    func generateGoals(req: Request) throws -> EventLoopFuture<[GeneratedGoal]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        
        guard let activityLevel = user.activityLevel,
              let goal = user.goal,
              let bodyType = user.bodyType else {
            throw Abort(.badRequest, reason: "Please complete your profile with activity level, goal, and body type before generating goals.")
        }

        // Delete previous goals for this user
        return GeneratedGoal.query(on: req.db)
            .filter(\.$user.$id == userID)
            .delete()
            .flatMap { _ -> EventLoopFuture<Measurement?> in
                // Fetch the latest measurement
                return Measurement.query(on: req.db)
                    .filter(\.$user.$id == userID)
                    .sort(\.$date, .descending)  // Sort by date to get the most recent
                    .first()
            }
            .flatMap { latestMeasurement -> EventLoopFuture<[GeneratedGoal]> in
                // Handle the case where no measurement is found
                guard let latestMeasurement = latestMeasurement else {
                    return req.eventLoop.future(error: Abort(.notFound, reason: "No measurements found."))
                }
                
                // Generate realistic goals based on the user's data
                let goals = self.generateRealisticGoals(
                    user: user,
                    currentMeasurements: latestMeasurement,
                    bmr: self.calculateBMR(gender: user.gender, weight: latestMeasurement.weight, height: latestMeasurement.height, age: user.age),
                    bmi: self.calculateBMI(weight: latestMeasurement.weight, height: latestMeasurement.height),
                    tdee: self.calculateTDEE(bmr: self.calculateBMR(gender: user.gender, weight: latestMeasurement.weight, height: latestMeasurement.height, age: user.age), activityLevel: user.activityLevel ?? "Moderately Active"),
                    bodyType: user.bodyType ?? "average"
                )

                // Save all generated goals to the database
                let saveFutures = goals.map { $0.save(on: req.db) }
                return saveFutures.flatten(on: req.eventLoop).map { goals }
            }
    }

    func getGoals(req: Request) throws -> EventLoopFuture<[GeneratedGoal.GoalPublic]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()

        return GeneratedGoal.query(on: req.db)
            .filter(\.$user.$id == userID)
            .all()
            .map { goals in
                goals.map { $0.toPublic() }
            }
    }

    // BMR Calculation based on gender, weight, height, and age
    func calculateBMR(gender: String, weight: Double, height: Double, age: Int) -> Double {
        if gender.lowercased() == "male" {
            return 88.362 + (13.397 * weight) + (4.799 * height) - (5.677 * Double(age))
        } else {
            return 447.593 + (9.247 * weight) + (3.098 * height) - (4.330 * Double(age))
        }
    }

    // BMI Calculation
    func calculateBMI(weight: Double, height: Double) -> Double {
        return weight / ((height / 100) * (height / 100))
    }

    // TDEE Calculation based on BMR and activity level
    func calculateTDEE(bmr: Double, activityLevel: String) -> Double {
        let activityMultiplier: Double
        switch activityLevel.lowercased() {
        case "sedentary":
            activityMultiplier = 1.2
        case "lightly active":
            activityMultiplier = 1.375
        case "moderately active":
            activityMultiplier = 1.55
        case "very active":
            activityMultiplier = 1.725
        case "super active":
            activityMultiplier = 1.9
        default:
            activityMultiplier = 1.55
        }
        return bmr * activityMultiplier
    }

    // Generate realistic goals based on the user's data
    func generateRealisticGoals(
        user: User,
        currentMeasurements: Measurement,
        bmr: Double,
        bmi: Double,
        tdee: Double,
        bodyType: String
    ) -> [GeneratedGoal] {
        var goals = [GeneratedGoal]()

        let weeksToTarget = 12.0
        let targetDate = Date().addingTimeInterval(weeksToTarget * 7 * 24 * 60 * 60)

        switch user.goal {
        case "Lose Fat/Weight":
            goals.append(contentsOf: generateWeightLossGoals(user: user, currentMeasurements: currentMeasurements, tdee: tdee, weeksToTarget: weeksToTarget, targetDate: targetDate, bodyType: bodyType, activityLevel: user.activityLevel ?? "Moderately Active"))
        case "Gain Muscle":
            goals.append(contentsOf: generateMuscleGainGoals(user: user, currentMeasurements: currentMeasurements, tdee: tdee, weeksToTarget: weeksToTarget, targetDate: targetDate, bodyType: bodyType, activityLevel: user.activityLevel ?? "Moderately Active"))
        case "Maintenance":
            goals.append(contentsOf: generateMaintenanceGoals(currentMeasurements: currentMeasurements, targetDate: targetDate))
        default:
            break
        }

        return goals
    }

    // Weight Loss Goals
    func generateWeightLossGoals(user: User, currentMeasurements: Measurement, tdee: Double, weeksToTarget: Double, targetDate: Date, bodyType: String, activityLevel: String) -> [GeneratedGoal] {
        var goals = [GeneratedGoal]()
        let calorieDeficit = getCalorieDeficitForWeightLoss(bodyType: bodyType, activityLevel: activityLevel)
        let weeklyWeightLoss = calorieDeficit * 7 / 7700.0 // Approximate weight loss per week
        let targetWeight = max(currentMeasurements.weight - (weeklyWeightLoss * weeksToTarget), 45.0) // Prevent unrealistic low weight

        // Weight loss calculation
        print("Target weight: \(targetWeight)")
        goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Weight", goalValue: targetWeight, targetDate: targetDate, dateGenerated: Date()))

        // Waist reduction calculation
        if currentMeasurements.waist > 0 {
            let waistLoss = calculateTargetWaistLoss(currentMeasurement: currentMeasurements.waist, bodyType: bodyType, activityLevel: activityLevel)
            print("Calculated waist loss: \(waistLoss)")
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Waist", goalValue: waistLoss, targetDate: targetDate, dateGenerated: Date()))
        } else {
            print("No valid waist measurement found.")
        }

        // Thigh reduction calculation
        if currentMeasurements.thigh > 0 {
            let thighLoss = calculateTargetThighLoss(currentMeasurement: currentMeasurements.thigh, bodyType: bodyType, activityLevel: activityLevel)
            print("Calculated thigh loss: \(thighLoss)")
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Thigh", goalValue: thighLoss, targetDate: targetDate, dateGenerated: Date()))
        }

        // Chest reduction calculation
        if currentMeasurements.chest > 0 {
            let chestLoss = calculateTargetChestLoss(currentMeasurement: currentMeasurements.chest, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Chest", goalValue: chestLoss, targetDate: targetDate, dateGenerated: Date()))
        }

        // Bicep reduction calculation
        if currentMeasurements.bicep > 0 {
            let bicepLoss = calculateTargetBicepLoss(currentMeasurement: currentMeasurements.bicep, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Bicep", goalValue: bicepLoss, targetDate: targetDate, dateGenerated: Date()))
        }

        // Calf reduction calculation
        if currentMeasurements.calf > 0 {
            let calfLoss = calculateTargetCalfLoss(currentMeasurement: currentMeasurements.calf, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Calf", goalValue: calfLoss, targetDate: targetDate, dateGenerated: Date()))
        }

        return goals
    }

    // Muscle Gain Goals
    func generateMuscleGainGoals(user: User, currentMeasurements: Measurement, tdee: Double, weeksToTarget: Double, targetDate: Date, bodyType: String, activityLevel: String) -> [GeneratedGoal] {
        var goals = [GeneratedGoal]()

        // Weight gain calculation
        let calorieSurplus  = getCalorieSurplusForMuscleGain(bodyType: bodyType, activityLevel: activityLevel)
        let weeklyWeightGain = calorieSurplus * 7 / 7700.0 // Approximate weight gain per week
        let targetWeight = currentMeasurements.weight + (weeklyWeightGain * weeksToTarget)
        goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Weight", goalValue: targetWeight, targetDate: targetDate, dateGenerated: Date()))

        // Bicep growth calculation
        if currentMeasurements.bicep > 0 {
            let bicepGain = calculateTargetBicepGain(currentMeasurement: currentMeasurements.bicep, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Bicep", goalValue: bicepGain, targetDate: targetDate, dateGenerated: Date()))
        }
        
        // Waist growth calculation (minimal to moderate increase for muscle gain)
        if currentMeasurements.waist > 0 {
               let waistGain = calculateTargetWaistGain(currentMeasurement: currentMeasurements.waist, bodyType: bodyType, activityLevel: activityLevel)
               goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Waist", goalValue: waistGain, targetDate: targetDate, dateGenerated: Date()))
           } else {
               print("Warning: Waist measurement is zero. No waist goal generated.")
           }

        // Chest growth calculation
        if currentMeasurements.chest > 0 {
            let chestGain = calculateTargetChestGain(currentMeasurement: currentMeasurements.chest, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Chest", goalValue: chestGain, targetDate: targetDate, dateGenerated: Date()))
        }

        // Thigh growth calculation
        if currentMeasurements.thigh > 0 {
            let thighGain = calculateTargetThighGain(currentMeasurement: currentMeasurements.thigh, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Thigh", goalValue: thighGain, targetDate: targetDate, dateGenerated: Date()))
        }

        // Calf growth calculation
        if currentMeasurements.calf > 0 {
            let calfGain = calculateTargetCalfGain(currentMeasurement: currentMeasurements.calf, bodyType: bodyType, activityLevel: activityLevel)
            goals.append(GeneratedGoal(userID: try! user.requireID(), measurementType: "Calf", goalValue: calfGain, targetDate: targetDate, dateGenerated: Date()))
        }

        return goals
    }

    // Maintenance Goals
    func generateMaintenanceGoals(currentMeasurements: Measurement, targetDate: Date) -> [GeneratedGoal] {
        var goals = [GeneratedGoal]()

        // Maintenance goals generally aim to keep the current measurements stable.
        goals.append(GeneratedGoal(
            userID: try! currentMeasurements.$user.id,
            measurementType: "Weight",
            goalValue: currentMeasurements.weight,
            targetDate: targetDate,
            dateGenerated: Date()))

        if currentMeasurements.waist > 0 {
            goals.append(GeneratedGoal(
                userID: try! currentMeasurements.$user.id,
                measurementType: "Waist",
                goalValue: currentMeasurements.waist,
                targetDate: targetDate,
                dateGenerated: Date()))
        }

        if currentMeasurements.thigh > 0 {
            goals.append(GeneratedGoal(
                userID: try! currentMeasurements.$user.id,
                measurementType: "Thigh",
                goalValue: currentMeasurements.thigh,
                targetDate: targetDate,
                dateGenerated: Date()))
        }

        if currentMeasurements.chest > 0 {
            goals.append(GeneratedGoal(
                userID: try! currentMeasurements.$user.id,
                measurementType: "Chest",
                goalValue: currentMeasurements.chest,
                targetDate: targetDate,
                dateGenerated: Date()))
        }

        if currentMeasurements.bicep > 0 {
            goals.append(GeneratedGoal(
                userID: try! currentMeasurements.$user.id,
                measurementType: "Bicep",
                goalValue: currentMeasurements.bicep,
                targetDate: targetDate,
                dateGenerated: Date()))
        }

        if currentMeasurements.calf > 0 {
            goals.append(GeneratedGoal(
                userID: try! currentMeasurements.$user.id,
                measurementType: "Calf",
                goalValue: currentMeasurements.calf,
                targetDate: targetDate,
                dateGenerated: Date()))
        }

        return goals
    }

    // Helper function to calculate a target weight loss based on body type and activity level
    func calculateTargetWeightLoss(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseLoss: Double = 0.02 // Base 2% loss

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: false) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 - baseLoss * adjustmentFactor)
    }

    // Helper function to calculate a target measurement loss based on body type and activity level
    func calculateTargetWaistLoss(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseLoss: Double = 0.03 // Base 3% loss

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: false) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 - baseLoss * adjustmentFactor)
    }

    func calculateTargetThighLoss(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseLoss: Double = 0.03 // Base 3% loss

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: false) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 - baseLoss * adjustmentFactor)
    }

    func calculateTargetChestLoss(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseLoss: Double = 0.02 // Base 2% loss

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: false) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 - baseLoss * adjustmentFactor)
    }

    func calculateTargetBicepLoss(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseLoss: Double = 0.015 // Base 1.5% loss

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: false) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 - baseLoss * adjustmentFactor)
    }

    func calculateTargetCalfLoss(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseLoss: Double = 0.015 // Base 1.5% loss

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: false) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 - baseLoss * adjustmentFactor)
    }

    // Helper function to calculate a target measurement gain based on body type and activity level
    func calculateTargetWeightGain(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseGain: Double = 0.02 // Base 2% gain

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: true) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 + baseGain * adjustmentFactor)
    }

    func calculateTargetBicepGain(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseGain: Double = 0.02 // Base 2% gain

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: true) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 + baseGain * adjustmentFactor)
    }

    func calculateTargetChestGain(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseGain: Double = 0.03 // Base 3% gain

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: true) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 + baseGain * adjustmentFactor)
    }

    func calculateTargetThighGain(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseGain: Double = 0.03 // Base 3% gain

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: true) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 + baseGain * adjustmentFactor)
    }

    func calculateTargetCalfGain(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseGain: Double = 0.02 // Base 2% gain

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: true) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 + baseGain * adjustmentFactor)
    }

    // Helper function to determine the adjustment factor based on body type
    func getAdjustmentFactor(bodyType: String, gain: Bool) -> Double {
        switch bodyType.lowercased() {
        case "ectomorph":
            return gain ? 1.1 : 0.9
        case "endomorph":
            return gain ? 0.9 : 1.1
        default: // mesomorph and average
            return 1.0
        }
    }

    // Helper function to determine the activity level adjustment factor
    func getActivityAdjustmentFactor(activityLevel: String) -> Double {
        switch activityLevel.lowercased() {
        case "sedentary":
            return 0.9
        case "lightly active":
            return 1.0
        case "moderately active":
            return 1.1
        case "very active":
            return 1.2
        default:
            return 1.0
        }
    }
    
    func getCalorieDeficitForWeightLoss(bodyType: String, activityLevel: String) -> Double {
        let baseDeficit: Double = 500.0 // Moderate base deficit

        let bodyTypeAdjustment: Double = {
            switch bodyType.lowercased() {
            case "ectomorph":
                return 0.9
            case "endomorph":
                return 1.1
            default:
                return 1.0
            }
        }()

        let activityLevelAdjustment: Double = {
            switch activityLevel.lowercased() {
            case "sedentary":
                return 1.0
            case "lightly active":
                return 0.9
            case "moderately active":
                return 0.8
            case "very active":
                return 0.7
            default:
                return 0.8
            }
        }()

        return baseDeficit * bodyTypeAdjustment * activityLevelAdjustment
    }
    func calculateTargetWaistGain(currentMeasurement: Double, bodyType: String, activityLevel: String) -> Double {
        let baseGain: Double = 0.01 // Base 1% gain for waist

        let adjustmentFactor = getAdjustmentFactor(bodyType: bodyType, gain: true) *
            getActivityAdjustmentFactor(activityLevel: activityLevel)

        return currentMeasurement * (1.0 + baseGain * adjustmentFactor)
    }


    func getCalorieSurplusForMuscleGain(bodyType: String, activityLevel: String) -> Double {
        let baseSurplus: Double = 250.0 // Moderate base surplus

        let bodyTypeAdjustment: Double = {
            switch bodyType.lowercased() {
            case "ectomorph":
                return 1.1
            case "endomorph":
                return 0.9
            default:
                return 1.0
            }
        }()

        let activityLevelAdjustment: Double = {
            switch activityLevel.lowercased() {
            case "sedentary":
                return 1.0
            case "lightly active":
                return 0.9
            case "moderately active":
                return 0.8
            case "very active":
                return 0.7
            default:
                return 0.8
            }
        }()

        return baseSurplus * bodyTypeAdjustment * activityLevelAdjustment
    }
}
