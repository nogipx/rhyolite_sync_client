import 'package:obsidian_dart/obsidian_dart.dart';
import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:rhyolite_client_core/rhyolite_client_core.dart';
import 'package:rhyolite_client_obsidian/src/engine/vault_picker_modal.dart';

import 'obsidian_config_storage.dart';
import 'payment_modal.dart';
import 'sign_in_modal.dart';
import 'sign_up_modal.dart';

/// Registers the settings tab. The tab rebuilds its UI on every open so that
/// auth and vault state are always up to date.
///
/// Returns a [refresh] function — call it to immediately re-render the tab
/// (e.g. right after sign-in/sign-out without waiting for the user to reopen).
void Function() registerSettingsTab({
  required PluginHandle plugin,
  required ObsidianConfigStorage configStorage,
  required VaultConfig config,
  required AuthConfig authConfig,
  required RpcAccountClient? authClient,
  required RpcAccountClient accountClient,
  required void Function(String url) openUrl,
  required void Function(VaultConfig updated) onConfigChanged,
  required void Function(AuthConfig updated, RpcAccountClient client)
  onAuthChanged,
  required void Function() onSignOut,
  required void Function() onDisconnectVault,
  required void Function(VaultConfig config, VaultCipher cipher) onVaultChanged,
  required void Function() onSubscribed,
  required Future<void> Function() onResetVault,
  required Future<void> Function() onRepairVault,
}) {
  // Mutable state captured by the builder closure — updated via callbacks.
  var currentConfig = config;
  var currentAuthConfig = authConfig;
  var currentAuthClient = authClient;
  DateTime? subscriptionEnd; // cached per tab open, refreshed on display

  late PluginSettingsTab tab;

  void build(PluginSettingsTab t) {
    VaultConfig patchVault({ConflictStrategy? conflictStrategy}) => VaultConfig(
      vaultId: currentConfig.vaultId,
      vaultName: currentConfig.vaultName,
      conflictStrategy: conflictStrategy ?? currentConfig.conflictStrategy,
    );

    void addConflictStrategyDropdown(PluginSettingsTab t) => t.addDropdown(
      name: 'Conflict strategy',
      description:
          'How to resolve edits made to the same file on multiple devices.',
      options: {
        ConflictStrategy.lww.name: 'Last Write Wins',
        ConflictStrategy.conflictCopy.name: 'Conflict Copy',
      },
      initialValue: currentConfig.conflictStrategy.name,
      onChange: (value) async {
        final cfg = patchVault(
          conflictStrategy: ConflictStrategy.values.byName(value),
        );
        currentConfig = cfg;
        await configStorage.save(cfg);
        onConfigChanged(cfg);
      },
    );

    void addSignOutButton(PluginSettingsTab t, String userEmail) => t.addButton(
      name: 'Auth status',
      description: 'Signed in as $userEmail. Click to sign out.',
      buttonText: 'Sign Out',
      onClick: () async {
        await currentAuthClient?.signOut();
        await configStorage.clearAuthSession();
        await configStorage.disconnectVault();
        currentAuthClient = null;
        currentConfig = const VaultConfig(vaultId: '', vaultName: '');
        onSignOut();
        tab.show();
      },
    );

    void addDisconnectVaultButton(PluginSettingsTab t) => t.addButton(
      name: 'Disconnect vault',
      description:
          'Stop sync and forget this vault on this device. '
          'Vault data on the server is not affected.',
      buttonText: 'Disconnect',
      onClick: () async {
        final vaultName = currentConfig.vaultName.isNotEmpty
            ? currentConfig.vaultName
            : currentConfig.vaultId;
        final confirmed = await _showDisconnectConfirmation(
          plugin,
          vaultName: vaultName,
        );
        if (!confirmed) return;
        await configStorage.disconnectVault();
        currentConfig = const VaultConfig(vaultId: '', vaultName: '');
        onDisconnectVault();
        tab.show();
      },
    );

    void addResetVaultButton(PluginSettingsTab t) => t.addButton(
      name: 'Reset vault history',
      description:
          'Wipe all sync history from the server and re-upload from disk. '
          'All connected clients will also reset. '
          'Your files are not deleted. '
          'Use this only when you want a full server-side reset.',
      buttonText: 'Reset History',
      onClick: () async {
        final vaultName = currentConfig.vaultName.isNotEmpty
            ? currentConfig.vaultName
            : currentConfig.vaultId;
        final confirmed = await _showResetConfirmation(
          plugin,
          vaultName: vaultName,
        );
        if (!confirmed) return;
        await onResetVault();
      },
    );

    void addRepairVaultButton(PluginSettingsTab t) => t.addButton(
      name: 'Repair vault',
      description:
          'Prune non-canonical branches, run GC, and push the canonical '
          'state back to the server. '
          'This keeps the server history and only normalizes the active graph.',
      buttonText: 'Repair Vault',
      onClick: () async {
        final vaultName = currentConfig.vaultName.isNotEmpty
            ? currentConfig.vaultName
            : currentConfig.vaultId;
        final confirmed = await _showRepairConfirmation(
          plugin,
          vaultName: vaultName,
        );
        if (!confirmed) return;
        await onRepairVault();
      },
    );

    void addConnectVaultButton(PluginSettingsTab t) => t.addButton(
      name: 'Vault',
      description: 'Connect to an existing vault or create a new one.',
      buttonText: 'Connect Vault',
      onClick: () async {
        final client = currentAuthClient;
        if (client == null || !client.isSignedIn) return;

        if (currentConfig.vaultId.isNotEmpty) return;

        final result = await showVaultPickerModal(
          plugin,
          client,
          configStorage,
        );
        if (result != null) {
          currentConfig = result.$1;
          onVaultChanged(result.$1, result.$2);
          tab.show();
        }
      },
    );

    void addSignInButton(PluginSettingsTab t) => t.addButton(
      name: 'Sign in',
      description: 'Sign in to Supabase to enable authenticated sync.',
      buttonText: 'Sign In',
      primary: true,
      onClick: () async {
        if (!currentAuthConfig.isConfigured) return;
        final client = await showSignInModal(plugin, client: accountClient);
        if (client == null) return;
        final session = client.session;
        if (session != null) {
          await configStorage.saveAuthSession(session);
        }
        currentAuthClient = client;
        onAuthChanged(currentAuthConfig, client);
        tab.show();
      },
    );

    void addSignUpButton(PluginSettingsTab t) => t.addButton(
      name: 'Create account',
      description: 'New to Rhyolite Sync? Create a free account.',
      buttonText: 'Create Account',
      onClick: () async {
        if (!currentAuthConfig.isConfigured) return;
        final result = await showSignUpModal(plugin, client: accountClient);
        if (result == null) return;
        if (result.emailConfirmationRequired) {
          await showModalWith<void>(
            plugin,
            build: (ctx) {
              ctx.h3('Check your email');
              ctx.spaceVertical(px: 12);
              ctx.createEl(
                'p',
                text:
                    'A confirmation link has been sent to your email address. '
                    'Please confirm it and then sign in.',
              );
              ctx.spaceVertical(px: 16);
              ctx.buttonRow([ButtonSpec('OK', () => ctx.close(null))]);
            },
          );
          return;
        }
        final client = result.client!;
        final session = client.session;
        if (session != null) {
          await configStorage.saveAuthSession(session);
        }
        currentAuthClient = client;
        onAuthChanged(currentAuthConfig, client);
        tab.show();
      },
    );

    void addSubscriptionSection(PluginSettingsTab t, DateTime? periodEnd) {
      t.addSection('Subscription');
      if (periodEnd != null) {
        final day = periodEnd.day.toString().padLeft(2, '0');
        final month = periodEnd.month.toString().padLeft(2, '0');
        final year = periodEnd.year;
        t.addCustom((s) {
          s.setName('Active until $day.$month.$year');
          s.setDesc('Your subscription is active.');
        });
      } else {
        t.addButton(
          name: 'Subscribe',
          description: 'Sync across all your devices.',
          buttonText: 'Subscribe',
          onClick: () async {
            final client = currentAuthClient;
            if (client == null) return;
            final paid = await showPaymentModal(
              plugin,
              authClient: client,
              openUrl: openUrl,
            );
            if (paid) {
              onSubscribed();
            }
          },
        );
        t.addButton(
          name: 'Already paid?',
          description: 'Check if your payment went through.',
          buttonText: 'Restore subscription',
          onClick: () async {
            final client = currentAuthClient;
            if (client == null) return;
            await _showRestoreSubscriptionModal(
              plugin,
              onRestore: () async {
                final restored = await client.restoreSubscription();
                return restored;
              },
              onSubscribed: () {
                onSubscribed();
                tab.show();
              },
            );
          },
        );
      }
    }

    final isSignedIn = currentAuthClient?.isSignedIn ?? false;
    final userEmail = currentAuthClient?.email ?? '';

    t.addSection('Authentication');
    if (isSignedIn) {
      addSignOutButton(t, userEmail);
      if (currentConfig.vaultId.isNotEmpty) {
        addDisconnectVaultButton(t);
        addResetVaultButton(t);
        addRepairVaultButton(t);
      } else {
        addConnectVaultButton(t);
      }
      addSubscriptionSection(t, subscriptionEnd);
    } else {
      addSignInButton(t);
      addSignUpButton(t);
    }

    t.addSection('Connection');
    addConflictStrategyDropdown(t);
  }

  Future<void> buildAsync(PluginSettingsTab t) async {
    final client = currentAuthClient;
    final DateTime? fetched;
    if (client != null && client.isSignedIn) {
      fetched = await checkSubscription(client);
    } else {
      fetched = null;
    }
    if (fetched != subscriptionEnd) {
      subscriptionEnd = fetched;
      tab.show();
    }
  }

  tab = PluginSettingsTab(
    plugin,
    name: 'Rhyolite Sync',
    onDisplay: build,
    onDisplayAsync: buildAsync,
  );
  build(tab); // initial sync build
  plugin.addSettingTab(tab.handle.raw);

  return tab.show; // caller can trigger a refresh
}

/// Asks the user to confirm resetting the vault.
Future<bool> _showResetConfirmation(
  PluginHandle plugin, {
  required String vaultName,
}) async {
  final confirmed = await showModalWith<bool>(
    plugin,
    build: (ctx) {
      ctx.h3('Reset Vault History?');
      ctx.spaceVertical(px: 12);
      ctx.createEl('p', text: 'Reset sync history for "$vaultName"?');
      ctx.spaceVertical(px: 8);
      ctx.createEl(
        'p',
        cls: 'rhyolite-setting-desc',
        text:
          'All sync records will be wiped from the server. '
          'Every connected client will re-upload from their disk. '
          'Your files are not deleted.',
      );
      ctx.spaceVertical(px: 16);
      ctx.buttonRow([
        ButtonSpec(
          'Reset History',
          () => ctx.close(true),
          variant: ButtonVariant.destructive,
        ),
        ButtonSpec('Cancel', () => ctx.close(false)),
      ]);
      ctx.onEscape(() => ctx.close(false));
    },
  );
  return confirmed ?? false;
}

/// Asks the user to confirm repairing the vault history.
Future<bool> _showRepairConfirmation(
  PluginHandle plugin, {
  required String vaultName,
}) async {
  final confirmed = await showModalWith<bool>(
    plugin,
    build: (ctx) {
      ctx.h3('Repair Vault?');
      ctx.spaceVertical(px: 12);
      ctx.createEl('p', text: 'Repair sync history for "$vaultName"?');
      ctx.spaceVertical(px: 8);
      ctx.createEl(
        'p',
        cls: 'rhyolite-setting-desc',
        text:
            'This will prune non-canonical branches, run GC, and push the '
            'canonical graph state back to the server. '
            'The server history is not wiped outright, but older branches may '
            'be detached from the active graph.',
      );
      ctx.spaceVertical(px: 16);
      ctx.buttonRow([
        ButtonSpec(
          'Repair',
          () => ctx.close(true),
          variant: ButtonVariant.primary,
        ),
        ButtonSpec('Cancel', () => ctx.close(false)),
      ]);
      ctx.onEscape(() => ctx.close(false));
    },
  );
  return confirmed ?? false;
}

/// Asks the user to confirm disconnecting from the current vault.
Future<bool> _showDisconnectConfirmation(
  PluginHandle plugin, {
  required String vaultName,
}) async {
  final confirmed = await showModalWith<bool>(
    plugin,
    build: (ctx) {
      ctx.h3('Disconnect Vault?');
      ctx.spaceVertical(px: 12);
      ctx.createEl('p', text: 'Disconnect from "$vaultName" on this device?');
      ctx.spaceVertical(px: 8);
      ctx.createEl(
        'p',
        cls: 'rhyolite-setting-desc',
        text:
            'Sync will stop. The vault config and remembered passphrase '
            'will be removed from this device. '
            'Your data on the server and files on disk are not affected.',
      );
      ctx.spaceVertical(px: 16);
      ctx.buttonRow([
        ButtonSpec(
          'Disconnect',
          () => ctx.close(true),
          variant: ButtonVariant.destructive,
        ),
        ButtonSpec('Cancel', () => ctx.close(false)),
      ]);
      ctx.onEscape(() => ctx.close(false));
    },
  );
  return confirmed ?? false;
}

/// Shows a modal that immediately starts checking for a restored subscription.
/// Displays a spinner while checking, then shows the result with an OK button.
Future<void> _showRestoreSubscriptionModal(
  PluginHandle plugin, {
  required Future<bool> Function() onRestore,
  required void Function() onSubscribed,
}) async {
  await showModalWith<void>(
    plugin,
    build: (ctx) {
      final title = ctx.h3('Checking subscription...');
      ctx.spaceVertical(px: 12);
      final spin = ctx.spinner(label: 'Contacting server');
      spin.show();
      ctx.spaceVertical(px: 4);
      final message = ctx.createEl('p', cls: 'rhyolite-setting-desc');
      ctx.spaceVertical(px: 16);
      final buttons = ctx.buttonRow([ButtonSpec('OK', () => ctx.close(null))]);
      buttons.first.setDisabled(value: true);

      Future(() async {
        bool restored;
        try {
          restored = await onRestore();
        } catch (_) {
          restored = false;
        }
        spin.hide();
        if (restored) {
          setText(title, 'Subscription activated!');
          setText(message, 'Your subscription has been successfully restored.');
          onSubscribed();
        } else {
          setText(title, 'No subscription found');
          setText(
            message,
            'No completed payment was found for your account. '
            'If you just paid, please wait a moment and try again.',
          );
        }
        buttons.first.setDisabled(value: false);
      });
    },
  );
}
