// ignore: file_names
import 'dart:convert';
import 'dart:io';

import 'package:autisecure/login_signup/login_screen.dart';
import 'package:autisecure/mainScreens/user/home_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
// 1. ADD THIS IMPORT
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  String dropDownValue = "User";
  File? doctorImage;
  var users = ["User", "Doctor"];

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController phController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController dobController = TextEditingController();

  // For the Doctor
  final TextEditingController docInfo = TextEditingController();
  final TextEditingController clinicLoc = TextEditingController();
  final TextEditingController experience = TextEditingController();
  final TextEditingController specialization = TextEditingController();

  @override
  void initState() {
    super.initState();
    // This delays the check until after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfLoggedIn();
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    confirmPasswordController.dispose();
    phController.dispose();
    addressController.dispose();
    dobController.dispose();
    docInfo.dispose();
    clinicLoc.dispose();
    experience.dispose();
    specialization.dispose();
    super.dispose();
  }

  // Helper function to safely show a SnackBar
  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _checkIfLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  Future<void> submitRegistration(BuildContext context) async {
    // --- START VALIDATION ---
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final phone = phController.text.trim();
    final address = addressController.text.trim();
    final dob = dobController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final fcmToken = await FirebaseMessaging.instance.getToken();

    // 1️⃣ Check for empty fields
    if (name.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        address.isEmpty ||
        dob.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showSnackBar("⚠️ Please fill all required fields.", Colors.red);
      debugPrint("⚠️ Please fill all required fields.");
      return;
    }

    // 2️⃣ Password match check
    if (password != confirmPassword) {
      _showSnackBar("⚠️ Passwords do not match.", Colors.red);
      debugPrint("⚠️ Passwords do not match");
      return;
    }

    // 3️⃣ Define Regex patterns
    final nameRegex = RegExp(r'^[a-zA-Z\s\-]+$');
    final emailRegex = RegExp(r"^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$");
    final phoneRegex = RegExp(r'^\d{10}$');
    final passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$');

    // 4️⃣ Apply Regex
    if (!nameRegex.hasMatch(name)) {
      _showSnackBar(
        "Enter a valid name (letters, spaces, hyphens only).",
        Colors.red,
      );
      debugPrint("Enter a valid name (letters, spaces, hyphens only).");
      return;
    }
    if (!emailRegex.hasMatch(email)) {
      _showSnackBar("Invalid email format.", Colors.red);
      debugPrint("Invalid email format.");
      return;
    }
    if (!phoneRegex.hasMatch(phone)) {
      _showSnackBar("Phone number must be exactly 10 digits.", Colors.red);
      debugPrint("Phone number must be exactly 10 digits.");
      return;
    }
    if (!passwordRegex.hasMatch(password)) {
      _showSnackBar(
        "Password must be at least 8 characters long and include one letter and one number.",
        Colors.red,
      );
      debugPrint(
        "Password must be at least 8 characters long and include one letter and one number.",
      );
      return;
    }

    // 5️⃣ Doctor-specific validation
    if (dropDownValue == "Doctor") {
      if (specialization.text.trim().isEmpty ||
          experience.text.trim().isEmpty ||
          docInfo.text.trim().isEmpty ||
          clinicLoc.text.trim().isEmpty) {
        _showSnackBar("Please fill all doctor-specific fields.", Colors.red);
        debugPrint("Please fill all doctor-specific fields.");
        return;
      }
    }

    // --- END VALIDATION ---

    // 6️⃣ Upload doctor image if provided
    String? imageUrl;
    if (doctorImage != null) {
      try {
        imageUrl = await uploadDoctorimage(doctorImage!);
      } catch (e) {
        _showSnackBar("Image upload failed. Please try again.", Colors.red);
        debugPrint("Image upload failed. Please try again.");
        return;
      }
    }

    // 7️⃣ Prepare request data
    final url = Uri.parse(
      dropDownValue == "Doctor"
          ? 'https://autisense-backend.onrender.com/api/doctor/register'
          : 'https://autisense-backend.onrender.com/api/user/register',
    );

    final Map<String, dynamic> data = {
      "name": name,
      "email": email,
      "phone": phone,
      "address": address,
      "dob": dob,
      "password": password,
      "imageUrl": imageUrl,
      "fcmToken": fcmToken,
    };

    if (dropDownValue == "Doctor") {
      data.addAll({
        "speciality": specialization.text.trim(),
        "experience": int.tryParse(experience.text.trim()) ?? 0,
        "description": docInfo.text.trim(),
        "clinicAddress": clinicLoc.text.trim(),
      });
    }

    // 8️⃣ Send data to both servers
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      debugPrint("FCM Token: $fcmToken");
      debugPrint("Response : ${response.statusCode} ${response.body}");

      if (!context.mounted) return;

      // 9️⃣ Handle responses clearly
      if (response.statusCode == 201) {
        // Clear all controllers
        nameController.clear();
        emailController.clear();
        phController.clear();
        addressController.clear();
        dobController.clear();
        passwordController.clear();
        confirmPasswordController.clear();
        specialization.clear();
        experience.clear();
        docInfo.clear();
        clinicLoc.clear();

        _showSnackBar("✅ Registration successful!", Colors.green);
        debugPrint("✅ Registration successful!");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      } else {
        final msg1 =
            jsonDecode(response.body)['message'] ??
            response.reasonPhrase ??
            "Unknown error from server 1.";
        _showSnackBar("❌ Registration failed.\nServer 1: $msg1", Colors.red);
        debugPrint("❌ Registration failed.\nServer 1: $msg1");
      }
    } catch (e) {
      _showSnackBar("⚠️ A network error occurred: $e", Colors.red);
      debugPrint("⚠️ A network error occurred: $e");
    }
  }

  Future<void> pickDoctorImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      setState(() {
        doctorImage = File(pickedFile.path);
      });
    }
  }

  Future<String?> uploadDoctorimage(File imageFile) async {
    final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'];
    final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'];

    if (cloudName == null || uploadPreset == null) {
      debugPrint("Cloudinary credentials not found in .env file");
      return null;
    }

    final url = Uri.parse(
      "https://api.cloudinary.com/v1_1/$cloudName/image/upload",
    );

    final request =
        http.MultipartRequest("POST", url)
          ..fields["upload_preset"] = uploadPreset
          ..files.add(
            await http.MultipartFile.fromPath("file", imageFile.path),
          );

    try {
      final response = await request.send();

      if (response.statusCode == 200) {
        final res = await http.Response.fromStream(response);
        final data = jsonDecode(res.body);
        debugPrint("Upload Success");
        return data["secure_url"];
      } else {
        debugPrint("Upload failed : ${response.statusCode}");
        final res = await http.Response.fromStream(response);
        debugPrint("Error: ${res.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Error uploading image: ${e.toString()}");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildTextField(
      String label,
      TextEditingController controller,
      bool obscureText, {
      TextInputType keyboardType = TextInputType.text,
      List<TextInputFormatter>? inputFormatters,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            labelText: label,
            fillColor: Colors.white,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.blue, width: 3),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.purple, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 15,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 245, 227),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset("assets/logo.png", width: 120),
              ),
              const Text(
                "AutiSecure",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: "Merriweather",
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: const BoxDecoration(color: Colors.white),
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 12,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      dropDownValue == "User"
                          ? "User Registration"
                          : "Doctor Registration",
                      style: const TextStyle(
                        fontFamily: "merriweather",
                        fontSize: 36,
                        color: Color(0xFF813400),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              // Background color
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.purple,
                                width: 1,
                              ),
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
                                          style: const TextStyle(
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
                          const SizedBox(height: 20),
                          buildTextField("Name", nameController, false),
                          const SizedBox(height: 10),
                          buildTextField(
                            "Email",
                            emailController,
                            false,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),
                          buildTextField(
                            "Phone Number",
                            phController,
                            false,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(
                                10,
                              ), // Limit to 10 digits
                            ],
                          ),
                          const SizedBox(height: 10),
                          buildTextField("Address", addressController, false),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: dobController,
                            readOnly: true,
                            onTap: () async {
                              DateTime? pickedDate = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now(),
                              );
                              if (pickedDate != null) {
                                dobController.text =
                                    "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";
                              }
                            },
                            decoration: InputDecoration(
                              labelText: "DOB",
                              fillColor: Colors.white,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          buildTextField("Password", passwordController, true),
                          const SizedBox(height: 10),
                          buildTextField(
                            "Confirm Password",
                            confirmPasswordController,
                            true,
                          ),
                        ],
                      ),
                    ),
                    if (dropDownValue == "Doctor") ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            buildTextField(
                              "Specialization",
                              specialization,
                              false,
                            ),
                            const SizedBox(height: 10),
                            buildTextField(
                              "Experience (in years)",
                              experience,
                              false,
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                            const SizedBox(height: 10),
                            buildTextField("About Yourself", docInfo, false),
                            const SizedBox(height: 10),
                            buildTextField("Clinic Address", clinicLoc, false),
                          ],
                        ),
                      ),
                    ],

                    // --- THIS IS THE CORRECTED IMAGE PICKER ---
                    // It is now outside the "if" statements, so it
                    // will show for both User and Doctor.
                    const SizedBox(height: 20),
                    doctorImage != null
                        ? Image.file(doctorImage!, height: 120)
                        : const Text("No image selected (Optional)"),
                    TextButton(
                      onPressed: pickDoctorImage,
                      child: const Text("Pick Profile Image"),
                    ),

                    // --- END OF CORRECTION ---
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => {submitRegistration(context)},
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
                        "Register",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Have an Account Already? "),
                            TextButton(
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                "Log-In",
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
