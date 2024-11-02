import Fluent
import Vapor

final class Measurement: Model, Content {
    static let schema = "measurements"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "weight")
    var weight: Double

    @Field(key: "height")
    var height: Double

    @Field(key: "bicep")
    var bicep: Double

    @Field(key: "calf")
    var calf: Double

    @Field(key: "waist")
    var waist: Double

    @Field(key: "thigh")
    var thigh: Double

    @Field(key: "chest")
    var chest: Double

    @Field(key: "date")
    var date: Date

    init() {}

    init(id: UUID? = nil, userID: UUID, weight: Double, height: Double, bicep: Double, calf: Double, waist: Double, thigh: Double, chest: Double, date: Date) {
        self.id = id
        self.$user.id = userID
        self.weight = weight
        self.height = height
        self.bicep = bicep
        self.calf = calf
        self.waist = waist
        self.thigh = thigh
        self.chest = chest
        self.date = date
    }

    struct Create: Content {
        var weight: Double
        var height: Double
        var bicep: Double
        var calf: Double
        var waist: Double
        var thigh: Double
        var chest: Double
        var date: Date
    }

    struct Public: Content {
        var id: UUID?
        var userID: UUID
        var weight: Double
        var height: Double
        var bicep: Double
        var calf: Double
        var waist: Double
        var thigh: Double
        var chest: Double
        var date: Date

        init(id: UUID? = nil, userID: UUID, weight: Double, height: Double, bicep: Double, calf: Double, waist: Double, thigh: Double, chest: Double, date: Date) {
            self.id = id
            self.userID = userID
            self.weight = weight
            self.height = height
            self.bicep = bicep
            self.calf = calf
            self.waist = waist
            self.thigh = thigh
            self.chest = chest
            self.date = date
        }
    }

    func toPublic() -> Public {
        return Public(
            id: self.id,
            userID: self.$user.id,
            weight: self.weight,
            height: self.height,
            bicep: self.bicep,
            calf: self.calf,
            waist: self.waist,
            thigh: self.thigh,
            chest: self.chest,
            date: self.date
        )
    }
}
