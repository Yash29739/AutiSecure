import 'package:flutter/material.dart';

class ShowSnackbar extends StatefulWidget {
  final BuildContext context;
  final String message;
  final Color backgroundColor;

  const ShowSnackbar({
    super.key,
    required this.context,
    required this.message,
    this.backgroundColor = const Color(0xFF22D928),
  });

  @override
  State<ShowSnackbar> createState() => _ShowSnackbarState();
}

class _ShowSnackbarState extends State<ShowSnackbar> {
  @override
  void initState() {
    super.initState();

    // Trigger snackbar after widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(widget.context).showSnackBar(
        SnackBar(
          content: Text(
            widget.message,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: widget.backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // Placeholder widget
  }
}
