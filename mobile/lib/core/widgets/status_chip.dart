import 'package:flutter/material.dart';
import '../../features/requests/data/hr_request.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final RequestStatus status;
  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      RequestStatus.pending => (Colors.orange.shade900, Icons.schedule),
      RequestStatus.approved => (
        Colors.green.shade800,
        Icons.check_circle_outline,
      ),
      RequestStatus.rejected => (Colors.red.shade800, Icons.cancel_outlined),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(status.label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide.none,
    );
  }
}
