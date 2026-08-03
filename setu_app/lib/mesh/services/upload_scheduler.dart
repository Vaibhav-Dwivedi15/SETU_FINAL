import 'retry_policy.dart';

class UploadScheduler {
  UploadScheduler({
    RetryPolicy? retryPolicy,
  }) : retryPolicy = retryPolicy ?? RetryPolicy();

  final RetryPolicy retryPolicy;

  Duration nextRetry(int attempt) {
    return retryPolicy.nextDelay(attempt);
  }
}