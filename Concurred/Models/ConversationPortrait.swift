import Foundation

enum ConversationPortrait {
    /// The random conversation UUID supplies a stable choice without storing
    /// another field or changing existing chat files. Each portrait from 20–44
    /// gets four tickets; each portrait from 10–19 gets one.
    static func number(for conversationID: UUID) -> Int {
        let hash = conversationID.uuidString.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        let ticket = Int(hash % 110)
        return ticket < 10 ? 10 + ticket : 20 + (ticket - 10) / 4
    }
}
