import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../notification_listener/notification_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCaptureTab = shell.currentIndex == 1;

    return Scaffold(
      backgroundColor: isCaptureTab ? Colors.black : null,
      appBar: isCaptureTab
          ? null
          : AppBar(
              toolbarHeight: 92,
              automaticallyImplyLeading: false,
              flexibleSpace: const _HeaderBackground(),
              titleSpacing: 16,
              title: const _HomeBrand(),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TopActionButton(
                        icon: Icons.notifications_none_rounded,
                        tooltip: 'Theo dõi giao dịch',
                        onPressed: () =>
                            context.push('/settings/notifications'),
                      ),
                      const SizedBox(width: 6),
                      _TopMenuButton(
                        onSelected: (value) async {
                          switch (value) {
                            case _HomeMenuAction.subscriptions:
                              context.push('/subscriptions');
                              break;
                            case _HomeMenuAction.quickAdd:
                              context.push('/quick-add');
                              break;
                            case _HomeMenuAction.email:
                              context.push('/settings/email');
                              break;
                            case _HomeMenuAction.logout:
                              await ref
                                  .read(notificationCaptureProvider)
                                  .stop();
                              ref.read(alertPollerProvider).stop();
                              await ref.read(repositoryProvider).logout();
                              ref.invalidate(authTokenProvider);
                              if (context.mounted) context.go('/login');
                              break;
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: shell.goBranch,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Giao dịch',
            ),
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt_rounded),
              label: 'Quét ảnh',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Ngân sách',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Phân tích',
            ),
          ],
        ),
      ),
    );
  }
}

enum _HomeMenuAction { subscriptions, quickAdd, email, logout }

class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B6490), Color(0xFF3C7AA8), Color(0xFF4C8AB5)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B6490).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -18,
            top: 0,
            child: _GlowOrb(
              size: 100,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Positioned(
            right: 60,
            top: -18,
            child: _GlowOrb(
              size: 86,
              color: AppColors.primary.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            right: -10,
            bottom: -26,
            child: _GlowOrb(
              size: 90,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _HomeBrand extends StatelessWidget {
  const _HomeBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.94),
                Colors.white.withValues(alpha: 0.76),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.pie_chart_rounded,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Tuchi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Quản lý chi tiêu cá nhân',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFE3EEF7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _TopMenuButton extends StatelessWidget {
  const _TopMenuButton({required this.onSelected});

  final Future<void> Function(_HomeMenuAction value) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_HomeMenuAction>(
      tooltip: 'Thêm tuỳ chọn',
      onSelected: (value) => onSelected(value),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _HomeMenuAction.subscriptions,
          child: _MenuItemRow(
            icon: Icons.auto_awesome_motion_rounded,
            label: 'Chi tiêu định kỳ',
          ),
        ),
        PopupMenuItem(
          value: _HomeMenuAction.quickAdd,
          child: _MenuItemRow(
            icon: Icons.content_paste_rounded,
            label: 'Dán thông báo',
          ),
        ),
        PopupMenuItem(
          value: _HomeMenuAction.email,
          child: _MenuItemRow(
            icon: Icons.mail_outline_rounded,
            label: 'Đồng bộ email',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _HomeMenuAction.logout,
          child: _MenuItemRow(icon: Icons.logout_rounded, label: 'Đăng xuất'),
        ),
      ],
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
