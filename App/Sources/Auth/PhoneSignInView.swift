import SwiftUI

struct PhoneSignInView: View {
    enum Step {
        case enterPhone
        case enterCode(phone: String)
    }

    @State private var step: Step = .enterPhone
    @State private var phoneInput = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .enterPhone:
                    Section {
                        TextField("+1 555 123 4567", text: $phoneInput)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    } header: {
                        Text("Your phone number")
                    } footer: {
                        Text("Include your country code. We text you a sign-in code — no passwords.")
                    }
                    Section {
                        Button(action: sendCode) {
                            if isBusy { ProgressView() } else { Text("Send code") }
                        }
                        .disabled(isBusy || PhoneNumber.e164(from: phoneInput) == nil)
                    }
                case .enterCode(let phone):
                    Section {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } header: {
                        Text("Code sent to \(phone)")
                    }
                    Section {
                        Button(action: { verify(phone: phone) }) {
                            if isBusy { ProgressView() } else { Text("Verify") }
                        }
                        .disabled(isBusy || code.count < 4)
                        Button("Use a different number") {
                            step = .enterPhone
                            code = ""
                            errorMessage = nil
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mood Ring")
        }
    }

    private func sendCode() {
        guard let phone = PhoneNumber.e164(from: phoneInput) else { return }
        run {
            try await Supa.client.auth.signInWithOTP(phone: phone)
            step = .enterCode(phone: phone)
        }
    }

    private func verify(phone: String) {
        run {
            try await Supa.client.auth.verifyOTP(phone: phone, token: code, type: .sms)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        errorMessage = nil
        isBusy = true
        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}
