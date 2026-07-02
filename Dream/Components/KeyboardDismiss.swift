import SwiftUI
import UIKit

extension View {
    /// Puts a "Done" button in the keyboard's accessory bar that ends editing.
    /// Apply once per screen that has text input; pair with
    /// `.scrollDismissesKeyboard(.interactively)` on the screen's ScrollView so
    /// the keyboard can also be dragged away.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(DreamTheme.Font.text(15, weight: .semibold))
                .foregroundStyle(DreamTheme.blue)
            }
        }
    }
}
