import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/async_content.dart';
import '../../../core/widgets/form_validation.dart';
import '../../requests/data/hr_request.dart';
import '../../requests/data/request_providers.dart';

class ReviewPanel extends ConsumerStatefulWidget {
  const ReviewPanel({super.key, required this.requestId});
  final String requestId;
  @override
  ConsumerState<ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends ConsumerState<ReviewPanel> {
  final _form = GlobalKey<FormState>();
  final _comment = TextEditingController();
  bool _confirming = false;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _review(RequestStatus status) async {
    if (_confirming ||
        ref.read(reviewRequestProvider(widget.requestId)).isLoading ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() => _confirming = true);
    final approved = status == RequestStatus.approved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approved ? 'Approve this request?' : 'Reject this request?',
        ),
        content: const Text('This decision cannot be changed after review.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    FocusScope.of(context).unfocus();
    final result = await ref
        .read(reviewRequestProvider(widget.requestId).notifier)
        .submit(ReviewInput(status: status, comment: _comment.text));
    if (mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request ${result.status.label.toLowerCase()}.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(reviewRequestProvider(widget.requestId));
    final busy = action.isLoading || _confirming;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Review request', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('review-comment'),
            controller: _comment,
            enabled: !busy,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              alignLabelWithHint: true,
            ),
            validator: (value) => validateText(
              value,
              label: 'Comment',
              max: 2000,
              required: false,
            ),
          ),
          if (action.hasError) ErrorMessage(action.error!),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _review(RequestStatus.rejected),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => _review(RequestStatus.approved),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
          if (action.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
