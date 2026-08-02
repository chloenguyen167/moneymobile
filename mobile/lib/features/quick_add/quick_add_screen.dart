import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';
import '../notification_listener/notification_parser.dart';

/// Primary: manual add. Secondary: paste bank notification text.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key, this.initialText});

  final String? initialText;

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _pasteCtrl;
  int? _categoryId;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _amountCtrl = TextEditingController();
    _merchantCtrl = TextEditingController();
    _pasteCtrl = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveManual() async {
    final amount = parseVndInput(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Nhập số tiền hợp lệ');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).createTransaction(
            amount: amount,
            merchantName: _merchantCtrl.text.trim().isEmpty
                ? null
                : _merchantCtrl.text.trim(),
            categoryId: _categoryId,
          );
      invalidateTransactionRelated(ref);
      if (mounted) context.pop(true);
    } catch (_) {
      setState(() => _error = 'Không lưu được. Thử lại nhé.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePaste() async {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final parsed = parseGenericAmount(text);
    if (parsed == null) {
      setState(() {
        _error = 'Không tìm thấy số tiền trong nội dung';
        _loading = false;
      });
      return;
    }

    try {
      await ref.read(repositoryProvider).ingestNotification(
            packageName: 'manual.share',
            amount: parsed.amount,
            merchant: parsed.merchant,
          );
      invalidateTransactionRelated(ref);
      if (mounted) context.pop(true);
    } catch (_) {
      setState(() => _error = 'Không lưu được. Thử lại nhé.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thêm nhanh'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.onSecondary,
          unselectedLabelColor: AppColors.onSecondary.withValues(alpha: 0.65),
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Nhập tay'),
            Tab(text: 'Dán thông báo'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ManualTab(
            amountCtrl: _amountCtrl,
            merchantCtrl: _merchantCtrl,
            categories: categories,
            categoryId: _categoryId,
            onCategory: (v) => setState(() => _categoryId = v),
            loading: _loading,
            error: _error,
            onSave: _saveManual,
          ),
          _PasteTab(
            controller: _pasteCtrl,
            loading: _loading,
            error: _error,
            onSave: _savePaste,
          ),
        ],
      ),
    );
  }
}

class _ManualTab extends StatelessWidget {
  const _ManualTab({
    required this.amountCtrl,
    required this.merchantCtrl,
    required this.categories,
    required this.categoryId,
    required this.onCategory,
    required this.loading,
    required this.error,
    required this.onSave,
  });

  final TextEditingController amountCtrl;
  final TextEditingController merchantCtrl;
  final List<CategoryModel> categories;
  final int? categoryId;
  final ValueChanged<int?> onCategory;
  final bool loading;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Số tiền',
            suffixText: 'đ',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: merchantCtrl,
          decoration: const InputDecoration(
            labelText: 'Người nhận / cửa hàng',
            hintText: 'Không bắt buộc',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          value: categoryId,
          decoration: const InputDecoration(labelText: 'Danh mục'),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Chưa phân loại'),
            ),
            ...categories.map(
              (c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
            ),
          ],
          onChanged: onCategory,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading ? null : onSave,
          child: loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Lưu giao dịch'),
        ),
      ],
    );
  }
}

class _PasteTab extends StatelessWidget {
  const _PasteTab({
    required this.controller,
    required this.loading,
    required this.error,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool loading;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Dán nội dung SMS / thông báo ngân hàng, ví điện tử.',
          style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText:
                'VD: TK ... -500,000VND luc 14:30 tai HIGHLANDS COFFEE',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading ? null : onSave,
          child: loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Thêm giao dịch'),
        ),
      ],
    );
  }
}
