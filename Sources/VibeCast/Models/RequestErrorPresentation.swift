import Foundation

/// Keeps recovery guidance in the request area and sanitized technical detail in Adv.
struct RequestErrorPresentation {
    enum Source { case request, chatGPT }

    let message: String
    let diagnostic: String

    init(_ error: Error, source: Source = .request) {
        diagnostic = Self.diagnostic(for: error)
        let description: String
        switch error {
        case is CancellationError:
            description = "Request cancelled."
        case let error as SpotifyAPIError:
            switch error {
            case .refused:
                description = "Spotify declined this request. Check your account access and Spotify permissions in Settings."
            case .playbackRefused(_, .unspecified):
                description = "Spotify declined this playback action. Try it in Spotify, then check Advanced View for details."
            case .requestFailed(let status, _) where status >= 500:
                description = "Spotify is temporarily unavailable. Try again shortly."
            case .requestFailed:
                description = "Spotify couldn't complete this request. Check Spotify, then try again."
            default:
                description = error.localizedDescription
            }
        case let error as URLError:
            switch error.code {
            case .cancelled:
                description = "Request cancelled."
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                description = "The connection is unavailable. Check your internet connection, then try again."
            case .timedOut:
                description = "The request timed out. Check the connection, then try again."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
                description = "A secure connection couldn't be established. Check your network and Mac's date and time."
            default:
                description = "The service couldn't be reached. Check your connection, then try again."
            }
        case is DecodingError:
            description = source == .chatGPT
                ? "ChatGPT returned an incomplete response. Try again; if it continues, update Codex."
                : "The service returned an incomplete response. Try again shortly."
        case is UserFacingError, is PlaybackConfirmationFailure, is PlaylistRecoveryError:
            // These errors already describe the outcome and safe recovery action.
            description = error.localizedDescription
        default:
            description = source == .chatGPT
                ? "The ChatGPT connection couldn't finish this request. Reconnect in Settings and try again."
                : "This request couldn't finish. Check Advanced View for details, then try again."
        }
        message = DiagnosticLog.redacted(description)
    }

    private static func diagnostic(for error: Error) -> String {
        let detail: String
        if let error = error as? SpotifyAPIError {
            switch error {
            case .refused(let path, let message): detail = "Spotify HTTP 403 \(path): \(message)"
            case .playbackRefused(let path, let reason): detail = "Spotify HTTP 403 \(path); reason=\(reason.rawValue)"
            case .requestFailed(let status, let message): detail = "Spotify HTTP \(status): \(message)"
            default: detail = "Spotify: \(error.localizedDescription)"
            }
        } else if error is DecodingError {
            detail = String(reflecting: error)
        } else {
            let value = error as NSError
            detail = "\(value.domain) (\(value.code)): \(error.localizedDescription)"
        }
        return DiagnosticLog.redacted(detail)
    }
}
