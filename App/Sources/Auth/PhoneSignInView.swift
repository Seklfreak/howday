import SwiftUI

/// Sign-in: pick a country, type the number the way you'd dial it at home,
/// then a 6-digit code that verifies itself as soon as it's complete (or as
/// soon as iOS fills it in from the SMS).
struct PhoneSignInView: View {
    private enum Step: Equatable {
        case enterPhone
        case enterCode(phone: String)
    }

    private enum Field: Hashable {
        case phone
        case code
    }

    /// How long the "Resend code" button stays disabled after a send, so a
    /// second tap can't burn an SMS on a message that's still in flight.
    private static let resendCooldown = 30

    @State private var step: Step = .enterPhone
    @State private var country = CountryCode.deviceDefault
    @State private var national = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showCountryPicker = false
    @State private var resendIn = 0
    @State private var countdown: Task<Void, Never>?
    /// The code already tried, so a rejected code doesn't auto-verify again
    /// on every keystroke that leaves it six digits long.
    @State private var attemptedCode: String?
    @FocusState private var focus: Field?

    /// What will actually be sent. A number typed in international form
    /// carries its own country and overrides the picker — derived on every
    /// read rather than written back into the field, because rewriting text
    /// somebody is still typing races their next keystroke and can swallow a
    /// digit. It did: App Review sent "+1505550001", one zero short of the
    /// test number, and spent the rest of the session hunting for a country
    /// that would take it.
    private var resolved: (country: CountryCode, national: String) {
        CountryCode.international(in: national) ?? (country, national)
    }

    private var e164: String? { PhoneNumber.e164(country: resolved.country, national: resolved.national) }

    /// Why "Send code" is still dim, once something is typed. A disabled
    /// button explains nothing on its own, and the number being refused
    /// before an SMS is spent is only an improvement if the person can tell
    /// that is what happened. The wording stays general on purpose: the app
    /// knows the number is not usable, not which digit is wrong.
    private var numberHint: String? {
        guard e164 == nil, !PhoneNumber.nationalDigits(resolved.national).isEmpty else { return nil }
        return "That doesn't look like a complete phone number."
    }

    var body: some View {
        ZStack {
            MoodBackground(theme: .brand)
            ScrollView {
                VStack(spacing: 28) {
                    header
                    switch step {
                    case .enterPhone: phoneStep
                    case .enterCode(let phone): codeStep(phone: phone)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .tint(MoodTheme.brand.accent)
        .sheet(isPresented: $showCountryPicker) {
            CountryPicker(selection: $country)
        }
        .onAppear {
            Analytics.screen(.signIn)
            focus = .phone
        }
        .onChange(of: country) { _, _ in
            // Picking from the list is an explicit answer to "which country",
            // so a "+49" still sitting in the field must not keep overriding
            // it. Rewriting the text is safe here in a way it never is while
            // typing: this runs on a discrete tap, with nothing in flight.
            if let match = CountryCode.international(in: national) { national = match.national }
        }
        .onDisappear { countdown?.cancel() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Howday")
                .font(.largeTitle.weight(.semibold))
            Text("One emoji a day, shared with the friends who already have you in their contacts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var phoneStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Button {
                    focus = nil
                    showCountryPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(resolved.country.flag)
                        Text(resolved.country.dialText).monospacedDigit()
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Country: \(resolved.country.name), \(resolved.country.dialText)")

                TextField("Phone number", text: $national)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($focus, equals: .phone)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            Text(numberHint ?? "We text you a 6-digit code; there's no password.")
                .font(.footnote)
                .foregroundStyle(numberHint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .multilineTextAlignment(.center)

            Button(action: sendCode) {
                Group {
                    if isBusy { ProgressView() } else { Text("Send code") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy || e164 == nil)
        }
    }

    private func codeStep(phone: String) -> some View {
        VStack(spacing: 16) {
            Text("Enter the code we texted to \(phone)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .tracking(6)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    // Six digits is the whole code — asking for a "Verify" tap
                    // on top of that (or on top of iOS's SMS autofill) is a
                    // step with nothing left to decide.
                    if digits.count == 6, digits != attemptedCode, !isBusy {
                        verify(phone: phone)
                    }
                }

            Button {
                verify(phone: phone)
            } label: {
                Group {
                    if isBusy { ProgressView() } else { Text("Verify") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy || code.count < 6)

            HStack(spacing: 20) {
                Button(resendIn > 0 ? "Resend in \(resendIn)s" : "Resend code") {
                    resend(phone: phone)
                }
                .disabled(isBusy || resendIn > 0)
                Button("Change number") {
                    countdown?.cancel()
                    step = .enterPhone
                    code = ""
                    attemptedCode = nil
                    errorMessage = nil
                    focus = .phone
                }
                .disabled(isBusy)
            }
            .font(.footnote)
        }
    }

    private func sendCode() {
        guard let phone = e164 else { return }
        run {
            try await Supa.client.auth.signInWithOTP(phone: phone)
            // Only once Twilio has actually taken it, so the pair with
            // signin_completed measures the code step, not failed sends.
            Analytics.track("signin_code_sent")
            step = .enterCode(phone: phone)
            focus = .code
            startCooldown()
        }
    }

    private func resend(phone: String) {
        run {
            try await Supa.client.auth.signInWithOTP(phone: phone)
            Analytics.track("signin_code_resent")
            code = ""
            attemptedCode = nil
            focus = .code
            startCooldown()
        }
    }

    private func verify(phone: String) {
        attemptedCode = code
        run {
            try await Supa.client.auth.verifyOTP(phone: phone, token: code, type: .sms)
            Analytics.track("signin_completed")
        }
    }

    private func startCooldown() {
        countdown?.cancel()
        resendIn = Self.resendCooldown
        countdown = Task {
            while resendIn > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        errorMessage = nil
        isBusy = true
        Task {
            do {
                try await work()
            } catch {
                error.report("auth.signIn")
                errorMessage = Self.friendlyMessage(for: error)
            }
            isBusy = false
        }
    }

    /// Supabase hands back the provider's own wording, which is written for
    /// developers ("sms_send_failed", "Token has expired or is invalid").
    /// These three are the failures a user can actually do something about.
    private static func friendlyMessage(for error: Error) -> String {
        let text = error.localizedDescription
        func mentions(_ needle: String) -> Bool { text.localizedCaseInsensitiveContains(needle) }

        if mentions("sms_send_failed") || mentions("invalid phone") || mentions("invalid_phone") {
            return "We couldn't text that number. Check the country and the number, then try again."
        }
        if mentions("expired") {
            return "That code has expired — send yourself a new one."
        }
        if mentions("token") || mentions("otp") {
            return "That code doesn't match. Check the digits, or send a new code."
        }
        return text
    }
}

/// The country list, searchable by name or code.
private struct CountryPicker: View {
    @Binding var selection: CountryCode
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                // The device's own region, one tap from the top. The full list
                // is alphabetical, so without this the first thing under a
                // reviewer's thumb is Afghanistan — and taking the top row is
                // exactly what someone does when the list is 200 long and they
                // only came here because the number was refused.
                if search.isEmpty {
                    Section("Your country") { row(for: .deviceDefault) }
                }
                // Still listed below in its alphabetical place: somebody
                // scrolling to "U" for the United States should find it there.
                Section {
                    ForEach(CountryCode.matching(searchText: search)) { row(for: $0) }
                }
            }
            .searchable(text: $search, prompt: "Country or code")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(for country: CountryCode) -> some View {
        Button {
            selection = country
            dismiss()
        } label: {
            HStack {
                Text(country.flag)
                Text(country.name)
                Spacer()
                Text(country.dialText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if country == selection {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
