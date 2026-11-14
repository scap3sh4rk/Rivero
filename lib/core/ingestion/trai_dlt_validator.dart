/// Validates sender identifiers against Telecom Regulatory Authority of India (TRAI)
/// Distributed Ledger Technology (DLT) commercial SMS regulations, as well as recognized
/// Indian banking and payment application package identifiers.
class TraiDltValidator {
  const TraiDltValidator({this.extraPackages = const {}});

  /// Apps the user told Rivero to trust (their primary UPI app).
  final Set<String> extraPackages;

  /// Regex pattern matching standard 2-character circle prefix + dash + 3..6 character entity code,
  /// or 2-character circle prefix + exactly 6-character entity code without dash.
  /// Examples: "VK-HDFCBK", "AD-ICICIB", "VM-SBINB", "BPAXISBK", "JDKOTAKB".
  static final RegExp dltHeaderRegex = RegExp(
    r'^(?:[a-zA-Z]{2}-([a-zA-Z0-9]{3,6})|[a-zA-Z]{2}([a-zA-Z0-9]{6}))$',
  );

  /// Known entity prefixes and bank code mappings.
  static const Map<String, String> knownBankEntities = {
    'HDFCBK': 'HDFC Bank',
    'HDFCBN': 'HDFC Bank',
    'HDFCCC': 'HDFC Bank Credit Card',
    'ICICIB': 'ICICI Bank',
    'ICICIN': 'ICICI Bank',
    'ICICAC': 'ICICI Bank',
    'SBINB': 'State Bank of India',
    'SBIPSG': 'State Bank of India',
    'SBIINB': 'State Bank of India',
    'ATMSBI': 'State Bank of India',
    'SBIUPI': 'State Bank of India',
    'SBICRD': 'State Bank of India',
    'SBIBNK': 'State Bank of India',
    'CBSSBI': 'State Bank of India',
    'AXISBK': 'Axis Bank',
    'AXISBN': 'Axis Bank',
    'AXISCC': 'Axis Bank Credit Card',
    'KOTAKB': 'Kotak Mahindra Bank',
    'KOTAKN': 'Kotak Mahindra Bank',
    'IDFCFB': 'IDFC First Bank',
    'IDFCBK': 'IDFC First Bank',
    'PNBSMS': 'Punjab National Bank',
    'PUNJAB': 'Punjab National Bank',
    'BOBSMS': 'Bank of Baroda',
    'BARODA': 'Bank of Baroda',
    'INDUSB': 'IndusInd Bank',
    'YESBNK': 'Yes Bank',
    'SCBANK': 'Standard Chartered Bank',
    'RBLBNK': 'RBL Bank',
    'FEDBNK': 'Federal Bank',
    'CANBNK': 'Canara Bank',
    'UNIONB': 'Union Bank of India',
    'PAYTMB': 'Paytm Payments Bank',
    'PAYTM': 'Paytm',
    'AIRTEL': 'Airtel Payments Bank',
  };

  /// Known Android payment app package identifiers.
  static const Map<String, String> knownPaymentPackages = {
    'com.google.android.apps.nbu.paisa.user': 'Google Pay',
    'com.phonepe.app': 'PhonePe',
    'net.one97.paytm': 'Paytm',
    'in.amazon.mShop.android.shopping': 'Amazon Pay',
    'com.dreamplug.androidapp': 'CRED',
    'in.org.npci.upiapp': 'BHIM UPI',
    'com.freecharge.android': 'Freecharge',
    'com.mobikwik_new': 'MobiKwik',
    'com.snapwork.hdfc': 'HDFC MobileBanking',
    'com.csam.icici.bank.imobile': 'iMobile Pay',
    'com.sbi.lotusintouch': 'YONO SBI',
    'com.axis.mobile': 'Axis Mobile',
    'com.msf.kopl': 'Kotak Mobile Banking',
  };

  /// Returns true if the sender header follows standard TRAI DLT commercial format.
  bool isValidDltHeader(String sender) {
    final clean = sender.trim();
    return dltHeaderRegex.hasMatch(clean);
  }

  /// Extracts the 6-character entity code from a TRAI DLT header (e.g. "VK-HDFCBK" -> "HDFCBK").
  String? extractEntityCode(String sender) {
    final match = dltHeaderRegex.firstMatch(sender.trim());
    if (match == null) return null;
    return (match.group(1) ?? match.group(2))?.toUpperCase();
  }

  /// Checks if either the [senderHeader] or [packageName] belongs to a recognized financial source.
  bool isFinancialSender({String? senderHeader, String? packageName}) {
    if (packageName != null &&
        (knownPaymentPackages.containsKey(packageName) ||
            extraPackages.contains(packageName))) {
      return true;
    }

    if (senderHeader != null) {
      final code = extractEntityCode(senderHeader);
      if (code != null && knownBankEntities.containsKey(code)) {
        return true;
      }
    }

    return false;
  }

  /// Resolves a human-readable financial institution or app name.
  String? resolveFinancialInstitutionName({
    String? senderHeader,
    String? packageName,
  }) {
    if (packageName != null && knownPaymentPackages.containsKey(packageName)) {
      return knownPaymentPackages[packageName];
    }

    if (senderHeader != null) {
      final code = extractEntityCode(senderHeader);
      if (code != null && knownBankEntities.containsKey(code)) {
        return knownBankEntities[code];
      }
    }

    return null;
  }
}
