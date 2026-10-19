import 'package:flutter/foundation.dart';
import '../models/bid_model.dart';
import '../models/booking_arguments.dart';
import '../services/review_service.dart';
import '../services/assignment_service.dart';

class ReviewFormController extends ChangeNotifier {
  final String jobId, mechanicId, bidId;
  final ReviewService service;
  AcceptedBooking? booking;
  bool loading = false, submitting = false, verified = false, submitted = false;
  bool _disposed = false;
  String? error;
  ReviewFormController(
      {required this.jobId,
      required this.mechanicId,
      required this.bidId,
      required this.service});
  bool get alreadyReviewed =>
      submitted || objectMap(booking?.job['review'])['stars'] != null;
  bool get canSubmit =>
      verified &&
      !loading &&
      !submitting &&
      !alreadyReviewed &&
      booking?.job['status'] == 'completed';
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> reload() async {
    if (loading || _disposed) return;
    loading = true;
    verified = false;
    error = null;
    _changed();
    try {
      if ([jobId, mechanicId, bidId].any((s) => objectId(s) == null)) {
        throw const ReviewFailure('Saved review identifiers are missing.');
      }
      final saved = await service.assignment(jobId);
      if (_disposed) return;
      if (saved.jobId != jobId ||
          saved.bid.mechanicId != mechanicId ||
          saved.bid.bidId != bidId) {
        throw const ReviewFailure(
            'Saved assignment does not match this review. Reopen your job.');
      }
      booking = saved;
      verified = true;
      if (saved.job['status'] != 'completed') {
        error = 'Only a completed repair can be reviewed.';
      }
    } on ReviewFailure catch (e) {
      error = e.message;
    } on AssignmentFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Unable to verify the completed job. Please retry.';
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<bool> submit(int stars, List<String> tags, String comment) async {
    if (!canSubmit ||
        stars < 1 ||
        stars > 5 ||
        comment.length > 300 ||
        tags.length > 3 ||
        tags.toSet().length != tags.length ||
        tags.any((t) => !ReviewService.tags.contains(t))) {
      return false;
    }
    submitting = true;
    error = null;
    _changed();
    try {
      await reload();
      if (_disposed ||
          !verified ||
          alreadyReviewed ||
          booking?.job['status'] != 'completed') {
        return false;
      }
      await service.submit(jobId, mechanicId, stars, tags, comment);
      if (_disposed) return false;
      submitted = true;
      return true;
    } on ReviewFailure catch (e) {
      if (e.status == 409) await reload();
      if ([401, 403, 404].contains(e.status)) verified = false;
      error = alreadyReviewed ? null : e.message;
    } catch (_) {
      error =
          'Review could not be confirmed. Your input is retained; please retry.';
    } finally {
      submitting = false;
      _changed();
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
