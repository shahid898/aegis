import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// Application name. Do not translate.
  ///
  /// In en, this message translates to:
  /// **'Aegis'**
  String get appName;

  /// Tagline shown on the splash screen.
  ///
  /// In en, this message translates to:
  /// **'Ready when the grid is not.'**
  String get splashTagline;

  /// No description provided for @actionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get actionStart;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionSkipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get actionSkipForNow;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// No description provided for @actionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get actionAllow;

  /// No description provided for @actionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get actionOpenSettings;

  /// No description provided for @actionAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get actionAllowed;

  /// No description provided for @readyTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re ready.'**
  String get readyTitle;

  /// No description provided for @readyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the icon anytime to ask Aegis a question. It works without internet.'**
  String get readyBody;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get languageTitle;

  /// Inline hint after auto-detecting the device language.
  ///
  /// In en, this message translates to:
  /// **'We detected {language}. Confirm or pick another.'**
  String languageDetected(String language);

  /// No description provided for @languageSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search 140 languages'**
  String get languageSearchHint;

  /// No description provided for @languageHearSample.
  ///
  /// In en, this message translates to:
  /// **'Hear sample'**
  String get languageHearSample;

  /// No description provided for @languageContinueIn.
  ///
  /// In en, this message translates to:
  /// **'Continue in {language}'**
  String languageContinueIn(String language);

  /// No description provided for @regionTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick your region'**
  String get regionTitle;

  /// No description provided for @regionUseGps.
  ///
  /// In en, this message translates to:
  /// **'Use GPS'**
  String get regionUseGps;

  /// No description provided for @regionLocating.
  ///
  /// In en, this message translates to:
  /// **'Locating...'**
  String get regionLocating;

  /// No description provided for @regionTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to select your district'**
  String get regionTapHint;

  /// No description provided for @regionDownloadCta.
  ///
  /// In en, this message translates to:
  /// **'Download data for this region'**
  String get regionDownloadCta;

  /// No description provided for @downloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Prepare offline voice'**
  String get downloadTitle;

  /// No description provided for @downloadHeading.
  ///
  /// In en, this message translates to:
  /// **'Downloading voice models'**
  String get downloadHeading;

  /// No description provided for @downloadBody.
  ///
  /// In en, this message translates to:
  /// **'Aegis works fully offline after this one-time download. You can skip and run in text-only mode.'**
  String get downloadBody;

  /// No description provided for @downloadPercentComplete.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String downloadPercentComplete(String percent);

  /// No description provided for @downloadPackInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get downloadPackInstalled;

  /// No description provided for @downloadPackPending.
  ///
  /// In en, this message translates to:
  /// **'{sizeMb} MB • pending'**
  String downloadPackPending(String sizeMb);

  /// No description provided for @downloadPackProgress.
  ///
  /// In en, this message translates to:
  /// **'{receivedMb} / {sizeMb} MB'**
  String downloadPackProgress(String receivedMb, String sizeMb);

  /// No description provided for @downloadVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get downloadVerifying;

  /// No description provided for @downloadExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get downloadExtracting;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed.'**
  String get downloadFailed;

  /// No description provided for @accessibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'A few questions'**
  String get accessibilityTitle;

  /// No description provided for @accessibilityBody.
  ///
  /// In en, this message translates to:
  /// **'Your answers shape how Aegis routes you in an emergency. Answers stay on this device.'**
  String get accessibilityBody;

  /// No description provided for @accessibilityQuestionWheelchair.
  ///
  /// In en, this message translates to:
  /// **'Do you use a wheelchair?'**
  String get accessibilityQuestionWheelchair;

  /// No description provided for @accessibilityQuestionMedication.
  ///
  /// In en, this message translates to:
  /// **'Do you take daily medication?'**
  String get accessibilityQuestionMedication;

  /// No description provided for @accessibilityQuestionDependent.
  ///
  /// In en, this message translates to:
  /// **'Is there someone in your home who needs special help (child, elderly, disabled)?'**
  String get accessibilityQuestionDependent;

  /// No description provided for @accessibilityYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get accessibilityYes;

  /// No description provided for @accessibilityNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get accessibilityNo;

  /// No description provided for @contactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency contacts'**
  String get contactsTitle;

  /// No description provided for @contactsBody.
  ///
  /// In en, this message translates to:
  /// **'Up to 5. We forward briefings and beacon alerts to these people. Stored only on this device.'**
  String get contactsBody;

  /// No description provided for @contactsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get contactsEmpty;

  /// No description provided for @contactsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get contactsAdd;

  /// No description provided for @contactsAddWithCount.
  ///
  /// In en, this message translates to:
  /// **'Add contact ({count}/{max})'**
  String contactsAddWithCount(int count, int max);

  /// No description provided for @contactsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get contactsName;

  /// No description provided for @contactsPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get contactsPhone;

  /// No description provided for @contactsPreferredLanguage.
  ///
  /// In en, this message translates to:
  /// **'Preferred language'**
  String get contactsPreferredLanguage;

  /// No description provided for @contactsSave.
  ///
  /// In en, this message translates to:
  /// **'Save contact'**
  String get contactsSave;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsTitle;

  /// No description provided for @permissionMicrophoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permissionMicrophoneTitle;

  /// No description provided for @permissionMicrophoneBody.
  ///
  /// In en, this message translates to:
  /// **'Needed to hear your question and transcribe it on-device.'**
  String get permissionMicrophoneBody;

  /// No description provided for @permissionCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permissionCameraTitle;

  /// No description provided for @permissionCameraBody.
  ///
  /// In en, this message translates to:
  /// **'Needed to scan wounds, medicine labels, and surroundings offline.'**
  String get permissionCameraBody;

  /// No description provided for @permissionLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get permissionLocationTitle;

  /// No description provided for @permissionLocationBody.
  ///
  /// In en, this message translates to:
  /// **'Needed to recommend routes and nearby shelters in your area.'**
  String get permissionLocationBody;

  /// No description provided for @permissionNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permissionNotificationsTitle;

  /// No description provided for @permissionNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'Needed to deliver emergency briefings and beacon alerts.'**
  String get permissionNotificationsBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
