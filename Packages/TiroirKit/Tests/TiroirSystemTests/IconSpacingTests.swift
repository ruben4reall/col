import Testing
@testable import TiroirSystem

@Suite struct IconSpacingTests {
    @Test func standardLeavesMacOSAlone() {
        #expect(IconSpacing.standard.values == nil)
    }

    @Test func stepsGetTighter() {
        let spacings = IconSpacing.allCases.map { $0.values?.spacing ?? 16 }
        #expect(spacings == spacings.sorted(by: >))
    }

    @Test func valuesSetByHandMapToTheClosestStep() {
        #expect(IconSpacing.closest(spacing: 16, padding: 16) == .standard)
        #expect(IconSpacing.closest(spacing: 12, padding: 8) == .snug)
        #expect(IconSpacing.closest(spacing: 6, padding: 7) == .tight)
        #expect(IconSpacing.closest(spacing: 8, padding: 8) == .compact)
    }
}
