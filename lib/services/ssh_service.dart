import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

class SshService {
  late SSHClient? _client;
  String _log = '';
  bool _isConnected = false;

  Future<bool> connect({
    required String host,
    required String username,
    required String passwordOrKey,
    int port = 22,
    bool isKeyAuth = false,
  }) async {
    try {
      _log += '⚡ Connexion à $username@$host:$port...\n';
      _isConnected = false;
      
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        passwordOrKey: isKeyAuth ? null : passwordOrKey,
        privateKey: isKeyAuth ? passwordOrKey : null,
      );

      // Test la connexion
      await _client?.execute('pwd');
      
      _log += '✅ Connecté avec succès!\n';
      _isConnected = true;
      return true;
    } catch (e) {
      _log += '❌ Erreur de connexion: ${e.toString()}\n';
      _client?.close();
      _client = null;
      return false;
    }
  }

  Future<void> syncFolder({
    required String localPath,
    required String remotePath,
  }) async {
    if (_client == null || !_isConnected) {
      throw Exception('Non connecté au serveur SSH');
    }

    final sftp = await _client!.sftp();
    _log += '\n🔄 Synchronisation: $localPath → $remotePath\n';
    await _uploadDirectory(sftp, localPath, remotePath);
  }

  Future<void> _uploadDirectory(SFTPClient sftp, String localPath, String remotePath) async {
    try {
      final dir = Directory(localPath);
      final files = await dir.list(recursive: true).toList();

      for (final file in files.whereType<File>()) {
        final relativePath = p.relative(file.path, from: localPath);
        final remoteFilePath = p.join(remotePath, relativePath).replaceAll(r'\', '/');

        try {
          // Crée le dossier distant si nécessaire
          final remoteDir = p.dirname(remoteFilePath);
          await sftp.mkdir(remoteDir, recursive: true);

          // Compare les dates de modification
          final localStat = await file.stat();
          final remoteStat = await sftp.stat(remoteFilePath).catchError((_) => null);

          if (remoteStat == null || 
              localStat.modified.isAfter(DateTime.parse(remoteStat.modified))) {
            _log += '⬆️ Transfert: $relativePath\n';
            await sftp.writeFile(remoteFilePath, file.openRead(), localStat.size);
          } else {
            _log += '≡ Déjà à jour: $relativePath\n';
          }
        } catch (e) {
          _log += '⚠️ Erreur sur $relativePath: ${e.toString()}\n';
        }
      }
    } catch (e) {
      _log += '❌ Erreur majeure: ${e.toString()}\n';
      rethrow;
    }
  }

  String get logs => _log;
  bool get isConnected => _isConnected;

  void dispose() {
    _client?.close();
    _client = null;
    _isConnected = false;
    _log = '';
  }
}