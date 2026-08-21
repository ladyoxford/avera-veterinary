import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PaymentCapture {
  const PaymentCapture({
    required this.amount,
    required this.method,
    required this.paidAt,
    this.reference,
  });

  final double amount;
  final String method;
  final DateTime paidAt;
  final String? reference;
}

Future<PaymentCapture?> showPaymentCaptureDialog({
  required BuildContext context,
  required double outstanding,
  required String currency,
}) async {
  return showDialog<PaymentCapture>(
    context: context,
    builder: (_) =>
        _PaymentCaptureDialog(outstanding: outstanding, currency: currency),
  );
}

class _PaymentCaptureDialog extends StatefulWidget {
  const _PaymentCaptureDialog({
    required this.outstanding,
    required this.currency,
  });

  final double outstanding;
  final String currency;

  @override
  State<_PaymentCaptureDialog> createState() => _PaymentCaptureDialogState();
}

class _PaymentCaptureDialogState extends State<_PaymentCaptureDialog> {
  late final TextEditingController _amount;
  final TextEditingController _reference = TextEditingController();
  String _method = 'Cash';
  DateTime _paidAt = DateTime.now();
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.outstanding > 0 ? widget.outstanding.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record Payment'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received',
              prefixText: '${widget.currency} ',
              helperText:
                  'Outstanding: ${widget.currency} ${widget.outstanding.toStringAsFixed(2)}',
              errorText: _validationMessage,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _method,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
              DropdownMenuItem(value: 'Card', child: Text('Card')),
              DropdownMenuItem(value: 'POS', child: Text('POS')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _method = value ?? _method),
            decoration: const InputDecoration(labelText: 'Payment method'),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Payment date'),
            subtitle: Text(DateFormat.yMMMd().format(_paidAt)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: _paidAt,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (selected != null) {
                setState(() {
                  _paidAt = DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    _paidAt.hour,
                    _paidAt.minute,
                  );
                });
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reference,
            textCapitalization: TextCapitalization.characters,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: 'Optional reference',
              hintText: 'Transfer, POS, or receipt reference',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = double.tryParse(_amount.text.trim());
          if (value == null || value <= 0) {
            setState(
              () => _validationMessage = 'Enter a payment greater than zero.',
            );
            return;
          }
          if (value > widget.outstanding + 0.001) {
            setState(
              () => _validationMessage =
                  'The payment cannot exceed the outstanding balance.',
            );
            return;
          }
          final normalizedReference = _reference.text.trim();
          Navigator.pop(
            context,
            PaymentCapture(
              amount: value,
              method: _method,
              paidAt: _paidAt,
              reference: normalizedReference.isEmpty
                  ? null
                  : normalizedReference,
            ),
          );
        },
        child: const Text('Record Payment'),
      ),
    ],
  );
}
