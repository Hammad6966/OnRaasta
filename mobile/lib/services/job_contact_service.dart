import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import 'assignment_service.dart';

String? pakistaniDialNumber(String? raw) {
  if (raw == null) return null;
  final compact = raw.replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^03\d{9}$').hasMatch(compact))
    return '+92${compact.substring(1)}';
  if (RegExp(r'^3\d{9}$').hasMatch(compact)) return '+92$compact';
  if (RegExp(r'^\+923\d{9}$').hasMatch(compact)) return compact;
  if (RegExp(r'^923\d{9}$').hasMatch(compact)) return '+$compact';
  if (RegExp(r'^00923\d{9}$').hasMatch(compact))
    return '+${compact.substring(2)}';
  return null;
}

Uri? pakistaniDialUri(String? raw) {
  final number = pakistaniDialNumber(raw);
  return number == null ? null : Uri(scheme: 'tel', path: number);
}

Future<void> callAssignedPerson(BuildContext context, AcceptedBooking booking,
    {required bool mechanic}) async {
  try {
    // The server rechecks account status and confirmed assignment each time.
    final confirmed = await AssignmentService.instance.load(booking.jobId);
    if (!context.mounted) return;
    final phone = mechanic
        ? textValue(confirmed.driver['phone'])
        : confirmed.bid.mechanicPhone;
    final uri = pakistaniDialUri(phone);
    if (uri == null) throw const FormatException('Phone number unavailable.');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) throw const FormatException('No phone dialer is available.');
  } catch (error) {
    if (!context.mounted) return;
    final message = error is FormatException
        ? error.message
        : error is AssignmentFailure
            ? error.message
            : 'Unable to open the phone dialer. Please retry.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
