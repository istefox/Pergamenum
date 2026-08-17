import Carbon.HIToolbox
import Foundation

/// The global hot key of ADR-0008 §D1: `RegisterEventHotKey`, not a global `NSEvent`
/// monitor.
///
/// `NSEvent.h` says of `addGlobalMonitorForEventsMatchingMask`, verbatim: *"Key-related
/// events may only be monitored if accessibility is enabled or if your application is
/// trusted for accessibility access."* Buying a keyboard shortcut with a permission that
/// lets the app see every keystroke in every application is the wrong trade, and TCC has
/// already cost this project two afternoons once. This asks for nothing and is handed one
/// event: the combination was pressed.
@MainActor
@Observable
final class GlobalHotkey {
    /// What the system actually did with the request.
    ///
    /// A type rather than a `Bool`, because §D2 turns on the difference between these
    /// cases: a settings pane that shows the shortcut the user chose while the system
    /// refused it is the failure `@remind` already shipped once, wired to nothing under
    /// five green tests.
    enum State: Equatable {
        case off
        case registered(KeyBinding)
        /// `eventHotKeyExistsErr`: another process holds it exclusively.
        case takenByAnotherApp(KeyBinding)
        /// No virtual key code for that key (`CarbonKey` could not translate it).
        case unusableKey(KeyBinding)
        /// Anything else the API said, kept as the number so it can be looked up.
        case failed(KeyBinding, OSStatus)

        var isRegistered: Bool {
            if case .registered = self { return true }
            return false
        }

        /// What Impostazioni › Scorciatoie puts beside the row.
        var explanation: String? {
            switch self {
            case .off, .registered: nil
            case .takenByAnotherApp: "già di un'altra applicazione"
            case .unusableKey: "questo tasto non si può usare da fuori l'app"
            case .failed(_, let status): "il sistema l'ha rifiutata (\(status))"
            }
        }
    }

    private(set) var state: State = .off

    /// Called on the main actor when the combination is pressed.
    var onPress: (() -> Void)?

    /// The two C handles, reachable from `deinit`.
    ///
    /// A `deinit` on a `@MainActor` type is not itself main-actor isolated, so touching
    /// isolated state from it does not compile - and these are exactly the two things
    /// that outlive the object if nobody releases them.
    ///
    /// Both attributes are needed and neither is decoration. `@ObservationIgnored`
    /// because the `@Observable` macro turns a stored property into a computed one, and
    /// `nonisolated` cannot be applied to that; they are opaque pointers, not state any
    /// view should redraw for. `nonisolated(unsafe)` because plain `nonisolated` is
    /// refused on a mutable stored property - unsafe is the accurate word here: every
    /// other access is on the main actor, and `deinit` runs when no other can be in
    /// flight.
    @ObservationIgnored private nonisolated(unsafe) var hotKey: EventHotKeyRef?
    @ObservationIgnored private nonisolated(unsafe) var handler: EventHandlerRef?
    /// `perg` in four bytes, so the id is recognisable in a debugger.
    private static let signature = OSType(0x7065_7267)

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    // MARK: Registering

    /// Registers a binding, replacing whatever was registered before.
    ///
    /// Returns the state rather than a `Bool` so the caller cannot record "it worked"
    /// without having looked at which way it did not.
    @discardableResult
    func register(_ binding: KeyBinding) -> State {
        unregister()

        guard let pair = CarbonKey.pair(for: binding) else {
            state = .unusableKey(binding)
            return state
        }
        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            pair.code,
            pair.modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(),
            // Exclusive on purpose: without it two apps can hold the same combination
            // and both are notified, which reads as the panel opening at random.
            OptionBits(kEventHotKeyExclusive),
            &reference
        )

        switch status {
        case noErr:
            hotKey = reference
            state = .registered(binding)
        case OSStatus(eventHotKeyExistsErr):
            state = .takenByAnotherApp(binding)
        default:
            state = .failed(binding, status)
        }
        return state
    }

    /// Gives the combination back to whoever wants it next.
    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        state = .off
    }

    // MARK: The callback

    /// Installs the one handler, once.
    ///
    /// The handler outlives individual registrations: re-installing it on every change
    /// would leave the previous one attached and fire the panel twice.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }

        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // A C function pointer cannot capture, so the instance travels as `userData`.
        // Unretained: the app owns this object for its whole life, and retaining it here
        // would make the handler keep it alive after the app let go.
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                // The dispatcher calls this on the main thread. Stating that with
                // `assumeIsolated` rather than hopping is what makes the panel appear on
                // the keystroke instead of a run loop later - and a hop here is exactly
                // the shape of the EventKit crash this project has already had.
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotkey>.fromOpaque(userData)
                        .takeUnretainedValue()
                        .onPress?()
                }
                return noErr
            },
            1,
            &specification,
            context,
            &handler
        )
    }
}
