import Testing
@testable import Luminux

struct SelectionModelTests {
    @Test func beginWithIDSelectsJustThatPhoto() {
        let selection = SelectionModel()
        selection.selectedIDs = ["old"]
        selection.begin(with: "a")

        #expect(selection.isActive)
        #expect(selection.selectedIDs == ["a"])
    }

    @Test func toggleAllFillsAPartlySelectedMonth() {
        let selection = SelectionModel()
        selection.selectedIDs = ["a", "other"]
        selection.toggleAll(["a", "b", "c"])

        #expect(selection.selectedIDs == ["a", "b", "c", "other"])
    }

    @Test func toggleAllClearsAFullySelectedMonthOnly() {
        let selection = SelectionModel()
        selection.selectedIDs = ["a", "b", "other"]
        selection.toggleAll(["a", "b"])

        #expect(selection.selectedIDs == ["other"])
    }
}
