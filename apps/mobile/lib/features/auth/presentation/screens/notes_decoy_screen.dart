import 'package:flutter/material.dart';
import '../../../../services/auth_service.dart';
import '../../../../navigation/main_navigation.dart';
import 'welcome_screen.dart';

class NoteItem {
  final String title;
  final String content;
  final String date;

  NoteItem({
    required this.title,
    required this.content,
    required this.date,
  });
}

class NotesDecoyScreen extends StatefulWidget {
  const NotesDecoyScreen({super.key});

  @override
  State<NotesDecoyScreen> createState() => _NotesDecoyScreenState();
}

class _NotesDecoyScreenState extends State<NotesDecoyScreen> {
  final List<NoteItem> _notes = [
    NoteItem(
      title: 'Shopping List',
      content: 'Eggs, Milk, Bread, Almond butter, Spinach, Coffee beans.',
      date: 'May 20',
    ),
    NoteItem(
      title: 'Project Ideas',
      content: '1. Offline mesh networking node logic.\n2. Toxicity scores classification algorithms.\n3. Decentralized identity.',
      date: 'May 18',
    ),
    NoteItem(
      title: 'Meeting Notes',
      content: 'Reviewed sprint plans. Core fastify server WebSocket relays look solid. Client keys agreement derived correctly.',
      date: 'May 15',
    ),
  ];

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isEditing = false;
  int? _editingIndex;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _handleSaveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) return;

    // Secret trigger: Type "unlock" in title or content to bypass
    if (title.toLowerCase() == 'unlock' || content.toLowerCase() == 'unlock') {
      final hasSession = await AuthService().tryAutoLogin();
      if (mounted) {
        if (hasSession) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainNavigation()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          );
        }
      }
      return;
    }

    setState(() {
      if (_editingIndex != null) {
        _notes[_editingIndex!] = NoteItem(
          title: title.isEmpty ? 'Untitled' : title,
          content: content,
          date: 'Today',
        );
      } else {
        _notes.insert(
          0,
          NoteItem(
            title: title.isEmpty ? 'Untitled' : title,
            content: content,
            date: 'Today',
          ),
        );
      }
      _isEditing = false;
      _editingIndex = null;
      _titleController.clear();
      _contentController.clear();
    });
  }

  void _startNewNote() {
    setState(() {
      _titleController.clear();
      _contentController.clear();
      _editingIndex = null;
      _isEditing = true;
    });
  }

  void _editNote(int index) {
    setState(() {
      _titleController.text = _notes[index].title;
      _contentController.text = _notes[index].content;
      _editingIndex = index;
      _isEditing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E24) : const Color(0xFFFAF6F0),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Note' : 'My Notes'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.check_rounded, color: Colors.amber),
              onPressed: _handleSaveNote,
            )
        ],
      ),
      body: _isEditing ? _buildEditor() : _buildNotesList(theme),
      floatingActionButton: _isEditing
          ? null
          : FloatingActionButton(
              onPressed: _startNewNote,
              backgroundColor: Colors.amber[700],
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
    );
  }

  Widget _buildNotesList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            title: Text(
              note.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                note.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
              ),
            ),
            trailing: Text(
              note.date,
              style: TextStyle(fontSize: 11, color: Colors.grey.withValues(alpha: 0.8)),
            ),
            onTap: () => _editNote(index),
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Title',
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: TextField(
              controller: _contentController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 16, height: 1.5),
              decoration: const InputDecoration(
                hintText: 'Type your note here...',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
