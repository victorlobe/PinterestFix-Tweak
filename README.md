<p align="center">
  <img width="120" height="120" alt="PinterestFixIcon" src="https://github.com/user-attachments/assets/0ed8cb9e-485f-473a-b8e4-47fb9dbc69ff" />
</p>

<h1 align="center">PinterestFix</h1>

<p align="center">
  An iOS tweak that keeps old Pinterest apps working on iOS 5+.
</p>

<p align="center">
  <a href="https://github.com/victorlobe/PinterestFix/releases/latest">
    <img alt="Download" src="https://img.shields.io/badge/download-latest-blue?logo=apple" />
  </a>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%205+-007AFF">
</p>

---

## Features

- Lets old Pinterest apps log in and talk to today's Pinterest API again
- Liking, unliking and saving pins work again
- Comments, Related pins and the list of people who liked a pin work again
- Fixes crashes in Pinterest 2.0.3
- Settings page in Settings.app:
  - **Hide promoted pins**
  - **Block tracking**
  - **Image loading fix** for devices without TLSFix
  - **App version** that PinterestFix reports to Pinterest (default: 14.42)
- Runs only inside Pinterest (finally)

## Compatibility

Works with Pinterest 2.0.3, 2.6.3 and 3.8.1, tested on iOS 5.1.1 and 6.1.2. Other versions in between will most likely work too. Pinterest 1.x is not supported because it uses an API that no longer exists.

The "Likes" tab on your profile stays empty, since Pinterest no longer keeps a list of liked pins.


## Requirements

- iOS 5 or newer
- Pinterest 2.0 or newer
- MobileSubstrate
- PreferenceLoader (for the settings page)
- Recommended: TLSFix (Skyglow repo) and the root certificates from tlsroot.litten.ca. Without TLSFix, turn on the image loading fix if pictures stay blank.

## Installation

1. **Add the repo** `repo.victorlobe.me` to Cydia
2. **Install PinterestFix**
3. **Restart Pinterest**

## Manual Installation

1. Download the `.deb` file
2. Install using `dpkg -i PinterestFix.deb`
3. Restart Pinterest

## Changelog

### v2.0.2
- This update fixes PinterestFix on iOS 5.

### v2.0.1
- Fixes an issue where Pinterest 3.8.1 could crash after entering four characters in the search field.

### v2
**New**
- Settings page in Settings.app
  - Hide promoted pins
  - Block tracking
  - Image loading fix for devices without TLSFix
  - App version: change the version PinterestFix reports to Pinterest, in case Pinterest asks you to update again
- "Related pins" working now
- Comments are working now
- The list of people who liked a pin works again

**Fixed**
- Liking and unliking pins works again
- Liked pins now show a filled heart and the correct like count
- Saving pins to boards works again
- Logging in works again
- Fixed a crash on the home feed after logging in (2.0.3)
- Fixed "API method not found" when opening a pin (2.0.3)
- Pictures no longer stay blank on devices without TLSFix when the image loading fix is turned on

**Changed**
- PinterestFix now only runs inside Pinterest. It no longer runs in SpringBoard or edit Pinterest's Info.plist, which fixes the safe mode and SpringBoard crashes some users had. Reinstalling or downgrading Pinterest no longer requires reinstalling the tweak or a respring.
- Pinterest now sees version 14.42
- Removed the update alert blocker, the alert no longer appears anyway

**Known limitations**
- Pinterest 1.x is not supported since it uses an API that no longer exists

### v1.0.2
- PinterestFix works again! Pinterest changed something on their end which broke the previous fix. In this version, the tweak modifies the version strings to empty strings instead of a specific version number.
- Update alerts are now automatically blocked.

### v1.0.1
- Fixed a bug that caused the SpringBoard to crash
- Fixed an issue where Pinterest sometimes wasn't patched

### v1.0.0
- Initial release

## Behind the Scenes

PinterestFix is loaded into Pinterest only. On launch it changes the app version in memory to a current one, so Pinterest's servers accept likes, saves and other actions again. The Info.plist on disk is never touched. Logins are sent with version 3.8.1, because Pinterest blocks password logins from clients that claim to be a modern app version.

Pinterest has retired or moved several endpoints the old apps use. PinterestFix redirects them to their current replacements:

- Likes: `pins/<id>/like/` → `pins/<id>/react/`
- People who liked a pin: `pins/<id>/likes/` → `pins/<id>/reactions/`
- Related pins: `pins/<id>/related/pin/` → `pins/<id>/related/modules/`
- Comments: `pins/<id>/comments/` → `aggregated_pin_data/<id>/comments/`

The API responses are then adjusted to what the old apps expect, for example the like status of a pin, comment authors, and removing new feed items the old apps can't display.

## Credits

This tweak is based on a manual fix tutorial that was originally shared in a Discord group. The method involved manually editing Pinterest's Info.plist file with iFile to change the version number. 
I DMed the creator, but he didn't respond. If he wants, I'll gladly mention him here.
Since v2, PinterestFix no longer edits the Info.plist and changes the version in memory instead.

## Author

Made with ❤️ by Victor Lobe

## License

MIT License – Free to use, share, and modify.
