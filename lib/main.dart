import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await Supabase.initialize(
    url: 'https://cvbubouqkoladwhemzcf.supabase.co',
    anonKey: 'sb_publishable_gSYtFINdgJzEQwYLJ9M8pg_zxMs6SK5',
  );

  runApp(const DeuaDeliveryApp());
}

Future showNewOrderNotification(String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'deua_new_orders_channel',
    'DEUA New Orders',
    channelDescription: 'Alerts for new delivery orders',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  const NotificationDetails details =
      NotificationDetails(android: androidDetails);
  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    details,
  );
}

class DeuaDeliveryApp extends StatelessWidget {
  const DeuaDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DEUA FRESH Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B7A2B),
          primary: const Color(0xFF1B7A2B),
        ),
      ),
      home: const DeliveryAuthGate(),
    );
  }
}

class DeliveryAuthGate extends StatefulWidget {
  const DeliveryAuthGate({super.key});

  @override
  State createState() => _DeliveryAuthGateState();
}

class _DeliveryAuthGateState extends State {
  final _supabase = Supabase.instance.client;
  bool _checking = true;
  Map? _boy;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('delivery_boy_session_id') ?? '';
      if (savedId.isNotEmpty) {
        final rows = await _supabase
            .from('deua_staff_accounts')
            .select()
            .eq('id', savedId)
            .eq('role', 'delivery_boy');
        final list = List.from(rows as List);
        if (list.isNotEmpty) {
          final acc = Map.from(list.first as Map);
          if (acc['is_active'] == true) {
            if (!mounted) return;
            setState(() {
              _boy = acc;
              _checking = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _checking = false);
  }

  Future _onLogin(Map user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('delivery_boy_session_id', user['id'].toString());
    if (!mounted) return;
    setState(() => _boy = user);
  }

  Future _onLogout() async {
    if (_boy != null) {
      try {
        await _supabase
            .from('deua_staff_accounts')
            .update({'is_on_duty': false}).eq('id', _boy!['id']);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('delivery_boy_session_id');
    if (!mounted) return;
    setState(() => _boy = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF1B7A2B))),
      );
    }
    if (_boy == null) {
      return DeliveryLoginScreen(onSuccess: _onLogin);
    }
    return DeliveryHomeScreen(
      boy: _boy!,
      onLogout: _onLogout,
      onBoyUpdated: (u) => setState(() => _boy = u),
    );
  }
}

class DeliveryLoginScreen extends StatefulWidget {
  final Future Function(Map user) onSuccess;
  const DeliveryLoginScreen({super.key, required this.onSuccess});

  @override
  State createState() => _DeliveryLoginScreenState();
}

class _DeliveryLoginScreenState extends State {
  final _supabase = Supabase.instance.client;
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  DeliveryLoginScreen get _w => widget as DeliveryLoginScreen;

  Future _login() async {
    final rawId = _idCtrl.text.trim();
    final pass = _passCtrl.text;
    if (rawId.isEmpty || pass.isEmpty) {
      setState(() => _error = 'कृपया ID और Password दोनों डालें।');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('deua_staff_accounts')
          .select()
          .eq('role', 'delivery_boy')
          .eq('login_id', rawId.toLowerCase());
      final list = List.from(rows as List);

      if (list.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'यह Delivery Boy ID सही नहीं है।';
        });
        return;
      }

      final acc = Map.from(list.first as Map);
      if (acc['is_active'] != true) {
        setState(() {
          _loading = false;
          _error = 'आपका अकाउंट बंद (Inactive) है। Owner से संपर्क करें।';
        });
        return;
      }

      if (acc['password'].toString() != pass) {
        setState(() {
          _loading = false;
          _error = 'गलत Password! सही Password डालें।';
        });
        return;
      }

      await _w.onSuccess(acc);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Login error: $e';
      });
    }
  }

  void _requestPasswordReset() {
    final ctrl = TextEditingController(text: _idCtrl.text.trim());
    String? msg;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setDlg) => AlertDialog(
          title: const Text('Forgot Password', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('अपनी Delivery ID डालें—Owner को नया Password बनाने का अनुरोध चला जाएगा।', style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Delivery ID (उदा: boy_ramesh)', border: OutlineInputBorder(), isDense: true),
              ),
              if (msg != null) ...[
                const SizedBox(height: 8),
                Text(msg!, style: const TextStyle(color: Color(0xFF1B7A2B), fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद करें')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A2B), foregroundColor: Colors.white),
              onPressed: () async {
                final idVal = ctrl.text.trim().toLowerCase();
                if (idVal.isEmpty) return;
                final rows = await _supabase
                    .from('deua_staff_accounts')
                    .select()
                    .eq('role', 'delivery_boy')
                    .eq('login_id', idVal);
                if ((rows as List).isEmpty) {
                  setDlg(() => msg = 'यह ID नहीं मिली।');
                  return;
                }
                await _supabase
                    .from('deua_staff_accounts')
                    .update({'reset_requested': true})
                    .eq('login_id', idVal);
                setDlg(() => msg = 'Owner को Reset Request भेज दी गई है।');
              },
              child: const Text('Request भेजें'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.delivery_dining, color: Color(0xFF1B7A2B), size: 34),
                  ),
                  const SizedBox(height: 12),
                  const Text('DEUA FRESH DELIVERY PARTNER', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1B7A2B))),
                  const Text('Delivery Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _idCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Delivery ID (उदा: boy_ramesh)',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _requestPasswordReset,
                      child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFF1B7A2B), fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A2B), foregroundColor: Colors.white),
                      onPressed: _loading ? null : _login,
                      child: Text(_loading ? 'जांच हो रही है...' : 'Login • लॉगिन करें', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DeliveryHomeScreen extends StatefulWidget {
  final Map boy;
  final Future Function() onLogout;
  final void Function(Map updated) onBoyUpdated;

  const DeliveryHomeScreen({
    super.key,
    required this.boy,
    required this.onLogout,
    required this.onBoyUpdated,
  });

  @override
  State createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends State {
  final _supabase = Supabase.instance.client;
  int _tabIndex = 0;
  bool _loading = true;
  bool _onDuty = false;
  List _openOrders = [];
  List _myOrders = [];
  final Set _knownOrderIds = {};
  Timer? _pollTimer;
  RealtimeChannel? _ordersChannel;

  DeliveryHomeScreen get _w => widget as DeliveryHomeScreen;

  String get _myId => _w.boy['id'].toString();
  String get _myName => _w.boy['name'].toString();

  @override
  void initState() {
    super.initState();
    _onDuty = _w.boy['is_on_duty'] == true;
    _fetchOrders(firstLoad: true);
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _fetchOrders());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_ordersChannel != null) {
      _supabase.removeChannel(_ordersChannel!);
    }
    super.dispose();
  }

  void _subscribeRealtime() {
    _ordersChannel = _supabase
        .channel('public:deua_orders_delivery')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deua_orders',
          callback: (_) => _fetchOrders(),
        )
        .subscribe();
  }

  Future _toggleDuty(bool value) async {
    setState(() => _onDuty = value);
    try {
      await _supabase
          .from('deua_staff_accounts')
          .update({'is_on_duty': value}).eq('id', _myId);
      final updated = Map.from(_w.boy)..['is_on_duty'] = value;
      _w.onBoyUpdated(updated);
      await _fetchOrders();
      _showSnack(value ? 'आप अब ON DUTY हैं — नए ऑर्डर दिखेंगे।' : 'आप OFF DUTY हो गए हैं।');
    } catch (e) {
      _showSnack('Duty update error: $e', isError: true);
    }
  }

  Future _fetchOrders({bool firstLoad = false}) async {
    try {
      final res = await _supabase
          .from('deua_orders')
          .select()
          .order('created_at', ascending: false);
      final all = List.from(res as List);

      final List openList = [];
      final List mineList = [];
      bool hasBrandNewOrder = false;
      String latestAlertText = '';

      for (final item in all) {
        final ord = Map.from(item as Map);
        final ordId = ord['id'].toString();
        final status = (ord['status'] ?? 'Pending').toString();
        final assignedId = (ord['delivery_boy_id'] ?? '').toString();

        final List rejectedList = [];
        if (ord['rejected_by_ids'] is List) {
          for (final r in (ord['rejected_by_ids'] as List)) {
            rejectedList.add(r.toString());
          }
        }

        if (assignedId == _myId) {
          mineList.add(ord);
        } else if (assignedId.isEmpty &&
            status == 'Pending' &&
            _onDuty &&
            !rejectedList.contains(_myId)) {
          openList.add(ord);
          if (!firstLoad && !_knownOrderIds.contains(ordId)) {
            hasBrandNewOrder = true;
            latestAlertText = '${ord['customer_name']} • ₹${ord['total_amount']} (${ord['delivery_address']})';
          }
        }
        _knownOrderIds.add(ordId);
      }

      if (!mounted) return;
      setState(() {
        _openOrders = openList;
        _myOrders = mineList;
        _loading = false;
      });

      if (hasBrandNewOrder) {
        SystemSound.play(SystemSoundType.alert);
        await showNewOrderNotification('नया डिलीवरी ऑर्डर आया है! • DEUA FRESH', latestAlertText);
        if (mounted) {
          _showSnack('नया ऑर्डर आया है! Accept करें: $latestAlertText');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future _acceptOrder(Map ord) async {
    try {
      final updated = await _supabase
          .from('deua_orders')
          .update({
            'delivery_boy_id': _myId,
            'delivery_boy_name': _myName,
            'status': 'Out for Delivery',
          })
          .eq('id', ord['id'])
          .isFilter('delivery_boy_id', null)
          .select();

      final list = List.from(updated as List);
      if (list.isEmpty) {
        _showSnack('यह ऑर्डर किसी और Delivery Boy ने पहले ही Accept कर लिया है।', isError: true);
      } else {
        _showSnack('ऑर्डर Accept हो गया! अब डिलीवरी के लिए निकलें।');
        setState(() => _tabIndex = 1);
      }
      await _fetchOrders();
    } catch (e) {
      _showSnack('Accept error: $e', isError: true);
    }
  }

  Future _rejectOrder(Map ord) async {
    try {
      final List existingRejected = [];
      if (ord['rejected_by_ids'] is List) {
        for (final r in (ord['rejected_by_ids'] as List)) {
          existingRejected.add(r.toString());
        }
      }
      if (!existingRejected.contains(_myId)) {
        existingRejected.add(_myId);
      }
      await _supabase
          .from('deua_orders')
          .update({'rejected_by_ids': existingRejected}).eq('id', ord['id']);
      _showSnack('ऑर्डर Reject किया गया — बाकी On-Duty boys को दिखेगा।');
      await _fetchOrders();
    } catch (e) {
      _showSnack('Reject error: $e', isError: true);
    }
  }

  Future _markDelivered(dynamic orderId) async {
    try {
      await _supabase
          .from('deua_orders')
          .update({'status': 'Delivered'}).eq('id', orderId);
      _showSnack('ऑर्डर Delivered मार्क हो गया!');
      await _fetchOrders();
    } catch (e) {
      _showSnack('Update error: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF1B7A2B),
      ),
    );
  }

  Widget _buildOrderCard(Map ord, {required bool isAvailableTab}) {
    final items = ord['items'] is List ? List.from(ord['items'] as List) : [];
    final status = (ord['status'] ?? 'Pending').toString();
    final isDelivered = status == 'Delivered';

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${ord['customer_name']} • ${ord['customer_phone']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isAvailableTab
                        ? Colors.orange.shade50
                        : (isDelivered ? const Color(0xFFE8F5E9) : Colors.blue.shade50),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isAvailableTab ? 'NEW ORDER' : status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAvailableTab
                          ? Colors.orange.shade900
                          : (isDelivered ? const Color(0xFF1B7A2B) : Colors.blue.shade800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('पता: ${ord['delivery_address']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
            const Divider(height: 16),
            ...items.map((it) {
              final m = Map.from(it as Map);
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('• ${m['name']} (${m['pack']}) x ${m['qty']}', style: const TextStyle(fontSize: 13))),
                    Text('₹${((m['price'] as num? ?? 0) * (m['qty'] as num? ?? 1)).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'कुल: ₹${ord['total_amount']} (${ord['payment_method'] ?? 'COD'})',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1B7A2B)),
                ),
                if (isAvailableTab)
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                        onPressed: () => _rejectOrder(ord),
                        child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A2B), foregroundColor: Colors.white),
                        onPressed: () => _acceptOrder(ord),
                        child: const Text('Accept • लें', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
                else if (!isDelivered)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7A2B), foregroundColor: Colors.white),
                    onPressed: () => _markDelivered(ord['id']),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Mark Delivered', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeOrderMap = _tabIndex == 0
        ? (_openOrders.isNotEmpty ? Map.from(_openOrders[_openOrders.length - 1] as Map) : null)
        : (_myOrders.isNotEmpty ? Map.from(_myOrders[_myOrders.length - 1] as Map) : null);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B7A2B),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DELIVERY • $_myName', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
            Text(_tabIndex == 0 ? 'नए उपलब्ध ऑर्डर (${_openOrders.length})' : 'मेरे ऑर्डर (${_myOrders.length})', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetchOrders()),
          IconButton(icon: const Icon(Icons.logout), onPressed: _w.onLogout),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: _onDuty ? const Color(0xFFE8F5E9) : Colors.red.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(_onDuty ? Icons.notifications_active : Icons.notifications_off, color: _onDuty ? const Color(0xFF1B7A2B) : Colors.red),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_onDuty ? 'ON DUTY • ड्यूटी चालू है' : 'OFF DUTY • ड्यूटी बंद है', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(_onDuty ? 'नए ऑर्डर की नोटिफिकेशन आएगी' : 'नए ऑर्डर पाने के लिए On करें', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                      ],
                    ),
                  ],
                ),
                Switch(value: _onDuty, activeColor: const Color(0xFF1B7A2B), onChanged: _toggleDuty),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B7A2B)))
                : RefreshIndicator(
                    onRefresh: () => _fetchOrders(),
                    child: activeOrderMap == null
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Text(
                                  _tabIndex == 0
                                      ? (_onDuty
                                          ? 'अभी कोई नया ऑर्डर उपलब्ध नहीं है'
                                          : 'नए ऑर्डर देखने के लिए ऊपर ON DUTY चालू करें')
                                      : 'आपने अभी तक कोई ऑर्डर Accept नहीं किया है',
                                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [_buildOrderCard(activeOrderMap, isAvailableTab: _tabIndex == 0)],
                          ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8F5E9),
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          NavigationDestination(
            icon: Badge(label: Text('${_openOrders.length}'), child: const Icon(Icons.notifications_outlined)),
            selectedIcon: const Icon(Icons.notifications, color: Color(0xFF1B7A2B)),
            label: 'New Orders',
          ),
          NavigationDestination(
            icon: const Icon(Icons.delivery_dining_outlined),
            selectedIcon: const Icon(Icons.delivery_dining, color: Color(0xFF1B7A2B)),
            label: 'My Deliveries',
          ),
        ],
      ),
    );
  }
}
