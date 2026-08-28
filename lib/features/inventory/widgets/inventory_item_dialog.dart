import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/avera_photo_actions.dart';
import '../../shared/widgets/catalogue_selector.dart';
import '../../shared/widgets/identity_avatar_image.dart';

class InventoryItemDraft {
  const InventoryItemDraft({
    required this.submissionId,
    required this.name,
    required this.categoryId,
    this.categoryName,
    this.subcategoryId,
    this.subcategoryName,
    required this.quantity,
    required this.minimumQuantity,
    required this.sellingPrice,
    required this.buyingPrice,
    this.remoteId,
    this.localId,
    this.batchNumber,
    this.expiryDate,
    this.revision,
    this.imageReference,
    this.pendingImagePath,
    this.genericName,
    this.brandName,
    this.manufacturer,
    this.supplier,
    this.sku,
    this.barcode,
    this.shortDescription,
    this.detailedDescription,
    this.dosageForm,
    this.packSize,
    this.baseUnitLabel = 'unit',
    this.activeIngredient,
    this.dosageAndRoute,
    this.withdrawalMeat,
    this.withdrawalMilk,
    this.withdrawalEggs,
    this.withdrawalOther,
    this.warnings,
    this.contraindications,
    this.adverseEffects,
    this.storageConditions,
    this.publicDisplayName,
    this.availableToPublic = false,
  });

  final String submissionId;
  final String? remoteId;
  final int? localId;
  final String name;
  final String categoryId;
  final String? categoryName;
  final String? subcategoryId;
  final String? subcategoryName;
  final int quantity;
  final int minimumQuantity;
  final String? batchNumber;
  final DateTime? expiryDate;
  final double sellingPrice;
  final double buyingPrice;
  final int? revision;
  final String? imageReference;
  final String? pendingImagePath;
  final String? genericName;
  final String? brandName;
  final String? manufacturer;
  final String? supplier;
  final String? sku;
  final String? barcode;
  final String? shortDescription;
  final String? detailedDescription;
  final String? dosageForm;
  final String? packSize;
  final String baseUnitLabel;
  final String? activeIngredient;
  final String? dosageAndRoute;
  final String? withdrawalMeat;
  final String? withdrawalMilk;
  final String? withdrawalEggs;
  final String? withdrawalOther;
  final String? warnings;
  final String? contraindications;
  final String? adverseEffects;
  final String? storageConditions;
  final String? publicDisplayName;
  final bool availableToPublic;

  factory InventoryItemDraft.fromRemote(RemoteInventoryItem item) =>
      InventoryItemDraft(
        submissionId: const Uuid().v4(),
        remoteId: item.id,
        name: item.name,
        categoryId: InventoryCategories.canonicalId(item.categoryId),
        categoryName: item.categoryName,
        subcategoryId: item.subcategoryId,
        subcategoryName: item.subcategoryName,
        quantity: item.quantity,
        minimumQuantity: item.reorderLevel,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        sellingPrice: item.sellingPrice.toDouble(),
        buyingPrice: item.purchasePrice.toDouble(),
        revision: item.revision,
        imageReference: item.imageUrl,
        genericName: item.genericName,
        brandName: item.brandName,
        manufacturer: item.manufacturer,
        supplier: item.supplier,
        sku: item.sku,
        barcode: item.barcode,
        shortDescription: item.shortDescription,
        detailedDescription: item.detailedDescription,
        dosageForm: item.dosageForm,
        packSize: item.packSize,
        baseUnitLabel: item.baseUnitLabel,
        activeIngredient: item.activeIngredient,
        dosageAndRoute: item.dosageAndRoute,
        withdrawalMeat: item.withdrawalMeat,
        withdrawalMilk: item.withdrawalMilk,
        withdrawalEggs: item.withdrawalEggs,
        withdrawalOther: item.withdrawalOther,
        warnings: item.warnings,
        contraindications: item.contraindications,
        adverseEffects: item.adverseEffects,
        storageConditions: item.storageConditions,
        publicDisplayName: item.publicDisplayName,
        availableToPublic: item.availableToPublic,
      );

  factory InventoryItemDraft.fromLocal(InventoryItem item) =>
      InventoryItemDraft(
        submissionId: const Uuid().v4(),
        localId: item.id,
        name: item.drugName,
        categoryId: InventoryCategories.canonicalId(
          item.categoryId ?? item.category,
        ),
        categoryName: item.category,
        subcategoryId: item.subcategoryId,
        subcategoryName: item.subcategory,
        quantity: item.quantity,
        minimumQuantity: item.minimumQuantity,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        sellingPrice: item.sellingPrice,
        buyingPrice: item.buyingPrice,
        imageReference: item.imagePath,
        genericName: item.genericName,
        brandName: item.brandName,
        manufacturer: item.manufacturer,
        supplier: item.supplier,
        sku: item.sku,
        barcode: item.barcode,
        shortDescription: item.shortDescription,
        detailedDescription: item.detailedDescription,
        dosageForm: item.dosageForm,
        packSize: item.packSize,
        baseUnitLabel: item.baseUnitLabel,
        activeIngredient: item.activeIngredient,
        dosageAndRoute: item.dosageAndRoute,
        withdrawalMeat: item.withdrawalMeat,
        withdrawalMilk: item.withdrawalMilk,
        withdrawalEggs: item.withdrawalEggs,
        withdrawalOther: item.withdrawalOther,
        warnings: item.warnings,
        contraindications: item.contraindications,
        adverseEffects: item.adverseEffects,
        storageConditions: item.storageConditions,
        publicDisplayName: item.publicDisplayName,
        availableToPublic: item.availableToPublic,
      );

  Map<String, dynamic> toRemotePayload() {
    final category = InventoryCategories.byId(
      InventoryCategories.canonicalId(categoryId),
    );
    final categoryLabel = category?.id == InventoryCategories.customCategoryId
        ? (categoryName?.trim().isNotEmpty == true
              ? categoryName!.trim()
              : category?.name ?? 'Other')
        : category?.name ?? categoryName ?? 'Other';
    return {
      if (remoteId == null) 'submissionId': submissionId,
      'name': name,
      'categoryId': category?.id ?? categoryId,
      'categoryName': categoryLabel,
      'subcategoryId': subcategoryId,
      'subcategoryName': subcategoryName,
      'genericName': genericName,
      'brandName': brandName,
      'manufacturer': manufacturer,
      'supplier': supplier,
      'sku': sku,
      'barcode': barcode,
      'shortDescription': shortDescription,
      'detailedDescription': detailedDescription,
      'dosageForm': dosageForm,
      'packSize': packSize,
      'quantity': quantity,
      'reorderLevel': minimumQuantity,
      'batchNumber': batchNumber,
      'expiryDate': expiryDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(expiryDate!),
      'purchasePrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'baseUnitLabel': baseUnitLabel,
      'activeIngredient': activeIngredient,
      'dosageAndRoute': dosageAndRoute,
      'withdrawalMeat': withdrawalMeat,
      'withdrawalMilk': withdrawalMilk,
      'withdrawalEggs': withdrawalEggs,
      'withdrawalOther': withdrawalOther,
      'warnings': warnings,
      'contraindications': contraindications,
      'adverseEffects': adverseEffects,
      'storageConditions': storageConditions,
      'publicDisplayName': publicDisplayName,
      'availableToPublic': availableToPublic,
      'isSellable': category?.isSellable ?? false,
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
  late final TextEditingController _customCategoryName;
  late final TextEditingController _customSubcategoryName;
  late final TextEditingController _genericName;
  late final TextEditingController _brandName;
  late final TextEditingController _manufacturer;
  late final TextEditingController _supplier;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _shortDescription;
  late final TextEditingController _detailedDescription;
  late final TextEditingController _dosageForm;
  late final TextEditingController _packSize;
  late final TextEditingController _baseUnitLabel;
  late final TextEditingController _activeIngredient;
  late final TextEditingController _dosageAndRoute;
  late final TextEditingController _withdrawalMeat;
  late final TextEditingController _withdrawalMilk;
  late final TextEditingController _withdrawalEggs;
  late final TextEditingController _withdrawalOther;
  late final TextEditingController _warnings;
  late final TextEditingController _contraindications;
  late final TextEditingController _adverseEffects;
  late final TextEditingController _storageConditions;
  late final TextEditingController _publicDisplayName;
  late final String _submissionId;
  String? _categoryId;
  String? _subcategoryId;
  String? _subcategoryName;
  String? _preservedIncompatibleSubcategory;
  DateTime? _expiry;
  bool _saving = false;
  String? _submissionError;
  String? _imageReference;
  String? _pendingImagePath;
  bool _availableToPublic = false;
  bool _basicExpanded = true;
  bool _catalogueExpanded = false;
  bool _veterinaryExpanded = false;
  bool _supplierExpanded = false;
  bool _stockExpanded = true;
  bool _publicExpanded = false;

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
    _customCategoryName = _controller(initial?.categoryName);
    _customSubcategoryName = _controller(initial?.subcategoryName);
    _genericName = _controller(initial?.genericName);
    _brandName = _controller(initial?.brandName);
    _manufacturer = _controller(initial?.manufacturer);
    _supplier = _controller(initial?.supplier);
    _sku = _controller(initial?.sku);
    _barcode = _controller(initial?.barcode);
    _shortDescription = _controller(initial?.shortDescription);
    _detailedDescription = _controller(initial?.detailedDescription);
    _dosageForm = _controller(initial?.dosageForm);
    _packSize = _controller(initial?.packSize);
    _baseUnitLabel = _controller(initial?.baseUnitLabel ?? 'unit');
    _activeIngredient = _controller(initial?.activeIngredient);
    _dosageAndRoute = _controller(initial?.dosageAndRoute);
    _withdrawalMeat = _controller(initial?.withdrawalMeat);
    _withdrawalMilk = _controller(initial?.withdrawalMilk);
    _withdrawalEggs = _controller(initial?.withdrawalEggs);
    _withdrawalOther = _controller(initial?.withdrawalOther);
    _warnings = _controller(initial?.warnings);
    _contraindications = _controller(initial?.contraindications);
    _adverseEffects = _controller(initial?.adverseEffects);
    _storageConditions = _controller(initial?.storageConditions);
    _publicDisplayName = _controller(initial?.publicDisplayName);
    _availableToPublic = initial?.availableToPublic ?? false;
    _expiry = initial?.expiryDate;
    _imageReference = initial?.imageReference;
    final allowedCategoryIds = widget.allowedCategoryIds
        .map(InventoryCategories.canonicalId)
        .toSet();
    final initialCategoryId = initial == null
        ? null
        : InventoryCategories.canonicalId(initial.categoryId);
    _categoryId = allowedCategoryIds.contains(initialCategoryId)
        ? initialCategoryId
        : allowedCategoryIds.isEmpty
        ? null
        : InventoryCategories.all
              .firstWhere(
                (category) => allowedCategoryIds.contains(category.id),
              )
              .id;
    final canonicalSubcategory = InventoryCategories.subcategoryById(
      _categoryId,
      initial?.subcategoryId,
    );
    if (canonicalSubcategory != null) {
      _subcategoryId = canonicalSubcategory.id;
      _subcategoryName = canonicalSubcategory.name;
      _customSubcategoryName.clear();
    } else if (initial?.subcategoryId ==
        InventoryCategories.customSubcategoryId) {
      _subcategoryId = InventoryCategories.customSubcategoryId;
      _subcategoryName = initial?.subcategoryName;
    } else {
      final resolvedSubcategory = InventoryCategories.resolveSubcategory(
        _categoryId,
        initial?.subcategoryName,
      );
      if (resolvedSubcategory != null) {
        _subcategoryId = resolvedSubcategory.id;
        _subcategoryName = resolvedSubcategory.name;
        _customSubcategoryName.clear();
      } else if (initial?.subcategoryName?.trim().isNotEmpty == true) {
        _subcategoryId = InventoryCategories.customSubcategoryId;
        _subcategoryName = initial!.subcategoryName;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _minimum.dispose();
    _batch.dispose();
    _selling.dispose();
    _cost.dispose();
    _customCategoryName.dispose();
    _customSubcategoryName.dispose();
    for (final controller in [
      _genericName,
      _brandName,
      _manufacturer,
      _supplier,
      _sku,
      _barcode,
      _shortDescription,
      _detailedDescription,
      _dosageForm,
      _packSize,
      _baseUnitLabel,
      _activeIngredient,
      _dosageAndRoute,
      _withdrawalMeat,
      _withdrawalMilk,
      _withdrawalEggs,
      _withdrawalOther,
      _warnings,
      _contraindications,
      _adverseEffects,
      _storageConditions,
      _publicDisplayName,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowedCategoryIds = widget.allowedCategoryIds
        .map(InventoryCategories.canonicalId)
        .toSet();
    final categories = InventoryCategories.all
        .where((item) => allowedCategoryIds.contains(item.id))
        .toList();
    final compact = MediaQuery.sizeOf(context).width < 600;

    if (compact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              widget.initial == null
                  ? 'New Inventory Item'
                  : 'Edit Inventory Item',
            ),
            actions: [
              IconButton(
                tooltip: 'Close',
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                ..._formFields(context, categories),
                const SizedBox(height: 24),
                _actionButtons(context),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                      children: _formFields(context, categories),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _actionButtons(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _formFields(
    BuildContext context,
    List<InventoryCategoryDefinition> categories,
  ) => [
    _sectionHeader(context, 'Product Image'),
    _InventoryImageField(
      name: _name.text.trim().isEmpty ? 'Inventory item' : _name.text.trim(),
      imageReference: _pendingImagePath ?? _imageReference,
      onPressed: _saving ? null : _manageImage,
    ),
    const SizedBox(height: AveraSpacing.sectionGap),
    _sectionHeader(
      context,
      'Basic Information',
      expanded: _basicExpanded,
      onTap: () => setState(() => _basicExpanded = !_basicExpanded),
    ),
    if (_basicExpanded) ...[
      AveraLabeledTextField(
        label: 'Item Name',
        controller: _name,
        hintText: 'Enter item name',
        textInputAction: TextInputAction.next,
        validator: _required,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      CatalogueSelectionField(
        label: 'Category',
        hintText: 'Select category',
        value: _categoryId == InventoryCategories.customCategoryId
            ? _customCategoryName.text
            : InventoryCategories.byId(_categoryId)?.name,
        onTap: _saving ? null : () => _selectCategory(context, categories),
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      CatalogueSelectionField(
        label: 'Subcategory',
        hintText: 'Select subcategory or leave unspecified',
        enabled: _categoryId != null,
        value: _subcategoryId == InventoryCategories.customSubcategoryId
            ? _customSubcategoryName.text
            : InventoryCategories.subcategoryDisplayName(
                _categoryId,
                _subcategoryId,
                _subcategoryName,
              ),
        onTap: _saving ? null : () => _selectSubcategory(context),
      ),
      if (_categoryId == InventoryCategories.customCategoryId) ...[
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledTextField(
          label: 'Custom Category',
          controller: _customCategoryName,
          hintText: 'Enter category name',
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          validator: (value) =>
              _categoryId == InventoryCategories.customCategoryId &&
                  (value?.trim().isEmpty ?? true)
              ? 'Please enter a category name.'
              : null,
        ),
      ],
      if (_subcategoryId == InventoryCategories.customSubcategoryId) ...[
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledTextField(
          label: 'Custom Subcategory',
          controller: _customSubcategoryName,
          hintText: 'Enter subcategory name',
          textInputAction: TextInputAction.next,
          onChanged: (value) => setState(() => _subcategoryName = value.trim()),
          validator: (value) =>
              _subcategoryId == InventoryCategories.customSubcategoryId &&
                  (value?.trim().isEmpty ?? true)
              ? 'Please enter a subcategory name.'
              : null,
        ),
      ],
      if (_preservedIncompatibleSubcategory != null) ...[
        const SizedBox(height: AveraSpacing.compactRowGap),
        Text(
          'Choose a new subcategory. "$_preservedIncompatibleSubcategory" belongs to the previous category.',
          style: averaText(
            context,
          ).caption.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Brand Name',
        controller: _brandName,
        hintText: 'Optional brand or trade name',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Generic Name',
        controller: _genericName,
        hintText: 'Optional generic product name',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Manufacturer',
        controller: _manufacturer,
        hintText: 'Optional manufacturer',
        textInputAction: TextInputAction.next,
      ),
    ],
    const SizedBox(height: AveraSpacing.sectionGap),
    _sectionHeader(
      context,
      'Catalogue Information',
      expanded: _catalogueExpanded,
      onTap: () => setState(() => _catalogueExpanded = !_catalogueExpanded),
    ),
    if (_catalogueExpanded) ...[
      _ResponsiveNumberFields(
        first: AveraLabeledTextField(
          label: 'SKU',
          controller: _sku,
          hintText: 'Optional stock code',
          textInputAction: TextInputAction.next,
        ),
        second: AveraLabeledTextField(
          label: 'Barcode',
          controller: _barcode,
          hintText: 'Optional barcode',
          textInputAction: TextInputAction.next,
        ),
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Short Description',
        controller: _shortDescription,
        hintText: 'A concise description for staff and customers',
        minLines: 2,
        maxLines: 3,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Detailed Description',
        controller: _detailedDescription,
        hintText: 'Optional product details',
        minLines: 3,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      _ResponsiveNumberFields(
        first: AveraLabeledTextField(
          label: 'Product Form / Presentation',
          controller: _dosageForm,
          hintText: 'Tablet, liquid, spray',
          textInputAction: TextInputAction.next,
        ),
        second: AveraLabeledTextField(
          label: 'Pack Size',
          controller: _packSize,
          hintText: '10 tablets, 100 ml',
          textInputAction: TextInputAction.next,
        ),
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Base Unit',
        controller: _baseUnitLabel,
        hintText: 'unit',
        textInputAction: TextInputAction.next,
        validator: (value) => value?.trim().isEmpty ?? true
            ? 'Enter the base stock and selling unit.'
            : null,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledTextField(
        label: 'Storage Conditions',
        controller: _storageConditions,
        hintText: 'Optional storage instructions',
        minLines: 2,
        maxLines: 4,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
      ),
    ],
    if (_showsVeterinaryFields) ...[
      const SizedBox(height: AveraSpacing.sectionGap),
      _sectionHeader(
        context,
        'Veterinary Information',
        expanded: _veterinaryExpanded,
        onTap: () => setState(() => _veterinaryExpanded = !_veterinaryExpanded),
      ),
      if (_veterinaryExpanded) ...[
        AveraLabeledTextField(
          label: 'Active Ingredients',
          controller: _activeIngredient,
          hintText: 'Optional active ingredients and strengths',
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledTextField(
          label: 'Dosage & Directions',
          controller: _dosageAndRoute,
          hintText: 'Optional dosage, route and directions',
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        _ResponsiveNumberFields(
          first: AveraLabeledTextField(
            label: 'Meat Withdrawal',
            controller: _withdrawalMeat,
            hintText: 'Optional',
            textInputAction: TextInputAction.next,
          ),
          second: AveraLabeledTextField(
            label: 'Milk Withdrawal',
            controller: _withdrawalMilk,
            hintText: 'Optional',
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        _ResponsiveNumberFields(
          first: AveraLabeledTextField(
            label: 'Egg Withdrawal',
            controller: _withdrawalEggs,
            hintText: 'Optional',
            textInputAction: TextInputAction.next,
          ),
          second: AveraLabeledTextField(
            label: 'Other Withdrawal',
            controller: _withdrawalOther,
            hintText: 'Optional',
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledTextField(
          label: 'Warnings',
          controller: _warnings,
          hintText: 'Optional safety warnings',
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledTextField(
          label: 'Contraindications',
          controller: _contraindications,
          hintText: 'Optional contraindications',
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: AveraSpacing.cardGap),
        AveraLabeledTextField(
          label: 'Adverse Effects',
          controller: _adverseEffects,
          hintText: 'Optional adverse effects',
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
      ],
    ],
    const SizedBox(height: AveraSpacing.sectionGap),
    _sectionHeader(
      context,
      'Supplier',
      expanded: _supplierExpanded,
      onTap: () => setState(() => _supplierExpanded = !_supplierExpanded),
    ),
    if (_supplierExpanded)
      AveraLabeledTextField(
        label: 'Supplier Name',
        controller: _supplier,
        hintText: 'Optional supplier',
        textInputAction: TextInputAction.next,
      ),
    const SizedBox(height: AveraSpacing.sectionGap),
    _sectionHeader(
      context,
      'Stock & Pricing',
      expanded: _stockExpanded,
      onTap: () => setState(() => _stockExpanded = !_stockExpanded),
    ),
    if (_stockExpanded) ...[
      _ResponsiveNumberFields(
        first: AveraLabeledTextField(
          label: widget.initial == null ? 'Initial Quantity' : 'Current Stock',
          controller: _quantity,
          hintText: '0',
          readOnly: widget.initial != null,
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
            _requiresBatchAndExpiry && (value?.trim().isEmpty ?? true)
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
                      : () => setState(() => _expiry = null),
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
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          validator: _money,
        ),
      ],
    ],
    const SizedBox(height: AveraSpacing.sectionGap),
    _sectionHeader(
      context,
      'Future Shop Information',
      expanded: _publicExpanded,
      onTap: () => setState(() => _publicExpanded = !_publicExpanded),
    ),
    if (_publicExpanded) ...[
      AveraLabeledTextField(
        label: 'Public Display Name',
        controller: _publicDisplayName,
        hintText: 'Defaults to the inventory item name',
        textInputAction: TextInputAction.done,
      ),
      const SizedBox(height: AveraSpacing.cardGap),
      AveraLabeledFieldCard(
        label: 'Customer Availability',
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Available to associated clients'),
          subtitle: const Text(
            'Off by default. This only prepares the item for a future clinic catalogue.',
          ),
          value: _availableToPublic,
          onChanged: _saving
              ? null
              : (value) => setState(() => _availableToPublic = value),
        ),
      ),
    ],
    if (_submissionError != null) ...[
      const SizedBox(height: AveraSpacing.cardGap),
      Text(
        _submissionError!,
        style: averaText(
          context,
        ).listItemSubtitle.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    ],
  ];

  Widget _actionButtons(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving' : 'Save'),
        ),
      ),
    ],
  );

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

  Future<void> _selectCategory(
    BuildContext context,
    List<InventoryCategoryDefinition> categories,
  ) async {
    final selected = await showSearchableCatalogueSelector(
      context: context,
      title: 'Select Category',
      selectedId: _categoryId,
      options: [
        for (final category in categories)
          CataloguePickerOption(
            id: category.id,
            title: category.name,
            subtitle: 'Inventory category',
            searchAliases: [...category.aliases, ...category.legacyIds],
          ),
      ],
    );
    if (!mounted || selected == null) return;
    final categoryId = InventoryCategories.canonicalId(selected);
    setState(() {
      if (_categoryId != categoryId && _subcategoryId != null) {
        final previous = InventoryCategories.subcategoryDisplayName(
          _categoryId,
          _subcategoryId,
          _subcategoryName ?? _customSubcategoryName.text,
        );
        if (InventoryCategories.subcategoryById(categoryId, _subcategoryId) ==
            null) {
          _preservedIncompatibleSubcategory = previous == 'Not specified'
              ? null
              : previous;
          _subcategoryId = null;
          _subcategoryName = null;
          _customSubcategoryName.clear();
        }
      }
      _categoryId = categoryId;
      _submissionError = null;
    });
  }

  Future<void> _selectSubcategory(BuildContext context) async {
    if (_categoryId == null) return;
    final options = <CataloguePickerOption>[
      const CataloguePickerOption(
        id: InventoryCategories.unspecifiedSubcategoryId,
        title: 'Not specified',
        subtitle: 'No subcategory recorded',
      ),
      for (final subcategory in InventoryCategories.subcategoriesFor(
        _categoryId,
      ))
        CataloguePickerOption(
          id: subcategory.id,
          title: subcategory.name,
          subtitle: 'Subcategory',
          searchAliases: subcategory.aliases,
        ),
      const CataloguePickerOption(
        id: InventoryCategories.customSubcategoryId,
        title: 'Other / Custom Subcategory',
        subtitle: 'Enter a clinic-specific subcategory',
      ),
    ];
    final selected = await showSearchableCatalogueSelector(
      context: context,
      title: 'Select Subcategory',
      options: options,
      selectedId:
          _subcategoryId ?? InventoryCategories.unspecifiedSubcategoryId,
    );
    if (!mounted || selected == null) return;
    setState(() {
      _preservedIncompatibleSubcategory = null;
      if (selected == InventoryCategories.unspecifiedSubcategoryId) {
        _subcategoryId = null;
        _subcategoryName = null;
        _customSubcategoryName.clear();
      } else if (selected == InventoryCategories.customSubcategoryId) {
        _subcategoryId = selected;
        _subcategoryName = _customSubcategoryName.text.trim().isEmpty
            ? null
            : _customSubcategoryName.text.trim();
      } else {
        _subcategoryId = selected;
        _subcategoryName = InventoryCategories.subcategoryDisplayName(
          _categoryId,
          selected,
          null,
        );
        _customSubcategoryName.clear();
      }
      _submissionError = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    if (_preservedIncompatibleSubcategory != null) {
      setState(() {
        _submissionError = 'Choose a subcategory that matches this category.';
      });
      return;
    }
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
    final category = InventoryCategories.byId(_categoryId);
    final categoryName = _categoryId == InventoryCategories.customCategoryId
        ? _customCategoryName.text.trim()
        : category?.name;
    final subcategoryName =
        _subcategoryId == InventoryCategories.customSubcategoryId
        ? _customSubcategoryName.text.trim()
        : _subcategoryName;
    final draft = InventoryItemDraft(
      submissionId: _submissionId,
      remoteId: initial?.remoteId,
      localId: initial?.localId,
      name: _name.text.trim(),
      categoryId: _categoryId!,
      categoryName: categoryName,
      subcategoryId: _subcategoryId,
      subcategoryName: subcategoryName?.isEmpty == true
          ? null
          : subcategoryName,
      quantity: int.parse(_quantity.text.trim()),
      minimumQuantity: int.parse(_minimum.text.trim()),
      batchNumber: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      expiryDate: _expiry,
      sellingPrice: double.parse(_selling.text.trim()),
      buyingPrice: widget.canSeeCost
          ? double.parse(_cost.text.trim())
          : initial?.buyingPrice ?? 0,
      revision: initial?.revision,
      imageReference: _imageReference,
      pendingImagePath: _pendingImagePath,
      genericName: _nullable(_genericName),
      brandName: _nullable(_brandName),
      manufacturer: _nullable(_manufacturer),
      supplier: _nullable(_supplier),
      sku: _nullable(_sku),
      barcode: _nullable(_barcode),
      shortDescription: _nullable(_shortDescription),
      detailedDescription: _nullable(_detailedDescription),
      dosageForm: _nullable(_dosageForm),
      packSize: _nullable(_packSize),
      baseUnitLabel: _baseUnitLabel.text.trim(),
      activeIngredient: _nullable(_activeIngredient),
      dosageAndRoute: _nullable(_dosageAndRoute),
      withdrawalMeat: _nullable(_withdrawalMeat),
      withdrawalMilk: _nullable(_withdrawalMilk),
      withdrawalEggs: _nullable(_withdrawalEggs),
      withdrawalOther: _nullable(_withdrawalOther),
      warnings: _nullable(_warnings),
      contraindications: _nullable(_contraindications),
      adverseEffects: _nullable(_adverseEffects),
      storageConditions: _nullable(_storageConditions),
      publicDisplayName: _nullable(_publicDisplayName),
      availableToPublic: _availableToPublic,
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

  bool get _showsVeterinaryFields =>
      _categoryId == 'drugs' ||
      _categoryId == 'vaccines' ||
      _categoryId == 'supplements';

  static TextEditingController _controller(String? value) =>
      TextEditingController(text: value ?? '');

  static String? _nullable(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Widget _sectionHeader(
    BuildContext context,
    String label, {
    bool expanded = true,
    VoidCallback? onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AveraSpacing.cardGap),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: averaText(context).sectionTitle),
            ),
            if (onTap != null)
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _manageImage() async {
    final current = _pendingImagePath ?? _imageReference;
    final action = await showAveraPhotoActionSheet(
      context: context,
      subjectName: _name.text.trim().isEmpty
          ? 'Inventory item'
          : _name.text.trim(),
      hasPhoto: current?.trim().isNotEmpty == true,
      canRemovePhoto: false,
    );
    if (!mounted || action == null) return;
    if (action == AveraPhotoAction.viewPhoto && current != null) {
      await showAveraPhotoViewer(
        context: context,
        subjectName: _name.text.trim().isEmpty
            ? 'Inventory item'
            : _name.text.trim(),
        photoReference: current,
      );
      return;
    }
    final picked = await pickAndCropAveraPhoto(action);
    if (!mounted || picked == null) return;
    setState(() => _pendingImagePath = picked.path);
  }

  static String _numberText(num value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

class _InventoryImageField extends StatelessWidget {
  const _InventoryImageField({
    required this.name,
    required this.imageReference,
    required this.onPressed,
  });

  final String name;
  final String? imageReference;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final reference = imageReference?.trim();
    final image = reference == null || reference.isEmpty
        ? null
        : reference.startsWith('http')
        ? NetworkImage(reference) as ImageProvider<Object>
        : localIdentityImage(reference);
    return AveraLabeledFieldCard(
      label: 'Product Image',
      child: InkWell(
        onTap: onPressed,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 76,
                child: image == null
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(Icons.add_photo_alternate_outlined),
                      )
                    : Image(
                        image: image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Colors.transparent,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image == null
                        ? 'Add product image'
                        : 'Change product image',
                    style: averaText(context).fieldValue,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Square photos display best in inventory and the future clinic shop.',
                    style: averaText(context).caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
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
