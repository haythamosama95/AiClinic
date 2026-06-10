# Auth presentation UI tests

Widget tests for the auth presentation layer (`LoginPage`, `LoginModal`, and related flows).

**Run:** `flutter test test/widget/auth/`

**Source files:**

| File                                                       | Scope                                                                        |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `frontend/test/widget/auth/login_modal_test.dart`          | Layout, validation, password visibility, loading, errors, animations, dialog |
| `frontend/test/widget/auth/forgot_password_page_test.dart` | Administrator-mediated forgot-password flow                                  |
| `frontend/test/widget/auth/login_page_test.dart`           | `LoginPage` Riverpod / GoRouter integration                                  |
| `frontend/test/widget/auth/login_modal_test_support.dart`  | Shared pump helpers and panel finders                                        |

---

## LoginModal layout

| Test Name                                    | Scenario                            | Pass Criteria                                                                                                                            | Fail Criteria                                     |
| -------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `renders branding panel and credential form` | Login modal opens on a wide surface | Branding title, illustration placeholder, username/password fields, Login button, Forgot Password link, and Close button are all visible | Any expected label or control is missing          |
| `uses side-by-side layout on wide surfaces`  | Viewport width ≥ 720 px             | `IntrinsicHeight` + `Row` layout is used (branding beside form)                                                                          | Compact stacked layout is used instead            |
| `uses stacked layout on compact surfaces`    | Viewport width &lt; 720 px          | Scrollable column layout; no side-by-side `IntrinsicHeight` row                                                                          | Wide two-column layout appears on a narrow screen |

## LoginModal form validation

| Test Name                                                  | Scenario                                                   | Pass Criteria                                                                   | Fail Criteria                                                 |
| ---------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `empty submit shows username and password required errors` | User taps Login with empty fields                          | `Username is required.` and `This field is required` validation messages appear | Submit proceeds or no validation feedback is shown            |
| `invalid short username shows validation error`            | Username shorter than 3 characters with a password entered | `Enter a valid username.` is shown                                              | Invalid username is accepted or wrong message appears         |
| `username containing @ shows validation error`             | Username contains `@` (email-style input)                  | `Enter a valid username.` is shown                                              | Email-style username is accepted                              |
| `invalid username characters show pattern error`           | Username contains spaces or other disallowed characters    | `Username may use letters, numbers, underscore, and hyphen.` is shown           | Invalid pattern is accepted or wrong message appears          |
| `enter in password field submits login`                    | Valid credentials entered; user presses Enter in password  | `onSubmit` receives username and password (same as tapping Login)               | Enter does nothing or credentials not submitted               |
| `valid credentials invoke onSubmit with trimmed username`  | Valid username and password submitted                      | `onSubmit` receives trimmed username (`Staff_One`) and raw password             | Callback not fired, username not trimmed, or password altered |

## LoginModal password visibility

| Test Name                                   | Scenario                                | Pass Criteria                                                         | Fail Criteria                              |
| ------------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------ |
| `password is obscured by default`           | Modal loads                             | Password field has `obscureText: true`; Show password tooltip visible | Password visible in plain text on load     |
| `toggle reveals password and swaps tooltip` | User taps Show password                 | `obscureText` becomes false; Hide password tooltip appears            | Password stays hidden or tooltip unchanged |
| `close button restores obscured password`   | User reveals password then closes modal | After close, password field returns to obscured state                 | Password remains visible after close       |

## LoginModal submit and loading

| Test Name                                                 | Scenario                                                   | Pass Criteria                                                            | Fail Criteria                                            |
| --------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------- |
| `submit hides forgot password info panel`                 | Forgot-password panel open; user submits valid credentials | Recovery info panel is hidden on submit                                  | Forgot-password copy remains visible after login attempt |
| `isSubmitting shows loading indicator and disables login` | `isSubmitting: true` passed to modal                       | `FCircularProgress` visible; Login button loading with `onPressed: null` | No spinner, or button remains tappable during submit     |

## LoginModal sign-in error panel

| Test Name                                                    | Scenario                                                      | Pass Criteria                                                                            | Fail Criteria                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `error message renders destructive alert below login button` | `errorMessage` set to generic sign-in failure                 | Error text visible in status panel below Login button                                    | Error missing or rendered above the button             |
| `error panel fades in to full opacity`                       | Error message appears after successful form validation submit | `FadeTransition` exists mid-animation with opacity between 0 and 1; settles at opacity 1 | No fade animation, or panel never reaches full opacity |

## LoginModal animations

| Test Name                                               | Scenario                                     | Pass Criteria                                                                | Fail Criteria                                            |
| ------------------------------------------------------- | -------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------- |
| `forgot password panel fades in during open transition` | User taps Forgot Password?                   | Mid-animation opacity is between 0 and 1; final opacity is 1                 | Panel appears instantly with no fade, or stays invisible |
| `forgot password panel fades out before removal`        | Panel open; user taps Forgot Password? again | Mid-animation opacity between 0 and 1; `FadeTransition` removed after settle | Panel disappears instantly or remains in tree            |
| `animated size grows modal while forgot panel opens`    | User opens forgot-password panel             | Modal height increases during animation and after settle                     | Modal height unchanged when panel opens                  |

## LoginModal.show dialog

| Test Name                                    | Scenario                                       | Pass Criteria                                          | Fail Criteria                         |
| -------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------ | ------------------------------------- |
| `presents centered dialog with dimmed scrim` | `LoginModal.show()` invoked from a host screen | `Dialog`, `LoginModal`, and `ModalBarrier` are present | Modal not shown or no scrim           |
| `close button dismisses dialog`              | Dialog open; user taps Close                   | `LoginModal` removed from tree                         | Dialog remains open                   |
| `barrier tap dismisses dialog`               | Dialog open; user taps outside on scrim        | `LoginModal` removed from tree                         | Dialog remains open after barrier tap |

## LoginModal forgot password

| Test Name                                                                      | Scenario                                                                | Pass Criteria                                                                                                                          | Fail Criteria                                                               |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `shows administrator-mediated recovery message only after forgot password tap` | Modal loads, then user taps Forgot Password?                            | No recovery text before tap; after tap, admin-mediated copy visible with `FadeTransition` at opacity 1; no self-service reset controls | Recovery shown on load, missing after tap, or self-service reset UI present |
| `does not show sign-in error alert before failed login`                        | Fresh modal with no prior sign-in attempt                               | No error text containing `incorrect` in status panel                                                                                   | Error alert visible before any login failure                                |
| `stupid user cannot find email field or submit reset`                          | Forgot-password panel open                                              | No email field, Submit button, or Reset password button                                                                                | Self-service password reset UI is exposed                                   |
| `showing forgot password panel grows modal and shifts form upward`             | Toggle forgot-password panel open then closed                           | Modal grows and Login button moves up when open; returns to original size/position when closed                                         | No layout change, or layout does not restore on close                       |
| `forgot password info appears below login button`                              | Forgot-password panel open                                              | Recovery panel top edge is below Login button                                                                                          | Recovery copy overlaps or appears above the button                          |
| `page explains administrators reset passwords from settings staff`             | Forgot-password panel open                                              | Copy mentions Settings, Staff, Reset password, and owner/administrator                                                                 | Required administrator guidance missing                                     |
| `initialShowForgotPasswordInfo opens panel without tapping link`               | Modal built with `initialShowForgotPasswordInfo: true`                  | Recovery panel visible immediately                                                                                                     | User must tap Forgot Password? to see guidance                              |
| `opening forgot password dismisses sign-in error permanently`                  | Sign-in error shown; user opens then closes forgot-password panel       | `onDismissSignInError` called once; error replaced by recovery copy, then both hidden; error does not return                           | Error persists, callback not fired, or error reappears after closing panel  |
| `close button resets modal and clears parent sign-in error`                    | Fields filled, forgot panel open, parent holds error state; user closes | `onClose` fired; fields cleared; error and recovery panels hidden                                                                      | Form state, error, or recovery copy survives close                          |
| `corner case: panel is visible on narrow width`                                | 320 px wide viewport with `initialShowForgotPasswordInfo: true`         | Recovery panel visible in compact layout                                                                                               | Panel clipped, missing, or broken on narrow screens                         |

## LoginPage integration

| Test Name                                                | Scenario                                                                         | Pass Criteria                                             | Fail Criteria                                     |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------- |
| `renders LoginModal on the login route`                  | Navigate to `/login` with test router                                            | `LoginPage` and `LoginModal` present; Login copy visible  | Login route renders wrong widget or missing modal |
| `displays auth notifier error message`                   | `AuthNotifier` sets generic sign-in failure                                      | Error text containing `incorrect` visible in status panel | Notifier error not surfaced in UI                 |
| `displays session failure when not submitting`           | Session has `failureMessage` and form is idle                                    | `Unable to sign in right now` copy visible                | Session failure hidden while idle                 |
| `hides session failure while submitting`                 | Session failure set, then `isSubmitting` becomes true                            | Session failure copy hidden during submit                 | Stale session error shown over loading state      |
| `forgot query parameter opens recovery panel on load`    | Route `/login?forgot=1`                                                          | Administrator-mediated recovery panel visible on load     | Query param ignored; panel not auto-opened        |
| `close navigates to startup entry when stack cannot pop` | Login is initial route; user taps Close                                          | Navigates to Startup Entry; modal gone                    | Wrong destination or modal remains                |
| `close pops when login was pushed onto stack`            | Login pushed from Startup Entry; user taps Close                                 | Returns to Startup Entry without modal                    | Stack not popped or wrong screen shown            |
| `successful sign-in navigates to bootstrap`              | Submitting transitions to success (`isSubmitting: true` → cleared with no error) | Router navigates to Bootstrap screen                      | Stays on login or navigates elsewhere             |
| `close clears displayed sign-in error`                   | Error shown; user closes then re-opens login                                     | After re-open, no error text in status panel              | Error persists across close/reset cycle           |
