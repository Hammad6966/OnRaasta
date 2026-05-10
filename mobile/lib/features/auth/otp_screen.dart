import 'package:flutter/material.dart';

class OtpScreen extends StatelessWidget {
  final String phone;

  const OtpScreen({super.key, required this.phone});

  @override
  Widget build(BuildContext context) {
    // TODO: implement OTP verification screen UI
    return const Scaffold(body: Center(child: Text('OTP Verification')));
  }
}
