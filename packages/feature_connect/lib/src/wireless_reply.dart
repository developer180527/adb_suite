/// Reading the outcome of `host:connect` and `host:pair`.
///
/// These two commands are the reason this file exists. Unlike the rest of the
/// host protocol, they answer `OKAY` even when they failed — the status word
/// only confirms the daemon understood the request, and the actual result is
/// English prose in the message body. Trusting `OKAY` leaves the app claiming
/// to be connected to a phone that is asleep, on another network, or refusing.
///
/// The wording is therefore the only signal available, which makes this a
/// parser, and parsers get tests.
library;

/// Whether an adb host reply reports that [verb] succeeded.
///
/// Matches on the prefix rather than searching the whole string: the failure
/// message "failed to connect to 10.0.0.5:5555" *contains* "connect", so a
/// `contains` check reports every failure as a success.
bool wirelessReplyIsSuccess(String reply, String verb) {
  final text = reply.trim().toLowerCase();
  if (text.isEmpty) return false;
  return text.startsWith(verb) ||
      text.startsWith('already $verb') ||
      text.startsWith('successfully $verb');
}
