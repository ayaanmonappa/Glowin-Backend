import Fluent
import Vapor

final class User: Model, Content, Authenticatable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "email")
    var email: String

    @Field(key: "password")
    var password: String

    @Field(key: "gender")
    var gender: String

    @Field(key: "age")
    var age: Int

    @Field(key: "goal")
    var goal: String?
    
    
    @OptionalField(key: "bodyType")
    var bodyType: String?

    @OptionalField(key: "activity_level")
      var activityLevel: String?
    
    @OptionalField(key: "lastGoalGeneration")
    var lastGoalGeneration: Date?
    
    

    @Children(for: \.$user)
    var measurements: [Measurement]

    init() {
    }

    init(id: UUID? = nil, username: String, email: String, password: String, gender: String, age: Int, goal: String? = nil, bodyType: String? = nil, activity_level: String? = nil, lastGoalGeneration: Date? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.password = password
        self.gender = gender
        self.age = age
        self.goal = goal
        self.bodyType = bodyType
        self.activityLevel = activityLevel
        self.lastGoalGeneration = lastGoalGeneration


    
    }
}
