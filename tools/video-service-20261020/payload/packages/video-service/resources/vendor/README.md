# Pinned browser dependencies

- Mux Player 3.14.0: `https://cdn.jsdelivr.net/npm/@mux/mux-player@3.14.0/dist/mux-player.js`
- UpChunk 3.5.0: `https://cdn.jsdelivr.net/npm/@mux/upchunk@3.5.0/dist/upchunk.js`

Unmodified upstream browser bundles, including embedded third-party licence notices.
Mux Player licence obtained from `https://github.com/muxinc/elements/blob/main/LICENSE`;
UpChunk licence from its versioned package. Source maps are not included.
The application serves these pinned scripts locally. Mux media delivery and its
player's standard telemetry still use provider endpoints; no user identity is
passed in player metadata.
