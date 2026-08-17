import OSLog

extension Logger {
    /// The one log stream global capture writes to.
    ///
    /// This is not debugging left behind. ADR-0008 §D2 records that a hot key can be
    /// registered successfully and still never fire, and that the only instrument which
    /// detects it is a person pressing the keys - which tells you the feature is broken
    /// and nothing about where. These three lines - registered, pressed, shown - turn one
    /// press into a readable trail:
    ///
    /// ```
    /// log stream --predicate 'subsystem == "it.stefer.pergamenum"' --info
    /// ```
    ///
    /// Nothing typed into the panel is ever logged. The text is the whole point of the
    /// capture and it is none of the system log's business.
    static let capture = Logger(subsystem: "it.stefer.pergamenum", category: "capture")
}
