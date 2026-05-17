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
  String get regionLabelCurrent => 'वर्तमान स्थान';

  @override
  String regionLabelCurrentWithCountry(String country) {
    return 'वर्तमान स्थान ($country)';
  }

  @override
  String get regionLabelSelected => 'चयनित क्षेत्र';

  @override
  String regionLabelSelectedWithCountry(String country) {
    return 'चयनित क्षेत्र ($country)';
  }

  @override
  String get regionErrorServiceOff =>
      'GPS उपयोग के लिए स्थान सेवाएँ चालू करें।';

  @override
  String get regionErrorPermissionDenied => 'स्थान अनुमति अस्वीकृत।';

  @override
  String regionErrorReadFailed(String error) {
    return 'स्थान नहीं पढ़ सका: $error';
  }

  @override
  String get downloadTitle => 'ऑफ़लाइन उपयोग के लिए तैयार करें';

  @override
  String get downloadHeading => 'ऑफ़लाइन डेटा डाउनलोड हो रहा है';

  @override
  String get downloadBody =>
      'इस एक बार के डाउनलोड के बाद Aegis पूरी तरह ऑफ़लाइन काम करता है — आवाज़ मॉडल, आपके क्षेत्र के निकट स्थान, और मानचित्र टाइलें।';

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
  String get downloadFirstInstallNote =>
      'पहली बार इंस्टॉल में 10–15 मिनट लगते हैं अच्छे कनेक्शन पर। डाउनलोड बैकग्राउंड में जारी रहेगा — स्क्रीन लॉक कर सकते हैं, पर बेहतर गति के लिए Wi-Fi पर रहें।';

  @override
  String get downloadAllRequired =>
      'आपातकाल में ऑफ़लाइन काम करने के लिए Aegis को हर पैक डिवाइस पर चाहिए। इस चरण को छोड़ नहीं सकते।';

  @override
  String get downloadCheckConnection =>
      'अपना कनेक्शन जाँचें और पुनः प्रयास करें। डाउनलोड वहीं से जारी होगा जहाँ रुका था।';

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

  @override
  String get homeSubtitle => 'ऑफ़लाइन. तैयार.';

  @override
  String get homeEmptyState =>
      'Aegis से बात शुरू करने के लिए\nनीचे का बटन दबाएँ।';

  @override
  String get homeStartTriage => 'ट्रायाज शुरू करें';

  @override
  String get homeReports => 'रिपोर्ट';

  @override
  String get homeTakePhoto => 'फ़ोटो लें';

  @override
  String get homePickFromGallery => 'गैलरी से चुनें';

  @override
  String get homeSave => 'सहेजें';

  @override
  String get homeVoiceDegraded => 'आवाज़ मॉडल इंस्टॉल नहीं। SOS अब भी उपलब्ध।';

  @override
  String get homeSomethingWentWrong => 'कुछ गलत हुआ।';

  @override
  String get homeEnginePreparing =>
      'AI इंजन तैयार हो रहा है — पहली बार लगभग 30 सेकंड लगते हैं। आप बात शुरू कर सकते हैं; पहला उत्तर धीमा हो सकता है।';

  @override
  String get homeNoEmergencyContact =>
      'कोई आपातकालीन संपर्क सहेजा नहीं। सेटिंग्स में जोड़ें।';

  @override
  String homeCouldNotDial(String phone) {
    return '$phone के लिए डायलर नहीं खोला जा सका।';
  }

  @override
  String get stageIdle => 'शुरू करने के लिए दबाएँ · SOS के लिए लंबा दबाएँ';

  @override
  String get stagePreparing => 'तैयार हो रहा है…';

  @override
  String get stageListening => 'सुन रहा हूँ… रोकने के लिए दबाएँ';

  @override
  String get stageTranscribing => 'लिप्यंतरण…';

  @override
  String get stageThinking => 'सोच रहा हूँ… बाधित करने के लिए दबाएँ';

  @override
  String get stageSpeaking => 'Aegis बोल रहा है · रोकने के लिए दबाएँ';

  @override
  String get stageAwaitingConfirmation =>
      'ऊपर का कार्ड देखें · पुष्टि या अस्वीकार करें';

  @override
  String get stageDegraded => 'आवाज़ अक्षम — SOS दबाएँ';

  @override
  String get stageError => 'पुनः प्रयास के लिए दबाएँ';

  @override
  String get thinkingReadingEvidence => 'आपके साक्ष्य पढ़ रहा हूँ…';

  @override
  String get thinkingLookingAtImage => 'छवि और ऑडियो देख रहा हूँ…';

  @override
  String get thinkingDraftingReport => 'रिपोर्ट तैयार कर रहा हूँ…';

  @override
  String get thinkingStillWorking => 'अभी काम चल रहा है — एक मिनट लग सकता है।';

  @override
  String get thinkingFinalisingReport =>
      'लगभग पूरा — रिपोर्ट अंतिम रूप दे रहा हूँ।';

  @override
  String get thinkingGeneric => 'सोच रहा हूँ…';

  @override
  String get thinkingComposingReply => 'उत्तर लिख रहा हूँ…';

  @override
  String get thinkingStillThinking =>
      'अभी सोच रहा हूँ — पहला उत्तर थोड़ा वक़्त लेता है।';

  @override
  String get thinkingFinalisingReply =>
      'लगभग पूरा — उत्तर अंतिम रूप दे रहा हूँ।';

  @override
  String get reportsTitle => 'ट्रायाज रिपोर्ट';

  @override
  String get reportsEmpty => 'अभी कोई रिपोर्ट नहीं।';

  @override
  String get reportsEmptyHint =>
      'रिपोर्ट बनाने के लिए होम स्क्रीन पर \"ट्रायाज शुरू करें\" दबाएँ।';

  @override
  String get reportsDetailTitle => 'रिपोर्ट';

  @override
  String get reportsDelete => 'रिपोर्ट हटाएँ?';

  @override
  String get reportsDeleteBody =>
      'यह रिपोर्ट अभिलेख से हट जाएगी। पूर्ववत नहीं किया जा सकता।';

  @override
  String get reportsCancel => 'रद्द करें';

  @override
  String get reportsDeleteAction => 'हटाएँ';

  @override
  String get reportsNoInputText => '(कोई इनपुट टेक्स्ट नहीं)';

  @override
  String get reportsYouEvidenceOnly =>
      'आप: (कोई बोला गया टेक्स्ट नहीं — साक्ष्य संलग्न)';

  @override
  String reportsYouQuote(String text) {
    return 'आप: \"$text\"';
  }

  @override
  String get reportsLegacy => '(पुरानी रिपोर्ट — कोई संरचित डेटा नहीं)';

  @override
  String get reportsDescribeScene => 'दृश्य का वर्णन करें';

  @override
  String get reportsDescribeHint =>
      'उदा. \"दो-मंज़िला घर, छत आंशिक रूप से गिरी, एक बुज़ुर्ग महिला सामने के दरवाज़े पर फँसी\"';

  @override
  String homePhotoCaptureFailed(String error) {
    return 'फ़ोटो कैप्चर विफल: $error';
  }
}
