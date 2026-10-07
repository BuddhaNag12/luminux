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

    @Test func swipeFromAnUnselectedPhotoSelectsTheRange() {
        let selection = SelectionModel()
        selection.selectedIDs = ["x"]
        selection.beginSwipe(on: "a")
        selection.updateSwipe(covering: ["a", "b", "c"])

        #expect(selection.selectedIDs == ["a", "b", "c", "x"])
    }

    @Test func swipingBackRestoresWhatWasThere() {
        let selection = SelectionModel()
        selection.selectedIDs = ["c"]
        selection.beginSwipe(on: "a")
        selection.updateSwipe(covering: ["a", "b", "c", "d"])
        selection.updateSwipe(covering: ["a", "b"])

        #expect(selection.selectedIDs == ["a", "b", "c"])
    }

    @Test func swipeFromASelectedPhotoClears() {
        let selection = SelectionModel()
        selection.selectedIDs = ["a", "b", "c", "z"]
        selection.beginSwipe(on: "a")
        selection.updateSwipe(covering: ["a", "b"])

        #expect(selection.selectedIDs == ["c", "z"])
    }
}
