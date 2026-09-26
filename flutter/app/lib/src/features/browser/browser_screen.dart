import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';

import '../../jobs/job_controller.dart';
import '../settings/settings_dialog.dart';
import '../sources/source_controller.dart';
import 'browser_controller.dart';
import 'browser_operations.dart';
import 'browser_widgets.dart';
import 'selection_controller.dart';

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceProvider);
    final browser = ref.watch(browserProvider);
    final selection = ref.watch(selectionProvider);
    final job = ref.watch(jobProvider);
    final l10n = AppLocalizations.of(context);
    final selecting = selection.isNotEmpty;
    final selectedItems = browser.items
        .where((i) => selection.contains(i.path))
        .toList();
    final up = source == null
        ? null
        : browserParentPath(source.root, browser.path);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            BrowserOperations.openLocal(context, ref),
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): () =>
            BrowserOperations.openSmb(context, ref),
        const SingleActivator(LogicalKeyboardKey.f5): () {
          final current = ref.read(sourceProvider);
          if (current != null) {
            final dir = ref.read(browserProvider).path;
            ref.read(browserProvider.notifier).load(current.vfs, dir);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => ref
            .read(selectionProvider.notifier)
            .select(ref.read(browserProvider).items.map((i) => i.path)),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(selectionProvider.notifier).clear(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: selecting
                ? IconButton(
                    tooltip: 'Cancel selection',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        ref.read(selectionProvider.notifier).clear(),
                  )
                : up == null
                ? null
                : IconButton(
                    tooltip: 'Up',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => navigate(ref, source!, up),
                  ),
            title: Text(
              selecting
                  ? '${selection.length} selected'
                  : (source?.label ?? l10n.appTitle),
            ),
            actions: selecting
                ? [
                    IconButton(
                      tooltip: 'Validate',
                      icon: const Icon(Icons.fact_check_outlined),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.validate(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Convert to WebP',
                      icon: const Icon(Icons.transform),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.convert(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Batch edit pages',
                      icon: const Icon(Icons.tune),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.batchEdit(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Remove ComicInfo',
                      icon: const Icon(Icons.bookmark_remove_outlined),
                      onPressed: job?.running == true || source == null
                          ? null
                          : () => BrowserOperations.removeComicInfo(
                              context,
                              ref,
                              source,
                              selectedItems,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Select all',
                      icon: const Icon(Icons.select_all),
                      onPressed: () => ref
                          .read(selectionProvider.notifier)
                          .select(browser.items.map((i) => i.path)),
                    ),
                  ]
                : [
                    if (source != null)
                      IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh),
                        onPressed: job?.running == true
                            ? null
                            : () => ref
                                  .read(browserProvider.notifier)
                                  .load(source.vfs, browser.path),
                      ),
                    if (source != null && browser.items.isNotEmpty)
                      IconButton(
                        tooltip: 'Select',
                        icon: const Icon(Icons.checklist),
                        onPressed: () => ref
                            .read(selectionProvider.notifier)
                            .select(browser.items.map((i) => i.path)),
                      ),
                    if (source != null && browser.items.isNotEmpty)
                      IconButton(
                        tooltip: 'Merge chapters',
                        icon: const Icon(Icons.merge_type),
                        onPressed: job?.running == true
                            ? null
                            : () => BrowserOperations.merge(
                                context,
                                ref,
                                source,
                                browser.items,
                              ),
                      ),
                    if (source != null && browser.items.any((i) => i.isCbr))
                      IconButton(
                        tooltip: 'Convert CBR to CBZ',
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: job?.running == true
                            ? null
                            : () => BrowserOperations.convertCbr(
                                context,
                                ref,
                                source,
                                [
                                  for (final i in browser.items)
                                    if (i.isCbr) i.name,
                                ],
                              ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Open source',
                      onSelected: (value) {
                        if (value == 'local') {
                          BrowserOperations.openLocal(context, ref);
                        } else {
                          BrowserOperations.openSmb(context, ref);
                        }
                      },
                      itemBuilder: (context) => [
                        if (!kIsWeb &&
                            defaultTargetPlatform != TargetPlatform.android)
                          const PopupMenuItem(
                            value: 'local',
                            child: Text('Open local folder'),
                          ),
                        const PopupMenuItem(
                          value: 'smb',
                          child: Text('Connect to SMB share'),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: l10n.settings,
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => showSettingsDialog(context),
                    ),
                  ],
            bottom: job == null
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(44),
                    child: BrowserJobBar(job: job),
                  ),
          ),
          body: source == null
              ? BrowserWelcome(
                  onLocal: () => BrowserOperations.openLocal(context, ref),
                  onSmb: () => BrowserOperations.openSmb(context, ref),
                )
              : PopScope(
                  // System back climbs out of a subfolder before leaving the app.
                  canPop: up == null,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop || up == null) return;
                    navigate(ref, source, up);
                  },
                  child: BrowserBody(source: source, browser: browser),
                ),
        ),
      ),
    );
  }
}
