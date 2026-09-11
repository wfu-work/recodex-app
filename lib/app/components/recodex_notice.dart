import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

enum RecodexNoticeTone { info, success, warning, error }

/// Transient feedback shared by all pages. New messages replace stale ones.
abstract final class RecodexNotice {
  static void show(
    BuildContext context,
    String message, {
    RecodexNoticeTone tone = RecodexNoticeTone.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted || message.trim().isEmpty) return;
    final host = context.findAncestorStateOfType<_RecodexNoticeHostState>();
    assert(host != null, 'Place RecodexNoticeHost in the app builder.');
    host?._show(
      message,
      tone,
      // Screen readers need time to reach the message and its close action.
      MediaQuery.accessibleNavigationOf(context) ? null : duration,
    );
  }
}

/// Lives above the navigator so feedback survives route changes and dialogs.
class RecodexNoticeHost extends StatefulWidget {
  const RecodexNoticeHost({
    required this.child,
    this.reduceMotion = false,
    super.key,
  });

  final Widget child;
  final bool reduceMotion;

  @override
  State<RecodexNoticeHost> createState() => _RecodexNoticeHostState();
}

class _RecodexNoticeHostState extends State<RecodexNoticeHost> {
  Timer? _timer;
  String? _message;
  RecodexNoticeTone _tone = RecodexNoticeTone.info;
  var _revision = 0;

  void _show(String message, RecodexNoticeTone tone, Duration? duration) {
    _timer?.cancel();
    setState(() {
      _message = message;
      _tone = tone;
      _revision++;
    });
    if (duration != null) _timer = Timer(duration, _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    setState(() => _message = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = widget.reduceMotion || media.disableAnimations;
    final windowInset = Theme.of(context).platform == TargetPlatform.macOS
        ? 28.0
        : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: media.viewPadding.top + windowInset + 12,
          left: media.viewPadding.left + 16,
          right: media.viewPadding.right + 16,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    for (final previous in previousChildren)
                      IgnorePointer(child: ExcludeSemantics(child: previous)),
                    ?currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _message == null
                    ? const SizedBox.shrink()
                    : _NoticeCard(
                        key: ValueKey(_revision),
                        message: _message!,
                        tone: _tone,
                        onDismiss: _dismiss,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    required this.tone,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final RecodexNoticeTone tone;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final (icon, color) = switch (tone) {
      RecodexNoticeTone.info => (RecodexIcons.info, colors.textMuted),
      RecodexNoticeTone.success => (RecodexIcons.checkCircle, colors.success),
      RecodexNoticeTone.warning => (RecodexIcons.warning, colors.warning),
      RecodexNoticeTone.error => (RecodexIcons.error, colors.error),
    };
    final media = MediaQuery.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.glassShadow,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: colors.glassColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.glassBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(240, media.size.height * 0.4),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(
                    RecodexIcons.close,
                    size: 16,
                    semanticLabel: '关闭提示',
                  ),
                  color: colors.textMuted,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
