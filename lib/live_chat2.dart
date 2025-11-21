import 'dart:async'; // <-- ADDED
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:autisecure/services/api_service.dart';
import 'package:autisecure/login_signup/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:badges/badges.dart' as badges;
import 'package:image_picker/image_picker.dart';

// Import the SocketService
import 'package:autisecure/services/socket_service.dart';

// --- ADD THESE IMPORTS ---
import 'package:autisecure/calls/video_call.dart'; // Import your VideoCall screen
// --- END IMPORTS ---

class LiveChat2 extends StatefulWidget {
  const LiveChat2({super.key});

  @override
  State<LiveChat2> createState() => _LiveLiveChat2State();
}

class _LiveLiveChat2State extends State<LiveChat2>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final SocketService socketService = SocketService();

  bool _isLoading = true;
  bool isChatOpen = false;
  String selectedUser = '';
  String? otherUserId;
  String? userId;
  String? userRole;
  String? selectedConversationId;
  Map<String, dynamic>? _currentPeer; // <-- ADDED
  List conversations = [];
  List messages = [];
  List<Map<String, dynamic>> approvedAppointments = [];
  List<Map<String, dynamic>> pendingAppointments = [];
  int _pendingCount = 0;

  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const String _pendingCacheKey = 'pendingAppointmentsCache';
  static const String _approvedCacheKey = 'approvedAppointmentsCache';
  static const String _conversationsCacheKey = 'conversationsCache';
  static const String _userIdKey = 'userId';
  static const String _roleKey = 'role';
  static const String _tokenKey = 'token';

  @override
  void initState() {
    super.initState();
    _loadDoctorDetailsAndInitialData();
  }

  @override
  void dispose() {
    messageController.dispose();
    _scrollController.dispose();
    socketService.offMessageReceived(_handleIncomingMessage);
    socketService.disconnect();
    super.dispose();
  }

  Future<void> _loadDoctorDetailsAndInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString(_userIdKey);
    userRole = prefs.getString("role");
    debugPrint("🔹 Doctor User ID: $userId, $userRole");

    if (userId == null || userId!.isEmpty) {
      _showSnackBar("User ID not found. Please log in again.", isError: true);
      _logOut();
      return;
    }

    await _connectAndListen();

    await Future.wait([_loadConversations(), _loadAppointments()]);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _connectAndListen() async {
    try {
      await socketService.connect();
      socketService.onMessageReceived(_handleIncomingMessage);
    } catch (e) {
      debugPrint("❌ Failed to connect socket: $e");
      _showSnackBar("Real-time connection failed.", isError: true);
    }
  }

  Future<void> downloadUserReport(String otherUserId) async {
    try {
      // ---------------- LOAD QUESTIONS ----------------
      final String questionsJson = await rootBundle.loadString(
        'assets/questions.json',
      );
      final List<dynamic> questions = jsonDecode(questionsJson);
      debugPrint("📌 Loaded ${questions.length} survey questions");

      // ---------------- API CALL ----------------
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        debugPrint("❌ ERROR: Token is NULL");
        return;
      }

      final response = await http.post(
        Uri.parse(
          "https://autisense-backend.onrender.com/api/doctor/user-info",
        ),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"userId": otherUserId}),
      );

      if (response.statusCode != 200) {
        debugPrint("❌ API failed with status ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);
      final user = data["user"] ?? {};
      final survey = data["survey"] ?? {};
      final video = data["video"] ?? {};

      debugPrint("📌 Parsed User: $user");
      debugPrint("📌 Parsed Survey: $survey");
      debugPrint("📌 Parsed Video: $video");

      // ---------------- LOAD FONTS ----------------
      final roboto = pw.Font.ttf(
        await rootBundle.load("fonts/Roboto-VariableFont_wdth,wght.ttf"),
      );
      final pacifico = pw.Font.ttf(
        await rootBundle.load("fonts/Pacifico-Regular.ttf"),
      );
      final merriweather = pw.Font.ttf(
        await rootBundle.load("fonts/Merriweather-BoldItalic.ttf"),
      );

      // ---------------- CREATE PDF ----------------
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(32),
          build:
              (context) => [
                // HEADER
                pw.Center(
                  child: pw.Text(
                    "ASD User Report",
                    style: pw.TextStyle(fontSize: 28, font: pacifico),
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 20),

                // USER INFO
                pw.Text(
                  "User Information",
                  style: pw.TextStyle(fontSize: 22, font: merriweather),
                ),
                pw.SizedBox(height: 10),
                pw.Bullet(
                  text: "Name: ${user['name'] ?? 'N/A'}",
                  style: pw.TextStyle(font: roboto),
                ),
                pw.Bullet(
                  text: "Email: ${user['email'] ?? 'N/A'}",
                  style: pw.TextStyle(font: roboto),
                ),
                pw.Bullet(
                  text: "Phone: ${user['phone'] ?? 'N/A'}",
                  style: pw.TextStyle(font: roboto),
                ),
                pw.Bullet(
                  text: "DOB: ${user['dob'] ?? 'N/A'}",
                  style: pw.TextStyle(font: roboto),
                ),
                pw.Bullet(
                  text: "Address: ${user['address'] ?? 'N/A'}",
                  style: pw.TextStyle(font: roboto),
                ),
                pw.SizedBox(height: 20),

                // ---------------- SURVEY TABLE ----------------
                pw.Text(
                  "Survey Results",
                  style: pw.TextStyle(fontSize: 22, font: merriweather),
                ),
                pw.SizedBox(height: 10),
                if (survey.isEmpty)
                  pw.Text(
                    "No survey data available",
                    style: pw.TextStyle(fontSize: 14, font: roboto),
                  )
                else
                  // SURVEY TABLE
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.blueGrey),
                    children: <pw.TableRow>[
                      // Header row
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.blue300),
                        children: [
                          pw.Padding(
                            padding: pw.EdgeInsets.all(4),
                            child: pw.Text(
                              "Question",
                              style: pw.TextStyle(
                                font: merriweather,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: pw.EdgeInsets.all(4),
                            child: pw.Text(
                              "Response",
                              style: pw.TextStyle(
                                font: merriweather,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Data rows
                      ...List<pw.TableRow>.generate(
                        (survey['responses'] as List<dynamic>).length,
                        (index) => pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color:
                                index % 2 == 0
                                    ? PdfColors.blue50
                                    : PdfColors.blue100,
                          ),
                          children: <pw.Widget>[
                            pw.Padding(
                              padding: pw.EdgeInsets.all(4),
                              child: pw.Text(
                                index < questions.length
                                    ? questions[index].toString()
                                    : "Question ${index + 1}",
                                style: pw.TextStyle(font: roboto, fontSize: 12),
                              ),
                            ),
                            pw.Padding(
                              padding: pw.EdgeInsets.all(4),
                              child: pw.Text(
                                survey['responses'][index].toString(),
                                style: pw.TextStyle(font: roboto, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                pw.SizedBox(height: 20),

                // ---------------- VIDEO TABLE ----------------
                pw.Text(
                  "Video Analysis",
                  style: pw.TextStyle(fontSize: 22, font: merriweather),
                ),
                pw.SizedBox(height: 10),
                if (video.isEmpty)
                  pw.Text(
                    "No video analysis available",
                    style: pw.TextStyle(fontSize: 14, font: roboto),
                  )
                else
                  // VIDEO TABLE
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.deepOrange),
                    children: <pw.TableRow>[
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: PdfColors.deepOrange300,
                        ),
                        children: [
                          pw.Padding(
                            padding: pw.EdgeInsets.all(4),
                            child: pw.Text(
                              "Field",
                              style: pw.TextStyle(
                                font: merriweather,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: pw.EdgeInsets.all(4),
                            child: pw.Text(
                              "Value",
                              style: pw.TextStyle(
                                font: merriweather,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      ...[
                            ["Video URL", video['videoUrl'] ?? 'N/A'],
                            [
                              "Final Prediction",
                              video['final_prediction']?['label'] ?? 'N/A',
                            ],
                            [
                              "Confidence",
                              video['final_prediction']?['confidence']
                                      ?.toString() ??
                                  'N/A',
                            ],
                            [
                              "Likelihood Score",
                              video['final_prediction']?['likelihood_score']
                                      ?.toString() ??
                                  'N/A',
                            ],
                            ...((video['detected_traits']
                                        as Map<String, dynamic>?)
                                    ?.entries
                                    .map((e) => [e.key, e.value.toString()]) ??
                                []),
                          ]
                          .map<pw.TableRow>(
                            (row) => pw.TableRow(
                              decoration: pw.BoxDecoration(
                                color:
                                    ((video['detected_traits']?.keys.toList() ??
                                                        [])
                                                    .indexOf(row[0]) %
                                                2 ==
                                            0)
                                        ? PdfColors.deepOrange50
                                        : PdfColors.deepOrange100,
                              ),
                              children: <pw.Widget>[
                                pw.Padding(
                                  padding: pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    row[0],
                                    style: pw.TextStyle(
                                      font: roboto,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding: pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    row[1],
                                    style: pw.TextStyle(
                                      font: roboto,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ],
                  ),

                pw.SizedBox(height: 20),
                pw.Divider(thickness: 1),
                pw.Center(
                  child: pw.Text(
                    "Generated on ${DateTime.now()}",
                    style: pw.TextStyle(fontSize: 12, font: roboto),
                  ),
                ),
              ],
        ),
      );

      final pdfBytes = await pdf.save();
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);

      debugPrint("✅ PDF generated and opened successfully!");
    } catch (e) {
      debugPrint("❌ ERROR in downloadUserReport(): $e");
    }
  }

  // Future<void> downloadUserReport(String otherUserId) async {
  //   try {
  //     debugPrint(
  //       "📌 STEP 1: Starting downloadUserReport() for userId = $otherUserId",
  //     );

  //     final prefs = await SharedPreferences.getInstance();
  //     final token = prefs.getString('token');
  //     if (token == null) return;

  //     final response = await http.post(
  //       Uri.parse(
  //         "https://autisense-backend.onrender.com/api/doctor/user-info",
  //       ),
  //       headers: {
  //         "Content-Type": "application/json",
  //         "Authorization": "Bearer $token",
  //       },
  //       body: jsonEncode({"userId": otherUserId}),
  //     );

  //     if (response.statusCode != 200) return;

  //     final data = jsonDecode(response.body);
  //     final user = data["user"] ?? {};
  //     final survey = data["survey"] ?? {};
  //     final video = data["video"] ?? {};

  //     final roboto = pw.Font.ttf(
  //       await rootBundle.load("fonts/Roboto-VariableFont_wdth,wght.ttf"),
  //     );
  //     final pacifico = pw.Font.ttf(
  //       await rootBundle.load("fonts/Pacifico-Regular.ttf"),
  //     );
  //     final merriweather = pw.Font.ttf(
  //       await rootBundle.load("fonts/Merriweather-BoldItalic.ttf"),
  //     );

  //     final pdf = pw.Document();

  //     pdf.addPage(
  //       pw.MultiPage(
  //         pageFormat: PdfPageFormat.a4,
  //         margin: pw.EdgeInsets.all(32),
  //         build:
  //             (context) => [
  //               // HEADER
  //               pw.Center(
  //                 child: pw.Text(
  //                   "ASD User Report",
  //                   style: pw.TextStyle(fontSize: 28, font: pacifico),
  //                 ),
  //               ),
  //               pw.Divider(thickness: 2),
  //               pw.SizedBox(height: 20),

  //               // USER INFO
  //               pw.Text(
  //                 "User Information",
  //                 style: pw.TextStyle(fontSize: 22, font: merriweather),
  //               ),
  //               pw.SizedBox(height: 10),
  //               pw.Bullet(
  //                 text: "Name: ${user['name'] ?? 'N/A'}",
  //                 style: pw.TextStyle(font: roboto),
  //               ),
  //               pw.Bullet(
  //                 text: "Email: ${user['email'] ?? 'N/A'}",
  //                 style: pw.TextStyle(font: roboto),
  //               ),
  //               pw.Bullet(
  //                 text: "Phone: ${user['phone'] ?? 'N/A'}",
  //                 style: pw.TextStyle(font: roboto),
  //               ),
  //               pw.Bullet(
  //                 text: "DOB: ${user['dob'] ?? 'N/A'}",
  //                 style: pw.TextStyle(font: roboto),
  //               ),
  //               pw.Bullet(
  //                 text: "Address: ${user['address'] ?? 'N/A'}",
  //                 style: pw.TextStyle(font: roboto),
  //               ),
  //               pw.SizedBox(height: 20),

  //               // SURVEY RESULTS AS TABLE
  //               pw.Text(
  //                 "Survey Results",
  //                 style: pw.TextStyle(fontSize: 22, font: merriweather),
  //               ),
  //               pw.SizedBox(height: 10),
  //               if (survey.isEmpty)
  //                 pw.Text(
  //                   "No survey data available",
  //                   style: pw.TextStyle(fontSize: 14, font: roboto),
  //                 )
  //               else
  //                 pw.Table.fromTextArray(
  //                   headers: ["Question #", "Response"],
  //                   data: List<List<String>>.generate(
  //                     (survey['responses'] as List<dynamic>).length,
  //                     (index) => [
  //                       (index + 1).toString(),
  //                       survey['responses'][index].toString(),
  //                     ],
  //                   ),
  //                   headerStyle: pw.TextStyle(font: merriweather, fontSize: 14),
  //                   cellStyle: pw.TextStyle(font: roboto, fontSize: 12),
  //                   cellAlignment: pw.Alignment.centerLeft,
  //                   headerDecoration: pw.BoxDecoration(
  //                     color: PdfColors.grey300,
  //                   ),
  //                   border: pw.TableBorder.all(color: PdfColors.grey),
  //                 ),
  //               pw.SizedBox(height: 20),

  //               // VIDEO ANALYSIS
  //               pw.Text(
  //                 "Video Analysis",
  //                 style: pw.TextStyle(fontSize: 22, font: merriweather),
  //               ),
  //               pw.SizedBox(height: 10),
  //               pw.Text(
  //                 video == null || video.isEmpty
  //                     ? "No video analysis available"
  //                     : jsonEncode(video),
  //                 style: pw.TextStyle(fontSize: 14, font: roboto),
  //                 softWrap: true,
  //               ),
  //               pw.SizedBox(height: 20),

  //               // FOOTER
  //               pw.Divider(thickness: 1),
  //               pw.Center(
  //                 child: pw.Text(
  //                   "Generated on ${DateTime.now()}",
  //                   style: pw.TextStyle(fontSize: 12, font: roboto),
  //                 ),
  //               ),
  //             ],
  //       ),
  //     );

  //     final pdfBytes = await pdf.save();
  //     await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
  //   } catch (e) {
  //     debugPrint("❌ ERROR in downloadUserReport(): $e");
  //   }
  // }

  void _handleIncomingMessage(dynamic data) {
    debugPrint('SOCKET: Message Received: $data');
    if (data is Map<String, dynamic>) {
      final newMessage = data;
      final msgConvoId = newMessage['conversationId'];

      if (isChatOpen && msgConvoId == selectedConversationId) {
        dynamic senderData = newMessage['sender'];
        String senderId = "";
        if (senderData is Map<String, dynamic>) {
          senderId = senderData['id']?.toString() ?? '';
        } else {
          senderId = senderData?.toString() ?? '';
        }

        if (senderId != userId) {
          if (mounted) {
            setState(() {
              messages.insert(0, newMessage);
            });
            _scrollToBottom();
          }
        }
      }

      if (mounted) {
        setState(() {
          final convoIndex = conversations.indexWhere(
            (c) => c['_id'] == msgConvoId,
          );
          if (convoIndex != -1) {
            final convo = conversations.removeAt(convoIndex);
            convo['lastMessage'] = newMessage['message'];
            convo['updatedAt'] = newMessage['createdAt'];
            conversations.insert(0, convo);
          }
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.orangeAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadConversations({bool forceRefresh = false}) async {
    // ... existing logic (no changes needed) ...
    final prefs = await SharedPreferences.getInstance();
    String? cachedDataString;

    if (!forceRefresh) {
      cachedDataString = prefs.getString(_conversationsCacheKey);
      if (cachedDataString != null) {
        try {
          final List<dynamic> cachedDynamicList = json.decode(cachedDataString);
          if (mounted) {
            setState(() {
              conversations = cachedDynamicList.cast<Map<String, dynamic>>();
              debugPrint("✅ Loaded conversations from cache.");
            });
          }
        } catch (e) {
          debugPrint("⚠️ Error decoding conversations cache: $e");
          await prefs.remove(_conversationsCacheKey);
        }
      }
    }

    try {
      final List<Map<String, dynamic>> fetchedConversations =
          await ApiService.fetchConversations(role: 'doctor');

      if (!mounted) return;

      final String fetchedDataString = json.encode(fetchedConversations);

      if (fetchedDataString != cachedDataString) {
        debugPrint("🔄 Updated conversations cache.");
        await prefs.setString(_conversationsCacheKey, fetchedDataString);
        setState(() {
          conversations = fetchedConversations;
        });
        if (cachedDataString != null) {
          _showSnackBar("Conversations updated.");
        }
      } else {
        debugPrint("ℹ️ Conversations are up-to-date.");
      }
    } catch (e) {
      debugPrint("❌ Error loading conversations: $e");
      if (cachedDataString == null) {
        if (mounted) {
          _showSnackBar("Could not load conversations.", isError: true);
        }
      }
    }
  }

  Future<void> _loadAppointments({bool forceRefresh = false}) async {
    // ... existing logic (no changes needed) ...
    final prefs = await SharedPreferences.getInstance();

    // 1️⃣ Load cached data if not forcing refresh
    if (!forceRefresh) {
      try {
        final cachedPending = prefs.getString(_pendingCacheKey);
        final cachedApproved = prefs.getString(_approvedCacheKey);

        if (cachedPending != null) {
          pendingAppointments =
              (json.decode(cachedPending) as List).cast<Map<String, dynamic>>();
        }
        if (cachedApproved != null) {
          approvedAppointments =
              (json.decode(cachedApproved) as List)
                  .cast<Map<String, dynamic>>();
        }

        if (mounted) {
          setState(() {
            _pendingCount = pendingAppointments.length;
          });
        }

        debugPrint("✅ Loaded appointments from cache.");
      } catch (e) {
        debugPrint("⚠️ Error decoding appointment cache: $e");
        await prefs.remove(_pendingCacheKey);
        await prefs.remove(_approvedCacheKey);
        pendingAppointments = [];
        approvedAppointments = [];
        if (mounted) setState(() => _pendingCount = 0);
      }
    } else {
      // Clear local data first
      pendingAppointments = [];
      approvedAppointments = [];
      if (mounted) setState(() => _pendingCount = 0);
    }

    // 2️⃣ Always fetch fresh data from the API
    try {
      final results = await Future.wait([
        ApiService.fetchPendingAppointments(),
        ApiService.fetchapprovedAppointments(),
      ]);

      debugPrint("✅ Loaded appointments from cache.");

      final List<Map<String, dynamic>> fetchedPending = results[0];
      final List<Map<String, dynamic>> fetchedApproved = results[1];

      // Update cache
      await prefs.setString(_pendingCacheKey, json.encode(fetchedPending));
      await prefs.setString(_approvedCacheKey, json.encode(fetchedApproved));

      // 3️⃣ Always update UI
      if (mounted) {
        setState(() {
          pendingAppointments = fetchedPending;
          approvedAppointments = fetchedApproved;
          _pendingCount = pendingAppointments.length;
        });
      }

      debugPrint("🔄 Appointments updated successfully from API.");
    } catch (e) {
      debugPrint("❌ Error loading appointments from API: $e");
      if (prefs.getString(_pendingCacheKey) == null &&
          prefs.getString(_approvedCacheKey) == null) {
        if (mounted) {
          _showSnackBar("Could not load appointments.", isError: true);
        }
      }
    }
  }

  Future<void> _loadMessages() async {
    // ... existing logic (no changes needed) ...
    if (selectedConversationId == null) return;
    try {
      final data = await ApiService.fetchMessages(selectedConversationId!);
      if (mounted) {
        setState(() => messages = data.reversed.toList());
      }
    } catch (e) {
      debugPrint("❌ Error fetching messages: $e");
      if (mounted) _showSnackBar("Could not load messages.", isError: true);
    }
  }

  Future<void> _openChat(Map conversation) async {
    if (userId == null) {
      _showSnackBar("User ID not found. Cannot open chat.", isError: true);
      return;
    }

    selectedConversationId = conversation["_id"]?.toString();
    if (selectedConversationId == null) {
      _showSnackBar("Conversation ID missing.", isError: true);
      return;
    }

    // Join socket room
    socketService.joinRoom(selectedConversationId!);

    // Extract participants
    final List participants = conversation["participants"] ?? [];

    final otherUser = participants.firstWhere(
      (p) => p is Map && p["id"] != userId,
      orElse:
          () =>
              participants.isNotEmpty && participants.first is Map
                  ? participants.first
                  : {"name": "Unknown", "id": null},
    );

    // Store name
    selectedUser = otherUser["name"] ?? "Unknown User";

    // Store the entire peer info
    _currentPeer = otherUser;

    // ✅ Store the other user's ID
    otherUserId = otherUser["id"]?.toString();

    debugPrint("OTHER USER ID: $otherUserId");

    setState(() => isChatOpen = true);

    await _loadMessages();
  }

  Future<void> _sendMessage() async {
    // ... existing logic (no changes needed) ...
    final text = messageController.text.trim();
    if (text.isEmpty || selectedConversationId == null || userId == null)
      return;

    if (!socketService.isConnected) {
      _showSnackBar("Not connected. Reconnecting...", isError: true);
      await _connectAndListen();
      await Future.delayed(const Duration(seconds: 1));
      if (!socketService.isConnected) {
        _showSnackBar("Connection failed. Please try again.", isError: true);
        return;
      }
    }

    final tempMessage = {
      "message": text,
      "sender": {"id": userId},
      "senderPic": null,
      "conversationId": selectedConversationId!,
      "createdAt": DateTime.now().toIso8601String(),
    };
    if (mounted) {
      setState(() {
        messages.insert(0, tempMessage);
        messageController.clear();
      });
      _scrollToBottom();
    }

    try {
      socketService.sendMessage(selectedConversationId!, text);
    } catch (e) {
      debugPrint("❌ Error emitting message: $e");
      if (mounted) {
        _showSnackBar("Error sending message: $e", isError: true);
        setState(() {
          messages.remove(tempMessage);
        });
      }
    }
  }

  // --- ADDED: Method to start the video call ---
  Future<void> _startVideoCall({required bool isvideoCall}) async {
    if (selectedConversationId == null ||
        userId == null ||
        _currentPeer == null) {
      _showSnackBar("Cannot start call. Chat not fully loaded.", isError: true);
      return;
    }

    final String peerUserId = _currentPeer!['id']?.toString() ?? '';
    final String peerName = _currentPeer!['name']?.toString() ?? 'Peer';
    // For now, we'll use a placeholder.
    final String selfName = "Doctor";

    if (peerUserId.isEmpty) {
      _showSnackBar("Cannot start call. Peer ID is missing.", isError: true);
      return;
    }

    debugPrint("📞 Initiating call to $peerName ($peerUserId)");

    // 1. Emit initiateCall (sends notification to peer)
    socketService.initiateCall(
      conversationId: selectedConversationId!,
      fromUserId: userId!,
      toUserId: peerUserId,
      callerName: selfName, // This is YOUR name
    );

    // 2. Navigate to VideoCall screen as the CALLER
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => VideoCall(
              socket: socketService.socket!,
              callerName: peerName, // Name of the person we are calling
              selfUserId: userId!,
              peerUserId: peerUserId,
              conversationId: selectedConversationId!,
              isCaller: true,
              isVideoCall: isvideoCall,
            ),
      ),
    );
  }

  Future<void> _logOut() async {
    // ... existing logic (no changes needed) ...
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_pendingCacheKey);
    await prefs.remove(_approvedCacheKey);
    await prefs.remove(_conversationsCacheKey);

    socketService.disconnect();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // ===========================
  // Appointments modal & approval
  // ===========================
  void _showAppointmentsSheet() async {
    // ... existing logic (no changes needed) ...
    showModalBottomSheet(
      // ignore: use_build_context_synchronously
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // 🧠 Small helper to trigger list reload
            Future<void> refreshLists() async {
              await _loadAppointments(forceRefresh: false);
              if (mounted) setModalState(() {});
            }

            Widget buildCard(
              Map<String, dynamic> req, {
              bool approved = false,
            }) {
              final dateStr = req['date'] ?? req['appointmentStartDate'];
              final date = DateTime.tryParse(dateStr ?? '');
              final formattedDate =
                  date != null
                      ? DateFormat('E, MMM d, yyyy').format(date)
                      : 'Unknown Date';

              final startTime = req['appointmentStartTime'] ?? 'N/A';
              final endTime = req['appointmentEndTime'] ?? 'N/A';
              final patient = req['patient']?['name'] ?? 'Unknown Patient';
              final description =
                  req['description'] ?? 'No description provided';
              final String appointmentId =
                  req['appointmentId']?.toString() ??
                  req['_id']?.toString() ??
                  '';

              return Card(
                color: approved ? Colors.green.shade50 : Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        approved
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                    child: Text(
                      patient.isNotEmpty ? patient[0].toUpperCase() : '?',
                      style: TextStyle(
                        color:
                            approved
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                      ),
                    ),
                  ),
                  title: Text(
                    patient,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("🗓️ Date: $formattedDate"),
                      Text("🕒 Time: $startTime - $endTime"),
                      Text(
                        "📋 Issue: $description",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  trailing:
                      approved
                          ? Icon(
                            Icons.check_circle_outline,
                            color: Colors.green.shade600,
                            size: 28,
                          )
                          : Icon(
                            Icons.pending_actions_outlined,
                            color: Colors.orange.shade700,
                            size: 28,
                          ),
                  onTap:
                      approved || appointmentId.isEmpty
                          ? null
                          : () async {
                            final result = await _showApprovalForm(req);
                            if (result == true) {
                              await refreshLists(); // ✅ always reload both lists
                            }
                          },
                ),
              );
            }

            Widget buildSection(
              String title,
              List<Map<String, dynamic>> list, {
              bool approved = false,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            approved
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                      ),
                    ),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          approved
                              ? "No approved appointments"
                              : "No pending requests",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  else
                    ...list.map((e) => buildCard(e, approved: approved)),
                  const SizedBox(height: 15),
                  if (!approved)
                    Divider(
                      thickness: 1,
                      color: Colors.grey.shade300,
                      height: 20,
                    ),
                ],
              );
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (_, controller) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 45,
                          height: 5,
                          margin: const EdgeInsets.only(top: 8, bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: controller,
                          children: [
                            buildSection(
                              "Pending Requests",
                              pendingAppointments,
                            ),
                            buildSection(
                              "Approved Appointments",
                              approvedAppointments,
                              approved: true,
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool?> _showApprovalForm(Map<String, dynamic> request) async {
    // ... existing logic (no changes needed) ...
    DateTime? date;
    TimeOfDay? start;
    TimeOfDay? end;
    bool isProcessing = false;

    final String appointmentId =
        request['appointmentId']?.toString() ??
        request['_id']?.toString() ??
        '';

    if (appointmentId.isEmpty) {
      _showSnackBar("Cannot approve: Missing appointment ID.", isError: true);
      return false;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setApprovalModalState) {
            final safeName = request['patient']?['name'] ?? 'Unknown Patient';
            final issue =
                (request['description']?.toString().trim().isNotEmpty ?? false)
                    ? request['description']
                    : 'No description provided';

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 45,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Text(
                      "Approve Appointment",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Patient: $safeName",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Issue: $issue",
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 20),

                    // date + time pickers
                    _buildPickerButton(
                      context: context,
                      icon: Icons.calendar_month_outlined,
                      label:
                          date == null
                              ? "Select Date"
                              : DateFormat('yyyy-MM-dd').format(date!),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: date ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setApprovalModalState(() => date = d);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildPickerButton(
                      context: context,
                      icon: Icons.access_time_outlined,
                      label:
                          start == null
                              ? "Select Start Time"
                              : start!.format(context),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: start ?? TimeOfDay.now(),
                        );
                        if (t != null) setApprovalModalState(() => start = t);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildPickerButton(
                      context: context,
                      icon: Icons.timer_off_outlined,
                      label:
                          end == null
                              ? "Select End Time"
                              : end!.format(context),
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: end ?? TimeOfDay.now(),
                        );
                        if (t != null) {
                          if (start != null) {
                            final startMin = start!.hour * 60 + start!.minute;
                            final endMin = t.hour * 60 + t.minute;
                            if (endMin <= startMin) {
                              _showSnackBar(
                                "End time must be after start time.",
                                isError: true,
                              );
                              return;
                            }
                          }
                          setApprovalModalState(() => end = t);
                        }
                      },
                    ),
                    const SizedBox(height: 25),

                    if (isProcessing)
                      Center(
                        child: CircularProgressIndicator(
                          color: Colors.orange.shade700,
                        ),
                      )
                    else
                      Row(
                        children: [
                          // ❌ Reject
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text("Reject"),
                              onPressed: () async {
                                setApprovalModalState(
                                  () => isProcessing = true,
                                );
                                try {
                                  final success =
                                      await ApiService.rejectAppointment(
                                        appointmentId,
                                      );
                                  if (success) {
                                    _showSnackBar(
                                      "Appointment rejected",
                                      isError: false,
                                    );
                                    Navigator.pop(context, true);
                                  } else {
                                    _showSnackBar(
                                      "Failed to reject appointment.",
                                      isError: true,
                                    );
                                  }
                                } catch (e) {
                                  _showSnackBar("Error: $e", isError: true);
                                } finally {
                                  if (mounted) {
                                    setApprovalModalState(
                                      () => isProcessing = false,
                                    );
                                  }
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade600,
                                side: BorderSide(
                                  color: Colors.red.shade300,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // ✅ Approve
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check),
                              label: const Text("Confirm"),
                              onPressed: () async {
                                if (date == null ||
                                    start == null ||
                                    end == null) {
                                  _showSnackBar(
                                    "Select date and time",
                                    isError: true,
                                  );
                                  return;
                                }
                                setApprovalModalState(
                                  () => isProcessing = true,
                                );
                                try {
                                  final success =
                                      await ApiService.approveAppointment(
                                        requestId: appointmentId,
                                        date: DateFormat(
                                          'yyyy-MM-dd',
                                        ).format(date!),
                                        startTime: start!.format(context),
                                        endTime: end!.format(context),
                                      );
                                  if (success) {
                                    _showSnackBar("Appointment approved");
                                    Navigator.pop(context, true);
                                  } else {
                                    _showSnackBar(
                                      "Failed to approve appointment.",
                                      isError: true,
                                    );
                                  }
                                } catch (e) {
                                  _showSnackBar(
                                    "Error approving: $e",
                                    isError: true,
                                  );
                                } finally {
                                  if (mounted) {
                                    setApprovalModalState(
                                      () => isProcessing = false,
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.orange.shade700,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Widget _buildPickerButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    // ... existing logic (no changes needed) ...
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.orange.shade700, size: 20),
      label: Text(
        label,
        style: TextStyle(color: Colors.orange.shade900, fontSize: 16),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange.shade900,
        side: BorderSide(color: Colors.orange.shade300, width: 1),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.centerLeft,
      ),
    );
  }

  // Chat window and chat list UI
  Widget _buildChatWindow() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(
            top: 8.0,
            bottom: 12.0,
            left: 8.0,
            right: 16.0,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade700, Colors.orange.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.shade200.withOpacity(0.6),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed:
                    () => setState(() {
                      isChatOpen = false;
                      _currentPeer = null; // <-- MODIFIED: Clear the peer
                    }),
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 22,
                ),
                tooltip: "Back to Chats",
              ),
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white.withOpacity(0.3),
                child: Text(
                  selectedUser.isNotEmpty ? selectedUser[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedUser,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.videocam_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  _startVideoCall(isvideoCall: true);
                }, // <-- MODIFIED
                tooltip: "Video Call",
              ),
              IconButton(
                icon: const Icon(
                  Icons.call_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  _startVideoCall(isvideoCall: false);
                },
                tooltip: "Voice Call",
              ),
              IconButton(
                icon: const Icon(
                  Icons.file_download_outlined,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  downloadUserReport(otherUserId!);
                },
                tooltip: "Download Report",
              ),
            ],
          ),
        ),
        Expanded(
          child:
              messages.isEmpty
                  ? const Center(
                    child: Text(
                      "No messages yet. Start chatting!",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                  : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: messages.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      if (msg == null ||
                          msg is! Map ||
                          msg["message"] == null ||
                          msg["sender"] == null) {
                        return const SizedBox.shrink();
                      }

                      dynamic senderData = msg['sender'];
                      String senderId = "";
                      if (senderData is Map<String, dynamic>) {
                        senderId = senderData['id']?.toString() ?? '';
                      } else {
                        senderId = senderData?.toString() ?? '';
                      }
                      final isMe = senderId == userId;

                      final bool isLocalFile = msg["filePath"] != null;
                      final bool isVideo = msg["message"].toString().contains(
                        "[Video File",
                      );

                      return Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding:
                              isLocalFile
                                  ? const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 12,
                                  )
                                  : const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 14,
                                  ),
                          decoration: BoxDecoration(
                            color:
                                isMe
                                    ? Colors.orange.shade200
                                    : Colors.grey.shade200,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 0),
                              bottomRight: Radius.circular(isMe ? 0 : 16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child:
                              isLocalFile
                                  ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isVideo
                                            ? Icons.videocam_outlined
                                            : Icons.image_outlined,
                                        color: Colors.grey.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          msg["message"].toString(),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.black87,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                  : Text(
                                    msg["message"].toString(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                        ),
                      );
                    },
                  ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: Colors.orange,
                    size: 28,
                  ),
                  tooltip: "Send Media",
                  onPressed: _pickMedia,
                ),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    style: const TextStyle(fontSize: 16),
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide(
                          color: Colors.orange.shade400,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatList() {
    // ... existing logic (no changes needed) ...
    if (conversations.isEmpty && !_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 60,
                color: Colors.orange.shade300,
              ),
              const SizedBox(height: 16),
              const Text(
                "No Conversations Yet",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A2500),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Approved appointments will appear here.",
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              IconButton(
                icon: const Icon(Icons.refresh, size: 30, color: Colors.orange),
                tooltip: "Refresh Conversations",
                onPressed: () => _loadConversations(forceRefresh: true),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadConversations(forceRefresh: true),
      color: Colors.orange,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final convo = conversations[index];
          if (convo == null ||
              convo is! Map ||
              convo["participants"] == null ||
              convo["participants"] is! List ||
              (convo["participants"] as List).isEmpty) {
            return const SizedBox.shrink();
          }

          final List participants = convo["participants"];
          final otherUser = participants.firstWhere(
            (p) => p is Map && p["id"] != userId,
            orElse:
                () => participants.firstWhere(
                  (p) => p is Map,
                  orElse: () => null,
                ),
          );

          if (otherUser == null) return const SizedBox.shrink();

          final String otherUserName = otherUser["name"] ?? "Unknown User";
          final String otherUserRole = otherUser["role"] ?? "User";
          final String initial =
              otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : "?";
          final String lastMessage =
              convo['lastMessage'] ?? 'No messages yet...';
          final String lastMessageTime =
              convo['updatedAt'] != null
                  ? DateFormat(
                    'h:mm a',
                  ).format(DateTime.parse(convo['updatedAt']).toLocal())
                  : '';
          final String? otherUserImageUrl = otherUser['imageUrl'];

          return Card(
            color: Colors.white,
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: Colors.orange.shade100,
                backgroundImage:
                    (otherUserImageUrl != null && otherUserImageUrl.isNotEmpty)
                        ? NetworkImage(otherUserImageUrl)
                        : null,
                child:
                    (otherUserImageUrl != null && otherUserImageUrl.isNotEmpty)
                        ? null
                        : Text(
                          initial,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
              ),
              title: Text(
                otherUserName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                lastMessage,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontStyle:
                      lastMessage == 'No messages yet...'
                          ? FontStyle.italic
                          : FontStyle.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    lastMessageTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.orange.shade400,
                    size: 16,
                  ),
                ],
              ),
              onTap: () => _openChat(convo),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... existing logic (no changes needed) ...
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.orange.shade50,
      floatingActionButton:
          !isChatOpen && userRole == "Doctor"
              ? badges.Badge(
                showBadge: _pendingCount > 0,
                position: badges.BadgePosition.topEnd(top: -4, end: -4),
                badgeContent: Text(
                  _pendingCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                badgeStyle: const badges.BadgeStyle(badgeColor: Colors.red),
                child: FloatingActionButton(
                  backgroundColor: Colors.orange.shade700,
                  onPressed: _showAppointmentsSheet,
                  tooltip: "View Appointments",
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    size: 28,
                    color: Colors.white,
                  ),
                ),
              )
              : null,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          key: ValueKey(isChatOpen),
          child:
              _isLoading
                  ? const Center(
                    child: CircularProgressIndicator(color: Colors.orange),
                  )
                  : isChatOpen
                  ? _buildChatWindow()
                  : _buildChatList(),
        ),
      ),
    );
  }

  // Media picker helpers (unchanged)
  void _sendMediaMessage(File file, {bool isVideo = false}) {
    // ... existing logic (no changes needed) ...
    _showSnackBar("Media upload not implemented yet.", isError: true);
    if (!mounted) return;
    setState(() {
      messages.insert(0, {
        "sender": {"id": userId, "role": "doctor"},
        "message":
            isVideo
                ? "[Video File: ${file.path.split('/').last}]"
                : "[Image File: ${file.path.split('/').last}]",
        "timestamp": DateTime.now().toIso8601String(),
        "filePath": file.path,
      });
    });
  }

  final ImagePicker _picker = ImagePicker();
  Future<void> _pickMedia() async {
    // ... existing logic (no changes needed) ...
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Text(
                  "Choose Media",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildSquareOption(
                      icon: Icons.photo_outlined,
                      label: "Gallery",
                      color: Colors.orange,
                      onTap: () async {
                        Navigator.pop(context);
                        final XFile? image = await _picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 80,
                        );
                        if (image != null) {
                          _sendMediaMessage(File(image.path), isVideo: false);
                        }
                      },
                    ),
                    _buildSquareOption(
                      icon: Icons.videocam_outlined,
                      label: "Video",
                      color: Colors.orange,
                      onTap: () async {
                        Navigator.pop(context);
                        final XFile? video = await _picker.pickVideo(
                          source: ImageSource.gallery,
                        );
                        if (video != null) {
                          _sendMediaMessage(File(video.path), isVideo: true);
                        }
                      },
                    ),
                    _buildSquareOption(
                      icon: Icons.camera_alt_outlined,
                      label: "Camera",
                      color: Colors.orange,
                      onTap: () async {
                        Navigator.pop(context);
                        final XFile? photo = await _picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 80,
                        );
                        if (photo != null) {
                          _sendMediaMessage(File(photo.path), isVideo: false);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSquareOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    // ... existing logic (no changes needed) ...
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withAlpha((255 * 0.08).round()),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha((255 * 0.3).round())),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
