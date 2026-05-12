import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/bridge_controller.dart';
import '../models/bridge_models.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  final BridgeController controller = Get.find();
  final PageController _pageController = PageController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://127.0.0.1:8765',
  );
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController(
    text: 'Flutter phone',
  );
  final TextEditingController _pairingController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _commitController = TextEditingController();
  int _index = 0;
  bool _commitConfirmed = false;
  bool _pushConfirmed = false;

  @override
  void dispose() {
    _pageController.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _deviceNameController.dispose();
    _pairingController.dispose();
    _promptController.dispose();
    _commitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        appBar: AppBar(
          title: const Text('Recodex'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StatusPill(
                label: controller.connectionLabel.value,
                active: controller.connected.value,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (controller.lastError.value.isNotEmpty)
                ErrorBanner(
                  message: controller.lastError.value,
                  onDismiss: () => controller.lastError.value = '',
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    BridgeView(
                      controller: controller,
                      baseUrlController: _baseUrlController,
                      tokenController: _tokenController,
                      deviceNameController: _deviceNameController,
                      pairingController: _pairingController,
                      onApplyPairing: _applyPairingText,
                      onScanPairing: _scanPairing,
                    ),
                    WorkspacesView(controller: controller),
                    SessionsView(
                      controller: controller,
                      promptController: _promptController,
                    ),
                    GitView(
                      controller: controller,
                      commitController: _commitController,
                      commitConfirmed: _commitConfirmed,
                      pushConfirmed: _pushConfirmed,
                      onCommitConfirmedChanged: (value) {
                        setState(() => _commitConfirmed = value);
                      },
                      onPushConfirmedChanged: (value) {
                        setState(() => _pushConfirmed = value);
                      },
                    ),
                    DevicesView(controller: controller),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) {
            setState(() => _index = value);
            _pageController.jumpToPage(value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub),
              label: 'Bridge',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Projects',
            ),
            NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal),
              label: 'Session',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_tree_outlined),
              selectedIcon: Icon(Icons.account_tree),
              label: 'Git',
            ),
            NavigationDestination(
              icon: Icon(Icons.devices_outlined),
              selectedIcon: Icon(Icons.devices),
              label: 'Devices',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyPairingText() async {
    final raw = _pairingController.text.trim();
    if (raw.isEmpty) return;
    final info = PairingInfo.tryParse(raw);
    if (info == null) {
      controller.lastError.value = 'Pairing text is not valid.';
      return;
    }
    if (raw.startsWith('http') && raw.endsWith('/pairing')) {
      final fetched = await controller.fetchPairing(info.baseUrl);
      if (fetched != null) _applyPairing(fetched);
      return;
    }
    _applyPairing(info);
  }

  Future<void> _scanPairing() async {
    final result = await Navigator.of(context).push<PairingInfo>(
      MaterialPageRoute(builder: (_) => const PairingScannerPage()),
    );
    if (result != null) _applyPairing(result);
  }

  void _applyPairing(PairingInfo info) {
    _baseUrlController.text = info.baseUrl;
    _tokenController.text = info.token;
    _pairingController.text = info.pairingUri;
  }
}

class BridgeView extends StatelessWidget {
  const BridgeView({
    required this.controller,
    required this.baseUrlController,
    required this.tokenController,
    required this.deviceNameController,
    required this.pairingController,
    required this.onApplyPairing,
    required this.onScanPairing,
    super.key,
  });

  final BridgeController controller;
  final TextEditingController baseUrlController;
  final TextEditingController tokenController;
  final TextEditingController deviceNameController;
  final TextEditingController pairingController;
  final VoidCallback onApplyPairing;
  final VoidCallback onScanPairing;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SectionHeader(
          title: 'Bridge',
          subtitle: controller.connected.value
              ? 'Connected to ${controller.baseUrl.value}'
              : 'Pair this phone with a trusted local bridge.',
        ),
        const SizedBox(height: 12),
        InfoStrip(
          icon: Icons.vpn_key_outlined,
          label: controller.hasDeviceKey
              ? 'Stored device key'
              : 'No device key',
          value: controller.deviceId.value,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: baseUrlController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Bridge URL',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tokenController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Pairing token',
            prefixIcon: Icon(Icons.password),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: deviceNameController,
          decoration: const InputDecoration(
            labelText: 'Device name',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.busy.value
                    ? null
                    : () => controller.connect(
                        inputBaseUrl: baseUrlController.text,
                        token: tokenController.text,
                        inputDeviceName: deviceNameController.text,
                      ),
                icon: controller.busy.value
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.power_settings_new),
                label: const Text('Connect'),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: 'Disconnect',
              onPressed: controller.connected.value
                  ? () => controller.disconnect()
                  : null,
              icon: const Icon(Icons.power_off),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: controller.hasDeviceKey
              ? () => controller.clearStoredCredentials()
              : null,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear stored credentials'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pairingController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Pairing URI or JSON',
            hintText: 'recodex://pair?...',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onScanPairing,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.busy.value ? null : onApplyPairing,
                icon: const Icon(Icons.input),
                label: const Text('Apply'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class WorkspacesView extends StatelessWidget {
  const WorkspacesView({required this.controller, super.key});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionHeader(
            title: 'Projects',
            subtitle: controller.connected.value
                ? '${controller.workspaces.length} allowlisted workspaces'
                : 'Connect first to load allowlisted workspaces.',
          ),
          const SizedBox(height: 12),
          if (controller.workspaces.isEmpty)
            const EmptyPanel(
              icon: Icons.folder_off_outlined,
              title: 'No projects loaded',
              text: 'The bridge will expose only directories on its allowlist.',
            )
          else
            ...controller.workspaces.map(
              (workspace) => WorkspaceTile(
                workspace: workspace,
                selected:
                    controller.selectedWorkspace.value?.name == workspace.name,
                onTap: () => controller.selectWorkspace(workspace),
              ),
            ),
        ],
      ),
    );
  }
}

class SessionsView extends StatelessWidget {
  const SessionsView({
    required this.controller,
    required this.promptController,
    super.key,
  });

  final BridgeController controller;
  final TextEditingController promptController;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionHeader(
            title: 'Session',
            subtitle:
                controller.selectedWorkspace.value?.name ??
                'Choose a project before starting a session.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: promptController,
            minLines: 4,
            maxLines: 7,
            enabled: controller.canUseWorkspace,
            decoration: const InputDecoration(
              labelText: 'Prompt',
              alignLabelWithHint: true,
              hintText:
                  'Ask Codex to inspect, edit, test, or explain this project.',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.canUseWorkspace
                      ? () {
                          final prompt = promptController.text.trim();
                          if (prompt.isEmpty) return;
                          controller.startSession(prompt);
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Interrupt running session',
                onPressed: controller.currentSessionId.value == null
                    ? null
                    : controller.interrupt,
                icon: const Icon(Icons.stop),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PanelTitle(
                  title: 'Live output',
                  trailing: controller.currentSessionId.value == null
                      ? 'idle'
                      : 'running',
                ),
                const SizedBox(height: 10),
                if (controller.events.isEmpty)
                  const Text(
                    'Streaming output will appear here after a session starts.',
                    style: TextStyle(color: Color(0xff667066)),
                  )
                else
                  ...controller.events.map((event) => EventLine(event: event)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle(title: 'Recent sessions'),
                const SizedBox(height: 8),
                if (controller.sessions.isEmpty)
                  const Text(
                    'No session history yet.',
                    style: TextStyle(color: Color(0xff667066)),
                  )
                else
                  ...controller.sessions.take(8).map((session) {
                    return SessionTile(session: session);
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GitView extends StatelessWidget {
  const GitView({
    required this.controller,
    required this.commitController,
    required this.commitConfirmed,
    required this.pushConfirmed,
    required this.onCommitConfirmedChanged,
    required this.onPushConfirmedChanged,
    super.key,
  });

  final BridgeController controller;
  final TextEditingController commitController;
  final bool commitConfirmed;
  final bool pushConfirmed;
  final ValueChanged<bool> onCommitConfirmedChanged;
  final ValueChanged<bool> onPushConfirmedChanged;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionHeader(
            title: 'Git',
            subtitle:
                controller.selectedWorkspace.value?.name ??
                'Select a project to inspect Git state.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: controller.canUseWorkspace
                      ? () => controller.gitStatus(includeDiff: false)
                      : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Status'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: controller.canUseWorkspace
                      ? () => controller.gitStatus(includeDiff: true)
                      : null,
                  icon: const Icon(Icons.difference_outlined),
                  label: const Text('Diff'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.gitSnapshot.value == null)
            const EmptyPanel(
              icon: Icons.account_tree_outlined,
              title: 'No Git snapshot',
              text: 'Request status or diff before committing or pushing.',
            )
          else
            GitSnapshotPanel(snapshot: controller.gitSnapshot.value!),
          const SizedBox(height: 18),
          TextField(
            controller: commitController,
            enabled: controller.canUseWorkspace,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Commit message',
              alignLabelWithHint: true,
            ),
          ),
          CheckboxListTile(
            value: commitConfirmed,
            onChanged: (value) => onCommitConfirmedChanged(value ?? false),
            title: const Text('Confirm commit on this workspace'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          FilledButton.icon(
            onPressed: controller.canUseWorkspace && commitConfirmed
                ? () =>
                      controller.gitCommit(commitController.text, confirm: true)
                : null,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Commit'),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: pushConfirmed,
            onChanged: (value) => onPushConfirmedChanged(value ?? false),
            title: const Text('Confirm push to remote'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          OutlinedButton.icon(
            onPressed: controller.canUseWorkspace && pushConfirmed
                ? () => controller.gitPush(confirm: true)
                : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Push'),
          ),
        ],
      ),
    );
  }
}

class DevicesView extends StatelessWidget {
  const DevicesView({required this.controller, super.key});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionHeader(
            title: 'Devices',
            subtitle: controller.connected.value
                ? 'Review paired clients and revoke stale access.'
                : 'Connect to review paired devices.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: controller.connected.value
                ? controller.refreshDevices
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh devices'),
          ),
          const SizedBox(height: 12),
          if (controller.devices.isEmpty)
            const EmptyPanel(
              icon: Icons.devices_other_outlined,
              title: 'No devices loaded',
              text: 'Paired devices appear after bridge authentication.',
            )
          else
            ...controller.devices.map(
              (device) => DeviceTile(
                device: device,
                current: device.id == controller.deviceId.value,
                onRevoke: () => controller.revokeDevice(device.id),
              ),
            ),
        ],
      ),
    );
  }
}

class PairingScannerPage extends StatefulWidget {
  const PairingScannerPage({super.key});

  @override
  State<PairingScannerPage> createState() => _PairingScannerPageState();
}

class _PairingScannerPageState extends State<PairingScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing code')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final raw = capture.barcodes
              .map((barcode) => barcode.rawValue)
              .whereType<String>()
              .firstOrNull;
          if (raw == null) return;
          final info = PairingInfo.tryParse(raw);
          if (info == null) return;
          _handled = true;
          Navigator.of(context).pop(info);
        },
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xff667066)),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.active, super.key});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xff2f7553) : const Color(0xff8f5a38);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    required this.message,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xffffeadf),
        border: Border.all(color: const Color(0xffefb18d)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xff9a4e26)),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class InfoStrip extends StatelessWidget {
  const InfoStrip({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff3f6f5a)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff667066),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfffffcf6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffd8d2c4)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class PanelTitle extends StatelessWidget {
  const PanelTitle({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: Color(0xff667066),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    required this.icon,
    required this.title,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xff7d897b), size: 28),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(color: Color(0xff667066))),
        ],
      ),
    );
  }
}

class WorkspaceTile extends StatelessWidget {
  const WorkspaceTile({
    required this.workspace,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final WorkspaceInfo workspace;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xffe4efdf) : const Color(0xfffffcf6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? const Color(0xff86a678) : const Color(0xffd8d2c4),
          ),
        ),
        child: ListTile(
          onTap: onTap,
          leading: Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: const Color(0xff3f6f5a),
          ),
          title: Text(workspace.name),
          subtitle: Text(
            workspace.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class EventLine extends StatelessWidget {
  const EventLine({required this.event, super.key});

  final SessionEvent event;

  @override
  Widget build(BuildContext context) {
    final isError = event.kind == 'error';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError ? const Color(0xffffeadf) : const Color(0xfff4f1ea),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.kind,
                style: TextStyle(
                  color: isError
                      ? const Color(0xff9a4e26)
                      : const Color(0xff3f6f5a),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                event.text.isEmpty ? '(empty)' : event.text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({required this.session, super.key});

  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, color: Color(0xff667066)),
      title: Text(session.prompt, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${session.workspace} - ${session.status}'),
    );
  }
}

class GitSnapshotPanel extends StatelessWidget {
  const GitSnapshotPanel({required this.snapshot, super.key});

  final GitSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(
            title: snapshot.branch.isEmpty ? 'Working tree' : snapshot.branch,
            trailing: snapshot.stat.isEmpty ? null : 'stat',
          ),
          const SizedBox(height: 10),
          CodeBlock(text: snapshot.status, emptyText: 'Clean status output.'),
          if (snapshot.stat.isNotEmpty) ...[
            const SizedBox(height: 10),
            CodeBlock(text: snapshot.stat, emptyText: ''),
          ],
          if (snapshot.diff.isNotEmpty) ...[
            const SizedBox(height: 10),
            CodeBlock(text: snapshot.diff, emptyText: ''),
          ],
          if (snapshot.log.isNotEmpty) ...[
            const SizedBox(height: 10),
            CodeBlock(text: snapshot.log, emptyText: ''),
          ],
        ],
      ),
    );
  }
}

class CodeBlock extends StatelessWidget {
  const CodeBlock({required this.text, required this.emptyText, super.key});

  final String text;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff252a24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SelectableText(
            text.trim().isEmpty ? emptyText : text.trim(),
            style: const TextStyle(
              color: Color(0xffedf1e8),
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    required this.device,
    required this.current,
    required this.onRevoke,
    super.key,
  });

  final DeviceInfo device;
  final bool current;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Row(
          children: [
            Icon(
              current ? Icons.phone_iphone : Icons.devices_other,
              color: const Color(0xff3f6f5a),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    current ? 'This device' : device.lastSeen,
                    style: const TextStyle(
                      color: Color(0xff667066),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: current ? 'Revoke this device' : 'Revoke device',
              onPressed: onRevoke,
              icon: const Icon(Icons.link_off),
            ),
          ],
        ),
      ),
    );
  }
}
