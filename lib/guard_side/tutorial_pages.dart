import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_page.dart'; // ✅ guard dashboard after tutorial

class GuardTutorialPages extends StatefulWidget {
  const GuardTutorialPages({super.key});

  @override
  State<GuardTutorialPages> createState() => _GuardTutorialPagesState();
}

class _GuardTutorialPagesState extends State<GuardTutorialPages> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> pages = [
    {
      "title": "Chat System",
      "bullets": [
        "💬 Access the chat icon to communicate instantly.",
        "👥 Stay connected with students and control room staff.",
        "⚡ Receive real-time updates during emergencies.",
      ],
      "image": "lib/assets/images/tutorial_chat.png",
    },
    {
      "title": "Live Map Navigation",
      "bullets": [
        "🗺️ Navigate directly to SOS locations.",
        "📍 Track live student positions during incidents.",
        "🚓 Ensure quick response with guided directions.",
      ],
      "image": "lib/assets/images/tutorial_map.png",
    },
    {
      "title": "SOS Report Interface",
      "bullets": [
        "🚨 View SOS alerts raised by students.",
        "📹 Access uploaded video and location instantly.",
        "✅ Respond quickly to emergencies with context-aware data.",
      ],
      "image": "lib/assets/images/tutorial_sos_guard.png",
    },
    {
      "title": "Incident Report Interface",
      "bullets": [
        "📝 Review detailed incident reports submitted by students.",
        "📊 Track resolution status and assigned actions.",
        "🔔 Get notified when new reports are filed.",
      ],
      "image": "lib/assets/images/tutorial_incident.png",
    },
  ];

  Future<void> _finishTutorial() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId != null) {
      await supabase
          .from('guard_details')
          .update({'seen_tutorial': true})
          .eq('user_id', userId);
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GuardMainPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          page["image"]!,
                          height: 200,
                          width: 200,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page["title"]!,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Inter',
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: (page["bullets"] as List<String>)
                                  .map((bullet) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          bullet,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontFamily: 'Inter',
                                            fontSize: 18,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 12 : 8,
                  height: _currentPage == index ? 12 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? theme.primaryColor
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(55),
                  backgroundColor: _currentPage == pages.length - 1
                      ? const Color.fromARGB(255, 247, 67, 67)
                      : Colors.grey.shade400,
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                onPressed: _currentPage == pages.length - 1
                    ? _finishTutorial
                    : null,
                child: const Text(
                  "Proceed to App",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}