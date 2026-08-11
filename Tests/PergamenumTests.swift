import Testing
@testable import Pergamenum

@Test func appInfoExposesProductName() {
    #expect(AppInfo.name == "Pergamenum")
    #expect(AppInfo.tagline.isEmpty == false)
}
