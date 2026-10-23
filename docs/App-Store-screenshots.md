# App Store screenshots

What to capture, and why each one is there. Apple requires 6.9" and 6.5"
iPhone sizes and a 13" iPad size; everything else is generated from those.

Shoot against a library with real covers. A screenshot of an empty shelf sells
nothing, and a screenshot of obviously fake books reads as a mock-up.

| # | Screen | What it has to show | Caption |
| --- | --- | --- | --- |
| 1 | Home, mid-book | The Continue hero with a real cover and a part-filled bar | "Pick up exactly where you left off." |
| 2 | Player | Cover-tinted player, chapter name, chapter-marked scrubber | "A player that knows about chapters." |
| 3 | Conflict prompt | Both positions, both device names | "It asks before it moves your place." |
| 4 | Library grid | A dense wall of covers | "Your whole library, on your own server." |
| 5 | Reader | A real page, sepia, with a highlight | "Read like a Kindle." |
| 6 | Downloads / offline | Storage screen with downloads, airplane mode on | "Works with no signal at all." |
| 7 | Widgets | Home screen with Continue and the streak widget | "On your home screen and your lock screen." |
| 8 (iPad) | Sidebar + player | Split layout with the sidebar showing | "At home on iPad." |

## Rules

- **No invented data.** Use a real server with real books. If a book's cover
  cannot be shown for licensing reasons, choose a different book.
- **Dark mode for the player, light for the library.** It shows both without a
  caption having to say so.
- **Show the offline state deliberately** in shot 6 — it is a feature here, not
  a failure, and it is the single thing that most distinguishes Firelight from
  a web client.
- **No device frames with notches cropped oddly.** Use Apple's own frames.

## Before submitting

- Privacy label: **Data Not Collected**. `App/PrivacyInfo.xcprivacy` is the
  machine-readable version; they must agree.
- The UnRAR copyright notice must appear in the App Store description's
  acknowledgements, as `README.md` carries it.
- Tip products must exist in App Store Connect with the identifiers in
  `App/Firelight.storekit`.
