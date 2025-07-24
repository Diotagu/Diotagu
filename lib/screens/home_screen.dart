import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ssh_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SshService _sshService = SshService();
  final _formKey = GlobalKey<FormState>();
  final _logController = ScrollController();
  
  String _host = '192.168.1.1';
  String _username = 'user';
  String _password = '';
  int _port = 22;
  bool _isKeyAuth = false;
  bool _isSyncing = false;
  bool _autoSync = false;
  
  List<String> _selectedFolders = [];
  final Map<String, String> _remotePaths = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _host = prefs.getString('host') ?? _host;
      _username = prefs.getString('username') ?? _username;
      _port = prefs.getInt('port') ?? _port;
      _isKeyAuth = prefs.getBool('isKeyAuth') ?? _isKeyAuth;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', _host);
    await prefs.setString('username', _username);
    await prefs.setInt('port', _port);
    await prefs.setBool('isKeyAuth', _isKeyAuth);
  }

  Future<void> _pickFolder() async {
    final String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null && !_selectedFolders.contains(path)) {
      setState(() {
        _selectedFolders.add(path);
        _remotePaths[path] = '/home/${_username}/sync/${path.split('/').last}';
      });
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    await _saveSettings();
    
    setState(() => _isSyncing = true);
    await _sshService.connect(
      host: _host,
      username: _username,
      passwordOrKey: _password,
      port: _port,
      isKeyAuth: _isKeyAuth,
    );
    setState(() => _isSyncing = false);
  }

  Future<void> _syncAll() async {
    if (!_formKey.currentState!.validate() || !_sshService.isConnected) return;
    
    setState(() => _isSyncing = true);
    try {
      for (final folder in _selectedFolders) {
        await _sshService.syncFolder(
          localPath: folder,
          remotePath: _remotePaths[folder]!,
        );
        setState(() {});
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Widget _buildConnectionForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Adresse IP du PC'),
                initialValue: _host,
                validator: (v) => v!.isEmpty ? 'Requis' : null,
                onChanged: (v) => _host = v.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Utilisateur SSH'),
                initialValue: _username,
                validator: (v) => v!.isEmpty ? 'Requis' : null,
                onChanged: (v) => _username = v.trim(),
              ),
              TextFormField(
                decoration: InputDecoration(
                  labelText: _isKeyAuth ? 'Clé privée' : 'Mot de passe',
                ),
                obscureText: !_isKeyAuth,
                validator: (v) => v!.isEmpty ? 'Requis' : null,
                onChanged: (v) => _password = v,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Port SSH'),
                      initialValue: _port.toString(),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Requis' : null,
                      onChanged: (v) => _port = int.tryParse(v) ?? 22,
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Clé SSH'),
                    value: _isKeyAuth,
                    onChanged: (v) => setState(() => _isKeyAuth = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _testConnection,
                    child: const Text('Tester la connexion'),
                  ),
                  const SizedBox(width: 10),
                  SwitchListTile(
                    title: const Text('Sync Auto'),
                    value: _autoSync,
                    onChanged: (v) => setState(() => _autoSync = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Dossiers à synchroniser', style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _pickFolder,
                ),
              ],
            ),
            ..._selectedFolders.map((folder) => ListTile(
              title: Text(folder),
              subtitle: Text(_remotePaths[folder] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => setState(() {
                  _selectedFolders.remove(folder);
                  _remotePaths.remove(folder);
                }),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Journal des opérations', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  controller: _logController,
                  reverse: true,
                  child: Text(
                    _sshService.logs,
                    style: const TextStyle(fontFamily: 'Monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchron'),
        actions: [
          IconButton(
            icon: _isSyncing 
                ? const CircularProgressIndicator()
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncAll,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            _buildConnectionForm(),
            _buildFolderList(),
            _buildLogPanel(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sshService.dispose();
    _logController.dispose();
    super.dispose();
  }
}