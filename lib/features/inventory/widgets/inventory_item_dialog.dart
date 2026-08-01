import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/inventory_catalog.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

class InventoryItemDraft {
  const InventoryItemDraft({
    required this.submissionId,
    required this.name,
    required this.categoryId,
    required this.quantity,
    required this.minimumQuantity,
    required this.sellingPrice,
    required this.buyingPrice,
    this.remoteId,
    this.batchNumber,
    this.expiryDate,
    this.revision,
  });

  final String submissionId;
  final String? remoteId;
  final String name;
  final String categoryId;
  final int quantity;
  final int minimumQuantity;
  final String? batchNumber;
  final DateTime? expiryDate;
  final double sellingPrice;
  final double buyingPrice;
  final int? revision;

  factory InventoryItemDraft.fromRemote(RemoteInventoryItem item) =>
      InventoryItemDraft(
        submissionId: const Uuid().v4(),
        remoteId: item.id,
        name: item.name,
        categoryId: item.categoryId,
        quantity: item.quantity,
        minimumQuantity: item.reorderLevel,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        sellingPrice: item.sellingPrice.toDouble(),
        buyingPrice: item.purchasePrice.toDouble(),
        revision: item.revision,
      );

  Map<String, dynamic> toRemotePayload() {
    final category = InventoryCategories.byId(categoryId);
    return {
      if (remoteId == null) 'submissionId': submissionId,
      'name': name,
      'categoryId': categoryId,
      'categoryName': category?.name ?? 'Other',
      'quantity': quantity,
      'reorderLevel': minimumQuantity,
      'batchNumber': batchNumber,
      'expiryDate': expiryDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(expiryDate!),
      'purchasePrice': buyingPrice,
      'sellingPrice': sellingPrice,
      if (revision != null) 'revision': revision,
    };
  }
}

Future<bool> showInventoryItemDialog({
  required BuildContext context,
  required Set<String> allowedCategoryIds,
  required bool canSeeCost,
  required Future<void> Function(InventoryItemDraft draft) onSubmit,
  InventoryItemDraft? initial,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _InventoryItemDialog(
      allowedCategoryIds: allowedCategoryIds,
      canSeeCost: canSeeCost,
      initial: initial,
      onSubmit: onSubmit,
    ),
  );
  return result == true;
}

class _InventoryItemDialog extends StatefulWidget {
  const _InventoryItemDialog({
    required this.allowedCategoryIds,
    required this.canSeeCost,
    required this.onSubmit,
    this.initial,
  });

  final Set<String> allowedCategoryIds;
  final bool canSeeCost;
  final InventoryItemDraft? initial;
  final Future<void> Function(InventoryItemDraft draft) onSubmit;

  @override
  State<_InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends State<_InventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _minimum;
  late final TextEditingController _batch;
  late final TextEditingController _selling;
  late final TextEditingController _cost;
  late final String _submissionId;
  String? _categoryId;
  DateTime? _expiry;
  bool _saving = false;
  String? _submissionError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _submissionId = initial?.submissionId ?? const Uuid().v4();
    _name = TextEditingController(text: initial?.name ?? '');
    _quantity = TextEditingController(text: '${initial?.quantity ?? 0}');
    _minimum = TextEditingController(text: '${initial?.minimumQuantity ?? 5}');
    _batch = TextEditingController(text: initial?.batchNumber ?? '');
    _selling = TextEditingController(
      text: _numberText(initial?.sellingPrice ?? 0),
    );
    _cost = TextEditingController(text: _numberText(initial?.buyingPrice ?? 0));
    _expiry = initial?.expiryDate;
    _categoryId = widget.allowedCategoryIds.contains(initial?.categoryId)
        ? initial!.categoryId
        : widget.allowedCategoryIds.isEmpty
        ? null
        : widget.allowedCategoryIds.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _minimum.dispose();
    _batch.dispose();
    _selling.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final categories = InventoryCategories.all
        .where((item) => widget.allowedCategoryIds.contains(item.id))
        .toList();
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + viewInsets.bottom),
        child: Dialog(
          insetPadding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.initial == null
                                ? 'New Inventory Item'
                                : 'Edit Inventory Item',
                            style: averaText(context).sectionTitle,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AveraLabeledTextField(
                            label: 'Item Name',
                            controller: _name,
                            hintText: 'Enter item name',
                            textInputAction: TextInputAction.next,
                            validator: _required,
                          ),
                          const SizedBox(height: AveraSpacing.cardGap),
                          AveraLabeledDropdownField<String>(
                            label: 'Category',
                            hintText: 'Select category',
                            value: _categoryId,
                            items: [
                              for (final category in categories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(
                                    category.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) =>
                                      setState(() => _categoryId = value),
                            validator: (value) => value == null
                                ? 'Please select a category.'
                                : null,
                          ),
                          const SizedBox(height: AveraSpacing.cardGap),
                          _ResponsiveNumberFields(
                            first: AveraLabeledTextField(
                              label: 'Quantity',
                              controller: _quantity,
                              hintText: '0',
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              validator: _wholeNumber,
                            ),
                            second: AveraLabeledTextField(
                              label: 'Minimum Quantity',
                              controller: _minimum,
                              hintText: '5',
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              validator: _wholeNumber,
                            ),
                          ),
                          const SizedBox(height: AveraSpacing.cardGap),
                          AveraLabeledTextField(
                            label: 'Batch Number',
                            controller: _batch,
                            hintText: _requiresBatchAndExpiry
                                ? 'Enter batch number'
                                : 'Optional batch number',
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                _requiresBatchAndExpiry &&
                                    (value?.trim().isEmpty ?? true)
                                ? 'Enter the manufacturer batch number.'
                                : null,
                          ),
                          const SizedBox(height: AveraSpacing.cardGap),
                          AveraLabeledFieldCard(
                            label: 'Expiry Date',
                            child: InkWell(
                              onTap: _saving ? null : _pickExpiry,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _expiry == null
                                          ? 'No expiry date'
                                          : DateFormat.yMMMd().format(_expiry!),
                                      style: _expiry == null
                                          ? averaText(context).fieldPlaceholder
                                          : averaText(context).fieldValue,
                                    ),
                                  ),
                                  if (_expiry != null)
                                    IconButton(
                                      tooltip: 'Clear expiry date',
                                      onPressed: _saving
                                          ? null
                                          : () =>
                                                setState(() => _expiry = null),
                                      icon: const Icon(Icons.clear_rounded),
                                    )
                                  else
                                    const Icon(Icons.calendar_today_outlined),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AveraSpacing.cardGap),
                          AveraLabeledTextField(
                            label: 'Selling Price (NGN)',
                            controller: _selling,
                            hintText: '0.00',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: widget.canSeeCost
                                ? TextInputAction.next
                                : TextInputAction.done,
                            validator: _money,
                          ),
                          if (widget.canSeeCost) ...[
                            const SizedBox(height: AveraSpacing.cardGap),
                            AveraLabeledTextField(
                              label: 'Cost Price (NGN)',
                              controller: _cost,
                              hintText: '0.00',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.done,
                              validator: _money,
                            ),
                          ],
                          if (_submissionError != null) ...[
                            const SizedBox(height: AveraSpacing.cardGap),
                            Text(
                              _submissionError!,
                              style: averaText(context).listItemSubtitle
                                  .copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _submit,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving' : 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 30),
      initialDate: _expiry ?? now,
    );
    if (mounted && picked != null) setState(() => _expiry = picked);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    if (_requiresBatchAndExpiry && _expiry == null) {
      setState(() {
        _submissionError =
            'Choose an expiry date for drugs and vaccine products.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _submissionError = null;
    });
    final initial = widget.initial;
    final draft = InventoryItemDraft(
      submissionId: _submissionId,
      remoteId: initial?.remoteId,
      name: _name.text.trim(),
      categoryId: _categoryId!,
      quantity: int.parse(_quantity.text.trim()),
      minimumQuantity: int.parse(_minimum.text.trim()),
      batchNumber: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      expiryDate: _expiry,
      sellingPrice: double.parse(_selling.text.trim()),
      buyingPrice: widget.canSeeCost
          ? double.parse(_cost.text.trim())
          : initial?.buyingPrice ?? 0,
      revision: initial?.revision,
    );
    try {
      await widget.onSubmit(draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submissionError = error is ApiException
            ? error.message
            : 'The inventory item could not be saved. Your entries are still available.';
      });
    }
  }

  String? _required(String? value) =>
      value?.trim().isEmpty ?? true ? 'Please enter an item name.' : null;

  String? _wholeNumber(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0
        ? 'Enter a whole number of zero or more.'
        : null;
  }

  String? _money(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0
        ? 'Enter a valid amount of zero or more.'
        : null;
  }

  bool get _requiresBatchAndExpiry =>
      _categoryId == 'drugs' || _categoryId == 'vaccines';

  static String _numberText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

class _ResponsiveNumberFields extends StatelessWidget {
  const _ResponsiveNumberFields({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 420) {
        return Column(
          children: [
            first,
            const SizedBox(height: AveraSpacing.cardGap),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: AveraSpacing.cardGap),
          Expanded(child: second),
        ],
      );
    },
  );
}
