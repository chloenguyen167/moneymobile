import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_service.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../notification_listener/notification_parser.dart';

/// Quick-add via pasted/shared notification text (iOS Share Sheet alternative).
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key, this.initialText});

  final String? initialText;

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  late final _textCtrl = TextEditingController(text: widget.initialText ?? '');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final ai = ref.read(aiServiceProvider);

    // Lớp 0: regex — lớp 1: AI local fallback
    double? amount;
    String? merchant;
    String? category;
    final parsed = parseGenericAmount(text);
    if (parsed != null) {
      amount = parsed.amount;
      merchant = parsed.merchant;
    } else {
      final aiParsed = await ai.parseNotification(text);
      if (aiParsed != null && aiParsed.isExpense) {
        amount = aiParsed.amount;
        merchant = aiParsed.merchant;
        category = aiParsed.category;
      }
    }

    if (amount == null) {
      setState(() {
        _error = 'Không tìm thấy số tiền trong text';
        _loading = false;
      });
      return;
    }

    try {
      category ??= merchant != null ? await ai.classifyMerchant(merchant) : null;
      int? categoryId;
      if (category != null) {
        final categories = await ref.read(repositoryProvider).getCategories();
        categoryId = categories.where((c) => c.name == category).firstOrNull?.id;
      }
      await ref.read(repositoryProvider).createTransaction(
            amount: amount,
            merchantName: merchant,
            categoryId: categoryId,
            source: 'manual',
            classificationReason: 'on-device quick add',
          );
      ref.invalidate(transactionsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm nhanh')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dán nội dung thông báo/email giao dịch',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Dùng khi share từ app ngân hàng/ví (iOS) hoặc copy SMS.',
              style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textCtrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'VD: TK ... -500,000VND luc 14:30 tai HIGHLANDS COFFEE',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Thêm giao dịch'),
            ),
          ],
        ),
      ),
    );
  }
}
