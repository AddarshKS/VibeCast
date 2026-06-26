import Foundation

struct SpotifyToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }

    func token(replacingRefreshToken existingRefreshToken: String? = nil) -> SpotifyToken {
        SpotifyToken(
            accessToken: accessToken,
            refreshToken: refreshToken ?? existingRefreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

struct SpotifyUserProfile: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct SpotifySearchResponse: Decodable {
    let tracks: SpotifyTrackPage
}

struct SpotifyTrackPage: Decodable {
    let items: [SpotifyTrack]
}

struct SpotifyTrack: Decodable {
    let uri: String
    let name: String
    let artists: [SpotifyArtist]

    var displayName: String {
        guard let artist = artists.first?.name else { return name }
        return "\(name) by \(artist)"
    }
}

struct SpotifyArtist: Decodable {
    let name: String
}

struct SpotifyDevicesResponse: Decodable {
    let devices: [SpotifyDevice]
}

struct SpotifyDevice: Decodable, Equatable {
    let id: String?
    let name: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
    }
}
