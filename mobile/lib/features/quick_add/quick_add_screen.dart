import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';

class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key, this.initialText});

  final String? initialText;

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  late final _amountCtrl = TextEditingController();
  late final _descriptionCtrl = TextEditingController();
  late final _merchantCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;
  int? _selectedCategoryId;
  DateTime _transactionTime = DateTime.now();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _transactionTime,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      locale: const Locale('vi'),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_transactionTime),
    );
    if (!mounted) return;

    setState(() {
      _transactionTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? _transactionTime.hour,
        pickedTime?.minute ?? _transactionTime.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final rawAmount = _amountCtrl.text.replaceAll('.', '').replaceAll(',', '');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Số tiền không hợp lệ.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(repositoryProvider)
          .createTransaction(
            amount: amount,
            merchantName: _merchantCtrl.text.trim().isEmpty
                ? null
                : _merchantCtrl.text.trim(),
            description: _descriptionCtrl.text.trim(),
            categoryId: _selectedCategoryId,
            transactionTime: _transactionTime,
            source: 'manual',
          );
      ref.invalidate(transactionsProvider);
      ref.invalidate(budgetsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(cashflowInsightsProvider);
      ref.invalidate(subscriptionsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final dateFmt = DateFormat('HH:mm · dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Thêm nhanh')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Tạo giao dịch thủ công',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nhập nhanh một giao dịch với đủ số tiền, nhóm chi tiêu, thời gian và mô tả.',
              style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền',
                hintText: 'VD: 150000',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return 'Nhập số tiền';
                final parsed = double.tryParse(
                  value!.replaceAll('.', '').replaceAll(',', ''),
                );
                if (parsed == null || parsed <= 0) {
                  return 'Số tiền không hợp lệ';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionCtrl,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLines: 2,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                hintText: 'VD: Ăn trưa, mua đồ siêu thị, gửi xe...',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return 'Nhập mô tả';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _merchantCtrl,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              decoration: const InputDecoration(
                labelText: 'Merchant',
                hintText: 'Không bắt buộc, VD: Highlands Coffee, Winmart...',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 14),
            categoriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(
                'Không tải được nhóm chi tiêu: $e',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              data: (categories) {
                return DropdownButtonFormField<int>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Phân loại nhóm',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: categories.map((cat) {
                    return DropdownMenuItem<int>(
                      value: cat.id,
                      child: Text(cat.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedCategoryId = value);
                  },
                  validator: (value) =>
                      value == null ? 'Chọn nhóm chi tiêu' : null,
                );
              },
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Thời gian giao dịch',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(dateFmt.format(_transactionTime))),
                    const Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_loading ? 'Đang lưu...' : 'Tạo giao dịch'),
            ),
          ],
        ),
      ),
    );
  }
}
