import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import 'mechanics_found_screen.dart';
import 'mechanic_profile_view.dart';
import 'live_tracking_screen.dart';
import 'job_in_progress_screen.dart';
import 'rate_review_screen.dart';
import '../mechanic/active_job_screen.dart';
import '../mechanic/new_request_detail.dart';
import '../mechanic/submit_bid_screen.dart';

Widget mechanicsFoundPage(Object? extra) {
  final job = objectMap(extra);
  return objectId(job['_id']) == null
      ? const InvalidBiddingArgumentsPage()
      : MechanicsFoundScreen(
          key: ValueKey<String>(objectId(job['_id'])!), job: job);
}

Widget mechanicProfilePage(Object? extra) {
  final selection = BidSelection.tryParse(extra);
  return selection == null
      ? const InvalidBiddingArgumentsPage()
      : MechanicProfileView(selection: selection);
}

Widget liveTrackingPage(Object? extra) {
  final booking = AcceptedBooking.tryParse(extra);
  return booking == null
      ? const InvalidBiddingArgumentsPage()
      : LiveTrackingScreen(booking: booking);
}

Widget jobInProgressPage(Object? extra) {
  final booking = AcceptedBooking.tryParse(extra);
  return booking == null
      ? const InvalidBiddingArgumentsPage()
      : JobInProgressScreen(booking: booking);
}

Widget rateReviewPage(Object? extra) {
  final booking = AcceptedBooking.tryParse(extra);
  if (booking == null || booking.job['status'] != 'completed') {
    return const InvalidBiddingArgumentsPage();
  }
  // Preserve assignment IDs; the form independently reloads authoritative state.
  return RateReviewScreen(bid: {
    'jobId': booking.jobId,
    'bidId': booking.bid.bidId,
    'mechanicId': booking.bid.mechanicId,
    'mechanicName': booking.bid.mechanicName,
    'rating': booking.bid.rating,
    'labourCost': booking.bid.labourCost,
    'partsCost': booking.bid.partsCost,
    'totalCost': booking.bid.totalCost,
    'status': 'completed'
  });
}

Widget opportunityPage(Object? extra, {bool submit = false}) {
  final job = objectMap(extra);
  if (objectId(job['_id'] ?? job['jobId']) == null) {
    return const InvalidBiddingArgumentsPage();
  }
  return submit ? SubmitBidScreen(job: job) : NewRequestDetailScreen(job: job);
}

Widget activeJobPage(Object? extra) {
  final booking = AcceptedBooking.tryParse(extra);
  return booking == null
      ? const InvalidBiddingArgumentsPage()
      : ActiveJobScreen(booking: booking);
}

class InvalidBiddingArgumentsPage extends StatelessWidget {
  const InvalidBiddingArgumentsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
            child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Booking information is unavailable. Please reopen your saved job.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.darkTextSecondary)),
          TextButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/user-home'),
              child: const Text('Go back')),
        ]))),
      );
}
