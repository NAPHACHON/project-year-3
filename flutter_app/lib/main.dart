import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const ink = Color(0xFF080B12);
const panel = Color(0xFF111722);
const line = Color(0xFF263142);
const muted = Color(0xFF8D9AAE);
const cyan = Color(0xFF67E8F9);
const green = Color(0xFF4ADE80);
const amber = Color(0xFFFBBF24);

void main() => runApp(const CafeApp());

class CafeApp extends StatefulWidget {
  const CafeApp({super.key, this.apiClient});
  final http.Client? apiClient;
  @override
  State<CafeApp> createState() => _CafeAppState();
}

class _CafeAppState extends State<CafeApp> {
  static const configuredBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );
  final String base = configuredBase.replaceAll(RegExp(r'/+$'), '');
  late final http.Client client = widget.apiClient ?? http.Client();
  final navigatorKey = GlobalKey<NavigatorState>();
  Timer? polling;
  Timer? clock;
  bool dialogOpen = false;
  Duration serverOffset = Duration.zero;

  @override
  void initState() {
    super.initState();
    polling = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && token != null && data != null && !busy && !dialogOpen)
        refreshSilently();
    });
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          data != null &&
          (data!['open_sessions'] as List).any((s) => s['status'] == 'active'))
        setState(() {});
    });
  }

  void updateData(Map<String, dynamic> result) {
    data = result;
    final time = DateTime.tryParse(result['server_time']?.toString() ?? '');
    if (time != null) serverOffset = time.difference(DateTime.now());
  }

  Future<void> refreshSilently() async {
    if (!mounted) return;
    setState(() => busy = true);
    try {
      updateData(await request('/data'));
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController(text: 'member@cybercafe.test');
  final password = TextEditingController(text: 'MemberCafe!2026');
  final confirmation = TextEditingController();
  Map<String, dynamic>? data;
  String? token;
  String message = '';
  bool busy = false;
  bool registering = false;

  double number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  int integer(dynamic value) => number(value).round();

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final uri = Uri.parse('$base$path');
      final response = await (method == 'GET'
              ? client.get(uri, headers: headers)
              : client.post(
                  uri,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body),
                ))
          .timeout(const Duration(seconds: 15));
      Map<String, dynamic> result;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        result = decoded;
      } on FormatException {
        throw Exception(
          'เซิร์ฟเวอร์ตอบกลับผิดรูปแบบ (HTTP ${response.statusCode}) ตรวจ URL ของ API',
        );
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401) {
          token = null;
          data = null;
        }
        var error = result['message']?.toString() ??
            'เกิดข้อผิดพลาด HTTP ${response.statusCode}';
        final errors = result['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) error = first.first.toString();
        }
        throw Exception(error);
      }
      return result;
    } on TimeoutException {
      throw Exception(
        'API ไม่ตอบกลับภายใน 15 วินาที ตรวจว่า Laravel และ MySQL ยังทำงานอยู่',
      );
    } on http.ClientException {
      throw Exception(
        'เชื่อมต่อ API ไม่ได้ที่ $base\nเปิด start.bat และตรวจการตั้งค่า CORS แล้วลองใหม่',
      );
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() {}); // redraw both success and error states
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> login() => perform(() async {
        final result = await request(
          '/auth/login',
          method: 'POST',
          body: {'email': email.text.trim(), 'password': password.text},
        );
        await completeAuthentication(result);
      });

  Future<void> register() => perform(() async {
        if (password.text != confirmation.text) {
          throw Exception('รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน');
        }
        final result = await request(
          '/auth/register',
          method: 'POST',
          body: {
            'name': name.text.trim(),
            'phone': phone.text.trim(),
            'email': email.text.trim(),
            'password': password.text,
            'password_confirmation': confirmation.text,
          },
        );
        await completeAuthentication(result);
        message = 'สมัครสมาชิกสำเร็จ ยินดีต้อนรับเข้าสู่ CyberCafe';
      });

  Future<void> completeAuthentication(Map<String, dynamic> result) async {
    final issued = result['token'];
    if (issued is! String || issued.isEmpty)
      throw Exception('API ไม่ส่ง token กลับมา');
    token = issued;
    updateData(await request('/data'));
  }

  Future<void> load() => perform(() async {
        updateData(await request('/data'));
      });

  Future<void> checkConnection() => perform(() async {
        final result = await request('/health');
        if (result['status'] != 'ok') throw Exception('API ตอบกลับผิดรูปแบบ');
        message = 'เชื่อมต่อ API สำเร็จ ลองเข้าสู่ระบบได้เลย';
      });

  String money(dynamic value) => '${number(value).toStringAsFixed(2)} บาท';

  Future<void> book(int id) async {
    if (busy || dialogOpen || data == null) return;
    final station = (data!['stations'] as List).firstWhere(
      (s) => integer(s['id']) == id,
    );
    final admin = data!['user']['role'] == 'admin';
    final members = (data!['members'] as List).cast<Map<String, dynamic>>();
    if (admin && members.isEmpty) {
      setState(() => message = 'ยังไม่มีสมาชิกให้จองเครื่อง');
      return;
    }
    int hours = 1;
    int? memberId = admin ? integer(members.first['id']) : null;
    dialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('จอง ${station['station_code']}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (admin) ...[
                    DropdownButtonFormField<int>(
                      initialValue: memberId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'สมาชิก'),
                      items: members
                          .map(
                            (m) => DropdownMenuItem(
                              value: integer(m['id']),
                              child: Text(
                                '${m['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => memberId = value),
                    ),
                    const SizedBox(height: 14),
                  ],
                  DropdownButtonFormField<int>(
                    initialValue: hours,
                    decoration: const InputDecoration(
                      labelText: 'จำนวนชั่วโมง',
                    ),
                    items: List.generate(
                      24,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} ชั่วโมง'),
                      ),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => hours = value ?? 1),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'ยอดชำระก่อนเริ่มเล่น ${money(number(station['package']['hourly_rate']) * hours)}',
                    style: const TextStyle(
                      color: cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ติดต่อเคาน์เตอร์ภายใน 15 นาที เวลาเล่นเริ่มเมื่อผู้ดูแลรับเงินและเปิดรายการ',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'จบก่อนเวลาได้ คิดตามนาทีและรับเงินส่วนต่างที่เคาน์เตอร์ หากเล่นเกินเวลามียอดชำระเพิ่ม',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('กลับ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ยืนยันจอง'),
            ),
          ],
        ),
      ),
    );
    dialogOpen = false;
    if (confirmed != true || !mounted) return;
    await perform(() async {
      final result = await request(
        admin ? '/admin/bookings' : '/bookings',
        method: 'POST',
        body: {
          'station_id': id,
          'hours': hours,
          if (admin) 'user_id': memberId,
        },
      );
      message = result['message']?.toString() ?? 'จองแล้ว';
      updateData(await request('/data'));
    });
  }

  Future<bool> confirmAction(String title, String content) async {
    if (busy || dialogOpen) return false;
    dialogOpen = true;
    final result = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('กลับ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    dialogOpen = false;
    return result == true && mounted;
  }

  Future<void> cancel(int id) async {
    if (!await confirmAction(
      'ยกเลิกการจอง',
      'ยังไม่เริ่มเล่น จึงไม่มีค่าบริการ ยืนยันยกเลิกรายการนี้?',
    )) return;
    await perform(() async {
      final result = await request('/sessions/$id/cancel', method: 'POST');
      message = result['message']?.toString() ?? 'ยกเลิกแล้ว';
      updateData(await request('/data'));
    });
  }

  Future<void> startSession(Map<String, dynamic> session) async {
    if (!await confirmAction(
      'รับเงิน / เริ่มเล่น',
      session['planned_minutes'] == null
          ? 'เริ่มรายการเดิมและคิดค่าบริการหลังเล่น?'
          : 'ยืนยันว่าได้รับเงิน ${money(session['quoted_amount'])} ที่เคาน์เตอร์แล้ว และเริ่มเล่น ${integer(session['planned_minutes']) ~/ 60} ชั่วโมง?',
    )) return;
    await perform(() async {
      final result = await request(
        '/admin/sessions/${session['id']}/start',
        method: 'POST',
        body: {'payment_received': true},
      );
      message = result['message']?.toString() ?? 'เริ่มเล่นแล้ว';
      updateData(await request('/data'));
    });
  }

  Future<void> endSession(int id) async {
    if (busy || dialogOpen) return;
    Map<String, dynamic>? bill;
    await perform(() async {
      bill = (await request('/sessions/$id/settlement?use_reward=0'))['data']
          as Map<String, dynamic>;
    });
    if (bill == null || !mounted) return;
    bool reward = false;
    bool calculating = false;
    String? error;
    dialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ยกเลิก / จบการใช้งาน'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: reward,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'ใช้สิทธิ์ชั่วโมงฟรี',
                      style: TextStyle(fontSize: 14),
                    ),
                    onChanged: calculating
                        ? null
                        : (value) async {
                            setDialogState(() {
                              reward = value ?? false;
                              calculating = true;
                              error = null;
                            });
                            try {
                              final result = await request(
                                '/sessions/$id/settlement?use_reward=${reward ? 1 : 0}',
                              );
                              if (dialogContext.mounted)
                                setDialogState(
                                  () => bill =
                                      result['data'] as Map<String, dynamic>,
                                );
                            } catch (e) {
                              if (dialogContext.mounted)
                                setDialogState(
                                  () => error = e.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                                );
                            } finally {
                              if (dialogContext.mounted)
                                setDialogState(() => calculating = false);
                            }
                          },
                  ),
                  if (calculating) const LinearProgressIndicator(),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: amber)),
                  _billLine('ชำระไว้แล้ว', money(bill!['prepaid_amount'])),
                  _billLine(
                    'ใช้เวลา',
                    '${integer(bill!['minutes_used'])} นาที',
                  ),
                  _billLine(
                    'ใช้สิทธิ์ฟรี',
                    '${integer(bill!['free_minutes_used'])} นาที',
                  ),
                  _billLine('ค่าบริการจริง', money(bill!['total_amount'])),
                  _billLine('ส่วนต่างรอคืน', money(bill!['refund_amount'])),
                  _billLine('ยอดชำระเพิ่ม', money(bill!['balance_due'])),
                  const SizedBox(height: 12),
                  const Text(
                    'ยอดประมาณการ ระบบคำนวณอีกครั้งเมื่อยืนยัน คิดตามนาทีโดยปัดนาทีที่เริ่มแล้วขึ้น',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'กรุณาติดต่อเคาน์เตอร์เพื่อรับเงินส่วนต่าง ไม่มีการโอนเงินอัตโนมัติ',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: calculating
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('กลับ'),
            ),
            FilledButton(
              onPressed: calculating || error != null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('ยืนยันจบ'),
            ),
          ],
        ),
      ),
    );
    dialogOpen = false;
    if (confirmed != true || !mounted) return;
    await perform(() async {
      final result = await request(
        '/sessions/$id/end',
        method: 'POST',
        body: {'use_reward': reward},
      );
      message = result['message']?.toString() ?? 'จบการใช้งานแล้ว';
      updateData(await request('/data'));
    });
  }

  Widget _billLine(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  Future<void> confirmRefund(Map<String, dynamic> session) async {
    if (!await confirmAction(
      'ยืนยันคืนเงินแล้ว',
      'ได้ส่งเงินส่วนต่าง ${money(session['refund_amount'])} คืนให้ ${session['user']?['name'] ?? 'สมาชิก'} แล้ว?',
    )) return;
    await perform(() async {
      final result = await request(
        '/admin/sessions/${session['id']}/refund',
        method: 'POST',
      );
      message = result['message']?.toString() ?? 'คืนเงินแล้ว';
      updateData(await request('/data'));
    });
  }

  Future<void> logout() => perform(() async {
        await request('/auth/logout', method: 'POST');
        token = null;
        data = null;
        registering = false;
        password.text = 'MemberCafe!2026';
      });

  ThemeData get theme => ThemeData(
        useMaterial3: true,
        fontFamily: 'IBMPlexSansThai',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: const ColorScheme.dark(
          primary: cyan,
          secondary: green,
          surface: panel,
          onSurface: Color(0xFFE7EDF7),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0F18),
          foregroundColor: Color(0xFFE7EDF7),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: panel,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(17)),
            side: BorderSide(color: line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0C121C),
          labelStyle: const TextStyle(color: muted),
          prefixIconColor: muted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: cyan, width: 1.5),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Builder(
          builder: (viewContext) => Scaffold(
            appBar: data == null ? null : _topBar(),
            body: Column(
              children: [
                if (busy) const LinearProgressIndicator(minHeight: 2),
                if (data != null && message.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    color: const Color(0xFF172234),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: SingleChildScrollView(
                        child: Row(children: [
                      Expanded(
                          child: Semantics(
                              liveRegion: true,
                              child: Text(message,
                                  style: const TextStyle(
                                      color: amber, fontSize: 13)))),
                      IconButton(
                          tooltip: 'ปิดข้อความ',
                          onPressed: () => setState(() => message = ''),
                          icon: const Icon(Icons.close, size: 18)),
                    ])),
                  ),
                Expanded(
                  child: data == null ? authView() : memberView(viewContext),
                ),
              ],
            ),
          ),
        ),
      );

  PreferredSizeWidget _topBar() => AppBar(
        toolbarHeight: 74,
        titleSpacing: 18,
        title: Row(
          children: [
            const BrandMark(),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CyberCafe Member',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'จองเครื่องและดูเวลาของคุณ',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            tooltip: 'รีเฟรชข้อมูล',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: busy ? null : logout,
            tooltip: 'ออกจากระบบ',
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 12),
        ],
      );

  Widget authView() => Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.1,
            colors: [Color(0xFF133A46), ink],
            stops: [0, .52],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: const BorderSide(color: line),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          BrandMark(),
                          SizedBox(width: 11),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CyberCafe Desk',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'ระบบบริหารจัดการร้านเกม',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ],
                          )),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Text(
                        registering ? 'สร้างบัญชีสมาชิก' : 'เข้าสู่ระบบ',
                        style: const TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        registering
                            ? 'สมัครสมาชิกเพื่อจองเครื่องและติดตามเวลาเล่น'
                            : 'เข้าสู่ระบบเพื่อใช้งานร้านเกม',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 22),
                      if (registering) ...[
                        TextField(
                          controller: name,
                          enabled: !busy,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อผู้ใช้',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 13),
                        TextField(
                          controller: phone,
                          enabled: !busy,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'เบอร์โทรศัพท์',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 13),
                      ],
                      TextField(
                        controller: email,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'อีเมล',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: 13),
                      TextField(
                        controller: password,
                        enabled: !busy,
                        obscureText: true,
                        textInputAction: registering
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) {
                          if (!busy && !registering) login();
                        },
                        decoration: const InputDecoration(
                          labelText: 'รหัสผ่าน',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (registering) ...[
                        const SizedBox(height: 13),
                        TextField(
                          controller: confirmation,
                          enabled: !busy,
                          obscureText: true,
                          onSubmitted: (_) {
                            if (!busy) register();
                          },
                          decoration: const InputDecoration(
                            labelText: 'ยืนยันรหัสผ่าน',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed:
                            busy ? null : (registering ? register : login),
                        icon: Icon(
                          registering ? Icons.person_add_alt_1 : Icons.login,
                        ),
                        label: Text(
                          busy
                              ? 'กำลังดำเนินการ...'
                              : (registering ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ'),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  registering = !registering;
                                  message = '';
                                  if (registering) {
                                    email.clear();
                                    password.clear();
                                  } else {
                                    email.text = 'member@cybercafe.test';
                                    password.text = 'MemberCafe!2026';
                                  }
                                }),
                        child: Text(
                          registering
                              ? 'มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'
                              : 'ยังไม่มีบัญชี? สมัครสมาชิก',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : checkConnection,
                        icon: const Icon(Icons.wifi_tethering, size: 17),
                        label: const Text('ตรวจการเชื่อมต่อ API'),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF38506E)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'บัญชีทดลอง\nสมาชิก: member@cybercafe.test / MemberCafe!2026\nผู้ดูแล: admin@cybercafe.test / AdminCafe!2026',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFA9C0DA),
                            height: 1.7,
                          ),
                        ),
                      ),
                      if (message.isNotEmpty) notice(),
                      const SizedBox(height: 8),
                      Center(
                        child: SelectableText(
                          'API: $base',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget notice() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: amber, fontSize: 12),
        ),
      );

  Widget memberView(BuildContext viewContext) {
    final stations = (data!['stations'] as List).cast<Map<String, dynamic>>();
    final sessions =
        (data!['open_sessions'] as List).cast<Map<String, dynamic>>();
    final isMember = data!['user']['role'] == 'user';
    final hasBooking = sessions.isNotEmpty;
    final compact = MediaQuery.sizeOf(viewContext).width < 480;
    const labels = {
      'available': 'ว่าง',
      'reserved': 'ติดจอง',
      'in_use': 'กำลังใช้งาน',
      'maintenance': 'ปิดปรับปรุง',
      'active': 'กำลังเล่น',
    };
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.2,
          colors: [Color(0xFF122433), ink],
          stops: [0, .42],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 20,
            24,
            compact ? 14 : 20,
            60,
          ),
          children: [
            _heroHeader(compact),
            const SizedBox(height: 24),
            if (!isMember)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'ผู้ดูแล: จองให้สมาชิก รับเงิน เริ่มเล่น และคืนส่วนต่างได้จากหน้านี้',
                  ),
                ),
              ),
            if (isMember && hasBooking) _bookingNotice(sessions, labels),
            _stats(stations, sessions, isMember, compact),
            const SizedBox(height: 10),
            if (sessions.isNotEmpty) ...[
              sectionTitle(
                isMember ? 'รายการของฉัน' : 'รายการที่กำลังเปิด',
                'จบการใช้งานเพื่อหยุดคิดค่าบริการ',
              ),
              ...sessions.map((session) => _sessionCard(session, !isMember)),
              const SizedBox(height: 14),
            ],
            sectionTitle('ส่วนต่างรอคืน', 'ติดต่อเคาน์เตอร์พร้อมรหัสรายการ'),
            if ((data!['refunds'] as List? ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Text(
                  'ไม่มีเงินส่วนต่างที่รอคืน',
                  style: TextStyle(color: muted),
                ),
              ),
            ...(data!['refunds'] as List? ?? []).map(
              (s) => _refundCard(s as Map<String, dynamic>, !isMember),
            ),
            sectionTitle('เครื่องในร้าน', 'แตะจองเครื่องที่ว่าง'),
            if (stations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'ยังไม่มีข้อมูลเครื่องในร้าน',
                  textAlign: TextAlign.center,
                ),
              ),
            ...stations.map(
              (s) => _stationCard(s, labels, isMember, hasBooking),
            ),
            const SizedBox(height: 12),
            if (isMember) _rewardCard(),
            const SizedBox(height: 18),
            sectionTitle('รายการย้อนหลัง', 'ค่าบริการและสถานะคืนเงิน'),
            ...(data!['history'] as List).map(
              (s) => _historyCard(s as Map<String, dynamic>),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroHeader(bool compact) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MEMBER PASS',
          style: TextStyle(
            color: cyan,
            letterSpacing: 2,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'เลือกเครื่องที่อยากเล่น',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const Text(
          'สถานะอัปเดตจากร้าน และการจองจะหมดอายุภายใน 15 นาที',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF09201D),
        border: Border.all(color: const Color(0xFF185D55)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, color: green, size: 7),
        SizedBox(width: 6),
        Text('ระบบพร้อมใช้งาน', style: TextStyle(color: green, fontSize: 11)),
      ]),
    );
    if (compact)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [copy, const SizedBox(height: 13), status],
      );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(child: copy),
        status,
      ],
    );
  }

  Widget _bookingNotice(
    List<Map<String, dynamic>> sessions,
    Map<String, String> labels,
  ) =>
      Card(
        color: const Color(0xFF172234),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline, color: amber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    'คุณมีรายการจองอยู่แล้ว',
                    style: TextStyle(color: amber, fontWeight: FontWeight.w700),
                  )),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'ระบบให้จองได้ครั้งละ 1 เครื่อง กรุณาจัดการรายการเดิมก่อนจองเครื่องใหม่',
                style: TextStyle(color: Color(0xFFD7E0EF), fontSize: 12),
              ),
              ...sessions.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s['station']?['station_code'] ?? '-'} · ${labels[s['status']] ?? s['status']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (s['status'] == 'reserved')
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => cancel((s['id'] as num).toInt()),
                          child: const Text('ยกเลิก'),
                        )
                      else
                        const Text(
                          'จบได้ในรายการของฉัน',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _showBookingBlockDialog() => showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          backgroundColor: panel,
          title: const Text('จองเครื่องไม่ได้ตอนนี้'),
          content: const Text(
            'คุณมีการจองหรือกำลังใช้งานเครื่องอยู่แล้ว ระบบอนุญาตให้มีได้ครั้งละ 1 รายการ กรุณายกเลิกรายการเดิม หรือจบการใช้งานก่อน',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('เข้าใจแล้ว'),
            ),
          ],
        ),
      );

  Widget sectionTitle(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700),
                ),
                Text(subtitle,
                    style: const TextStyle(color: muted, fontSize: 12)),
              ],
            )),
          ],
        ),
      );

  Widget _stats(List<Map<String, dynamic>> stations,
      List<Map<String, dynamic>> sessions, bool isMember, bool compact) {
    final values = [
      ['เครื่องทั้งหมด', '${stations.length} เครื่อง', cyan],
      [
        'เครื่องว่าง',
        '${stations.where((x) => x['status'] == 'available').length} เครื่อง',
        green
      ],
      [
        isMember ? 'รายการของฉัน' : 'รายการที่เปิด',
        '${sessions.length} รายการ',
        amber
      ],
      [
        isMember ? 'ฟรีที่ใช้ได้' : 'สมาชิก',
        isMember
            ? '${integer(data!['rewards']['free_minutes_available']) ~/ 60} ชม.'
            : '${(data!['members'] as List).length} คน',
        const Color(0xFFA78BFA)
      ],
    ];
    return LayoutBuilder(
        builder: (context, constraints) => Wrap(
            spacing: 9,
            runSpacing: 9,
            children: values
                .map((value) => SizedBox(
                    width: (constraints.maxWidth - 9) / 2,
                    child: Card(
                        margin: EdgeInsets.zero,
                        child: Container(
                            constraints: const BoxConstraints(minHeight: 112),
                            padding: const EdgeInsets.all(13),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(value[0] as String,
                                      style: const TextStyle(
                                          color: muted, fontSize: 11)),
                                  const SizedBox(height: 5),
                                  Text(value[1] as String,
                                      style: TextStyle(
                                          fontSize: compact ? 20 : 21,
                                          fontWeight: FontWeight.w700,
                                          color: value[2] as Color)),
                                ])))))
                .toList()));
  }

  Widget _stationCard(
    Map<String, dynamic> s,
    Map<String, String> labels,
    bool isMember,
    bool hasBooking,
  ) {
    final status = s['status'] as String? ?? '';
    final color = {
          'available': green,
          'reserved': amber,
          'in_use': const Color(0xFFFB7185),
          'maintenance': muted,
        }[status] ??
        muted;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: color, width: 3)),
          borderRadius: BorderRadius.circular(17),
        ),
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(
                  '${s['station_code']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                )),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    labels[status] ?? status,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '${s['zone_name']}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '${s['specs_info'] ?? 'ยังไม่มีรายละเอียด'}',
                style: const TextStyle(color: Color(0xFFAAB5C7), fontSize: 12),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  '฿${number(s['package']['hourly_rate']).toStringAsFixed(2)}/ชั่วโมง',
                  style: const TextStyle(
                    color: cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (status == 'available')
                  (isMember && hasBooking
                      ? OutlinedButton(
                          onPressed: busy ? null : _showBookingBlockDialog,
                          child: const Text('มีรายการเดิม'),
                        )
                      : FilledButton(
                          onPressed: busy
                              ? null
                              : () => book((s['id'] as num).toInt()),
                          child: Text(isMember ? 'จองเครื่อง' : 'จองให้สมาชิก'),
                        )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String playingTime(Map<String, dynamic> session) {
    final start = DateTime.tryParse(session['started_at']?.toString() ?? '');
    if (start == null) return '';
    final now = DateTime.now().add(serverOffset);
    final used = (now.difference(start).inSeconds / 60).ceil().clamp(0, 999999);
    final end = DateTime.tryParse(
      session['scheduled_end_at']?.toString() ?? '',
    );
    if (end == null) return 'เล่นแล้ว $used นาที';
    final remaining = end.difference(now).inSeconds;
    return remaining > 0
        ? 'เล่นแล้ว $used นาที · เหลือ ${remaining ~/ 3600} ชม. ${(remaining % 3600) ~/ 60} นาที'
        : 'ครบเวลาที่จองแล้ว กรุณาจบการใช้งานเพื่อหยุดคิดค่าบริการ';
  }

  Widget _sessionCard(Map<String, dynamic> session, bool admin) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${session['station']?['station_code'] ?? '-'} · ${session['session_code']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (admin)
                Text(
                  '${session['user']?['name'] ?? ''}',
                  style: const TextStyle(color: muted),
                ),
              const SizedBox(height: 8),
              Text(
                session['planned_minutes'] == null
                    ? 'รายการเดิม: คิดค่าบริการหลังเล่น'
                    : 'เลือกเล่น ${integer(session['planned_minutes']) ~/ 60} ชม. · ยอดจอง ${money(session['quoted_amount'])}',
              ),
              if (session['status'] == 'active') ...[
                Text('รับเงินแล้ว ${money(session['prepaid_amount'])}'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    playingTime(session),
                    style: const TextStyle(color: amber, fontSize: 13),
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      busy ? null : () => endSession(integer(session['id'])),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('ยกเลิก / จบการใช้งาน'),
                ),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'รอเริ่มเล่น · ติดต่อเคาน์เตอร์ภายใน 15 นาที',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                if (admin)
                  FilledButton(
                    onPressed: busy ? null : () => startSession(session),
                    child: const Text('รับเงิน / เริ่มเล่น'),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : () => cancel(integer(session['id'])),
                  child: const Text('ยกเลิกการจอง'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _refundCard(Map<String, dynamic> session, bool admin) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${session['session_code']} · ${session['station']?['station_code'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (admin) Text('${session['user']?['name'] ?? ''}'),
              const SizedBox(height: 8),
              Text('ชำระแล้ว ${money(session['prepaid_amount'])}'),
              Text('ค่าบริการจริง ${money(session['total_amount'])}'),
              Text(
                'ส่วนต่างรอคืน ${money(session['refund_amount'])}',
                style:
                    const TextStyle(color: green, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'ติดต่อเคาน์เตอร์ พร้อมแจ้งรหัสรายการนี้เพื่อรับเงินส่วนต่าง',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              if (admin)
                FilledButton(
                  onPressed: busy ? null : () => confirmRefund(session),
                  child: const Text('ยืนยันคืนเงินแล้ว'),
                ),
            ],
          ),
        ),
      );

  Widget _historyCard(Map<String, dynamic> session) {
    const statuses = {
      'completed': 'จบการใช้งาน',
      'cancelled': 'ยกเลิก',
      'expired': 'หมดเวลาจอง',
    };
    const refunds = {
      'pending': 'รอคืนที่เคาน์เตอร์',
      'paid': 'คืนเงินแล้ว',
      'none': 'ไม่มีส่วนต่าง',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${session['station']?['station_code'] ?? '-'} · ${session['session_code']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              statuses[session['status']] ?? '${session['status']}',
              style: const TextStyle(color: muted),
            ),
            Text(
              'ใช้เวลา ${integer(session['minutes_used'])} นาที · ฟรี ${integer(session['free_minutes_used'])} นาที',
            ),
            Text(
              'ชำระแล้ว ${money(session['prepaid_amount'])} · ค่าบริการจริง ${money(session['total_amount'])}',
            ),
            Text(
              'ส่วนต่าง ${money(session['refund_amount'])} · ${refunds[session['refund_status']] ?? ''}',
              style: const TextStyle(color: green),
            ),
            if (number(session['balance_due']) > 0)
              Text(
                'ชำระเพิ่มที่เคาน์เตอร์ ${money(session['balance_due'])}',
                style: const TextStyle(color: amber),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard() {
    final rewards = data!['rewards'] as Map<String, dynamic>;
    final paid = integer(rewards['paid_minutes']);
    final free = integer(rewards['free_minutes_available']);
    final percent = ((paid % 600) / 600).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ชั่วโมงสะสมของฉัน',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 9),
            Text(
              'สะสมเวลาแบบจ่ายแล้ว ${paid ~/ 60} ชม. ${paid % 60} นาที',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 7,
                backgroundColor: const Color(0xFF273247),
                color: cyan,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'สิทธิ์ฟรีคงเหลือ ${free ~/ 60} ชั่วโมง',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    polling?.cancel();
    clock?.cancel();
    client.close();
    name.dispose();
    phone.dispose();
    email.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 37,
        height: 37,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: const LinearGradient(colors: [cyan, Color(0xFF8B5CF6)]),
        ),
        child: const Icon(Icons.bolt, color: ink, size: 22),
      );
}
