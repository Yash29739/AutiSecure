// ignore: file_names
import 'dart:convert';
import 'package:autisecure/landing_screens/doctor_landing_screen.dart';
import 'package:autisecure/landing_screens/admin_landing_screen.dart';
import 'package:autisecure/landing_screens/landing_screen.dart';
import 'package:autisecure/login_signup/signup_screen.dart';
import 'package:autisecure/main.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String dropDownValue = "User";
  var users = ["User", "Doctor", "Admin"];
  @override
  void initState() {
    super.initState();
    // This delays the check until after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfLoggedIn(context);
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _checkIfLoggedIn(context) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    // final role = prefs.getString('role');

    if (token != null && token.isNotEmpty) {
      // Check if the widget is still mounted before navigating
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder:
              (context) =>
                  dropDownValue == "Admin"
                      ? AdminLandingScreen()
                      : dropDownValue == "Doctor"
                      ? DoctorLndingScreen()
                      : Landingscreen(),
        ),
        (Route<dynamic> route) =>
            false, // This line removes all previous routes
      );
    }
  }

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<void> submitLogin(BuildContext context) async {
    // --- Regex Validation ---
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
    );
    final passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$');

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email and password cannot be empty")),
      );
      return;
    }
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid email format")));
      return;
    }
    if (!passwordRegex.hasMatch(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must be 8+ characters with at least one letter and one number",
          ),
        ),
      );
      return;
    }
    // --- End of Validation ---

    // Show loading indicator (optional but good UX)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final url = Uri.parse(
      dropDownValue == "Doctor"
          ? "https://autisense-backend.onrender.com/api/doctor/login"
          : dropDownValue == "Admin"
          ? "https://autisense-backend.onrender.com/api/admin/login"
          : "https://autisense-backend.onrender.com/api/user/login",
    );

    final Map<String, dynamic> data = {"email": email, "password": password};

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      // Dismiss loading indicator
      if (mounted) Navigator.pop(context); // Pops the loading dialog
      if (!mounted) return; // Check mount status again after async gap

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final message = responseData['message'] ?? 'Login successful!';
        final token = responseData['token'];

        // --- Safely Extract userId and Name ---
        String? userId;
        String? userName;
        // Adjust keys ('user', 'id', 'name') if your backend response differs
        if (responseData['user'] != null && responseData['user'] is Map) {
          // Use 'id' or '_id' depending on your backend
          userId =
              responseData['user']['id']?.toString() ??
              responseData['user']['_id']?.toString();
          userName = responseData['user']['name']?.toString();
        } else if (responseData['doctor'] != null &&
            responseData['doctor'] is Map) {
          // Handle doctor login response structure if different
          userId =
              responseData['doctor']['id']?.toString() ??
              responseData['doctor']['_id']?.toString();
          userName = responseData['doctor']['name']?.toString();
        } else if (responseData['admin'] != null &&
            responseData['admin'] is Map) {
          // Handle admin login response structure if different
          userId =
              responseData['admin']['id']?.toString() ??
              responseData['admin']['_id']?.toString();
          userName = responseData['admin']['name']?.toString();
        }

        // Check if token and userId were actually received
        if (token == null ||
            token.isEmpty ||
            userId == null ||
            userId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Login failed: Missing token or user ID in response.",
              ),
            ),
          );
          return;
        }
        // --- End Extraction ---

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('role', dropDownValue);
        // --- SAVE USER ID ---
        await prefs.setString('userId', userId);
        // --- SAVE USER NAME (Optional) ---
        if (userName != null) {
          await prefs.setString(
            'userName',
            userName,
          ); // Store name if available
        }

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await updateFcmToken(fcmToken);
        }

        _emailController.clear();
        _passwordController.clear();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));

        // Use pushAndRemoveUntil to clear the stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    dropDownValue == "Admin"
                        ? const AdminLandingScreen()
                        : dropDownValue == "Doctor"
                        ? const DoctorLndingScreen()
                        : const Landingscreen(),
          ),
          (Route<dynamic> route) => false, // Remove all previous routes
        );
      } else {
        // Try to parse error message from backend
        String errorMessage = "Login Failed";
        try {
          final errorData = json.decode(response.body);
          errorMessage = errorData['message'] ?? response.body;
        } catch (_) {
          errorMessage = response.body; // Fallback to raw body
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      // Dismiss loading indicator on error
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Network error: ${e.toString()}")));
    }
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    bool obscureText,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          fillColor: Colors.white,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blue, width: 3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.purple, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5E3),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(padding: EdgeInsets.symmetric(vertical: 20)),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset("assets/logo.png", width: 120),
              ),
              Text(
                "AutiSecure",
                style: TextStyle(
                  color: Color.fromARGB(255, 0, 0, 0),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: "Merriweather",
                ),
              ),
              SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      "LogIn",
                      style: TextStyle(
                        fontFamily: "merriweather",
                        fontSize: 40,
                        color: Color(0xFF813400),
                      ),
                    ),
                    SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        // Background color
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple, width: 1),
                      ),
                      child: DropdownButtonHideUnderline(
                        // Hide default underline
                        child: DropdownButton<String>(
                          value: dropDownValue,
                          isExpanded: true, // Makes it take full width
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: Colors.grey[600],
                          ),
                          items:
                              users.map((String i) {
                                return DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    i,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              dropDownValue = newValue!;
                            });
                          },
                          borderRadius: BorderRadius.circular(
                            8,
                          ), // Dropdown menu background
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    _buildTextField("Email", _emailController, false),
                    SizedBox(height: 10),
                    _buildTextField("Password", _passwordController, true),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => submitLogin(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        "LogIn",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Don't have an Account?"),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SignUpScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                "Register here",
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
