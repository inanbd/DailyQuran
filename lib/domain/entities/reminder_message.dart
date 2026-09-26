import 'package:meta/meta.dart';

/// The text a reminder actually shows.
///
/// Composed in the domain layer and handed down to the scheduler, so the
/// platform adapter never needs to know anything about ayat, editions or plans
/// — it is given two strings and arms them.
@immutable
class ReminderMessage {
  const ReminderMessage({required this.title, required this.body});

  /// What a reminder says when the reader has asked it to reveal nothing.
  static const ReminderMessage invitation = ReminderMessage(
    title: 'Today’s Ayah',
    body: 'Your next ayah is ready.',
  );

  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ReminderMessage && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'ReminderMessage($title / $body)';
}

/// One reminder for a reading plan: when it arrives and what it says.
///
/// A plan's goal changes from day to day — it grows after a missed day and
/// shrinks after a long one — so a single repeating alarm with fixed text
/// would soon be announcing the wrong number. Each day's reminder is armed on
/// its own instead, carrying the goal as it will stand that day.
@immutable
class PlanReminder {
  const PlanReminder({required this.at, required this.message});

  /// When the reminder arrives, as wall-clock time.
  final DateTime at;

  final ReminderMessage message;

  @override
  bool operator ==(Object other) =>
      other is PlanReminder && other.at == at && other.message == message;

  @override
  int get hashCode => Object.hash(at, message);

  @override
  String toString() => 'PlanReminder($at: $message)';
}
