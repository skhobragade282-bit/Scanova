# StoreKit Testing

This project includes a local StoreKit configuration file at [Scanova.storekit](/Users/salonikhobragade/Documents/Scanova/Scanova.storekit).

It defines the current Scanova Pro subscriptions:
- `com.scanova.pro.monthly`
- `com.scanova.pro.yearly`

It also configures a 7-day free trial on the annual plan only.

## Hook It Up In Xcode

1. Open the project in Xcode.
2. Choose `Product` -> `Scheme` -> `Edit Scheme...`
3. Select `Run`.
4. Open the `Options` tab.
5. Set `StoreKit Configuration` to `Scanova.storekit`.

Because the project does not currently commit a shared scheme file, this selection is made in Xcode locally.

## Test Scenarios

### Trial Eligible

1. Run the app with `Scanova.storekit` selected.
2. Open the paywall.
3. Confirm the annual plan is selected by default.
4. Expected:
   - annual shows the trial badge
   - CTA reads `Start Free Trial`

### Trial Ineligible

1. With the app still running under the StoreKit config, buy the annual subscription once.
2. In Xcode, open `Debug` -> `StoreKit` -> `Manage Transactions`.
3. Keep the prior transaction history so the user stays ineligible for the intro offer.
4. Relaunch or reopen the paywall.
5. Expected:
   - annual can remain selected
   - CTA reads `Continue with Pro`
   - trial-specific messaging no longer leads the purchase flow

## Resetting Back To Eligible

In `Debug` -> `StoreKit` -> `Manage Transactions`, clear the local transaction history for the StoreKit test session, then relaunch the app.

## Notes

- Local StoreKit testing is best for UI and purchase-flow validation.
- Sandbox test accounts are still useful for end-to-end App Store behavior.
- The app now uses StoreKit intro-offer eligibility for the annual CTA, so the local config is helpful for checking both paths quickly.
