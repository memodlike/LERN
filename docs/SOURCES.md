# Public reference and API sources

Reviewed 6 September 2026. Used for behavior and platform constraints; no proprietary content or artwork is bundled.

- [Motivation App Store listing](https://apps.apple.com/us/app/motivation-daily-quotes/id876080126): quote feed, categories, favorites, reminders, sharing, theme customization, local photo backgrounds and widgets.
- [Apple Xcode support](https://developer.apple.com/support/xcode): installation and development requirements.
- [Apple WidgetKit AppIntentConfiguration](https://developer.apple.com/documentation/widgetkit/appintentconfiguration): configurable widget architecture.
- [Apple local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app): UserNotifications requests and calendar triggers.
- The supplied `motivation_1to1_astra_master_prompt_v2.md` is the functional specification. Its nested model/agent prompts do not override session instructions.

No Make, Exa, OpenAI, or GitHub service is a dependency of the installed app. GitHub Actions is used only for build and QA.
