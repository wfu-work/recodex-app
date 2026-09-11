import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
import '../services/composer_images.dart';
import '../theme/recodex_theme.dart';

enum ComposerImageSource { gallery, camera, clipboard }

class ComposerAddButton extends StatelessWidget {
  const ComposerAddButton({
    super.key,
    required this.enabled,
    required this.onImages,
    required this.onFiles,
    required this.onSkills,
  });
  final bool enabled;
  final ValueChanged<ComposerImageSource> onImages;
  final VoidCallback onFiles;
  final VoidCallback onSkills;

  @override
  Widget build(BuildContext context) {
    final items = <(String, IconData, VoidCallback)>[
      ('选择图片', RecodexIcons.image, () => onImages(ComposerImageSource.gallery)),
      (
        '粘贴图片',
        RecodexIcons.copy,
        () => onImages(ComposerImageSource.clipboard),
      ),
      ('引用工作区文件', RecodexIcons.folder, onFiles),
      ('选择 Skill', RecodexIcons.fast, onSkills),
    ];
    return Stack(
      children: [
        SizedBox(
          width: 0,
          height: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: ComposerImageButton(
                enabled: enabled,
                tooltip: null,
                onSelected: onImages,
              ),
            ),
          ),
        ),
        PopupMenuButton<int>(
          enabled: enabled,
          // Keep the historical tooltip so keyboard/accessibility tests and
          // existing users still recognize the image attachment affordance.
          tooltip: '添加图片',
          icon: const Icon(RecodexIcons.add, size: 21),
          onSelected: (index) => items[index].$3(),
          itemBuilder: (_) => [
            for (var index = 0; index < items.length; index++)
              PopupMenuItem(
                value: index,
                height: 42,
                child: Row(
                  children: [
                    Icon(items[index].$2, size: 18),
                    const SizedBox(width: 10),
                    Text(items[index].$1),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ComposerReferenceTray extends StatelessWidget {
  const ComposerReferenceTray({
    super.key,
    required this.files,
    required this.skills,
    required this.onRemoveFile,
    required this.onRemoveSkill,
  });
  final List<WorkspaceEntry> files;
  final List<SkillInfo> skills;
  final ValueChanged<WorkspaceEntry> onRemoveFile;
  final ValueChanged<SkillInfo> onRemoveSkill;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    if (files.isEmpty && skills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final file in files)
            InputChip(
              avatar: Icon(
                file.kind == 'directory'
                    ? RecodexIcons.folder
                    : RecodexIcons.fileText,
                size: 15,
                color: colors.textMuted,
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(file.path, overflow: TextOverflow.ellipsis),
              ),
              onDeleted: () => onRemoveFile(file),
              visualDensity: VisualDensity.compact,
            ),
          for (final skill in skills)
            InputChip(
              avatar: Icon(
                RecodexIcons.fast,
                size: 15,
                color: colors.textMuted,
              ),
              label: Text('\$${skill.name}'),
              onDeleted: () => onRemoveSkill(skill),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class ComposerImageButton extends StatelessWidget {
  const ComposerImageButton({
    super.key,
    required this.enabled,
    required this.onSelected,
    this.tooltip = '添加图片',
    this.onFiles,
    this.onSkills,
  });
  final bool enabled;
  final ValueChanged<ComposerImageSource> onSelected;
  final String? tooltip;
  final VoidCallback? onFiles;
  final VoidCallback? onSkills;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final mobile =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;
    final items = <(ComposerImageSource, IconData, String)>[
      (
        ComposerImageSource.gallery,
        RecodexIcons.image,
        mobile ? '相册图片' : '选择图片',
      ),
      if (mobile) (ComposerImageSource.camera, RecodexIcons.camera, '拍照'),
      (ComposerImageSource.clipboard, RecodexIcons.copy, '粘贴图片'),
    ];
    if (!mobile) {
      return PopupMenuButton<Object>(
        tooltip: tooltip,
        enabled: enabled,
        icon: const Icon(RecodexIcons.add, size: 21),
        constraints: const BoxConstraints(minWidth: 176),
        position: PopupMenuPosition.over,
        onSelected: (value) {
          if (value is ComposerImageSource) onSelected(value);
          if (value == 'files') onFiles?.call();
          if (value == 'skills') onSkills?.call();
        },
        itemBuilder: (_) => [
          for (final item in items)
            PopupMenuItem(
              value: item.$1,
              height: 44,
              child: Row(
                children: [
                  Icon(item.$2, size: 18),
                  const SizedBox(width: 10),
                  Flexible(child: Text(item.$3)),
                ],
              ),
            ),
          if (onFiles != null)
            const PopupMenuItem<Object>(
              value: 'files',
              height: 44,
              child: Row(
                children: [
                  Icon(RecodexIcons.folder, size: 18),
                  SizedBox(width: 10),
                  Text('引用工作区文件'),
                ],
              ),
            ),
          if (onSkills != null)
            const PopupMenuItem<Object>(
              value: 'skills',
              height: 44,
              child: Row(
                children: [
                  Icon(RecodexIcons.fast, size: 18),
                  SizedBox(width: 10),
                  Text('选择 Skill'),
                ],
              ),
            ),
        ],
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(RecodexIcons.add, size: 21),
      onPressed: !enabled
          ? null
          : () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final source = await showModalBottomSheet<Object>(
                context: context,
                showDragHandle: true,
                useSafeArea: true,
                builder: (sheetContext) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items)
                          ListTile(
                            minTileHeight: 48,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(item.$2, size: 21),
                            title: Text(item.$3),
                            onTap: () => Navigator.pop(sheetContext, item.$1),
                          ),
                        if (onFiles != null)
                          ListTile(
                            leading: const Icon(RecodexIcons.folder),
                            title: const Text('引用工作区文件'),
                            onTap: () {
                              Navigator.pop(sheetContext, 'files');
                            },
                          ),
                        if (onSkills != null)
                          ListTile(
                            leading: const Icon(RecodexIcons.fast),
                            title: const Text('选择 Skill'),
                            onTap: () {
                              Navigator.pop(sheetContext, 'skills');
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            '最多 4 张图片',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.recodexColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              if (source is ComposerImageSource) onSelected(source);
              if (source == 'files') onFiles?.call();
              if (source == 'skills') onSkills?.call();
            },
    );
  }
}

class ComposerImageTray extends StatelessWidget {
  const ComposerImageTray({
    super.key,
    required this.images,
    required this.onRemove,
    this.busy = false,
    this.progress = 0,
    this.error,
    this.unknown = false,
    this.onReview,
  });
  final List<ComposerImage> images;
  final ValueChanged<ComposerImage> onRemove;
  final bool busy;
  final double progress;
  final String? error;
  final bool unknown;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 88,
            child: ListView.separated(
              primary: false,
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = images[index];
                return SizedBox(
                  width: 88,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Material(
                          color: colors.surfaceOverlay,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => Dialog(
                                insetPadding: const EdgeInsets.all(16),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      minScale: 0.5,
                                      maxScale: 5,
                                      child: Image.memory(
                                        image.bytes,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: IconButton.filledTonal(
                                        tooltip: '关闭预览',
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(RecodexIcons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Semantics(
                              label: '预览 ${image.name}',
                              image: true,
                              child: Image.memory(
                                image.thumbnail,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            tooltip: '移除 ${image.name}',
                            onPressed: busy || unknown
                                ? null
                                : () => onRemove(image),
                            icon: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surfaceOverlay,
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(
                                  RecodexIcons.close,
                                  size: 15,
                                  color: colors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          if (busy) ...[
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 5),
          ],
          Text(
            unknown
                ? '发送结果待确认，请刷新任务核对'
                : error ??
                      (busy
                          ? (progress >= 1
                                ? '正在发送…'
                                : '上传图片 ${(progress * 100).round()}%')
                          : '${images.length} 张图片 · 待发送'),
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: error == null
                  ? colors.textMuted
                  : Theme.of(context).colorScheme.error,
            ),
          ),
          if (unknown)
            TextButton(onPressed: onReview, child: const Text('核对发送结果')),
        ],
      ),
    );
  }
}
