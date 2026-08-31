import SwiftUI
import UIKit

/// The phone field, backed by UIKit for one reason: `shouldChangeCharactersIn`
/// is the only place the app can tell a paste from typing. A multi-character
/// insertion is a paste, an AutoFill or dictation — never a keystroke, because
/// UIKit reports those one character at a time. That is what makes it safe to
/// move a pasted "+49 162…" into the country picker: guessing from the text
/// alone (a jump in length between two `onChange` values) reads fast typing as
/// a paste, rewrites the field mid-word and swallows the rest of the number.
struct PhoneNumberField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    /// A number pasted in international form, already split into its country
    /// and the national part. Nothing else is reported: an ordinary paste is
    /// inserted as typed.
    var onPasteInternational: (CountryCode, String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .phonePad
        field.textContentType = .telephoneNumber
        field.placeholder = "Phone number"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        // Let the surrounding frame decide the width; a UITextField otherwise
        // asks for the width of its own text.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PhoneNumberField

        init(parent: PhoneNumberField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textField(
            _ field: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard string.count > 1 else { return true }
            let candidate = (field.text as NSString? ?? "").replacingCharacters(in: range, with: string)
            guard let match = CountryCode.international(in: candidate) else { return true }
            parent.onPasteInternational(match.country, match.national)
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
