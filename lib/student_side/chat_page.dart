import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _messagesStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('sos_id', widget.sosId)
        .order('created_at')
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

  Future<void> _sendMessage({String? content, String? attachmentUrl}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('messages').insert({
      'sos_id': widget.sosId,
      'sender_id': userId,
      'receiver_id': userId == widget.guardId ? widget.studentId : widget.guardId,
      'content': content ?? '',
      'attachment_url': attachmentUrl,
    });

    _controller.clear();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final path = 'chat/${widget.sosId}/${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      await _supabase.storage.from('chat_attachments').upload(path, file);

      final publicUrl =
          _supabase.storage.from('chat_attachments').getPublicUrl(path);

      await _sendMessage(attachmentUrl: publicUrl);
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final userId = _supabase.auth.currentUser?.id;
    final isMe = message['sender_id'] == userId;

    final content = message['content'] as String?;
    final attachmentUrl = message['attachment_url'] as String?;

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
            if (content != null && content.isNotEmpty)
              Text(
                content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
            if (attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: GestureDetector(
                  onTap: () {
                    // TODO: open image viewer
                  },
                  child: Image.network(
                    attachmentUrl,
                    height: 150,
                    width: 150,
                    fit: BoxFit.cover,
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
    final title = "${studentName ?? 'Student'} ↔ ${guardName ?? 'Guard'}";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.red,
        centerTitle: true,
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
                  PopupMenuButton<ImageSource>(
                    icon: const Icon(Icons.attach_file, color: Colors.red),
                    onSelected: (source) => _pickImage(source),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: ImageSource.camera,
                        child: Text("Camera"),
                      ),
                      const PopupMenuItem(
                        value: ImageSource.gallery,
                        child: Text("Gallery"),
                      ),
                    ],
                  ),
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
                    onPressed: () => _sendMessage(content: _controller.text),
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