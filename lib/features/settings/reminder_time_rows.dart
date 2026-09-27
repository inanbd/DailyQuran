import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../domain/entities/notification_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/settings_group.dart';

/// The rows that edit a day's reminder times: one per time — tap it to move
/// it, and a button to remove it while there is more than one — then a row to
/// add another, up to [ReminderTimes.maxPerDay].
///
/// Rows rather than a widget, so they sit inside whichever settings surface
/// holds them with its own dividers between them.
///
/// [firstNote] and [laterNote] describe what the first reminder of the day and
/// the ones after it do, shown once there is more than one to tell apart.
List<Widget> reminderTimeRows({
  required BuildContext context,
  required List<TimeOfDayValue> times,
  required ValueChanged<List<TimeOfDayValue>> onChanged,
  String? firstNote,
  String? laterNote,
}) {
  final bool use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
  final bool several = times.length > 1;

  String format(TimeOfDayValue time) =>
      Formatting.timeOfDay(time.hour, time.minute, use24Hour: use24Hour);

  Future<void> replace(int index) async {
    final TimeOfDayValue? picked = await _pick(
      context,
      times[index],
      helpText: several ? '${_ordinals[index]} reminder' : 'Reminder time',
    );
    if (picked == null) return;
    onChanged(<TimeOfDayValue>[...times]..[index] = picked);
  }

  Future<void> add() async {
    final TimeOfDayValue? picked = await _pick(
      context,
      _suggestedNext(times),
      helpText: 'Another reminder',
    );
    if (picked == null) return;
    onChanged(<TimeOfDayValue>[...times, picked]);
  }

  return <Widget>[
    for (int i = 0; i < times.length; i++)
      SettingsRow(
        label: several ? '${_ordinals[i]} reminder' : 'Reminder time',
        description: !several
            ? null
            : i == 0
                ? firstNote
                : laterNote,
        onTap: () => replace(i),
        trailing: _TimeValue(
          text: format(times[i]),
          onRemove: several
              ? () => onChanged(<TimeOfDayValue>[...times]..removeAt(i))
              : null,
          removeLabel: 'Remove the ${format(times[i])} reminder',
        ),
      ),
    if (times.length < ReminderTimes.maxPerDay)
      SettingsRow(
        label: 'Add another reminder',
        description: several
            ? null
            : 'Up to ${ReminderTimes.maxPerDay} a day.',
        onTap: add,
        trailing: Icon(Icons.add, size: 20, color: context.colors.accent),
      ),
  ];
}

const List<String> _ordinals = <String>[
  'First',
  'Second',
  'Third',
  'Fourth',
  'Fifth',
];

/// A few hours after the last reminder, so a second one is offered later in
/// the day rather than on top of the first.
TimeOfDayValue _suggestedNext(List<TimeOfDayValue> times) {
  if (times.isEmpty) return TimeOfDayValue.defaultTime;
  final TimeOfDayValue last = times.last;
  final int hour = last.hour + 4;
  return hour <= 21
      ? TimeOfDayValue(hour, last.minute)
      : const TimeOfDayValue(21, 0);
}

Future<TimeOfDayValue?> _pick(
  BuildContext context,
  TimeOfDayValue initial, {
  required String helpText,
}) async {
  final TimeOfDay? picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    helpText: helpText,
  );
  return picked == null ? null : TimeOfDayValue(picked.hour, picked.minute);
}

/// The time, and a button to remove it when it is not the only one.
class _TimeValue extends StatelessWidget {
  const _TimeValue({
    required this.text,
    required this.onRemove,
    required this.removeLabel,
  });

  final String text;
  final VoidCallback? onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          text,
          style: AppTypography.body.copyWith(color: colors.textSecondary),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
            tooltip: removeLabel,
          )
        else
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Icon(
              Icons.chevron_right,
              size: 20,
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}
