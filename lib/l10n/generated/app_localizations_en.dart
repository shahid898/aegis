// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Aegis';

  @override
  String get splashTagline => 'Ready when the grid is not.';

  @override
  String get actionStart => 'Start';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionSkipForNow => 'Skip for now';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionResume => 'Resume';

  @override
  String get actionAllow => 'Allow';

  @override
  String get actionOpenSettings => 'Open settings';

  @override
  String get actionAllowed => 'Allowed';

  @override
  String get readyTitle => 'You\'re ready.';

  @override
  String get readyBody =>
      'Tap the icon anytime to ask Aegis a question. It works without internet.';

  @override
  String get languageTitle => 'Choose your language';

  @override
  String languageDetected(String language) {
    return 'We detected $language. Confirm or pick another.';
  }

  @override
  String get languageSearchHint => 'Search 140 languages';

  @override
  String get languageHearSample => 'Hear sample';

  @override
  String languageContinueIn(String language) {
    return 'Continue in $language';
  }

  @override
  String get regionTitle => 'Pick your region';

  @override
  String get regionUseGps => 'Use GPS';

  @override
  String get regionLocating => 'Locating...';

  @override
  String get regionTapHint => 'Tap the map to select your district';

  @override
  String get regionDownloadCta => 'Download data for this region';

  @override
  String get regionLabelCurrent => 'Current location';

  @override
  String regionLabelCurrentWithCountry(String country) {
    return 'Current location ($country)';
  }

  @override
  String get regionLabelSelected => 'Selected area';

  @override
  String regionLabelSelectedWithCountry(String country) {
    return 'Selected area ($country)';
  }

  @override
  String get regionErrorServiceOff => 'Turn on location services to use GPS.';

  @override
  String get regionErrorPermissionDenied => 'Location permission denied.';

  @override
  String regionErrorReadFailed(String error) {
    return 'Could not read location: $error';
  }

  @override
  String get downloadTitle => 'Prepare for offline use';

  @override
  String get downloadHeading => 'Downloading offline data';

  @override
  String get downloadBody =>
      'Aegis works fully offline after this one-time download — voice models, your region\'s nearby places, and map tiles.';

  @override
  String downloadPercentComplete(String percent) {
    return '$percent% complete';
  }

  @override
  String get downloadPackInstalled => 'Installed';

  @override
  String downloadPackPending(String sizeMb) {
    return '$sizeMb MB • pending';
  }

  @override
  String downloadPackProgress(String receivedMb, String sizeMb) {
    return '$receivedMb / $sizeMb MB';
  }

  @override
  String get downloadVerifying => 'Verifying…';

  @override
  String get downloadExtracting => 'Extracting…';

  @override
  String get downloadFailed => 'Download failed.';

  @override
  String get downloadFirstInstallNote =>
      'First install takes 5–10 minutes on a good connection. The download continues in the background — you can lock the screen, but stay on Wi-Fi for best speed.';

  @override
  String get downloadAllRequired =>
      'Aegis needs every pack on-device to work offline in an emergency. You can\'t skip this step.';

  @override
  String get downloadCheckConnection =>
      'Check your connection and try again. The download will resume from where it stopped.';

  @override
  String get accessibilityTitle => 'A few questions';

  @override
  String get accessibilityBody =>
      'Your answers shape how Aegis routes you in an emergency. Answers stay on this device.';

  @override
  String get accessibilityQuestionWheelchair => 'Do you use a wheelchair?';

  @override
  String get accessibilityQuestionMedication => 'Do you take daily medication?';

  @override
  String get accessibilityQuestionDependent =>
      'Is there someone in your home who needs special help (child, elderly, disabled)?';

  @override
  String get accessibilityYes => 'Yes';

  @override
  String get accessibilityNo => 'No';

  @override
  String get contactsTitle => 'Emergency contacts';

  @override
  String get contactsBody =>
      'Up to 5. We forward briefings and beacon alerts to these people. Stored only on this device.';

  @override
  String get contactsEmpty => 'No contacts yet';

  @override
  String get contactsAdd => 'Add contact';

  @override
  String contactsAddWithCount(int count, int max) {
    return 'Add contact ($count/$max)';
  }

  @override
  String get contactsName => 'Name';

  @override
  String get contactsPhone => 'Phone';

  @override
  String get contactsPreferredLanguage => 'Preferred language';

  @override
  String get contactsSave => 'Save contact';

  @override
  String get permissionsTitle => 'Permissions';

  @override
  String get permissionMicrophoneTitle => 'Microphone';

  @override
  String get permissionMicrophoneBody =>
      'Needed to hear your question and transcribe it on-device.';

  @override
  String get permissionCameraTitle => 'Camera';

  @override
  String get permissionCameraBody =>
      'Needed to scan wounds, medicine labels, and surroundings offline.';

  @override
  String get permissionLocationTitle => 'Location';

  @override
  String get permissionLocationBody =>
      'Needed to recommend routes and nearby shelters in your area.';

  @override
  String get permissionNotificationsTitle => 'Notifications';

  @override
  String get permissionNotificationsBody =>
      'Needed to deliver emergency briefings and beacon alerts.';

  @override
  String get homeSubtitle => 'Offline. Ready.';

  @override
  String get homeEmptyState =>
      'Tap the button below to start a\nconversation with Aegis.';

  @override
  String get homeStartTriage => 'Start triage';

  @override
  String get homeReports => 'Reports';

  @override
  String get homeTakePhoto => 'Take a photo';

  @override
  String get homePickFromGallery => 'Pick from gallery';

  @override
  String get homeSave => 'Save';

  @override
  String get homeVoiceDegraded =>
      'Voice models are not installed. You can still use SOS.';

  @override
  String get homeSomethingWentWrong => 'Something went wrong.';

  @override
  String get homeEnginePreparing =>
      'Preparing AI engine — first time takes about 30 seconds. You can start talking; the first reply may be slow.';

  @override
  String get homeNoEmergencyContact =>
      'No emergency contact saved. Add one in settings.';

  @override
  String homeCouldNotDial(String phone) {
    return 'Could not open dialer for $phone.';
  }

  @override
  String get stageIdle => 'Tap to start · long-press for SOS';

  @override
  String get stagePreparing => 'Getting ready…';

  @override
  String get stageListening => 'Listening… tap to stop';

  @override
  String get stageTranscribing => 'Transcribing…';

  @override
  String get stageThinking => 'Thinking… tap to interrupt';

  @override
  String get stageSpeaking => 'Aegis is speaking · tap to stop';

  @override
  String get stageAwaitingConfirmation =>
      'Review the card above · confirm or reject';

  @override
  String get stageDegraded => 'Voice disabled — tap SOS';

  @override
  String get stageError => 'Tap to retry';

  @override
  String get thinkingReadingEvidence => 'Reading your evidence…';

  @override
  String get thinkingLookingAtImage => 'Looking at the image and audio…';

  @override
  String get thinkingDraftingReport => 'Drafting the report…';

  @override
  String get thinkingStillWorking => 'Still working — this can take a minute.';

  @override
  String get thinkingFinalisingReport =>
      'Almost there — finalising the report.';

  @override
  String get thinkingGeneric => 'Thinking…';

  @override
  String get thinkingComposingReply => 'Composing a reply…';

  @override
  String get thinkingStillThinking =>
      'Still thinking — first reply takes a moment.';

  @override
  String get thinkingFinalisingReply => 'Almost there — finalising the reply.';

  @override
  String get reportsTitle => 'Triage Reports';

  @override
  String get reportsEmpty => 'No reports yet.';

  @override
  String get reportsEmptyHint =>
      'Tap \"Start triage\" on the home screen to draft one.';

  @override
  String get reportsDetailTitle => 'Report';

  @override
  String get reportsDelete => 'Delete report?';

  @override
  String get reportsDeleteBody =>
      'This removes the report from the archive. Cannot be undone.';

  @override
  String get reportsCancel => 'Cancel';

  @override
  String get reportsDeleteAction => 'Delete';

  @override
  String get reportsNoInputText => '(no input text)';

  @override
  String get reportsYouEvidenceOnly =>
      'You: (no spoken text — evidence attached)';

  @override
  String reportsYouQuote(String text) {
    return 'You: \"$text\"';
  }

  @override
  String get reportsLegacy => '(legacy report — no structured payload)';

  @override
  String get reportsDescribeScene => 'Describe the scene';

  @override
  String get reportsDescribeHint =>
      'eg. \"Two-storey house, partial roof collapse, one elderly woman trapped near the front door\"';

  @override
  String homePhotoCaptureFailed(String error) {
    return 'Photo capture failed: $error';
  }
}
