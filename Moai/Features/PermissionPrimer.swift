import AVFoundation
import EventKit
import Speech

/// One button in the welcome tour asks for everything the island
/// uses, so a new user is not ambushed by prompts one feature at a
/// time. Anything denied stays deniable; this only fronts the asking.
enum PermissionPrimer {
    static func primeAll() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToReminders()
        _ = try? await store.requestFullAccessToEvents()
    }
}
