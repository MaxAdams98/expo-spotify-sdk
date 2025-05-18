import SpotifyiOS

struct ExpoSpotifyConfiguration: Codable {
    let clientID: String
    let host: String
    let scheme: String

    var redirectURL: URL? {
        // Ensure the URL is properly formatted
        let urlString = "\(scheme)://\(host)"
        guard let url = URL(string: urlString),
              url.scheme?.isEmpty == false,
              url.host?.isEmpty == false else {
            print("ExpoSpotifySDK: Invalid redirect URL format: \(urlString)")
            return nil
        }
        return url
    }

    init(clientID: String = "defaultClientID",
         host: String = "defaultHost",
         scheme: String = "defaultScheme"
    ) {
        self.clientID = clientID
        self.host = host
        self.scheme = scheme

        // Validate configuration
        if clientID == "defaultClientID" {
            print("ExpoSpotifySDK: Warning - Using default client ID")
        }
        if host == "defaultHost" {
            print("ExpoSpotifySDK: Warning - Using default host")
        }
        if scheme == "defaultScheme" {
            print("ExpoSpotifySDK: Warning - Using default scheme")
        }

        // Validate redirect URL
        if redirectURL == nil {
            print("ExpoSpotifySDK: Error - Invalid redirect URL configuration")
        }
    }

    // Validate the configuration is properly set up
    var isValid: Bool {
        return clientID != "defaultClientID" &&
               host != "defaultHost" &&
               scheme != "defaultScheme" &&
               redirectURL != nil
    }
}
