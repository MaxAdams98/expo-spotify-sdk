export interface SpotifySession {
  accessToken: string;
  refreshToken: string;
  expirationDate: number;
  scopes: SpotifyScope[];
}

export interface SpotifyConfig {
  scopes: SpotifyScope[];
  tokenSwapURL?: string;
  tokenRefreshURL?: string;
}

// PlayerState interface for playback information
export interface PlayerState {
  playing: boolean;
  track: {
    uri: string;
    name: string;
    duration: number;
    artists: { name: string; uri: string }[];
    album?: {
      name: string;
      uri: string;
      images?: { url: string; width: number; height: number }[];
    };
  } | null;
  playbackPosition: number;
  playbackSpeed: number;
  repeatMode: 'off' | 'track' | 'context';
  shuffleModeEnabled: boolean;
}

// Playback options interface
export interface PlaybackOptions {
  position?: number; // Position in ms to start playback
  playlistIndex?: number; // Start index for playlist playback
}

export type SpotifyScope =
  | 'ugc-image-upload'
  | 'user-read-playback-state'
  | 'user-modify-playback-state'
  | 'user-read-currently-playing'
  | 'app-remote-control'
  | 'streaming'
  | 'playlist-read-private'
  | 'playlist-read-collaborative'
  | 'playlist-modify-private'
  | 'playlist-modify-public'
  | 'user-follow-modify'
  | 'user-follow-read'
  | 'user-top-read'
  | 'user-read-recently-played'
  | 'user-library-modify'
  | 'user-library-read'
  | 'user-read-email'
  | 'user-read-private';
