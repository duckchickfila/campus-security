import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String sosId;
  final String guardId;   // assigned guard
  final String studentId; // student user id

  const ChatPage({
    super.key,
    required this.sosId,
    required this.guardId,
    required this.studentId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  String? guardName;
  String? studentName;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _messagesStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('sos_id', widget.sosId)
        .order('created_at', ascending: true) // oldest → newest
        .map((rows) => rows);

    _fetchNames();
  }

  Future<void> _fetchNames() async {
    final guard = await _supabase
        .from('guard_details')
        .select('name')
        .eq('user_id', widget.guardId)
        .maybeSingle();

    final student = await _supabase
        .from('student_details')
        .select('name')
        .eq('user_id', widget.studentId)
        .maybeSingle();

    setState(() {
      guardName = guard?['name'] ?? 'Guard';
      studentName = student?['name'] ?? 'Student';
    });
  }

  Future<void> _sendMessage(String content) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      print("⚠️ No logged in user, cannot send message");
      return;
    }

    if (content.trim().isEmpty) {
      print("⚠️ Empty message, not sending");
      return;
    }

    try {
      final response = await _supabase
          .from('messages')
          .insert({
            'sos_id': widget.sosId,
            'sender_id': userId,
            'receiver_id': userId == widget.guardId ? widget.studentId : widget.guardId,
            'content': content.trim(),
          })
          .select();

      print("✅ Message insert response: $response");
      _controller.clear();

      // scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      print("❌ Failed to send message: $e");
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final userId = _supabase.auth.currentUser?.id;
    final isMe = message['sender_id'] == userId;

    final content = message['content'] as String?;

    // show sender name
    final senderId = message['sender_id'] as String?;
    final senderName =
        senderId == widget.guardId ? guardName ?? 'Guard' : studentName ?? 'Student';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isMe ? Colors.red[700] : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              senderName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            if (content != null && content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  content,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = "${studentName ?? 'Student'}  ↔  ${guardName ?? 'Guard'}";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red,
        centerTitle: true,
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600, // modern semi-bold
          fontSize: 20,
          letterSpacing: 0.3,
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _buildMessageBubble(messages[index]),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.red),
                    onPressed: () => _sendMessage(_controller.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}