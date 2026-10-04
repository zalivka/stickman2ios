import AmplitudeSwift

enum Analytics {
    private static let apiKey = "8d2d11bbeedf5ae1ece40dfa960d0e78"

    #if DEBUG
    private static let client = Amplitude(
        configuration: Configuration(
            apiKey: apiKey,
            flushQueueSize: 1,
            flushIntervalMillis: 1000
        )
    )
    #else
    private static let client = Amplitude(
        configuration: Configuration(apiKey: apiKey)
    )
    #endif

    static func boot() {
        _ = client
    }

    static func event(_ name: String) {
        client.track(eventType: name)
    }

    static func event(_ name: String, _ properties: [String: Any]) {
        client.track(eventType: name, eventProperties: properties)
    }
}
