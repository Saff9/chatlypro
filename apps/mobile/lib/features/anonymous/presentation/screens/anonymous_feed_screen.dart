import 'package:flutter/material.dart';
import '../../../../services/api_service.dart';

class AnonymousFeedScreen extends StatefulWidget {
  const AnonymousFeedScreen({super.key});

  @override
  State<AnonymousFeedScreen> createState() => _AnonymousFeedScreenState();
}

class _AnonymousFeedScreenState extends State<AnonymousFeedScreen> {
  final List<PulseItemData> _pulses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPulses();
  }

  Future<void> _loadPulses() async {
    setState(() => _loading = true);
    final raw = await ApiService().getPulses();
    setState(() {
      _pulses.clear();
      for (final p in raw) {
        final topics = (p['topics'] is List)
            ? List<String>.from(p['topics'])
            : <String>[];
        _pulses.add(PulseItemData(
          id: p['id'] ?? '',
          text: p['text'] ?? '',
          topics: topics,
          seenCount: (p['seen_count'] ?? 0) as int,
          repliesCount: (p['replies_count'] ?? 0) as int,
          timeLeft: '7 days',
        ));
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lucky Pulse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPulses,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => _showExplainPulseDialog(context, theme),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Anonymous Pulse Feed',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Posts auto-delete after 7 days. Completely anonymous.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Feed list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _pulses.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(Icons.masks_outlined, size: 40, color: Color(0xFFF59E0B)),
                              ),
                              const SizedBox(height: 20),
                              const Text('The feed is quiet',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE4E1ED))),
                              const SizedBox(height: 8),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 40),
                                child: Text(
                                  'Be the first to broadcast an anonymous pulse to the community.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: Color(0xFFC7C4D7), height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPulses,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _pulses.length,
                          itemBuilder: (context, index) {
                            final pulse = _pulses[index];
                            // Mark as seen
                            ApiService().markPulseSeen(pulse.id);
                            return _buildPulseCard(pulse, theme);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton.extended(
          onPressed: () => _showCreatePulseSheet(context, theme),
          backgroundColor: const Color(0xFFF59E0B),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Broadcast Pulse', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildPulseCard(PulseItemData pulse, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.12), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pulse.topics.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: pulse.topics.map((topic) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      topic.startsWith('#') ? topic : '#$topic',
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),
            if (pulse.topics.isNotEmpty) const SizedBox(height: 16),
            Text(pulse.text,
                style: TextStyle(fontSize: 16, height: 1.5, color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.remove_red_eye_outlined, size: 16,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text('${pulse.seenCount} seen',
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                    const SizedBox(width: 16),
                    Icon(Icons.chat_bubble_outline_rounded, size: 16,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text('${pulse.repliesCount} replies',
                        style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showConnectionRequestDialog(context, theme),
                  icon: const Icon(Icons.flash_on_rounded, size: 14, color: Colors.white),
                  label: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExplainPulseDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('How Pulse Works'),
        content: const Text(
          'Broadcast an anonymous post to all users.\n\n'
          '• No one can see who you are.\n'
          '• Tap "Connect" to start a private E2E encrypted chat.\n'
          '• Posts self-destruct after 7 days automatically.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
        ],
      ),
    );
  }

  void _showConnectionRequestDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('⚡ Connect Request'),
        content: const Text(
          'Send a connection request to reveal your identities and start a secure, E2E encrypted private chat?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Request dispatched! We\'ll let you know when they accept.')),
              );
            },
            child: const Text('Request Connection'),
          ),
        ],
      ),
    );
  }

  void _showCreatePulseSheet(BuildContext context, ThemeData theme) {
    final textController = TextEditingController();
    final topicsController = TextEditingController();
    bool posting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Broadcast Anonymous Pulse',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Share what\'s on your mind. Safe, anonymous, encrypted.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLength: 200,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'What is on your mind? (200 chars max)'),
              ),
              const SizedBox(height: 12),
              const Text('Topics (space-separated, e.g. #advice #fun)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: topicsController,
                decoration: const InputDecoration(hintText: '#advice #fun #music'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: posting
                    ? null
                    : () async {
                        final text = textController.text.trim();
                        if (text.isEmpty) return;
                        final topics = topicsController.text
                            .trim()
                            .split(' ')
                            .where((t) => t.isNotEmpty)
                            .toList();
                        setModalState(() => posting = true);
                        final ok = await ApiService().createPulse(text: text, topics: topics);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Anonymous pulse broadcasted! 🔥'
                                : 'Failed to post. Please try again.'),
                          ));
                        }
                        if (ok) await _loadPulses();
                      },
                child: posting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Broadcast Anonymously', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class PulseItemData {
  final String id;
  final String text;
  final List<String> topics;
  final int seenCount;
  final int repliesCount;
  final String timeLeft;

  PulseItemData({
    required this.id,
    required this.text,
    required this.topics,
    required this.seenCount,
    required this.repliesCount,
    required this.timeLeft,
  });
}
