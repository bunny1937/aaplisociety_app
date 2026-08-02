import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_error.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/pulse_field.dart';
import '../member/pulse/pulse.dart';
import 'tenant_api.dart';

/// The shared owner ↔ tenant message thread.
///
/// The tenant could already send a note to their owner, and the backend pushed
/// a notification for it — but the OWNER app had no way to read it. The owner
/// side only had a one-shot "Add note" prompt that wrote into the void: it
/// posted to the same endpoint and then threw the response away, never showing
/// the conversation. So the owner got "your tenant sent you a note" and had
/// nowhere to go.
///
/// One sheet now serves both sides. `mineIsTenant` only decides which bubbles
/// are aligned right and labelled "You"; both parties read and write the same
/// `noteThread`.
Future<void> showTenancyThreadSheet(
  BuildContext context, {
  required String requestId,
  required String title,
  required bool mineIsTenant,
}) {
  return showPulseSheet<void>(
    context,
    title: title,
    full: true,
    builder: (ctx) => _TenancyThreadBody(
      requestId: requestId,
      mineIsTenant: mineIsTenant,
    ),
  );
}

class _TenancyThreadBody extends StatefulWidget {
  const _TenancyThreadBody({
    required this.requestId,
    required this.mineIsTenant,
  });

  final String requestId;
  final bool mineIsTenant;

  @override
  State<_TenancyThreadBody> createState() => _TenancyThreadBodyState();
}

class _TenancyThreadBodyState extends State<_TenancyThreadBody> {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _notes = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes =
          await fetchTenancyNotes(context.read<Dio>(), widget.requestId);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(err);
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final notes =
          await postTenancyNote(context.read<Dio>(), widget.requestId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _notes = notes;
        _sending = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppToast(context, apiErrorMessage(err), kind: AppToastKind.alert);
    }
  }

  /// "Tenant" / "Owner" as written by the backend.
  bool _isMine(Map note) {
    final by = '${note['by'] ?? 'Owner'}'.toLowerCase();
    return widget.mineIsTenant ? by == 'tenant' : by != 'tenant';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 34),
            child: Center(child: PulseSpinner()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Column(
              children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: t.fg3)),
                const SizedBox(height: 10),
                PulseButton(
                  label: 'Try again',
                  variant: PulseBtnVariant.secondary,
                  size: PulseBtnSize.sm,
                  onTap: () {
                    setState(() => _loading = true);
                    _load();
                  },
                ),
              ],
            ),
          )
        else if (_notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Text(
              widget.mineIsTenant
                  ? 'No messages yet. Send the first one to your flat owner.'
                  : 'No messages yet. Anything you send here reaches your '
                      'tenant on their phone.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.fg4),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.46),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 6),
              itemCount: _notes.length,
              itemBuilder: (_, i) => _Bubble(
                note: _notes[i],
                mine: _isMine(_notes[i]),
              ),
            ),
          ),
        const SizedBox(height: 10),
        PulseField(
          label: 'Message',
          controller: _input,
          required: false,
          maxLines: 3,
          hint: widget.mineIsTenant
              ? 'e.g. The kitchen tap is leaking'
              : 'e.g. Rent received, thanks',
        ),
        const SizedBox(height: 10),
        PulseButton(
          label: 'Send message',
          icon: Icons.send_rounded,
          full: true,
          loading: _sending,
          onTap: _send,
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.note, required this.mine});
  final Map note;
  final bool mine;

  String _stamp(Object? raw) {
    final d = DateTime.tryParse('$raw');
    if (d == null) return '';
    final local = d.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final stamp = _stamp(note['at'] ?? note['createdAt']);
    final who = mine ? 'You' : '${note['by'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: mine ? t.brand.withValues(alpha: 0.12) : t.canvas,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: mine ? t.brand : t.border, width: 1),
            ),
            child: Text(
              '${note['text'] ?? note['note'] ?? ''}',
              style: TextStyle(fontSize: 13, color: t.fg1, height: 1.3),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            [if (who.isNotEmpty) who, if (stamp.isNotEmpty) stamp]
                .join(' \u00B7 '),
            style: TextStyle(fontSize: 10.5, color: t.fg5),
          ),
        ],
      ),
    );
  }
}
