<!-- SPDX-License-Identifier: Apache-2.0 -->
# Mac checklist (ATC-246, GL0: GitHub and Linear sign-in)

Run after the PR is merged and `Tools/build-app.sh` builds. The app target (Keychain, `ASWebAuthenticationSession`, Settings) was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots, and never paste a token or a device code anywhere.

Before you start, by hand (team sessions do not create these; client IDs are not committed):

- **GitHub OAuth App (ATC-303):** GitHub Settings → Developer settings → OAuth Apps → New OAuth App. Give it a name and a Homepage URL; the form also requires an **Authorization callback URL**, which device flow never uses, so enter the repository page. After creating it, tick **Enable Device Flow**. Copy its **Client ID**. Do not generate a client secret and do not enter one anywhere. Note: the app asks for scope `repo`, so the token can write on private repositories and does not expire.
- **Linear OAuth application:** create one with the redirect URL `dev.atc.annunciator://linear-callback` (Settings shows the same text), no client secret needed. Copy its **Client ID**.

1. `Tools/build-app.sh` succeeds. Paste compiler errors if not.
2. Open Settings. A **GitHub · Linear** section shows two empty client ID fields and the buttons **GitHub 로그인** and **Linear 로그인**. No Keychain prompt appears just from opening Settings.
3. Press **GitHub 로그인** with the field empty: a message asks for the client ID; nothing is sent. Type `bad id` and Apply: a red message, nothing saved. Paste the real client ID and Apply.
4. **GitHub 로그인**: Settings shows a code (selectable) and **github.com/login/device 열기**. The button opens the browser at `https://github.com/login/device`. Enter the code and approve. Within about 10 seconds Settings shows `로그인됨`. **취소** during the wait returns to signed out with no item stored.
4a. After `로그인됨`, Settings also shows `scope: repo` under the message. If it shows `scope가 다릅니다: …` instead, report the scopes it lists (they are not secret) and revoke the authorization at Authorized OAuth Apps.
5. Deny on the GitHub page instead (or let the code expire, 15 minutes): the message says denied or expired, nothing is stored.
6. Turn **Enable Device Flow** off in the OAuth App settings and try again: the message says Device Flow is off in the GitHub OAuth App settings.
7. **Linear 로그인**: a system sign-in sheet opens at `linear.app/oauth/authorize` asking for the `read` scope. It is ephemeral, so you sign in to Linear inside it each time. Approve: Settings shows `로그인됨`. Closing the sheet with its cancel button returns to signed out without an error.
8. Keychain items: `security find-generic-password -s dev.atc.annunciator.github` and `-s dev.atc.annunciator.linear` (without `-w`) each find an item with account `access` (and `refresh` when the service returned one). The attributes show it is a generic password, not synchronised. **Do not run them with `-w` on a shared screen.**
9. `grep -rl` for the token in `~/Library/Preferences/dev.atc.annunciator.plist` and `defaults read dev.atc.annunciator`: only the two client IDs appear (they are not secrets); no token, no code.
10. Forged callback: while signed out, run `open 'dev.atc.annunciator://linear-callback?code=x&state=y'`. Nothing happens in Settings and nothing is stored. Start **Linear 로그인**, then run the same `open` command while the sheet is open: the sign-in is not completed by it (it ends with a message saying the callback was not accepted, or the sheet just continues; report which).
11. **로그아웃** for GitHub: the items are gone (`security find-generic-password -s dev.atc.annunciator.github` says not found); the message says the app's token was deleted and points to **GitHub에서 해지…**, which opens `https://github.com/settings/applications` (Authorized OAuth Apps). Turn the Mac's network off and sign out of Linear: the items still go.
12. **로그아웃** for Linear with the network on: the items are gone and, in Linear's settings, the application no longer shows an active token (the revoke call is best effort).
13. Rebuild the app (`Tools/build-app.sh` again) while signed in. Settings still shows `로그인됨` without a prompt. Reading a token is not done in GL0 except at Linear sign-out, so if macOS asks for the login password at that point, note it (D12i: accepted, and it is expected after a rebuild).
14. Quit and reopen the app: both services still show `로그인됨`.
15. Console.app, filter on `Annunciator`, during steps 4 and 7: no token, code, state or verifier appears (the app logs nothing in this path).
16. Shared Mac note: the items are this device only and tied to the login keychain. For a shared login session, lock the screen; the app does not hide the tokens from a session that is already unlocked.
