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
