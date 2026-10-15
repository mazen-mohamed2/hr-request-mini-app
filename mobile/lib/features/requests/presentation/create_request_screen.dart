import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/async_content.dart';
import '../../../core/widgets/form_validation.dart';
import '../data/hr_request.dart';
import '../data/request_providers.dart';

class CreateRequestScreen extends ConsumerStatefulWidget {
  const CreateRequestScreen({super.key});
  @override
  ConsumerState<CreateRequestScreen> createState() =>
      _CreateRequestScreenState();
}

class _CreateRequestScreenState extends ConsumerState<CreateRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  RequestType? _type;
  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(createRequestProvider).isLoading ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final created = await ref
        .read(createRequestProvider.notifier)
        .submit(
          CreateRequestInput(
            type: _type!,
            subject: _subject.text,
            description: _description.text,
          ),
        );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request submitted successfully.')),
    );
    context.go('/requests/${Uri.encodeComponent(created.id)}');
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(createRequestProvider);
    return PopScope(
      canPop: !action.isLoading,
      child: Scaffold(
        appBar: AppBar(title: const Text('New request')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<RequestType>(
                  key: const Key('request-type'),
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Request type'),
                  items: RequestType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: action.isLoading
                      ? null
                      : (value) => setState(() => _type = value),
                  validator: (value) =>
                      value == null ? 'Request type is required.' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('request-subject'),
                  controller: _subject,
                  enabled: !action.isLoading,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  maxLength: 160,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      validateText(value, label: 'Subject', max: 160),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('request-description'),
                  controller: _description,
                  enabled: !action.isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                  maxLength: 5000,
                  minLines: 5,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) =>
                      validateText(value, label: 'Description', max: 5000),
                ),
                if (action.hasError) ErrorMessage(action.error!),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('request-submit'),
                  onPressed: action.isLoading ? null : _submit,
                  child: action.isLoading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit request'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
