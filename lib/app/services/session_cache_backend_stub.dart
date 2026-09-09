import 'session_cache_backend_api.dart';

/// Fallback for Web and unsupported targets. The controller still benefits
/// from debounced, incremental cache writes during the current process; a
/// platform adapter can later replace this with IndexedDB without changing
/// the controller contract.
SessionCacheBackend createSessionCacheBackend() => MemorySessionCacheBackend();
