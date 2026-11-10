import Foundation

enum Copy {
    static let notTaxAdvice = "Records are for you and your tax professional. This is not tax advice."
    static let locationUsage = "FairMile uses your location while you record a trip to calculate mileage. Location is not used in the background in this version."
    static let cameraUsage = "FairMile uses the camera to photograph a receipt. The photo stays on this iPhone unless you turn on iCloud sync."
    static let standardMileageReminder = "If you use the IRS standard mileage rate, you generally cannot also deduct actual vehicle expenses such as gas. Parking and tolls can be separate. Confirm with your tax professional."
    static let editedMeaning = "Edited means the miles or endpoints differ from the original recording or the first saved entry, or the trip was split or merged."
    static let notTheIRS = "FairMile is not affiliated with the IRS and does not certify a deduction."
    static let gapWarning = "FairMile missed part of this drive. That gap is not included in the miles. Set the miles yourself if you drove through it."
    static let manualMiles = "Enter the miles you drove. The map marks places and does not estimate the route."
    static let pinDoesNotChangeMiles = "The pin marks the place. Miles stay as they are until you change them."
    static let pathMiles = "Miles follow the driven path, not a straight line between the pins."
    static let keepOpen = "Keep FairMile open. This version does not record in the background."
    static let privacyPolicyURL = URL(string: "https://leawee.github.io/FairMile/")!
}

enum Prefs {
    static let onboarded = "hasOnboarded"
    static let iCloud = "icloudEnabled"
}

enum PlusProduct: String, CaseIterable, Sendable {
    case monthly = "app.fairmile.plus.monthly"
    case yearly = "app.fairmile.plus.yearly"
    case lifetime = "app.fairmile.plus.lifetime"
}
