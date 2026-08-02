import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';

/// Money Lover–style amount-first form for create / edit.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.transaction,
    this.transactionId,
  });

  final TransactionModel? transaction;
  final int? transactionId;

  bool get isEditing => transaction != null || transactionId != null;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _merchantCtrl;
  DateTime _date = DateTime.now();
  int? _categoryId;
  int? _editingId;
  String _type = 'expense';
  bool _saving = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    _editingId = tx?.id ?? widget.transactionId;
    _amountCtrl = TextEditingController(
      text: tx != null ? tx.amount.round().toString() : '',
    );
    _merchantCtrl = TextEditingController(text: tx?.merchantName ?? '');
    _date = tx?.transactionDate ?? DateTime.now();
    _categoryId = tx?.categoryId;
    _type = tx?.transactionType ?? 'expense';
    if (tx == null && widget.transactionId != null) {
      _load(widget.transactionId!);
    }
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      final tx = await ref.read(repositoryProvider).getTransaction(id);
      if (!mounted) return;
      setState(() {
        _editingId = tx.id;
        _amountCtrl.text = tx.amount.round().toString();
        _merchantCtrl.text = tx.merchantName ?? '';
        _date = tx.transactionDate;
        _categoryId = tx.categoryId;
        _type = tx.transactionType;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Không tải được giao dịch');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.secondary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = parseVndInput(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Nhập số tiền hợp lệ');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(repositoryProvider);
      if (_editingId != null) {
        await repo.updateTransaction(
          id: _editingId!,
          amount: amount,
          merchantName: _merchantCtrl.text.trim().isEmpty
              ? null
              : _merchantCtrl.text.trim(),
          categoryId: _categoryId,
          transactionDate: _date,
          transactionType: _type,
        );
      } else {
        await repo.createTransaction(
          amount: amount,
          merchantName: _merchantCtrl.text.trim().isEmpty
              ? null
              : _merchantCtrl.text.trim(),
          categoryId: _categoryId,
          transactionDate: _date,
          transactionType: _type,
        );
      }
      invalidateTransactionRelated(ref);
      if (mounted) context.pop(true);
    } catch (e) {
      setState(() => _error = 'Không lưu được. Thử lại nhé.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCats = ref.watch(categoriesProvider).valueOrNull ?? [];
    final categories = allCats.where((c) {
      final isIncomeCat = incomeCategoryNames.contains(c.name);
      return _type == 'income' ? isIncomeCat : !isIncomeCat;
    }).toList();
    final dateFmt = DateFormat('dd/MM/yyyy');
    if (_categoryId != null &&
        categories.every((c) => c.id != _categoryId)) {
      // Reset if type switch invalidates selection
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryId = null);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Sửa giao dịch' : 'Thêm giao dịch'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(
              'Lưu',
              style: TextStyle(
                color: AppColors.onSecondary.withValues(
                  alpha: _saving || _loading ? 0.5 : 1,
                ),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'expense',
                      label: Text('Chi'),
                      icon: Icon(Icons.north_east_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text('Thu'),
                      icon: Icon(Icons.south_west_rounded, size: 16),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    _categoryId = null;
                  }),
                ),
                const SizedBox(height: 16),
                _AmountHero(controller: _amountCtrl, isIncome: _type == 'income'),
                const SizedBox(height: 20),
                _FormCard(
                  children: [
                    _FormTile(
                      icon: Icons.storefront_rounded,
                      label: _type == 'income'
                          ? 'Nguồn / người gửi'
                          : 'Người nhận / cửa hàng',
                      child: TextField(
                        controller: _merchantCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: _type == 'income'
                              ? 'VD: Công ty ABC'
                              : 'VD: Highlands Coffee',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    _FormTile(
                      icon: Icons.calendar_today_rounded,
                      label: 'Ngày',
                      onTap: _pickDate,
                      child: Text(
                        dateFmt.format(_date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    _FormTile(
                      icon: Icons.category_rounded,
                      label: 'Danh mục',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          isExpanded: true,
                          value: _categoryId,
                          hint: const Text('Chọn danh mục'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Chưa phân loại'),
                            ),
                            ...categories.map(
                              (c) => DropdownMenuItem<int?>(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _categoryId = v),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.isEditing ? 'Cập nhật' : 'Thêm giao dịch'),
                ),
              ],
            ),
    );
  }
}

class _AmountHero extends StatelessWidget {
  const _AmountHero({required this.controller, this.isIncome = false});

  final TextEditingController controller;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isIncome
              ? const [Color(0xFF2E7D32), Color(0xFF43A047)]
              : const [AppColors.secondary, Color(0xFF3E7CAA)],
        ),
        boxShadow: [
          BoxShadow(
            color: (isIncome ? AppColors.success : AppColors.secondary)
                .withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            isIncome ? 'Số tiền thu' : 'Số tiền chi',
            style: const TextStyle(
              color: Color(0xFFE3EEF7),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
            decoration: const InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(color: Color(0x99FFFFFF), fontSize: 40),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              suffixText: 'đ',
              suffixStyle: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _FormTile extends StatelessWidget {
  const _FormTile({
    required this.icon,
    required this.label,
    required this.child,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.secondary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.onSurfaceMuted,
              ),
          ],
        ),
      ),
    );
  }
}
