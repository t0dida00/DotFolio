import DotFolioModels
import Foundation
import SwiftData

/// One-time cleanup from before "Service" (what) and "Provider" (who) were
/// separate: category words typed into the provider field ("Database",
/// "DB", "Cache") move to the category, and leave accounts' provider lists.
public enum ServiceCategoryMigration {
    @MainActor
    @discardableResult
    public static func run(context: ModelContext) -> Int {
        var moved = 0
        let variables = (try? context.fetch(FetchDescriptor<Variable>())) ?? []
        for v in variables {
            let label = v.serviceLabel
            guard !label.isEmpty, ServiceType(matching: label) == nil,
                  let category = ServiceCategory(matching: label) else { continue }
            if v.serviceCategory.isEmpty { v.serviceCategory = category.displayName }
            v.serviceLabel = ""
            moved += 1
        }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts {
            for service in account.services where ServiceType(matching: service) == nil && ServiceCategory(matching: service) != nil {
                account.removeService(service)
            }
        }
        if moved > 0 { try? context.save() }
        return moved
    }
}
