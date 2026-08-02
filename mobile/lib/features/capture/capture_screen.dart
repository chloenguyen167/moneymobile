import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF5F9FC), AppColors.background],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Text(
            'Nhập ảnh',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Chọn đúng loại ảnh để OCR dễ đọc và chính xác hơn.',
            style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
          ),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CaptureModeCard(
                    icon: Icons.receipt_long_rounded,
                    eyebrow: 'Receipt OCR',
                    title: 'Hóa đơn',
                    subtitle: 'Ảnh có nhiều dòng sản phẩm.',
                    bullets: const [
                      'Tách item theo nhóm',
                      'Phù hợp siêu thị, cửa hàng',
                    ],
                    actionLabel: 'Chụp hóa đơn',
                    accent: AppColors.secondary,
                    backgroundTint: const Color(0xFFEAF3FA),
                    onTap: () => context.push('/capture/receipt'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CaptureModeCard(
                    icon: Icons.account_balance_wallet_rounded,
                    eyebrow: 'Payment OCR',
                    title: 'Ảnh giao dịch',
                    subtitle: 'Screenshot thanh toán từ ngân hàng, ví.',
                    bullets: const [
                      'Đọc 1 giao dịch',
                      'Ưu tiên số tiền, người nhận',
                    ],
                    actionLabel: 'Mở ảnh GD',
                    accent: AppColors.primary,
                    backgroundTint: const Color(0xFFFFF5CC),
                    onTap: () => context.push('/capture/payment'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _CompareCard(),
        ],
      ),
    );
  }
}

class _CaptureModeCard extends StatelessWidget {
  const _CaptureModeCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.actionLabel,
    required this.accent,
    required this.backgroundTint,
    required this.onTap,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final String actionLabel;
  final Color accent;
  final Color backgroundTint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: backgroundTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                eyebrow.toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.onSurfaceMuted,
                  height: 1.42,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              ...bullets.map(
                (bullet) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bullet,
                          style: const TextStyle(height: 1.35, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: accent == AppColors.primary
                        ? AppColors.onPrimary
                        : AppColors.onSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Khi nào chọn loại nào?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          SizedBox(height: 14),
          _CompareRow(
            label: 'Hóa đơn',
            description:
                'Có nhiều mặt hàng, cần tách item và phân loại từng nhóm.',
          ),
          SizedBox(height: 10),
          _CompareRow(
            label: 'Ảnh giao dịch',
            description:
                'Chỉ có một khoản thanh toán, ưu tiên đọc số tiền và người nhận.',
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(height: 1.45),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: description,
                  style: const TextStyle(color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
