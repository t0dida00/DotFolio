import Foundation
import SwiftData
import Testing
@testable import DotFolioModels

@MainActor
struct ProjectOriginFilterTests {
    @Test func splitsGitAndLocal() throws {
        let context = ModelContext(try DotFolioSchema.makeContainer(inMemory: true))
        let git = Project.create(name: "Git", link: URL(string: "https://github.com/o/r"), in: context)
        let local = Project.create(name: "Local", link: URL(string: "https://github.com/o/l"), in: context)
        local.localFolderBookmark = Data([1])
        let hand = Project.create(name: "Hand", in: context)
        let all = [git, local, hand]
        #expect(all.filter(ProjectOriginFilter.all.matches).count == 3)
        #expect(all.filter(ProjectOriginFilter.git.matches).map(\.name) == ["Git"])
        #expect(all.filter(ProjectOriginFilter.local.matches).map(\.name) == ["Local"])
    }
}
