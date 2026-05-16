// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'Aegis';

  @override
  String get splashTagline => 'जब ग्रिड न हो, तब भी तैयार।';

  @override
  String get actionStart => 'शुरू करें';

  @override
  String get actionContinue => 'जारी रखें';

  @override
  String get actionSkip => 'छोड़ें';

  @override
  String get actionSkipForNow => 'अभी छोड़ें';

  @override
  String get actionRetry => 'पुनः प्रयास करें';

  @override
  String get actionSave => 'सहेजें';

  @override
  String get actionCancel => 'रद्द करें';

  @override
  String get actionResume => 'जारी रखें';

  @override
  String get actionAllow => 'अनुमति दें';

  @override
  String get actionOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get actionAllowed => 'अनुमत';

  @override
  String get readyTitle => 'आप तैयार हैं।';

  @override
  String get readyBody =>
      'Aegis से कुछ पूछने के लिए कभी भी आइकन दबाएँ। यह बिना इंटरनेट के काम करता है।';

  @override
  String get languageTitle => 'अपनी भाषा चुनें';

  @override
  String languageDetected(String language) {
    return 'हमने $language का पता लगाया। पुष्टि करें या दूसरी चुनें।';
  }

  @override
  String get languageSearchHint => '140 भाषाओं में खोजें';

  @override
  String get languageHearSample => 'नमूना सुनें';

  @override
  String languageContinueIn(String language) {
    return '$language में जारी रखें';
  }

  @override
  String get regionTitle => 'अपना क्षेत्र चुनें';

  @override
  String get regionUseGps => 'GPS का उपयोग करें';

  @override
  String get regionLocating => 'स्थान खोजा जा रहा है...';

  @override
  String get regionTapHint => 'अपना ज़िला चुनने के लिए नक़्शे पर टैप करें';

  @override
  String get regionDownloadCta => 'इस क्षेत्र के लिए डेटा डाउनलोड करें';

  @override
  String get downloadTitle => 'ऑफ़लाइन आवाज़ तैयार करें';

  @override
  String get downloadHeading => 'आवाज़ मॉडल डाउनलोड हो रहे हैं';

  @override
  String get downloadBody =>
      'इस एक बार के डाउनलोड के बाद Aegis पूरी तरह ऑफ़लाइन काम करता है। आप छोड़कर केवल-टेक्स्ट मोड में चला सकते हैं।';

  @override
  String downloadPercentComplete(String percent) {
    return '$percent% पूर्ण';
  }

  @override
  String get downloadPackInstalled => 'इंस्टॉल किया गया';

  @override
  String downloadPackPending(String sizeMb) {
    return '$sizeMb MB • प्रतीक्षारत';
  }

  @override
  String downloadPackProgress(String receivedMb, String sizeMb) {
    return '$receivedMb / $sizeMb MB';
  }

  @override
  String get downloadVerifying => 'सत्यापित किया जा रहा है…';

  @override
  String get downloadExtracting => 'निकाला जा रहा है…';

  @override
  String get downloadFailed => 'डाउनलोड विफल।';

  @override
  String get accessibilityTitle => 'कुछ प्रश्न';

  @override
  String get accessibilityBody =>
      'आपके उत्तर तय करते हैं कि आपातकाल में Aegis आपको कैसे मार्गदर्शन करता है। उत्तर केवल इस डिवाइस पर रहते हैं।';

  @override
  String get accessibilityQuestionWheelchair =>
      'क्या आप व्हीलचेयर का उपयोग करते हैं?';

  @override
  String get accessibilityQuestionMedication => 'क्या आप रोज़ दवा लेते हैं?';

  @override
  String get accessibilityQuestionDependent =>
      'क्या आपके घर में कोई है जिसे विशेष सहायता चाहिए (बच्चा, बुज़ुर्ग, विकलांग)?';

  @override
  String get accessibilityYes => 'हाँ';

  @override
  String get accessibilityNo => 'नहीं';

  @override
  String get contactsTitle => 'आपातकालीन संपर्क';

  @override
  String get contactsBody =>
      'अधिकतम 5। हम इन लोगों को ब्रीफिंग और बीकन अलर्ट भेजते हैं। केवल इस डिवाइस पर संग्रहित।';

  @override
  String get contactsEmpty => 'अभी कोई संपर्क नहीं';

  @override
  String get contactsAdd => 'संपर्क जोड़ें';

  @override
  String contactsAddWithCount(int count, int max) {
    return 'संपर्क जोड़ें ($count/$max)';
  }

  @override
  String get contactsName => 'नाम';

  @override
  String get contactsPhone => 'फ़ोन';

  @override
  String get contactsPreferredLanguage => 'पसंदीदा भाषा';

  @override
  String get contactsSave => 'संपर्क सहेजें';

  @override
  String get permissionsTitle => 'अनुमतियाँ';

  @override
  String get permissionMicrophoneTitle => 'माइक्रोफ़ोन';

  @override
  String get permissionMicrophoneBody =>
      'आपका प्रश्न सुनने और डिवाइस पर लिप्यंतरण के लिए ज़रूरी।';

  @override
  String get permissionCameraTitle => 'कैमरा';

  @override
  String get permissionCameraBody =>
      'घावों, दवा के लेबल और आसपास के दृश्यों को ऑफ़लाइन स्कैन करने के लिए ज़रूरी।';

  @override
  String get permissionLocationTitle => 'स्थान';

  @override
  String get permissionLocationBody =>
      'आपके क्षेत्र में मार्ग और निकट के आश्रय सुझाने के लिए ज़रूरी।';

  @override
  String get permissionNotificationsTitle => 'सूचनाएँ';

  @override
  String get permissionNotificationsBody =>
      'आपातकालीन ब्रीफिंग और बीकन अलर्ट देने के लिए ज़रूरी।';
}
