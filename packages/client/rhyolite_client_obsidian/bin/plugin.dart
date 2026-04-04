// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:js_util' as jsu;

import 'package:obsidian_dart/obsidian_dart.dart';
import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:rhyolite_client_obsidian/rhyolite_client_obsidian.dart';
import 'package:rhyolite_client_obsidian/src/engine/build_env.dart';
import 'package:rhyolite_client_obsidian/src/engine/db_recovery.dart';
import 'package:rhyolite_client_obsidian/src/engine/sign_in_modal.dart';
import 'package:rhyolite_client_obsidian/src/engine/vault_picker_modal.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_blob_sqlite/rpc_blob_sqlite.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_compression/rpc_dart_compression.dart';
import 'package:rpc_dart_http/rpc_dart_http.dart';
import 'package:rpc_data_sqlite/rpc_data_sqlite.dart';

final _log = RpcLogger('rhyolite');

SyncEngine? _engine;
DatabaseConnection? _dbConn;

/// Returns true if [error] indicates a corrupted or incompatible SQLite database.
bool _isSqliteCorrupt(Object error) {
  final msg = error.toString();
  // SqliteException(11) — SQLITE_CORRUPT
  if (msg.contains('SqliteException(11)') ||
      (msg.contains('SqliteException') && msg.contains('malformed'))) {
    return true;
  }
  // IndexedDB VFS failures — stale or incompatible DB layout:
  // 1. Chunk shorter than expected → negative typed array length.
  if (msg.contains('Invalid typed array length') && msg.contains('-')) {
    return true;
  }
  // 2. IDB cursor key is null when a number is expected (missing chunk).
  if (msg.contains('JSNull') && msg.contains('double')) {
    return true;
  }
  return false;
}

void main() {
  RpcGzipCodec.register();
  if (!kDebug) RpcLogger.disableLogger();
  bootstrapPlugin(
    extraCss: '''
      .rhyolite-setting-desc { color: var(--text-muted); font-size: 0.85em; }
      .rhyolite-vault-label { font-weight: 500; }
    ''',
    onLoad: (plugin) async {
      String dbFileName = '';
      String dbName = '';
      bool handlingCorruption = false;

      void onCorruptDb() {
        if (handlingCorruption) return;
        handlingCorruption = true;
        () async {
          try {
            await _engine?.stop();
            await _dbConn?.close();
            _engine = null;
            _dbConn = null;
          } catch (_) {}
          await showDbCorruptionModal(
            plugin,
            dbFileName: dbFileName,
            dbName: dbName,
          );
          handlingCorruption = false;
        }();
      }

      await runZonedGuarded(
        () async {
          final configStorage = ObsidianConfigStorage(plugin);

          // -----------------------------------------------------------------------
          // Auth — account service URL comes from compile-time dart-define only.
          // -----------------------------------------------------------------------
          final authConfig = AuthConfig(
            accountServiceUrl: kEnv.accountServiceUrl,
          );

          final accountTransport = RpcHttpCallerTransport(
            baseUrl: authConfig.accountServiceUrl,
          );
          final accountEndpoint = RpcCallerEndpoint(
            transport: accountTransport,
          );
          final accountClient = RpcAccountClient(accountEndpoint);

          RpcAccountClient? authClient;

          if (authConfig.isConfigured) {
            final savedSession = await configStorage.loadAuthSession();
            if (savedSession != null) {
              if (!savedSession.isExpired) {
                accountClient.useSession(savedSession);
                authClient = accountClient;
              } else {
                // Token expired — try to refresh.
                try {
                  accountClient.useSession(savedSession);
                  await accountClient.refreshSession();
                  final newSession = accountClient.session;
                  if (newSession != null) {
                    await configStorage.saveAuthSession(newSession);
                  }
                  authClient = accountClient;
                } catch (e) {
                  final msg = e.toString();
                  if (msg.contains('(400)') || msg.contains('(401)')) {
                    await configStorage.clearAuthSession();
                  } else {
                    accountClient.useSession(savedSession);
                    authClient = accountClient;
                  }
                }
              }
            }
          }

          // -----------------------------------------------------------------------
          // Vault
          // -----------------------------------------------------------------------
          var config = await configStorage.tryLoad();
          VaultCipher? cipher;

          if (authClient != null) {
            if (config == null) {
              final result = await showVaultPickerModal(
                plugin,
                authClient,
                configStorage,
              );
              if (result != null) {
                config = result.$1;
                cipher = result.$2;
              }
            } else if (!config.e2eeEnabled ||
                (config.verificationToken == null ||
                    config.verificationToken!.isEmpty)) {
              final result = await showVaultPickerModal(
                plugin,
                authClient,
                configStorage,
              );
              if (result != null) {
                config = result.$1;
                cipher = result.$2;
              }
            } else {
              cipher =
                  await configStorage.tryUnlockFromStorage() ??
                  await showPassphraseModal(
                    plugin,
                    configStorage,
                    vaultId: config.vaultId,
                    verificationToken: config.verificationToken!,
                  );
            }
          }

          final cfg = config ?? const VaultConfig(vaultId: '', vaultName: '');

          VaultConfig buildConfig(VaultConfig base, RpcAccountClient? client) {
            if (client == null) return base;
            return base.copyWith(
              tokenProvider: RpcAccountClientTokenProvider(client),
            );
          }

          final activeConfig = buildConfig(cfg, authClient);

          final pluginDir =
              plugin.manifestDir ?? '.obsidian/plugins/rhyolite-sync';
          final wasmUri = Uri.parse(
            plugin.app.vault.adapter.getResourcePath(
              '$pluginDir/sqlite3mc.wasm',
            ),
          );

          final vaultId = cfg.vaultId;
          final raw = await plugin.loadData();
          final dbSuffix =
              (raw as Map<Object?, Object?>?)?['dbSuffix'] as String? ?? '';
          final suffix = dbSuffix.isNotEmpty ? '-$dbSuffix' : '';
          dbFileName = '$vaultId$suffix.db';
          dbName = 'rhyolite-$vaultId$suffix';

          final dbConn = await openFileDb(
            options: SqliteConnectionOptions(
              webDatabaseName: dbName,
              webFileName: dbFileName,
              webSqliteWasmUri: wasmUri,
            ),
          );
          _dbConn = dbConn;

          final nodeStore = LocalNodeStore(
            SqliteDataRepository(
              storage: SqliteDataStorageAdapter.connection(dbConn),
            ),
          );
          final blobRepo = SqliteBlobRepository.db(
            dbConn.database,
            enableWal: false,
          );

          final engine = SyncEngine(
            vaultPath: '',
            serverUrl: kEnv.syncServiceUrl,
            config: activeConfig,
            cipher: cipher,
            nodeStore: nodeStore,
            blobStore: LocalBlobStore(blobRepo),
            io: ObsidianIO(plugin.app.vault),
            changeProvider: ObsidianChangeProvider(plugin),
          );
          _engine = engine;

          _registerSettings(
            plugin: plugin,
            configStorage: configStorage,
            config: cfg,
            authConfig: authConfig,
            authClient: authClient,
            accountClient: accountClient,
            engine: engine,
            buildConfig: buildConfig,
          );

          plugin.addCommand(
            id: 'rhyolite-sync-start',
            name: 'Start Sync',
            callback: () async {
              if (cipher == null) {
                final verificationToken = config?.verificationToken;
                if (verificationToken != null && verificationToken.isNotEmpty) {
                  cipher = await showPassphraseModal(
                    plugin,
                    configStorage,
                    vaultId: cfg.vaultId,
                    verificationToken: verificationToken,
                  );
                }
                if (cipher == null) return;
                engine.cipher = cipher;
              }
              await engine.start();
            },
          );
          plugin.addCommand(
            id: 'rhyolite-sync-stop',
            name: 'Stop Sync',
            callback: engine.stop,
          );
          plugin.addCommand(
            id: 'rhyolite-graph-viz',
            name: 'Show Graph',
            callback: () async {
              final html = GraphHtmlGenerator().generate(engine.graph);
              const htmlPath = '.obsidian/plugins/rhyolite-sync/graph.html';
              final exists = await plugin.app.vault.adapter.exists(htmlPath);
              if (exists) {
                await plugin.app.vault.adapter.write(htmlPath, html);
              } else {
                await plugin.app.vault.create(htmlPath, html);
              }
              final file = plugin.app.vault.getFileByPath(htmlPath);
              if (file != null) {
                final url = plugin.app.vault.getResourcePath(file);
                jsu.callMethod<void>(jsu.globalThis, 'open', [url]);
              }
            },
          );

          if (cipher == null) {
            _log.info('No vault key — sync disabled. Sign in and connect a vault.');
          } else if (kEnv.syncServiceUrl.isEmpty) {
            _log.info('Server URL not set — sync disabled.');
          } else {
            await engine.start();
          }

          // Listen for session expiry and prompt re-authentication.
          engine.events.listen((event) async {
            if (event is SyncSubscriptionExpired) {
              showNotice(
                '⚠️ Rhyolite Sync: subscription expired. '
                'Open plugin settings to renew.',
              );
              return;
            }

            if (event is! SyncSessionExpired) return;
            _log.warning('Auth rejected — attempting token refresh');

            final client = authClient;
            if (client != null) {
              try {
                final session = await client.refreshSession();
                await configStorage.saveAuthSession(session);
                engine.config = buildConfig(cfg, client);
                await engine.start();
                _log.info('Token refreshed — restarted');
                return;
              } catch (_) {
                _log.warning('Refresh failed — prompting re-authentication');
              }
            }

            await configStorage.clearAuthSession();
            authClient = null;
            engine.config = cfg;

            if (!authConfig.isConfigured) return;
            final newClient = await showSignInModal(
              plugin,
              client: accountClient,
            );
            if (newClient == null) return;
            final newSession = newClient.session;
            if (newSession != null) {
              await configStorage.saveAuthSession(newSession);
            }
            authClient = newClient;
            engine.config = buildConfig(cfg, newClient);
            await engine.start();
          });
        },
        (error, stack) {
          if (_isSqliteCorrupt(error)) {
            onCorruptDb();
          } else {
            _log.error('Unhandled error', error: error, stackTrace: stack);
          }
        },
      );
    },
    onUnload: (_) async {
      await _engine?.stop();
      _engine = null;
      await _dbConn?.close();
      _dbConn = null;
    },
  );
}

void _registerSettings({
  required PluginHandle plugin,
  required ObsidianConfigStorage configStorage,
  required VaultConfig config,
  required AuthConfig authConfig,
  required RpcAccountClient? authClient,
  required RpcAccountClient accountClient,
  required SyncEngine engine,
  required VaultConfig Function(VaultConfig, RpcAccountClient?) buildConfig,
}) {
  late final void Function() refreshSettings;
  refreshSettings = registerSettingsTab(
    plugin: plugin,
    configStorage: configStorage,
    config: config,
    authConfig: authConfig,
    authClient: authClient,
    accountClient: accountClient,
    openUrl: (url) => jsu.callMethod<void>(jsu.globalThis, 'open', [url]),
    onConfigChanged: (updated) async {
      engine.config = buildConfig(updated, authClient);
      await engine.stop();
      await engine.start();
    },
    onAuthChanged: (newAuthConfig, client) async {
      authClient = client;
      engine.config = buildConfig(config, client);
      _log.info('Signed in');
    },
    onSignOut: () async {
      authClient = null;
      engine.config = config;
      await engine.stop();
      _log.info('Signed out');
    },
    onDisconnectVault: () async {
      engine.cipher = null;
      await engine.stop();
      _log.info('Vault disconnected');
    },
    onVaultChanged: (newConfig, newCipher) async {
      engine.config = buildConfig(newConfig, authClient);
      engine.cipher = newCipher;
      await engine.stop();
      await engine.start();
      _log.info('Switched to vault ${newConfig.vaultId}');
    },
    onSubscribed: () => _waitForSubscriptionAndStart(
      plugin: plugin,
      engine: engine,
      accountClient: accountClient,
      onDone: refreshSettings,
    ),
    onResetVault: () async {
      await engine.triggerReset();
      _log.info('Vault reset initiated');
    },
  );
}

/// Polls the account service's getSubscription endpoint every 10 seconds for up to 5 minutes.
/// Shows a modal with a spinner while waiting. Starts the engine on success.
Future<void> _waitForSubscriptionAndStart({
  required PluginHandle plugin,
  required SyncEngine engine,
  required RpcAccountClient accountClient,
  void Function()? onDone,
}) async {
  const interval = Duration(seconds: 10);
  const timeout = Duration(minutes: 5);
  final deadline = DateTime.now().add(timeout);

  _log.info('Waiting for subscription activation...');

  ModalContext<void>? modalCtx;
  SpinnerRef? spinnerRef;

  // Open a modal with a spinner — the polling runs in the background.
  // We capture ctx/spinner via the build closure and close/update from below.
  unawaited(
    showModalWith<void>(
      plugin,
      build: (ctx) {
        modalCtx = ctx;
        ctx.h3('Activating subscription…');
        ctx.spaceVertical(px: 12);
        ctx.createEl('p', text: 'Please wait while we confirm your payment.');
        ctx.spaceVertical(px: 12);
        spinnerRef = ctx.spinner(label: 'Checking…');
        spinnerRef!.show();
        ctx.spaceVertical(px: 4);
        ctx.onEscape(() {}); // disable accidental close
      },
    ),
  );

  // Give the modal a moment to render before polling starts.
  await Future<void>.delayed(const Duration(milliseconds: 300));

  bool confirmed = false;

  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);

    try {
      final subscription = await accountClient.getSubscription();
      if (subscription.isActive) {
        confirmed = true;
        break;
      }
      _log.debug('Subscription not yet active, retrying...');
    } catch (e) {
      _log.error('checkAccess error', error: e);
    }
  }

  final ctx = modalCtx;
  if (ctx == null) return;

  if (confirmed) {
    _log.info('Subscription confirmed — starting engine');
    spinnerRef?.hide();
    // Replace modal content with success message.
    ctx.close(null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await showModalWith<void>(
      plugin,
      build: (ctx2) {
        ctx2.h3('🎉 Subscription activated!');
        ctx2.spaceVertical(px: 12);
        ctx2.createEl(
          'p',
          text: 'Your subscription is now active. Sync will start shortly.',
        );
        ctx2.spaceVertical(px: 16);
        ctx2.buttonRow([
          ButtonSpec(
            'Got it',
            () => ctx2.close(null),
            variant: ButtonVariant.primary,
          ),
        ]);
        ctx2.onEscape(() => ctx2.close(null));
      },
    );
    onDone?.call();
    await engine.start();
  } else {
    _log.warning('Subscription not activated within 5 minutes');
    spinnerRef?.hide();
    ctx.close(null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await showModalWith<void>(
      plugin,
      build: (ctx2) {
        ctx2.h3('Payment not confirmed');
        ctx2.spaceVertical(px: 12);
        ctx2.createEl(
          'p',
          text:
              'We could not confirm your payment within 5 minutes. '
              'If you completed the payment, please restart Obsidian. '
              'If the issue persists, contact support.',
        );
        ctx2.spaceVertical(px: 16);
        ctx2.buttonRow([ButtonSpec('Close', () => ctx2.close(null))]);
        ctx2.onEscape(() => ctx2.close(null));
      },
    );
    onDone?.call();
  }
}
