# Common Issues

This document contains common Khylo issues, troubleshooting steps, and resolutions for items that come up frequently.

If your issue isn't here, please check our [existing issues](https://github.com/khylo/Khylo/issues) before opening a new one. For issues or questions about playback, see the [Players Documentation](players.md). For library support, see [Libraries Documentation](libraries.md).

---

## Before You Report

These four steps resolve many common issues or help narrow down unique issues from known ones:

| Step | Why |
|------|-----|
| **1. Update Khylo** | We are only able to support the current release which may already have a code fix for the issue you are experiencing. If you see a closed issue for your problem, but it's still not resolved on the latest release, please try using our [TestFlight](https://testflight.apple.com/join/SqNPfdxq) before reporting a new issue. |
| **2. Switch the player** <br>*Settings > Advanced > Video Player > Engine* | Each player is based on a different playback engine. Confirming which player(s) has an issue helps narrow the troubleshooting steps. |
| **3. Connect by direct `IP:port`** | If this works and your domain doesn't, the problem is your reverse proxy or network. |
| **4. Check the logs** <br>*Login Issues: Settings > Advanced > Logs* <br>*Other Issues: Settings > Logs* | These logs show network traffic and logs for Khylo. Identifying the failing decodes or packets that exist can help resolve network/proxy issues. |

---

## Playback

### Nothing Plays, but Browsing Works

Your library, posters, and metadata all load. Pressing play gives a black screen or a spinner. This issue is commonly caused by one of the following:

**Your reverse proxy is TLS 1.3 only.** libvlc only supports TLS **1.1 and 1.2**, so media playback fails while everything else works. NGINX has included 1.3 by default since 1.23.4, so this can appear after an update. Enable 1.2 alongside 1.3 (having both is fine) and libvlc will fall back to using the supported version. This is a libvlc limitation and is documented in the [Players Documentation](players.md).

**You entered `http` for an `https` server.** You can sign in and browse everything, but nothing plays. Khylo attempts to resolve this at login, but HSTS and redirects can mask the issue since some requests follow the redirect but media requests do not. Re-add the server with the correct scheme.

If neither applies, please test on a direct `IP:port` connection before reporting.

### HDR or Dolby Vision Looks Wrong

Purple casts, washed out color, or no tone mapping at all. Both players handle HDR differently and neither is perfect:

- **VLC** tone maps, but colorspace accuracy varies with content and device.
- **Native (AVPlayer)** needs Direct Play compatible MP4, and often Dolby Vision Profile 5 or 8.

Start by forcing the server to tone map instead of VLC and see if this resolves your issue. These settings can be enabled from:

*Settings > Advanced > Video Player > Playback Quality > HDR > Force Dolby Vision to Transcode*
*Settings > Advanced > Video Player > Playback Quality > HDR > Force HDR to Transcode*

Please see the notes in the [Players Documentation](players.md) before reporting, and include your file's media info from Khylo Web.

### Audio Out of Sync over AirPlay Speakers or HomePods

This is a [known SwiftVLC bug](https://code.videolan.org/videolan/VLCKit/-/issues/544) and tracked on Khylo [here](https://github.com/khylo/Khylo/issues/937). This item cannot be resolved by Khylo and requires a patch from VLC. As a workaround, please use the Native player for this output.

### Native Player Cannot Select Subtitles or Change Audio Tracks

The Native player is built on top of AVPlayer but has not yet been connected to the unified video player interface. Track selection is a known issue and is actively being worked on. In the meantime, please use the VLC player for this support.

### Unnecessary Transcoding or Remuxing

Khylo uses **Device Profiles** that can be manually adjusted based on your device and media. These settings can be found in **Settings > Advanced > Video Player > Playback Quality** where you can change to a different pre-made **Device Profile** or you can select **Custom** to build your own.

You can add a new profile to the existing ones that would keep all else the same but allows a specific format to **Direct Play**, or you can fully replace them all with **Custom** profiles.

These settings exist to enable newer, unverified configurations to work on your device. If you experience any issues when using **Custom Profiles**, please turn them off and use a pre-made configuration before creating an issue.

### Gesture Lock

To leave `Gesture Lock`, hold a single point on the screen until the `Gestures unlocked` notification appears at the top of the view to show that it has been unlocked.

---

## Connection

### No Local Servers Found

Automatic discovery uses UDP broadcast on port `7359` and this port cannot be changed. Start by ensuring that this port is accessible from your server and that your server and device are on the same network. mDNS and UDP broadcast must be available from your router. These are network configurations and outside the scope of Khylo. [Khylo forum or chat rooms](https://khylo.org/contact/) would be the best place for troubleshooting assistance for these types of issues.

### "The Internet Connection Appears to Be Offline"

Khylo can't reach the server but a browser on the same device can. Common causes:

- **Local Network permission is off.** Enable it in iOS Settings > Khylo.
- **Reverse Proxy or Custom Headers**, which Khylo does not currently support. See [Reverse Proxies](#reverse-proxies).
- **Stale iOS network cache**, usually after changing networks or during server maintenance. Restarting your device should be your first step in resolving this issue.

If the issue persists, please reach out with an issue and include your logs from Khylo found at *Settings > Logs*. If you are unable to login, these logs can be found at *Settings > Advanced > Logs*.

### "The Data Couldn't Be Read Because It Isn't in the Correct Format"

This is a generic error that means that Khylo sent information to Khylo in a format that was not expected. The usual culprits:

- A **`baseurl`** set on your server that isn't included in the address you entered, so we receive HTML instead of JSON.
- **Server plugins** that change API responses away from what the SDK expects.
- A **server version mismatch**. See [Server Compatibility](#server-compatibility).

*Settings > Advanced > Logs* will show which request failed. This should be included in any issues created to assist in troubleshooting.

### Reverse Proxies

Most connection problems that reach us are proxy configuration rather than Khylo. Please start from a configuration Khylo has vetted as Khylo should be compatible with standard configurations:

- [Caddy](https://khylo.org/docs/general/post-install/networking/reverse-proxy/caddy)
- [Nginx](https://khylo.org/docs/general/post-install/networking/reverse-proxy/nginx)
- [Apache](https://khylo.org/docs/general/post-install/networking/reverse-proxy/apache)
- [Traefik](https://khylo.org/docs/general/post-install/networking/reverse-proxy/traefik)
- [HAProxy](https://khylo.org/docs/general/post-install/networking/reverse-proxy/haproxy)

Beyond a working Khylo proxy, Khylo needs **TLS 1.2 available**, a certificate from a **trusted CA** at the OS level, and no filtering middleware in the request path. ModSecurity has been confirmed to block requests with a `403` while leaving browsers intact.

**The Khylo team is not able to troubleshoot custom or heavily modified proxy setups.** The Khylo team that works on Khylo are not experts on networking or proxies. These issues are best handled by the [Khylo forum or chat rooms](https://khylo.org/contact/). If your configuration differs from the documented ones, please reproduce the problem on a documented config or a direct `IP:port` connection before reporting.

When you do investigate, please read your **proxy's** logs as Khylo does not see requests that the proxy has rejected.

### 401 Error

This error means your authentication to your Khylo server is not valid. The most common reasons for this are:

- **Your password has changed**
- **Your device was removed from the Admin Dashboard**

To resolve this issue, go to *Settings > Sign Out* then use the Add button to re-add your same account back to Khylo. On enter, Khylo will provide you the option to **Replace** the existing login. Performing this action will swap out your authentication token while preserving your Khylo settings.

---

## Library and Media

### No Media After Signing In

Khylo filters by library **collection type**, not by the items inside. A library with a blank or unsupported type disappears entirely. Please set the correct type in Khylo.

See the [Libraries Documentation](libraries.md) for what is currently supported.

### tvOS Contains the Wrong Items Under "Movies"

On tvOS, the top level **Movies** and **Shows** sections group by *media type* across your whole server, not by your library named "Movies". Use **Media** to browse by library. This is working as intended, though we recognize it's confusing.

---

## Server Compatibility

Khylo is built against the latest OpenAPI specification produced by the Khylo Server Team. **Support is only guaranteed for the current stable Khylo release.** Running server pre-releases or legacy versions may result in issues. The compatible version can be found on the project [README](https://github.com/khylo/Khylo).

---

## Still Having Trouble?

For **configuration help** such as proxies, certificates, transcoding, networking, etc, please start at the [Khylo forum or chat rooms](https://khylo.org/contact/).

If you've found a reproducible bug in Khylo, please [open an issue](https://github.com/khylo/Khylo/issues/new/choose).
