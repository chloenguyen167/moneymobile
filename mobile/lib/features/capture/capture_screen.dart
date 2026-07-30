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
          const _CaptureHero(),
          const SizedBox(height: 20),
          _CaptureModeCard(
            icon: Icons.receipt_long_rounded,
            eyebrow: 'Receipt OCR',
            title: 'Hóa đơn mua hàng',
            subtitle:
                'Dùng cho siêu thị, cửa hàng, quán ăn và các hóa đơn có nhiều dòng sản phẩm.',
            bullets: const [
              'Giữ nguyên pipeline OCR hóa đơn hiện tại',
              'Phù hợp khi cần tách từng món và cộng dồn theo nhóm',
            ],
            actionLabel: 'Mở chụp hóa đơn',
            accent: AppColors.secondary,
            backgroundTint: const Color(0xFFEAF3FA),
            onTap: () => context.push('/capture/receipt'),
          ),
          const SizedBox(height: 16),
          _CaptureModeCard(
            icon: Icons.account_balance_wallet_rounded,
            eyebrow: 'Payment OCR',
            title: 'Ảnh giao dịch ngân hàng / ví',
            subtitle:
                'Dùng cho screenshot thanh toán từ TPBank, MoMo, ZaloPay, ShopeePay và các app tương tự.',
            bullets: const [
              'Tập trung đọc ra một giao dịch duy nhất',
              'Tối ưu cho số tiền, người nhận, mã giao dịch và nội dung chuyển khoản',
            ],
            actionLabel: 'Mở ảnh giao dịch',
            accent: AppColors.primary,
            backgroundTint: const Color(0xFFFFF5CC),
            onTap: () => context.push('/capture/payment'),
          ),
          const SizedBox(height: 18),
          const _CompareCard(),
        ],
      ),
    );
  }
}

class _CaptureHero extends StatelessWidget {
  const _CaptureHero();

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.secondary, Color(0xFF3E7CAA)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Nhập ảnh thông minh',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Chọn đúng loại ảnh để OCR ổn định hơn',
            style: titleStyle?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tuchi tách riêng receipt OCR và payment OCR để tránh nhầm luồng, tăng độ chính xác và giúp kết quả dễ đọc hơn.',
            style: TextStyle(
              color: Color(0xFFEAF2F8),
              height: 1.45,
              fontSize: 14,
            ),
          ),
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
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: backgroundTint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow.toUpperCase(),
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.onSurfaceMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              ...bullets.map(
                (bullet) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bullet,
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: accent == AppColors.primary
                        ? AppColors.onPrimary
                        : AppColors.onSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel),
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
