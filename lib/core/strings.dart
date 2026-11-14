/// Tiny localisation layer: English literals are the keys; Telugu is looked up
/// when the app language is `te`, otherwise (or when missing) English is shown.
/// Layouts are built to tolerate ~30% longer strings.
class Lang {
  static String code = 'en';
  static bool get isTe => code == 'te';
}

String tr(String en) => Lang.isTe ? (_te[en] ?? en) : en;

/// Shows "తెలుగు · English" pairs for parent screens, matching the artboards.
String bi(String en) => Lang.isTe && _te.containsKey(en) ? '${_te[en]} · $en' : en;

const _te = <String, String>{
  // Navigation
  'Today': 'ఈరోజు',
  'Health': 'ఆరోగ్యం',
  'Records': 'రికార్డులు',
  'Family': 'కుటుంబం',
  'More': 'మరిన్ని',
  'Add': 'చేర్చు',
  // Actions
  'Taken': 'తీసుకున్నాను',
  'Skip': 'వదిలేయి',
  'Skip this dose': 'ఈ మోతాదు వదిలేయి',
  'Snooze 10 min': '10 నిమిషాలు ఆపు',
  'Save': 'సేవ్ చేయి',
  'Save reading': 'నమోదు సేవ్ చేయి',
  'Cancel': 'రద్దు',
  'Done': 'పూర్తయింది',
  'Close': 'మూసివేయి',
  'Undo': 'వెనక్కి',
  'Next': 'తదుపరి',
  'Back': 'వెనక్కి',
  'Retry': 'మళ్ళీ ప్రయత్నించు',
  'Edit': 'మార్చు',
  'Delete': 'తొలగించు',
  'Unlock': 'తెరువు',
  // Today
  'Next medicine': 'తదుపరి మందు',
  'Due now': 'ఇప్పుడు తీసుకోవాలి',
  'Log BP': 'బీపీ నమోదు',
  'Log Sugar': 'షుగర్ నమోదు',
  'Next doctor visit': 'తదుపరి డాక్టర్',
  'Next appointment': 'తదుపరి అపాయింట్‌మెంట్',
  'Today’s readings': 'ఈరోజు రీడింగులు',
  'Latest readings': 'తాజా రీడింగులు',
  'Blood pressure': 'రక్తపోటు',
  'Sugar before breakfast': 'అల్పాహారానికి ముందు షుగర్',
  'Weight': 'బరువు',
  'No medicines due': 'ఈరోజు మందులు లేవు',
  'All doses done for today': 'ఈరోజు అన్ని మందులు అయ్యాయి',
  // Food
  'After food': 'భోజనం తర్వాత',
  'Before food': 'భోజనానికి ముందు',
  'Any time': 'ఎప్పుడైనా',
  // Status words
  'Normal': 'సాధారణం',
  'High': 'ఎక్కువ',
  'Low': 'తక్కువ',
  'Borderline': 'కొద్దిగా ఎక్కువ',
  'Under target': 'లక్ష్యంలో',
  'Above target': 'లక్ష్యం పైన',
  'Missed': 'తప్పింది',
  'Upcoming': 'రాబోయేది',
  'Parsed': 'చదివారు',
  'Needs review': 'పరిశీలించాలి',
  'Failed': 'చదవలేకపోయాం',
  // Reminder
  'Medicine time': 'మందు సమయం',
  'Voice on': 'వాయిస్ ఆన్',
  'Voice off': 'వాయిస్ ఆఫ్',
  '1 tablet': '1 మాత్ర',
  // Medicines
  'Medicines': 'మందులు',
  'Morning': 'ఉదయం',
  'Afternoon': 'మధ్యాహ్నం',
  'Night': 'రాత్రి',
  'No medicines': 'మందులు లేవు',
  'Add medicine': 'మందు చేర్చు',
  'Save medicine': 'మందు సేవ్ చేయి',
  'Adherence': 'మందుల క్రమం',
  // Log reading
  'Log reading': 'రీడింగ్ నమోదు',
  'Systolic': 'సిస్టోలిక్ (పై)',
  'Diastolic': 'డయాస్టోలిక్ (కింద)',
  'Pulse': 'నాడి',
  'Sugar': 'షుగర్',
  'Before breakfast': 'అల్పాహారానికి ముందు',
  'Fasting': 'పరగడుపున',
  'Fasting sugar': 'పరగడుపున షుగర్',
  'Sugar after meal': 'భోజనం తర్వాత షుగర్',
  'Reading history': 'రీడింగ్‌ల చరిత్ర',
  'After meal': 'భోజనం తర్వాత',
  'Saved on phone': 'ఫోన్‌లో సేవ్ అయింది',
  // Appointments
  'Appointments': 'అపాయింట్‌మెంట్లు',
  'Upcoming appointments': 'రాబోయే అపాయింట్‌మెంట్లు',
  'Past visits': 'గత సందర్శనలు',
  // Settings
  'Settings': 'సెట్టింగ్‌లు',
  'Language': 'భాష',
  'Large text mode': 'పెద్ద అక్షరాలు',
  'Voice reminders': 'వాయిస్ రిమైండర్లు',
  'Reminder sound': 'రిమైండర్ శబ్దం',
  'Backup': 'బ్యాకప్',
  'Home server': 'హోమ్ సర్వర్',
  'App lock': 'యాప్ లాక్',
  'Export health summary (PDF)': 'ఆరోగ్య సారాంశం (PDF)',
  // Lock
  'Touch the sensor to unlock': 'అన్‌లాక్ చేయడానికి సెన్సార్‌ను తాకండి',
  'Use PIN instead': 'బదులుగా PIN వాడండి',
  'Enter your 4-digit PIN': '4 అంకెల PIN నమోదు చేయండి',
  // Emergency
  'Emergency card': 'అత్యవసర కార్డు',
  'Conditions': 'ఆరోగ్య సమస్యలు',
  'Current medicines': 'ప్రస్తుత మందులు',
  'Allergies': 'అలెర్జీలు',
  // Health
  'Preventive check-ups due': 'చేయించుకోవలసిన పరీక్షలు',
  'Diabetes': 'మధుమేహం',
  'Cholesterol': 'కొలెస్ట్రాల్',
  'Thyroid': 'థైరాయిడ్',
  'Vitamins': 'విటమిన్లు',
  'Prostate': 'ప్రోస్టేట్',
  'Gall bladder': 'పిత్తాశయం',
};
