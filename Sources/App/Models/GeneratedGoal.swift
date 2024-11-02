import Fluent
import Vapor

final class GeneratedGoal: Model, Content {
    static let schema = "generated_goals"
    
    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "measurement_type")
    var measurementType: String

    @Field(key: "goal_value")
    var goalValue: Double

    @Field(key: "target_date")
    var targetDate: Date

    @Field(key: "date_generated")
    var dateGenerated: Date

    init() {}

    init(id: UUID? = nil, userID: UUID, measurementType: String, goalValue: Double, targetDate: Date, dateGenerated: Date) {
        self.id = id
        self.$user.id = userID
        self.measurementType = measurementType
        self.goalValue = goalValue
        self.targetDate = targetDate
        self.dateGenerated = dateGenerated
    }

    struct GoalPublic: Content {
        var id: UUID?
        var measurementType: String
        var goalValue: Double
        var targetDate: Date
        var dateGenerated: Date

        init(id: UUID? = nil, measurementType: String, goalValue: Double, targetDate: Date, dateGenerated: Date) {
            self.id = id
            self.measurementType = measurementType
            self.goalValue = goalValue
            self.targetDate = targetDate
            self.dateGenerated = dateGenerated
        }
    }

    func toPublic() -> GoalPublic {
        return GoalPublic(id: self.id, measurementType: self.measurementType, goalValue: self.goalValue, targetDate: self.targetDate, dateGenerated: self.dateGenerated)
    }
}
