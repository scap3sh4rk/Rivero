/// UPI apps the user can pick as their primary one. Notifications from the
/// chosen app are always read, even if it is not a bank Rivero knows.
class UpiApp {
  const UpiApp(this.name, this.package);

  final String name;
  final String package;

  static const List<UpiApp> all = [
    UpiApp('Google Pay', 'com.google.android.apps.nbu.paisa.user'),
    UpiApp('PhonePe', 'com.phonepe.app'),
    UpiApp('Paytm', 'net.one97.paytm'),
    UpiApp('BHIM', 'in.org.npci.upiapp'),
    UpiApp('CRED', 'com.dreamplug.androidapp'),
    UpiApp('Amazon Pay', 'in.amazon.mShop.android.shopping'),
    UpiApp('YONO SBI', 'com.sbi.lotusintouch'),
    UpiApp('iMobile Pay (ICICI)', 'com.csam.icici.bank.imobile'),
    UpiApp('HDFC Bank app', 'com.snapwork.hdfc'),
    UpiApp('Axis Mobile', 'com.axis.mobile'),
    UpiApp('Navi', 'com.naviapp'),
    UpiApp('MobiKwik', 'com.mobikwik_new'),
  ];

  static UpiApp? byPackage(String? package) {
    for (final a in all) {
      if (a.package == package) return a;
    }
    return null;
  }
}
